# 定义 RandomEventSystem 的状态和可用操作。
class_name RandomEventSystem
extends Node

## Online-only rare fish-shadow opportunities. Scheduling uses absolute times,
## but intentionally does not participate in offline settlement.

@onready var GameConfig: Node = get_node("/root/GameConfig")
var _rng := RandomNumberGenerator.new()
var _next_event_unix := 0
var _current_event: Dictionary = {}


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	_rng.randomize()
	_schedule_next(_now())
	_connect_bus("tick", Callable(self, "_on_tick"))


# 读取 current_event，供调用方继续处理。
func get_current_event() -> Dictionary:
	return _current_event.duplicate(true)


# 读取 next_event_unix，供调用方继续处理。
func get_next_event_unix() -> int:
	return _next_event_unix


# 封装 force_start 的处理，供相关流程复用。
func force_start(event_id: String = "") -> bool:
	if not _current_event.is_empty():
		return false
	return _start_event(event_id, _now())


# 解析 event，供调用方继续处理。
func resolve_event(success: bool) -> Dictionary:
	if _current_event.is_empty():
		return {}
	var event := _current_event.duplicate(true)
	var reward_id := ""
	if success:
		reward_id = _grant_reward(event)
	_current_event.clear()
	_emit("rare_event_resolved", [success, reward_id])
	_schedule_next(_now())
	return {"success": success, "reward_id": reward_id, "event_id": str(event.get("id", ""))}


# 响应 tick 对应的事件或条件。
func _on_tick(now_unix: int, _delta_seconds: int) -> void:
	if not _current_event.is_empty():
		if now_unix >= int(_current_event.get("expires_at", now_unix + 1)):
			resolve_event(false)
		return
	if now_unix >= _next_event_unix:
		_start_event("", now_unix)


# 启动 event，供调用方继续处理。
func _start_event(requested_id: String, now_unix: int) -> bool:
	var registry: Variant = _registry()
	var event: Dictionary = {}
	if registry != null:
		if not requested_id.is_empty():
			event = registry.get_entry("events", requested_id)
		else:
			var events: Array = registry.get_all("events")
			if not events.is_empty():
				event = events[_rng.randi_range(0, events.size() - 1)]
	if event.is_empty():
		event = {"id": "rare_fish_shadow", "duration_seconds": GameConfig.get_int("random_events", "default_event_duration_seconds")}
	_current_event = event.duplicate(true)
	_current_event["started_at"] = now_unix
	_current_event["expires_at"] = now_unix + maxi(GameConfig.get_int("random_events", "minimum_event_duration_seconds"), int(event.get("duration_seconds", GameConfig.get_int("random_events", "default_event_duration_seconds"))))
	_emit("rare_event_started", [str(_current_event.get("id", "rare_fish_shadow"))])
	return true


# 封装 grant_reward 的处理，供相关流程复用。
func _grant_reward(event: Dictionary) -> String:
	var state: Variant = _state()
	if state == null:
		return ""
	var reward = event.get("reward", {})
	if not reward is Dictionary:
		return ""
	var reward_type := str(reward.get("type", "fish"))
	var reward_id := str(reward.get("id", reward.get("item_id", "")))
	var amount := maxi(1, int(reward.get("amount", 1)))
	match reward_type:
		"fish":
			var first_time: bool = not state.discovered_fish.has(reward_id)
			DropService.grant_fish(reward_id, amount, "pond")
			_emit("fish_caught", [reward_id, first_time])
			_emit("achievement_action", [state.next_achievement_event_id(), "fish_caught", {"fish_id": reward_id, "rod_id": ""}])
		"bait", "item":
			DropService.grant_item(reward_id, amount, "worker", reward_type)
		"coins":
			DropService.grant_coins(amount, "worker")
		_:
			return ""
	_request_save()
	return reward_id


# 封装 schedule_next 的处理，供相关流程复用。
func _schedule_next(now_unix: int) -> void:
	_next_event_unix = now_unix + _rng.randi_range(GameConfig.get_int("random_events", "delay_min_seconds"), GameConfig.get_int("random_events", "delay_max_seconds"))


# 封装 state 的处理，供相关流程复用。
func _state():
	return get_node_or_null("/root/GameState")


# 封装 registry 的处理，供相关流程复用。
func _registry():
	return get_node_or_null("/root/DataRegistry")


# 封装 now 的处理，供相关流程复用。
func _now() -> int:
	var time_manager = get_node_or_null("/root/TimeManager")
	return time_manager.now_unix() if time_manager != null else int(Time.get_unix_time_from_system())


# 请求 save，供调用方继续处理。
func _request_save() -> void:
	var saver = get_node_or_null("/root/SaveManager")
	if saver != null:
		saver.request_save()


# 绑定 bus，供调用方继续处理。
func _connect_bus(signal_name: String, callable: Callable) -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus != null and bus.has_signal(signal_name) and not bus.is_connected(signal_name, callable):
		bus.connect(signal_name, callable)


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
