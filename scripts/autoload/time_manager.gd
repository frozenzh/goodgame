extends Node

## Configurable gameplay clock and the single owner of offline elapsed time.

@onready var GameConfig: Node = get_node("/root/GameConfig")
var _timer: Timer
var _last_tick_unix := 0
var _pending_offline: Dictionary = {}


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	_last_tick_unix = now_unix()
	_timer = Timer.new()
	_timer.name = "GameplayTick"
	_timer.wait_time = GameConfig.get_float("time_save", "tick_seconds")
	_timer.one_shot = false
	_timer.autostart = true
	_timer.timeout.connect(_on_tick)
	add_child(_timer)


# 封装 now_unix 的处理，供相关流程复用。
func now_unix() -> int:
	return int(Time.get_unix_time_from_system())


# 准备 offline，供调用方继续处理。
func prepare_offline(last_save_unix: int) -> int:
	var current := now_unix()
	var elapsed := clampi(current - maxi(0, last_save_unix), 0, GameConfig.get_int("time_save", "offline_cap_seconds"))
	_pending_offline = {
		"seconds": elapsed,
		"from_unix": current - elapsed,
		"to_unix": current
	}
	if elapsed > 0:
		_emit("offline_settlement_requested", [elapsed, current - elapsed, current])
	return elapsed


# 判断是否具有 pending_offline 对应的条件。
func has_pending_offline() -> bool:
	return int(_pending_offline.get("seconds", 0)) > 0


# 封装 peek_pending_offline 的处理，供相关流程复用。
func peek_pending_offline() -> Dictionary:
	return _pending_offline.duplicate(true)


# 封装 consume_pending_offline 的处理，供相关流程复用。
func consume_pending_offline() -> Dictionary:
	var result := _pending_offline.duplicate(true)
	_pending_offline.clear()
	return result


# 封装 publish_offline_result 的处理，供相关流程复用。
func publish_offline_result(result: Dictionary) -> void:
	_emit("offline_result_ready", [result])


# 响应 tick 对应的事件或条件。
func _on_tick() -> void:
	var current := now_unix()
	var delta := clampi(current - _last_tick_unix, 1, GameConfig.get_int("time_save", "offline_cap_seconds"))
	_last_tick_unix = current
	_emit("tick", [current, delta])


# 封装 emit 的处理，供相关流程复用。
func _emit(signal_name: String, arguments: Array = []) -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus == null or not bus.has_signal(signal_name):
		return
	match arguments.size():
		0: bus.emit_signal(signal_name)
		1: bus.emit_signal(signal_name, arguments[0])
		2: bus.emit_signal(signal_name, arguments[0], arguments[1])
		3: bus.emit_signal(signal_name, arguments[0], arguments[1], arguments[2])

