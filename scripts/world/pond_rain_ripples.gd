extends Node2D

## Each Marker2D child is a static, editable rain impact point on the pond water.
@export var cycle_seconds: float = 2.5
@export var maximum_radius: float = 12.0
@export_range(0.2, 1.0, 0.05) var perspective_y_scale: float = 0.5
@export var line_width: float = 2.2
@export var ripple_color: Color = Color(0.78, 0.96, 1.0, 0.72)

var _elapsed := 0.0
var _rain_active := false


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.weather_changed.connect(_on_weather_changed)
		bus.weather_preferences_changed.connect(_on_weather_preferences_changed)
	call_deferred("_sync_weather")


# 随渲染帧更新状态，时间增量以秒计。
func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()


# 提交本节点的自定义绘制命令。
func _draw() -> void:
	if not _rain_active:
		return
	var index := 0
	for child in get_children():
		var impact := child as Marker2D
		if impact == null:
			continue
		for ring in range(2):
			var phase := fposmod(_elapsed / maxf(cycle_seconds, 0.2) + float(index) * 0.19 + float(ring) * 0.5, 1.0)
			var radius := lerpf(2.5, maximum_radius, phase)
			var color := ripple_color
			color.a *= 1.0 - phase
			var points := PackedVector2Array()
			for segment in range(33):
				var angle := TAU * float(segment) / 32.0
				points.append(impact.position + Vector2(cos(angle) * radius, sin(angle) * radius * perspective_y_scale))
			draw_polyline(points, color, line_width, false)
		index += 1


# 响应 weather_changed 对应的事件或条件。
func _on_weather_changed(_previous_id: String, current_id: String) -> void:
	_set_weather(current_id)


# 响应 weather_preferences_changed 对应的事件或条件。
func _on_weather_preferences_changed() -> void:
	_sync_weather()


# 同步 weather，供调用方继续处理。
func _sync_weather() -> void:
	var weather := get_tree().get_first_node_in_group("weather_system")
	_set_weather(str(weather.get_weather_id()) if weather != null else "sunny")


# 设置 weather，供调用方继续处理。
func _set_weather(weather_id: String) -> void:
	var state := get_node_or_null("/root/GameState")
	var settings: Dictionary = state.settings if state != null else {}
	_rain_active = weather_id == "rain" and str(settings.get("weather_effect_mode", "standard")) != "off"
	set_process(_rain_active)
	visible = _rain_active
	queue_redraw()
