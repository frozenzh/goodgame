# 定义 AchievementSystem 的状态和可用操作。
class_name AchievementSystem
extends Node

## Permanent local achievements. Successful gameplay actions carry a monotonic
## event id; repeated delivery of the same action cannot advance progress twice.

const STAGES := {"beginner": 0, "development": 1, "formed": 2}
const COUNT_METRICS := ["harvest_successes", "bait_craft_successes", "fish_catch_successes", "fish_sale_successes", "upgraded_rod_catches"]


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.achievement_action.connect(_on_achievement_action)
		bus.game_loaded.connect(_on_game_loaded)
		bus.game_reset.connect(_on_game_reset)
	call_deferred("_reconcile_from_state")


# 读取 entries，供调用方继续处理。
func get_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var registry := get_node_or_null("/root/DataRegistry")
	if registry == null:
		return result
	for value in registry.get_all("achievements"):
		if not value is Dictionary:
			continue
		var entry: Dictionary = value.duplicate(true)
		var id := str(entry.get("id", ""))
		var target := maxi(1, int(entry.get("target", 1)))
		var current := _metric_value(str(entry.get("metric", "")))
		entry["progress"] = mini(current, target)
		entry["raw_progress"] = current
		entry["unlocked"] = _is_unlocked(id)
		var unlock: Dictionary = _unlock_record(id)
		entry["unlocked_at"] = int(unlock.get("unlocked_at", 0))
		entry["migrated"] = bool(unlock.get("migrated", false))
		result.append(entry)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var stage_a := int(STAGES.get(str(a.get("stage", "")), 99))
		var stage_b := int(STAGES.get(str(b.get("stage", "")), 99))
		return int(a.get("sort_order", 0)) < int(b.get("sort_order", 0)) if stage_a == stage_b else stage_a < stage_b
	)
	return result


# 读取 progress_summary，供调用方继续处理。
func get_progress_summary() -> Dictionary:
	var entries := get_entries()
	var complete := 0
	for entry in entries:
		if bool(entry.get("unlocked", false)):
			complete += 1
	return {"unlocked": complete, "total": entries.size()}


# 响应 game_loaded 对应的事件或条件。
func _on_game_loaded() -> void:
	_reconcile_from_state()


# 响应 game_reset 对应的事件或条件。
func _on_game_reset() -> void:
	_reconcile_from_state()


# 封装 reconcile_from_state 的处理，供相关流程复用。
func _reconcile_from_state() -> void:
	var state := get_node_or_null("/root/GameState")
	if state == null:
		return
	var migrated := int(state.achievement_schema_version) < 1
	if migrated:
		_migrate_legacy_progress(state)
		state.achievement_schema_version = 1
	var unlocked := _evaluate_all(migrated)
	if migrated or not unlocked.is_empty():
		_request_save()
	_emit_unlock_batch(unlocked, migrated)


# 响应 achievement_action 对应的事件或条件。
func _on_achievement_action(event_id: int, action: String, payload: Dictionary) -> void:
	var state := get_node_or_null("/root/GameState")
	if state == null or event_id <= int(state.achievement_last_processed_event_id):
		return
	state.achievement_last_processed_event_id = event_id
	state.achievement_event_sequence = maxi(int(state.achievement_event_sequence), event_id)
	var stats: Dictionary = state.achievement_stats
	match action:
		"harvest":
			if not str(payload.get("crop_id", "")).is_empty() and int(payload.get("amount", 0)) > 0:
				_increment(stats, "harvest_successes")
		"bait_crafted":
			var bait_id := str(payload.get("bait_id", ""))
			if not bait_id.is_empty() and int(payload.get("charges", 0)) > 0:
				_increment(stats, "bait_craft_successes")
				var crafted: Array = stats.get("crafted_bait_ids", [])
				if not crafted.has(bait_id):
					crafted.append(bait_id)
				stats["crafted_bait_ids"] = crafted
		"fish_caught":
			if not str(payload.get("fish_id", "")).is_empty():
				_increment(stats, "fish_catch_successes")
				if _is_upgraded_owned_rod(str(payload.get("rod_id", ""))):
					_increment(stats, "upgraded_rod_catches")
		"fish_sold":
			if not str(payload.get("fish_id", "")).is_empty() and int(payload.get("amount", 0)) > 0 and int(payload.get("coins", 0)) > 0:
				_increment(stats, "fish_sale_successes")
		"plot_unlocked", "cottage_completed":
			pass # Read the authoritative completed world state below.
		_:
			return
	var unlocked := _evaluate_all(false)
	_request_save()
	_emit_unlock_batch(unlocked, false)


