extends Node

## 所有游戏内产出通过这里发放。source_key 指向世界触发点：plot:<id>、pond、workbench、shop、house、worker。

var _pending: Dictionary = {}
var _flush_scheduled := false


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.connect("game_reset", Callable(self, "_on_game_reset"))


# 响应 game_reset 对应的事件或条件。
func _on_game_reset() -> void:
	_pending.clear()


# 封装 grant_item 的处理，供相关流程复用。
func grant_item(item_id: String, amount: int, source_key: String, item_type: String = "item") -> void:
	if amount <= 0:
		return
	var state := get_node_or_null("/root/GameState")
	if state == null:
		return
	state.call("add_item", item_id, amount)
	announce(item_type, item_id, amount, source_key)


# 封装 grant_fish 的处理，供相关流程复用。
func grant_fish(fish_id: String, amount: int, source_key: String) -> void:
	if amount <= 0:
		return
	var state := get_node_or_null("/root/GameState")
	if state == null:
		return
	state.call("add_fish", fish_id, amount)
	announce("fish", fish_id, amount, source_key)


# 封装 grant_coins 的处理，供相关流程复用。
func grant_coins(amount: int, source_key: String) -> void:
	if amount <= 0:
		return
	var state := get_node_or_null("/root/GameState")
	if state == null:
		return
	state.call("add_coins", amount)
	announce("coins", "coins", amount, source_key)


# 封装 grant_fertilizer 的处理，供相关流程复用。
func grant_fertilizer(amount: int, source_key: String) -> void:
	if amount <= 0:
		return
	var state := get_node_or_null("/root/GameState")
	if state == null:
		return
	state.call("add_fertilizer", amount)
	announce("fertilizer", "fertilizer", amount, source_key)


# 封装 announce 的处理，供相关流程复用。
func announce(item_type: String, item_id: String, amount: int, source_key: String) -> void:
	if amount <= 0:
		return
	var key := "%s|%s|%s" % [item_type, item_id, source_key]
	if _pending.has(key):
		var pending: Dictionary = _pending[key]
		pending["amount"] = int(pending["amount"]) + amount
		_pending[key] = pending
	else:
		_pending[key] = {"item_type": item_type, "item_id": item_id, "amount": amount, "source_key": source_key}
	if not _flush_scheduled:
		_flush_scheduled = true
		call_deferred("_flush_announcements")


# 封装 flush_announcements 的处理，供相关流程复用。
func _flush_announcements() -> void:
	_flush_scheduled = false
	var bus := get_node_or_null("/root/EventBus")
	if bus == null:
		_pending.clear()
		return
	var ready := _pending.duplicate(true)
	_pending.clear()
	for value in ready.values():
		var entry: Dictionary = value
		bus.emit_signal("item_dropped", str(entry["item_type"]), str(entry["item_id"]), int(entry["amount"]), str(entry["source_key"]))
