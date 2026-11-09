# 定义 CraftingSystem 的状态和可用操作。
class_name CraftingSystem
extends Node

## Workbench bait recipes. Ingredients are paid when queued; charges are added
## when the timestamp completes, so closing the game cannot duplicate materials.
const RARITY_ORDER := ["common", "good", "rare", "epic"]


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	_connect_bus("tick", Callable(self, "_on_tick"))


# 检查是否允许 craft 对应的条件。
func can_craft(bait_id: String, batches: int = 1) -> bool:
	if batches <= 0:
		return false
	var state: Variant = _state()
	var recipe := _recipe_for(bait_id)
	if state == null or not state.workbench_unlocked or recipe.is_empty() or bool(recipe.get("shop_only", false)) or str(recipe.get("source", "craft")) == "shop":
		return false
	if state.get_workbench_tier() < maxi(1, int(recipe.get("required_workbench_tier", 1))):
		return false
	if not state.unlocked_baits.is_empty() and not state.unlocked_baits.has(bait_id):
		return false
	var ingredients := _ingredients(recipe)
	for item_id in ingredients:
		if state.get_item_count(str(item_id)) < int(ingredients[item_id]) * batches:
			return false
	return true


# 封装 craft_bait 的处理，供相关流程复用。
func craft_bait(bait_id: String, batches: int = 1, now_unix: int = 0, worker_finished: bool = false) -> Dictionary:
	if not can_craft(bait_id, batches):
		return {}
	var state: Variant = _state()
	var recipe := _recipe_for(bait_id)
	var ingredients := _ingredients(recipe)
	for item_id in ingredients:
		state.consume_item(str(item_id), int(ingredients[item_id]) * batches)
	var charges_per_batch := maxi(1, int(recipe.get("charges_per_batch", recipe.get("charges", recipe.get("output_amount", 1)))))
	var current := _now() if now_unix <= 0 else now_unix
	# The worker already spent the recipe time at the bench for player commands.
	# Keep timestamp jobs only for older saves and direct system callers.
	var craft_seconds := 0 if worker_finished else maxi(0, int(ceil(float(recipe.get("craft_seconds", 0.0)))))
	var job := {
		"id": "craft_%s_%s" % [bait_id, current],
		"type": "CRAFT_BAIT",
		"bait_id": bait_id,
		"batches": batches,
		"charges": charges_per_batch * batches,
		"started_at": current,
		"finish_at": current + craft_seconds
	}
	state.crafting_jobs.append(job)
	if craft_seconds == 0:
		_complete_due_jobs(current)
	_request_save()
	return job.duplicate(true)


# 更新后续抛竿的鱼饵选择；进行中的 fishing_cast 保留已消耗的原鱼饵和进度，下一轮由 start_cast 读取新选择。
func select_bait(bait_id: String) -> bool:
	var state: Variant = _state()
	var registry: Variant = _registry()
	if state == null or registry == null:
		return false
	if not bait_id.is_empty() and not registry.has_entry("baits", bait_id) and state.get_item_count(bait_id) <= 0:
		return false
	state.selected_bait = bait_id
	_emit("bait_changed", [bait_id])
	_request_save()
	return true


# 选择 rod，供调用方继续处理。
func select_rod(rod_id: String) -> bool:
	var state: Variant = _state()
	var registry: Variant = _registry()
	if state == null or rod_id.is_empty():
		return false
	if not state.unlocked_rods.is_empty() and not state.unlocked_rods.has(rod_id):
		return false
	if registry != null and not registry.get_all("rods").is_empty() and not registry.has_entry("rods", rod_id):
		return false
	state.selected_rod = rod_id
	_emit("rod_changed", [rod_id])
	_request_save()
	return true


