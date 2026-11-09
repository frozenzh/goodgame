# 定义 WeatherVisual 的状态和可用操作。
class_name WeatherVisual
extends Node2D

@onready var rain: WeatherParticles = $RainLayer
@onready var snow: WeatherParticles = $SnowLayer
@onready var rain_audio: AudioStreamPlayer = $RainAudio
@onready var snow_piles: Node2D = $SnowPiles
@onready var pond_ice: Sprite2D = get_node_or_null("../ResourceNodes/Pond/FrozenWater") as Sprite2D
@onready var clouds: Node2D = $Clouds

@export var rain_world_tint := Color(0.88, 0.94, 1.0, 1.0)
@export var snow_world_tint := Color(0.84, 0.93, 1.0, 1.0)
@export var wind_world_tint := Color(0.94, 0.97, 1.0, 1.0)

var _transition: Tween
var _base_world_color := Color.WHITE
var _active_weather := "sunny"
var _visuals_on := true
const CLOUD_DURATIONS := [16.0, 21.0, 27.0]
const CLOUD_DRIFT := [260.0, 360.0, 400.0]
const CLOUD_PHASES := [0.0, 0.32, 0.63]
const ROOF_SNOW_STAGE_SECONDS := 100.0
const ROOF_SNOW_STAGE_COUNT := 3

