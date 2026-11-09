# 定义 WeatherBar 的状态和可用操作。
class_name WeatherBar
extends Node2D

## The three weather tiles are static children in Main.tscn. Only their state
## changes at runtime, so their positions and appearance remain editor-owned.
const TILES := {
	"sunny": "Sunny",
	"rain": "Rain",
	"snow": "Snow",
	"wind": "Wind",
}
const WEATHER_NAMES := {"sunny": "ui.5656dc6e75", "rain": "ui.d23564dfaf", "snow": "ui.51ea8f26e9", "wind": "weather.wind.name"}

@onready var _hover_tooltip: PanelContainer = $HoverTooltip
@onready var _hover_title: Label = $HoverTooltip/Content/Title
@onready var _hover_effect: Label = $HoverTooltip/Content/Effect
@onready var _hover_remaining: Label = $HoverTooltip/Content/Remaining
@onready var _countdown_timer: Timer = $CountdownTimer
var _hovered_id := ""


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	for id in TILES:
		var tile := get_node_or_null(str(TILES[id]))
		if tile == null:
			continue
		var hit := tile.get_node_or_null("HoverHit") as Control
		if hit != null:
			hit.mouse_entered.connect(_show_hover.bind(id))
			hit.mouse_exited.connect(_hide_hover.bind(id))
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.weather_changed.connect(_on_weather_changed)
		bus.game_loaded.connect(_refresh)
		bus.game_reset.connect(_refresh)
	_countdown_timer.timeout.connect(_update_countdown)
	call_deferred("_refresh")


# 显示 hover，供调用方继续处理。
func _show_hover(weather_id: String) -> void:
	_hovered_id = weather_id
	var name_id := str(WEATHER_NAMES.get(weather_id, ""))
	_hover_title.text = TextDB.text(name_id) if not name_id.is_empty() else TextDB.text("ui.6055fe4b90")
	var weather_system := get_tree().get_first_node_in_group("weather_system")
	_hover_effect.text = str(weather_system.call("get_effect_hint", weather_id)) if weather_system != null else ""
	_hover_tooltip.visible = true
	_update_countdown()
	var tile := get_node_or_null(str(TILES.get(weather_id, "")))
	if tile != null:
		(tile.get_node("Hover") as CanvasItem).visible = true


# 隐藏 hover，供调用方继续处理。
func _hide_hover(weather_id: String) -> void:
	var tile := get_node_or_null(str(TILES.get(weather_id, "")))
	if tile != null:
		(tile.get_node("Hover") as CanvasItem).visible = false
	if _hovered_id == weather_id:
		_hovered_id = ""
		_hover_tooltip.visible = false


# 响应 weather_changed 对应的事件或条件。
func _on_weather_changed(_previous_id: String, current_id: String) -> void:
	_apply(current_id)


# 封装 refresh 的处理，供相关流程复用。
func _refresh() -> void:
	var state := get_node_or_null("/root/GameState")
	var weather_id := str(state.weather_state.get("id", "sunny")) if state != null else "sunny"
	_apply(weather_id)


# 封装 apply 的处理，供相关流程复用。
func _apply(weather_id: String) -> void:
	if not TILES.has(weather_id):
		weather_id = "sunny"
	for id in TILES:
		var tile := get_node_or_null(str(TILES[id]))
		if tile == null:
			continue
		var dim := tile.get_node_or_null("Dim") as CanvasItem
		var countdown_mask := tile.get_node_or_null("CountdownMask") as CanvasItem
		var highlight := tile.get_node_or_null("Highlight") as CanvasItem
		if dim != null:
			dim.visible = id != weather_id
		if countdown_mask != null:
			countdown_mask.visible = id == weather_id
		if highlight != null:
			highlight.visible = id == weather_id
	_update_countdown()


# 更新 countdown，供调用方继续处理。
func _update_countdown() -> void:
	var state := get_node_or_null("/root/GameState")
	if state == null:
		return
	var weather_id := str(state.weather_state.get("id", "sunny"))
	if not TILES.has(weather_id):
		return
	var started_at := float(state.weather_state.get("started_at", 0))
	var ends_at := float(state.weather_state.get("ends_at", 0))
	var now := float(Time.get_unix_time_from_system())
	var duration := maxf(1.0, ends_at - started_at)
	var elapsed_fraction := clampf((now - started_at) / duration, 0.0, 1.0) if started_at > 0.0 else 0.0
	var mask := get_node_or_null("%s/CountdownMask" % str(TILES[weather_id])) as Sprite2D
	if mask != null and mask.material is ShaderMaterial:
		(mask.material as ShaderMaterial).set_shader_parameter("progress", elapsed_fraction)
	_hover_remaining.visible = _hovered_id == weather_id
	if _hover_remaining.visible:
		var seconds := maxi(0, ceili(ends_at - now))
		_hover_remaining.text = TextDB.text("ui.fa747c473c") % _format_remaining(seconds)


# 格式化 remaining，供调用方继续处理。
func _format_remaining(seconds: int) -> String:
	if seconds >= 3600:
		return "%02d:%02d:%02d" % [seconds / 3600, seconds / 60 % 60, seconds % 60]
	return "%02d:%02d" % [seconds / 60, seconds % 60]