# 迁移 legacy_progress，供调用方继续处理。
func _migrate_legacy_progress(state: Node) -> void:
	var stats: Dictionary = state.achievement_stats
	var had_harvest: bool = not state.discovered_crops.is_empty()
	for amount in state.harvested_crop_totals.values():
		if int(amount) > 0:
			had_harvest = true
	if had_harvest:
		stats["harvest_successes"] = maxi(1, int(stats.get("harvest_successes", 0)))
	var crafted: Array = stats.get("crafted_bait_ids", [])
	var registry := get_node_or_null("/root/DataRegistry")
	if registry != null:
		var sold_bait_ids: Array[String] = []
		for shop_value in registry.get_all("shop_items"):
			if shop_value is Dictionary and str(shop_value.get("item_type", "bait")) in ["bait", "baits"]:
				sold_bait_ids.append(str(shop_value.get("item_id", shop_value.get("bait_id", ""))))
		for bait_id_value in state.crafted_baits:
			var bait_id := str(bait_id_value)
			var bait: Dictionary = registry.get_bait(bait_id)
			if not bait.is_empty() and bait.get("recipe", {}) is Dictionary and not bait.get("recipe", {}).is_empty() and not bool(bait.get("shop_only", false)) and not sold_bait_ids.has(bait_id) and not crafted.has(bait_id):
				crafted.append(bait_id)
	stats["crafted_bait_ids"] = crafted
	if not crafted.is_empty():
		stats["bait_craft_successes"] = maxi(1, int(stats.get("bait_craft_successes", 0)))
	if not state.discovered_fish.is_empty():
		stats["fish_catch_successes"] = maxi(1, int(stats.get("fish_catch_successes", 0)))
	# Old coin balances and inventory do not prove a sale. Rod ownership does
	# not prove which rod was used for a historical catch.


# 封装 metric_value 的处理，供相关流程复用。
func _metric_value(metric: String) -> int:
	var state := get_node_or_null("/root/GameState")
	if state == null:
		return 0
	match metric:
		"crafted_bait_variety":
			var ids: Array = state.achievement_stats.get("crafted_bait_ids", [])
			return ids.size()
		"fish_species": return state.discovered_fish.size()
		"cottage_level": return int(state.cottage_level)
		"unlocked_plots":
			var count := 0
			for plot_value in state.plots:
				if plot_value is Dictionary and bool(plot_value.get("unlocked", false)):
					count += 1
			return count
		_:
			return maxi(0, int(state.achievement_stats.get(metric, 0))) if COUNT_METRICS.has(metric) else 0


# 封装 evaluate_all 的处理，供相关流程复用。
func _evaluate_all(migrated: bool) -> Array[String]:
	var state := get_node_or_null("/root/GameState")
	var registry := get_node_or_null("/root/DataRegistry")
	var unlocked: Array[String] = []
	if state == null or registry == null:
		return unlocked
	for value in registry.get_all("achievements"):
		if not value is Dictionary:
			continue
		var entry: Dictionary = value
		var id := str(entry.get("id", ""))
		if id.is_empty() or _is_unlocked(id):
			continue
		if _metric_value(str(entry.get("metric", ""))) < maxi(1, int(entry.get("target", 1))):
			continue
		state.achievement_unlocks[id] = {"unlocked_at": 0 if migrated else int(Time.get_unix_time_from_system()), "migrated": migrated}
		unlocked.append(id)
	return unlocked


# 判断是否满足 unlocked 对应的条件。
func _is_unlocked(id: String) -> bool:
	var state := get_node_or_null("/root/GameState")
	return state != null and state.achievement_unlocks.has(id)


# 封装 unlock_record 的处理，供相关流程复用。
func _unlock_record(id: String) -> Dictionary:
	var state := get_node_or_null("/root/GameState")
	if state == null:
		return {}
	var value: Variant = state.achievement_unlocks.get(id, {})
	return value if value is Dictionary else {}


# 判断是否满足 upgraded_owned_rod 对应的条件。
func _is_upgraded_owned_rod(rod_id: String) -> bool:
	var state := get_node_or_null("/root/GameState")
	var registry := get_node_or_null("/root/DataRegistry")
	if state == null or registry == null or rod_id.is_empty() or not state.unlocked_rods.has(rod_id):
		return false
	var rod: Dictionary = registry.get_rod(rod_id)
	return not rod.is_empty() and int(rod.get("tier", 1)) > 1


# 封装 increment 的处理，供相关流程复用。
func _increment(stats: Dictionary, key: String) -> void:
	stats[key] = maxi(0, int(stats.get(key, 0))) + 1


# 发出 unlock_batch，供调用方继续处理。
func _emit_unlock_batch(ids: Array[String], migrated: bool) -> void:
	if ids.is_empty():
		return
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.achievements_unlocked.emit(ids, migrated)


# 请求 save，供调用方继续处理。
func _request_save() -> void:
	var saver := get_node_or_null("/root/SaveManager")
	if saver != null:
		saver.request_save()
