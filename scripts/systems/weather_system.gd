# 定义 WeatherSystem 的状态和可用操作。
class_name WeatherSystem
extends Node

## Online weather authority. Expired offline periods advance exactly once.
const WEATHER_IDS := ["sunny", "rain", "snow", "wind"]
const SAFE_DURATION := 600
const OPENING_WEATHER := ["sunny", "rain", "snow"]
const OPENING_SUNNY_SECONDS := 300

var _rng := RandomNumberGenerator.new()
var _initialized := false
var _last_observed_now := 0


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	add_to_group("weather_system")
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.tick.connect(_on_tick)
		bus.game_loaded.connect(_on_game_loaded)
		bus.game_reset.connect(_on_game_reset)


# 响应 game_loaded 对应的事件或条件。
func _on_game_loaded() -> void:
	_initialized = false
	restore_or_initialize(_now())


# 新游戏和重置进度都从固定的开局天气开始。
func _on_game_reset() -> void:
	initialize_at(_now(), 0, true)


# 响应 tick 对应的事件或条件。
func _on_tick(now_unix: int, _delta_seconds: int) -> void:
	advance_if_due(now_unix)


# now_unix 为 Unix 秒数，seed_override 为 0 时自动取种子；仅新游戏启用固定天气。
func initialize_at(now_unix: int, seed_override: int = 0, new_game: bool = false) -> void:
	var seed_value := seed_override if seed_override != 0 else Time.get_ticks_usec() ^ now_unix
	_rng.seed = seed_value
	_initialized = true
	_last_observed_now = now_unix
	_start_segment("sunny", now_unix, "", 0 if new_game else -1)


# 恢复 or_initialize，供调用方继续处理。
func restore_or_initialize(now_unix: int) -> void:
	var state: Node = _state()
	if state == null:
		return
	var saved: Dictionary = state.weather_state
	var saved_id := str(saved.get("id", ""))
	var started_at := int(saved.get("started_at", 0))
	var ends_at := int(saved.get("ends_at", 0))
	var rng_text := str(saved.get("rng_state", ""))
	if not saved.is_empty() and (saved_id not in WEATHER_IDS or started_at <= 0 or ends_at <= started_at or not rng_text.is_valid_int()):
		push_warning(TextDB.text("ui.31ce0ab4cf"))
		initialize_at(now_unix)
		return
	if saved.is_empty():
		initialize_at(now_unix)
		return
	_rng.state = int(rng_text)
	_initialized = true
	_last_observed_now = now_unix
	if now_unix < started_at:
		_repair_clock_rollback(now_unix)
	if now_unix >= int(state.weather_state.get("ends_at", 0)):
		advance_if_due(now_unix, true)
	else:
		_emit_change("", saved_id)


# 封装 advance_if_due 的处理，供相关流程复用。
func advance_if_due(now_unix: int, initial_display: bool = false) -> bool:
	if not _initialized:
		restore_or_initialize(now_unix)
		return false
	var state: Node = _state()
	if state == null:
		return false
	if now_unix < _last_observed_now:
		_repair_clock_rollback(now_unix)
	_last_observed_now = now_unix
	if now_unix < int(state.weather_state.get("ends_at", 0)):
		return false
	var previous := get_weather_id()
	var opening_step := int(state.weather_state.get("opening_step", -1))
	if opening_step >= 0 and opening_step < OPENING_WEATHER.size() - 1:
		opening_step += 1
		_start_segment(OPENING_WEATHER[opening_step], now_unix, "" if initial_display else previous, opening_step)
	else:
		var next_id := choose_next_id(previous, _weights(), _rng)
		_start_segment(next_id, now_unix, "" if initial_display else previous)
	return true


# 读取 weather_id，供调用方继续处理。
func get_weather_id() -> String:
	var state: Node = _state()
	var value := str(state.weather_state.get("id", "sunny")) if state != null else "sunny"
	return value if value in WEATHER_IDS else "sunny"


# 读取 fishing_speed_multiplier，供调用方继续处理。
func get_fishing_speed_multiplier() -> float:
	return get_fishing_speed_for(get_weather_id())


# 读取 fishing_speed_for，供调用方继续处理。
func get_fishing_speed_for(weather_id: String) -> float:
	return maxf(1.0, _config_float("rain_fishing_speed_multiplier", 2.0)) if weather_id == "rain" else 1.0


# 读取 crop_growth_speed_multiplier，供调用方继续处理。
func get_crop_growth_speed_multiplier() -> float:
	return get_crop_growth_speed_for(get_weather_id())


# 读取 crop_growth_speed_for，供调用方继续处理。
func get_crop_growth_speed_for(weather_id: String) -> float:
	if weather_id == "snow":
		return maxf(1.0, _config_float("snow_crop_growth_speed_multiplier", 2.0))
	if weather_id == "wind":
		return 1.0 / maxf(1.0, _config_float("wind_crop_growth_time_multiplier", 1.2))
	return 1.0


# 读取 rule_hint，供调用方继续处理。
func get_rule_hint() -> String:
	var weather_id := get_weather_id()
	var names := {"sunny": TextDB.text("ui.5656dc6e75"), "rain": TextDB.text("ui.d23564dfaf"), "snow": TextDB.text("ui.51ea8f26e9"), "wind": TextDB.text("weather.wind.name")}
	return "%s：%s" % [names.get(weather_id, TextDB.text("ui.5656dc6e75")), get_effect_hint(weather_id)]