# 读取 next_rod_upgrade，供调用方继续处理。
func get_next_rod_upgrade() -> Dictionary:
	var state: Variant = _state()
	var registry: Variant = _registry()
	if state == null or registry == null:
		return {}
	var rods: Array = registry.get_all("rods")
	rods.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return _rod_tier(left) < _rod_tier(right))
	var highest_tier := 0
	for rod_value in rods:
		var rod: Dictionary = rod_value
		if state.unlocked_rods.has(str(rod.get("id", ""))):
			highest_tier = maxi(highest_tier, _rod_tier(rod))
	for rod_value in rods:
		var rod: Dictionary = rod_value
		if _rod_tier(rod) > highest_tier:
			return rod
	return {}


# 封装 rod_tier 的处理，供相关流程复用。
func _rod_tier(rod: Dictionary) -> int:
	var configured := int(rod.get("tier", 0))
	return configured if configured > 0 else RARITY_ORDER.find(str(rod.get("rarity", "common"))) + 1


# 封装 upgrade_rod 的处理，供相关流程复用。
func upgrade_rod() -> bool:
	var state: Variant = _state()
	var next_rod := get_next_rod_upgrade()
	if state == null or not state.workbench_unlocked or next_rod.is_empty():
		return false
	var cost := maxi(0, int(next_rod.get("upgrade_cost", 0)))
	if not state.spend_coins(cost):
		return false
	var rod_id := str(next_rod.get("id", ""))
	state.unlocked_rods.append(rod_id)
	state.selected_rod = rod_id
	_emit("rod_changed", [rod_id])
	_request_save()
	return true


# 读取 pending_jobs，供调用方继续处理。
func get_pending_jobs() -> Array:
	var state: Variant = _state()
	return state.crafting_jobs.duplicate(true) if state != null else []


# 封装 settle_offline 的处理，供相关流程复用。
func settle_offline(_seconds: int, _from_unix: int, to_unix: int) -> Dictionary:
	return _complete_due_jobs(to_unix)


# 响应 tick 对应的事件或条件。
func _on_tick(now_unix: int, _delta_seconds: int) -> void:
	_complete_due_jobs(now_unix)


# 封装 complete_due_jobs 的处理，供相关流程复用。
func _complete_due_jobs(now_unix: int) -> Dictionary:
	var state: Variant = _state()
	var summary := {"crafted_baits": {}}
	if state == null:
		return summary
	var remaining: Array = []
	for value in state.crafting_jobs:
		if not value is Dictionary:
			continue
		var job: Dictionary = value
		if int(job.get("finish_at", 0)) > now_unix:
			remaining.append(job)
			continue
		var bait_id := str(job.get("bait_id", ""))
		var charges := maxi(1, int(job.get("charges", 1)))
		if not state.workbench_crafted_baits.has(bait_id):
			state.workbench_crafted_baits.append(bait_id)
		DropService.grant_item(bait_id, charges, "workbench", "bait")
		if str(state.selected_bait).is_empty() or state.get_item_count(str(state.selected_bait)) <= 0:
			state.selected_bait = bait_id
			_emit("bait_changed", [bait_id])
		var crafted: Dictionary = summary["crafted_baits"]
		crafted[bait_id] = int(crafted.get(bait_id, 0)) + charges
		_emit("bait_crafted", [bait_id, charges])
		_emit("achievement_action", [state.next_achievement_event_id(), "bait_crafted", {"bait_id": bait_id, "charges": charges}])
	state.crafting_jobs = remaining
	if not summary["crafted_baits"].is_empty():
		_request_save()
	return summary


# 封装 recipe_for 的处理，供相关流程复用。
func _recipe_for(bait_id: String) -> Dictionary:
	var registry: Variant = _registry()
	return registry.get_recipe(bait_id) if registry != null else {}


# 封装 ingredients 的处理，供相关流程复用。
func _ingredients(recipe: Dictionary) -> Dictionary:
	var value = recipe.get("recipe", recipe.get("ingredients", {}))
	return value if value is Dictionary else {}


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