var _cloud_time := 0.0
var _cloud_origins: Array[Vector2] = []
var _snow_melt_started_at := -1.0
var _snow_melt_progress := 0.0
var _last_snow_progress := 0.0
var _last_roof_snow_coverage := 0.0
var _roof_snow_layers: Array[Sprite2D] = []
var _roof_snow_materials: Array[ShaderMaterial] = []
var _roof_snow_coverage := 0.0


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	_base_world_color = get_parent().modulate
	rain.modulate.a = 0.0
	snow.modulate.a = 0.0
	for pile in snow_piles.get_children():
		(pile as SnowPile).visible = false
	if pond_ice != null:
		pond_ice.visible = false
	for roof_snow in get_parent().find_children("RoofSnow", "Sprite2D", true, false):
		var layer := roof_snow as Sprite2D
		layer.hide()
		_roof_snow_layers.append(layer)
		var snow_material := layer.material as ShaderMaterial
		if snow_material != null and not _roof_snow_materials.has(snow_material):
			_roof_snow_materials.append(snow_material)
	for cloud in clouds.get_children():
		_cloud_origins.append((cloud as Sprite2D).position)
	clouds.hide()
	if rain_audio.stream is AudioStreamWAV:
		(rain_audio.stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	rain_audio.volume_db = -60.0
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.weather_changed.connect(_on_weather_changed)
		bus.weather_preferences_changed.connect(_on_preferences_changed)
		bus.game_reset.connect(_on_game_reset)
	call_deferred("_initialize_from_weather")


# 封装 initialize_from_weather 的处理，供相关流程复用。
func _initialize_from_weather() -> void:
	var weather := get_tree().get_first_node_in_group("weather_system")
	_apply_weather(str(weather.get_weather_id()) if weather != null else "sunny", false)


# 响应 weather_changed 对应的事件或条件。
func _on_weather_changed(previous_id: String, current_id: String) -> void:
	_apply_weather(current_id, not previous_id.is_empty())


# 响应 preferences_changed 对应的事件或条件。
func _on_preferences_changed() -> void:
	_apply_weather(_current_id(), false)


# 响应 game_reset 对应的事件或条件。
func _on_game_reset() -> void:
	_snow_melt_started_at = -1.0
	_snow_melt_progress = 0.0
	_last_snow_progress = 0.0
	_last_roof_snow_coverage = 0.0
	_update_snow_piles()


# 应用 weather，供调用方继续处理。
func _apply_weather(weather_id: String, animate: bool) -> void:
	var state := get_node_or_null("/root/GameState")
	var settings: Dictionary = state.settings if state != null else {}
	var mode := str(settings.get("weather_effect_mode", "standard"))
	var visuals_on := mode != "off"
	if _active_weather == "snow" and weather_id != "snow":
		_snow_melt_progress = _last_snow_progress
		_snow_melt_started_at = float(Time.get_unix_time_from_system())
	elif weather_id == "snow":
		_snow_melt_started_at = -1.0
	if weather_id == "wind" and _active_weather != "wind":
		_cloud_time = 0.0
	_active_weather = weather_id
	_visuals_on = visuals_on
	clouds.visible = visuals_on and weather_id == "wind"
	if clouds.visible:
		_update_clouds()
	_update_snow_piles()
	var rain_target := 1.0 if visuals_on and weather_id == "rain" else 0.0
	var snow_target := 1.0 if visuals_on and weather_id == "snow" else 0.0
	var color_target := _base_world_color
	if visuals_on and weather_id == "rain":
		color_target *= rain_world_tint
	elif visuals_on and weather_id == "snow":
		color_target *= snow_world_tint
	elif visuals_on and weather_id == "wind":
		color_target *= wind_world_tint
	var config := get_node_or_null("/root/GameConfig")
	var low := mode == "low"
	rain.configure(int(config.get_int("weather", "rain_particles_low" if low else "rain_particles_standard")), float(config.get_float("weather", "rain_speed")), float(config.get_float("weather", "rain_drift")))
	snow.configure(int(config.get_int("weather", "snow_particles_low" if low else "snow_particles_standard")), float(config.get_float("weather", "snow_speed")), float(config.get_float("weather", "snow_drift")))
	var sound_on := bool(settings.get("weather_ambient_enabled", true)) and weather_id == "rain"
	var target_db := float(config.get_float("weather", "rain_volume_db")) if sound_on else -60.0
	if _transition != null and _transition.is_running():
		_transition.kill()
	rain.set_process(rain_target > 0.0 or rain.modulate.a > 0.0)
	snow.set_process(snow_target > 0.0 or snow.modulate.a > 0.0)
	if sound_on and not rain_audio.playing:
		rain_audio.play()
	if not animate:
		get_parent().modulate = color_target
		rain.modulate.a = rain_target
		snow.modulate.a = snow_target
		rain_audio.volume_db = target_db
		_finish_transition(sound_on)
		return
	var duration := maxf(0.0, float(config.get_float("weather", "transition_seconds")))
	if duration <= 0.0:
		get_parent().modulate = color_target
		rain.modulate.a = rain_target
		snow.modulate.a = snow_target
		rain_audio.volume_db = target_db
		_finish_transition(sound_on)
		return
	_transition = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	_transition.tween_property(get_parent(), "modulate", color_target, duration)
	_transition.tween_property(rain, "modulate:a", rain_target, duration)
	_transition.tween_property(snow, "modulate:a", snow_target, duration)
	_transition.tween_property(rain_audio, "volume_db", target_db, duration)
	_transition.set_parallel(false)
	_transition.tween_callback(_finish_transition.bind(sound_on))


# 结束 transition，供调用方继续处理。
func _finish_transition(sound_on: bool) -> void:
	rain.set_process(rain.modulate.a > 0.001)
	snow.set_process(snow.modulate.a > 0.001)
	if not sound_on and rain_audio.playing:
		rain_audio.stop()


# 封装 current_id 的处理，供相关流程复用。
func _current_id() -> String:
	var weather := get_tree().get_first_node_in_group("weather_system")
	return str(weather.get_weather_id()) if weather != null else "sunny"


# 随渲染帧更新状态，时间增量以秒计。
func _process(delta: float) -> void:
	_update_snow_piles()
	if clouds.visible:
		_cloud_time += delta
		_update_clouds()


# 更新 clouds，供调用方继续处理。
func _update_clouds() -> void:
	# Keep the cloud lanes in the upper half of the game, even when the farm scrolls.
	clouds.global_position = Vector2.ZERO
	for index in range(_cloud_origins.size()):
		var cloud := clouds.get_child(index) as Sprite2D
		var phase := fposmod(_cloud_time / CLOUD_DURATIONS[index] + CLOUD_PHASES[index], 1.0)
		cloud.position = _cloud_origins[index] + Vector2((phase - 0.5) * CLOUD_DRIFT[index], 0.0)
		var fade_in := smoothstep(0.0, 0.22, phase)
		var fade_out := 1.0 - smoothstep(0.74, 1.0, phase)
		cloud.self_modulate.a = 0.78 * fade_in * fade_out


# 更新 snow_piles，供调用方继续处理。
func _update_snow_piles() -> void:
	var piles := snow_piles.get_children()
	if not _visuals_on:
		_update_roof_snow(0.0)
		for pile in piles:
			(pile as SnowPile).visible = false
		if pond_ice != null:
			pond_ice.visible = false
		return
	var progress := 0.0
	var melt_alpha := 1.0
	if _active_weather == "snow":
		progress = _snow_progress()
		_last_snow_progress = progress
		_last_roof_snow_coverage = _roof_snow_stage_coverage()
	elif _snow_melt_started_at >= 0.0:
		progress = _snow_melt_progress
		var melt_seconds := maxf(1.0, GameConfig.get_float("weather", "snow_melt_seconds"))
		melt_alpha = clampf(1.0 - (float(Time.get_unix_time_from_system()) - _snow_melt_started_at) / melt_seconds, 0.0, 1.0)
	else:
		melt_alpha = 0.0
	var first := clampf(GameConfig.get_float("weather", "snow_pile_first_fraction"), 0.0, 0.95)
	for pile_node in piles:
		var pile := pile_node as SnowPile
		var threshold := maxf(first, pile.appear_fraction)
		pile.visible = melt_alpha > 0.0 and progress >= threshold
		if pile.visible:
			pile.self_modulate.a = clampf((progress - threshold) / pile.fade_fraction, 0.0, 1.0) * melt_alpha
	_update_pond_ice(progress, melt_alpha)
	_update_roof_snow(_last_roof_snow_coverage * melt_alpha)


# 按降雪开始时间每 100 秒增加一段，读档时直接恢复对应覆盖比例。
func _roof_snow_stage_coverage() -> float:
	var started_at := float(GameState.weather_state.get("started_at", 0))
	if started_at <= 0.0:
		return 0.0
	var elapsed := Time.get_unix_time_from_system() - started_at
	var stage := clampi(floori(elapsed / ROOF_SNOW_STAGE_SECONDS), 0, ROOF_SNOW_STAGE_COUNT)
	return float(stage) / ROOF_SNOW_STAGE_COUNT


# coverage 为屋顶覆盖比例。普通雪层和带烟囱开口的雪层同步更新。
func _update_roof_snow(coverage: float) -> void:
	if _roof_snow_layers.is_empty() or coverage == _roof_snow_coverage:
		return
	var show_snow := coverage > 0.0
	if show_snow != (_roof_snow_coverage > 0.0):
		for layer in _roof_snow_layers:
			layer.visible = show_snow
	_roof_snow_coverage = coverage
	for snow_material in _roof_snow_materials:
		snow_material.set_shader_parameter("coverage", coverage)


# 更新 pond_ice，供调用方继续处理。
func _update_pond_ice(snow_progress: float, melt_alpha: float) -> void:
	if pond_ice == null:
		return
	var start := clampf(GameConfig.get_float("weather", "pond_freeze_start_fraction"), 0.0, 0.95)
	var full := clampf(GameConfig.get_float("weather", "pond_freeze_full_fraction"), start + 0.01, 1.0)
	var freeze_progress := clampf((snow_progress - start) / (full - start), 0.0, 1.0)
	pond_ice.visible = freeze_progress > 0.0 and melt_alpha > 0.0
	if pond_ice.visible:
		var ice_material := pond_ice.material as ShaderMaterial
		ice_material.set_shader_parameter("freeze_progress", freeze_progress)
		ice_material.set_shader_parameter("melt_opacity", melt_alpha)


# 封装 snow_progress 的处理，供相关流程复用。
func _snow_progress() -> float:
	var state := get_node_or_null("/root/GameState")
	var segment: Dictionary = state.weather_state if state != null else {}
	var start := float(segment.get("started_at", 0))
	var end := float(segment.get("ends_at", 0))
	if end <= start:
		return 0.0
	return clampf((float(Time.get_unix_time_from_system()) - start) / maxf(1.0, end - start), 0.0, 1.0)