# 读取 effect_hint，供调用方继续处理。
func get_effect_hint(weather_id: String) -> String:
	match weather_id:
		"rain": return TextDB.text("ui.c10448f21e") % roundi((get_fishing_speed_for("rain") - 1.0) * 100.0)
		"snow": return TextDB.text("ui.0e1c8957ba") % roundi((get_crop_growth_speed_for("snow") - 1.0) * 100.0)
		"wind": return TextDB.text("weather.wind.effect") % roundi((_config_float("wind_crop_growth_time_multiplier", 1.2) - 1.0) * 100.0)
		_: return TextDB.text("ui.70aee086af")


# 封装 debug_force_weather 的处理，供相关流程复用。
func debug_force_weather(weather_id: String, now_unix: int = -1) -> bool:
	if not is_debug_allowed():
		return false
	return force_weather(weather_id, now_unix)


# 封装 force_weather 的处理，供相关流程复用。
func force_weather(weather_id: String, now_unix: int = -1) -> bool:
	if weather_id not in WEATHER_IDS:
		return false
	var current := _now() if now_unix < 0 else now_unix
	if not _initialized:
		initialize_at(current)
	var previous := get_weather_id()
	_start_segment(weather_id, current, previous)
	return true


# 封装 debug_expire_now 的处理，供相关流程复用。
func debug_expire_now(now_unix: int = -1) -> bool:
	if not is_debug_allowed():
		return false
	var current := _now() if now_unix < 0 else now_unix
	if not _initialized:
		initialize_at(current)
	var state: Node = _state()
	if state == null:
		return false
	state.weather_state["ends_at"] = current
	return advance_if_due(current)


# 判断是否满足 debug_allowed 对应的条件。
func is_debug_allowed() -> bool:
	return OS.has_feature("debug") or Engine.is_editor_hint()


# 封装 choose_next_id 的处理，供相关流程复用。
static func choose_next_id(current_id: String, weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0
	for weather_id in WEATHER_IDS:
		if weather_id != current_id:
			total += maxi(0, int(weights.get(weather_id, 0)))
	if total <= 0:
		return "sunny"
	var draw := rng.randi_range(1, total)
	for weather_id in WEATHER_IDS:
		if weather_id == current_id:
			continue
		draw -= maxi(0, int(weights.get(weather_id, 0)))
		if draw <= 0:
			return weather_id
	return "sunny"


# 启动并保存一段天气。opening_step 为 -1 时使用常规轮换，旧存档缺失此字段时同样处理。
func _start_segment(weather_id: String, now_unix: int, previous_id: String, opening_step: int = -1) -> void:
	var state: Node = _state()
	if state == null:
		return
	var minimum := _config_int("duration_min_seconds", SAFE_DURATION)
	var maximum := _config_int("duration_max_seconds", SAFE_DURATION)
	if minimum <= 0 or maximum < minimum or _total_weight() <= 0:
		push_warning(TextDB.text("ui.9920f73834"))
		if opening_step < 0:
			weather_id = "sunny"
		minimum = SAFE_DURATION
		maximum = SAFE_DURATION
	var duration := OPENING_SUNNY_SECONDS if opening_step == 0 else _rng.randi_range(minimum, maximum)
	state.weather_state = {
		"id": weather_id,
		"started_at": now_unix,
		"ends_at": now_unix + duration,
		"rng_state": str(_rng.state),
	}
	if opening_step >= 0:
		state.weather_state["opening_step"] = opening_step
	_last_observed_now = now_unix
	_emit_change(previous_id, weather_id)
	_request_save()


# 封装 repair_clock_rollback 的处理，供相关流程复用。
func _repair_clock_rollback(now_unix: int) -> void:
	var state: Node = _state()
	if state == null or state.weather_state.is_empty():
		return
	var maximum := maxi(1, _config_int("duration_max_seconds", SAFE_DURATION))
	var remaining := clampi(int(state.weather_state.get("ends_at", now_unix)) - now_unix, 0, maximum)
	state.weather_state["started_at"] = mini(int(state.weather_state.get("started_at", now_unix)), now_unix)
	state.weather_state["ends_at"] = now_unix + remaining
	_last_observed_now = now_unix
	_request_save()


# 封装 weights 的处理，供相关流程复用。
func _weights() -> Dictionary:
	return {"sunny": _config_int("sunny_weight", 50), "rain": _config_int("rain_weight", 30), "snow": _config_int("snow_weight", 20), "wind": _config_int("wind_weight", 15)}


# 封装 total_weight 的处理，供相关流程复用。
func _total_weight() -> int:
	var total := 0
	for weight in _weights().values():
		total += maxi(0, int(weight))
	return total


# 封装 config_int 的处理，供相关流程复用。
func _config_int(key: String, fallback: int) -> int:
	var config := get_node_or_null("/root/GameConfig")
	var value: Variant = config.get_value("weather", key) if config != null else null
	return int(value) if value is int or value is float else fallback


# 封装 config_float 的处理，供相关流程复用。
func _config_float(key: String, fallback: float) -> float:
	var config := get_node_or_null("/root/GameConfig")
	var value: Variant = config.get_value("weather", key) if config != null else null
	return float(value) if value is int or value is float else fallback


# 封装 now 的处理，供相关流程复用。
func _now() -> int:
	return int(Time.get_unix_time_from_system())


# 封装 state 的处理，供相关流程复用。
func _state():
	return get_node_or_null("/root/GameState")


# 发出 change，供调用方继续处理。
func _emit_change(previous_id: String, current_id: String) -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.weather_changed.emit(previous_id, current_id)


# 请求 save，供调用方继续处理。
func _request_save() -> void:
	var saver := get_node_or_null("/root/SaveManager")
	if saver != null:
		saver.request_save()
