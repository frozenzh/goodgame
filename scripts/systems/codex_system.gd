# 定义 CodexSystem 的状态和可用操作。
class_name CodexSystem
extends Node

## Permanent knowledge layer for crops, baits, and fish. Inventory changes never
## remove discoveries. Unknown entries expose only catalog-authored safe hints.

const FISH_MILESTONES := []


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	_connect_bus("crop_harvested", Callable(self, "_on_crop_harvested"))
	_connect_bus("bait_crafted", Callable(self, "_on_bait_crafted"))
	_connect_bus("bait_purchased", Callable(self, "_on_bait_purchased"))
	_connect_bus("fish_caught", Callable(self, "_on_fish_caught"))


# 封装 unlock_entry 的处理，供相关流程复用。
func unlock_entry(entry_type: String, entry_id: String) -> bool:
	var state: Variant = _state()
	var normalized := _normalize_type(entry_type)
	if state == null or normalized.is_empty() or entry_id.is_empty():
		return false
	if not state.discover(normalized, entry_id):
		return false
	_emit("codex_entry_unlocked", [normalized, entry_id])
	if normalized == "fish":
		_check_fish_milestones()
	_request_save()
	return true


# 判断是否满足 discovered 对应的条件。
func is_discovered(entry_type: String, entry_id: String) -> bool:
	var state: Variant = _state()
	if state == null:
		return false
	match _normalize_type(entry_type):
		"crop": return state.discovered_crops.has(entry_id)
		"bait": return state.crafted_baits.has(entry_id)
		"fish": return state.discovered_fish.has(entry_id)
		_: return false


# 读取 entries，供调用方继续处理。
func get_entries(entry_type: String) -> Array:
	var registry: Variant = _registry()
	var normalized := _normalize_type(entry_type)
	if registry == null or normalized.is_empty():
		return []
	var category := "fish" if normalized == "fish" else normalized + "s"
	var result: Array = []
	for value in registry.get_all(category):
		var source: Dictionary = value
		var entry_id := str(source.get("id", ""))
		var discovered := is_discovered(normalized, entry_id)
		if discovered:
			var full := source.duplicate(true)
			full["discovered"] = true
			result.append(full)
		else:
			result.append({
				"id": entry_id,
				"discovered": false,
				"display_name": "???",
				"rarity": source.get("rarity", "unknown"),
				"hint": source.get("codex_hint", source.get("unknown_hint", "")),
				"silhouette": source.get("silhouette", source.get("icon", ""))
			})
	return result


# 读取 progress，供调用方继续处理。
func get_progress(entry_type: String) -> Dictionary:
	var entries := get_entries(entry_type)
	var discovered := 0
	for entry in entries:
		if bool(entry.get("discovered", false)):
			discovered += 1
	return {"discovered": discovered, "total": entries.size(), "complete": not entries.is_empty() and discovered == entries.size()}


# 响应 crop_harvested 对应的事件或条件。
func _on_crop_harvested(crop_id: String, _amount: int) -> void:
	unlock_entry("crop", crop_id)


# 响应 bait_crafted 对应的事件或条件。
func _on_bait_crafted(bait_id: String, _charges: int) -> void:
	unlock_entry("bait", bait_id)


# 响应 bait_purchased 对应的事件或条件。
func _on_bait_purchased(bait_id: String, _amount: int, _coins_spent: int) -> void:
	var state: Variant = _state()
	if state != null and not state.unlocked_baits.has(bait_id):
		state.unlocked_baits.append(bait_id)
	unlock_entry("bait", bait_id)


# 响应 fish_caught 对应的事件或条件。
func _on_fish_caught(fish_id: String, _first_time: bool) -> void:
	unlock_entry("fish", fish_id)


# 检查 fish_milestones，供调用方继续处理。
func _check_fish_milestones() -> void:
	var state: Variant = _state()
	if state == null:
		return
	var count: int = state.discovered_fish.size()
	for milestone in FISH_MILESTONES:
		var key := "fish:%s" % milestone
		if count >= milestone and not state.codex_milestones.has(key):
			state.codex_milestones.append(key)
			_apply_milestone_rewards(milestone)
			_emit("codex_milestone_reached", ["fish", milestone])


# 应用 milestone_rewards，供调用方继续处理。
func _apply_milestone_rewards(milestone: int) -> void:
	var state: Variant = _state()
	var registry: Variant = _registry()
	if state == null or registry == null:
		return
	var milestone_data: Dictionary = registry.get_entry("codex_milestones", str(milestone))
	for reward_value in milestone_data.get("rewards", []):
		if not reward_value is Dictionary:
			continue
		var reward: Dictionary = reward_value
		var reward_type := str(reward.get("type", ""))
		var ids: Array = reward.get("ids", []) if reward.get("ids", []) is Array else []
		match reward_type:
			"unlock_crops":
				_append_unique(state.unlocked_crops, ids)
			"unlock_baits":
				_append_unique(state.unlocked_baits, ids)
			"unlock_rods":
				_append_unique(state.unlocked_rods, ids)
			"unlock_upgrade":
				# Marks availability, not ownership; UI can inspect this flag list.
				state.flags["available_upgrades"] = _merged_unique(state.flags.get("available_upgrades", []), ids)
			"coins":
				DropService.grant_coins(maxi(0, int(reward.get("amount", 0))), "worker")
			"set_flag":
				state.flags[str(reward.get("id", ""))] = reward.get("value", true)


# 封装 append_unique 的处理，供相关流程复用。
func _append_unique(target: Array, values: Array) -> void:
	for value in values:
		var text := str(value)
		if not text.is_empty() and not target.has(text):
			target.append(text)


# 封装 merged_unique 的处理，供相关流程复用。
func _merged_unique(existing: Variant, values: Array) -> Array:
	var result: Array = existing.duplicate() if existing is Array else []
	_append_unique(result, values)
	return result


# 规范化 type，供调用方继续处理。
func _normalize_type(value: String) -> String:
	match value.to_lower():
		"crop", "crops", "plant", "plants": return "crop"
		"bait", "baits": return "bait"
		"fish", "fishes": return "fish"
		_: return ""


# 封装 state 的处理，供相关流程复用。
func _state():
	return get_node_or_null("/root/GameState")


# 封装 registry 的处理，供相关流程复用。
func _registry():
	return get_node_or_null("/root/DataRegistry")


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
