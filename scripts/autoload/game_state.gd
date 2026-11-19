extends Node

## Authoritative mutable state. Systems validate rules and mutate state through
## these small helpers so UI can observe one consistent event stream.

const DEFAULT_PLOT_COUNT := 7
const DEFAULT_UNLOCKED_PLOT_COUNT := 2
const CROP_IDS := ["wheat", "corn", "carrot", "white_radish", "strawberry", "tomato", "cabbage", "lettuce"]
const BAIT_IDS := ["wheat_bait", "corn_bait", "carrot_bait", "white_radish_bait", "strawberry_bait", "tomato_bait", "cabbage_bait", "lettuce_bait"]

@onready var GameConfig: Node = get_node("/root/GameConfig")
var coins := 0
var fish_fertilizer := 0
var inventory: Dictionary = {}
var fish_basket: Dictionary = {}
var fish_size_records: Dictionary = {}
var leaderboard_pending: Array = []
var plots: Array = []
var pond_level := 1
var cottage_level := 1
var workbench_unlocked := false
var shop_unlocked := false
var shop_level := 1
var shop_offers: Array = []
var shop_refresh_at := 0
var selected_bait := ""
var selected_rod := "basic_rod"
var discovered_crops: Array = []
var crafted_baits: Array = []
var workbench_crafted_baits: Array = []
var discovered_fish: Array = []
var codex_milestones: Array = []
var unlocked_crops: Array = []
var harvested_crop_totals: Dictionary = {}
var unlocked_baits: Array = []
var unlocked_rods: Array = []
var owned_upgrades: Array = []
var crafting_jobs: Array = []
var fishing_cast: Dictionary = {}
var weather_state: Dictionary = {}
var base_fish_interval_seconds := 18
var last_save_unix := 0
var playtime_seconds := 0.0
var flags: Dictionary = {}
var settings: Dictionary = {}
var achievement_stats: Dictionary = {}
var achievement_unlocks: Dictionary = {}
var achievement_event_sequence := 0
var achievement_last_processed_event_id := 0
var achievement_schema_version := 1


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	if plots.is_empty():
		reset_to_defaults(false)


# 重置 to_defaults，供调用方继续处理。
func reset_to_defaults(emit_event := true) -> void:
	playtime_seconds = 0.0
	coins = 0
	fish_fertilizer = 0
	inventory = {}
	fish_basket = {}
	fish_size_records = {}
	leaderboard_pending = []
	plots = []
	for index in range(DEFAULT_PLOT_COUNT):
		plots.append({
			"id": str(index),
			"unlocked": _is_default_plot_unlocked(index),
			"crop": "",
			"planted_at": 0,
			"mature_at": 0,
			"mutation": {},
			"fertility": 0,
			"planned_crop": ""
		})
	pond_level = 1
	cottage_level = 1
	workbench_unlocked = false
	shop_unlocked = false
	shop_level = 1
	shop_offers = []
	shop_refresh_at = 0
	selected_bait = ""
	selected_rod = "basic_rod"
	discovered_crops = []
	crafted_baits = []
	workbench_crafted_baits = []
	discovered_fish = []
	codex_milestones = []
	unlocked_crops = _initially_unlocked_crop_ids()
	harvested_crop_totals = {}
	unlocked_baits = BAIT_IDS.duplicate()
	unlocked_rods = ["basic_rod"]
	owned_upgrades = []
	crafting_jobs = []
	fishing_cast = {}
	weather_state = {}
	base_fish_interval_seconds = 18
	last_save_unix = 0
	flags = {}
	settings = {"idle_auto_fish": false, "always_on_top": false, "always_on_top_user_set": false}
	settings["weather_effect_mode"] = "standard"
	settings["weather_ambient_enabled"] = true
	achievement_stats = _default_achievement_stats()
	achievement_unlocks = {}
	achievement_event_sequence = 0
	achievement_last_processed_event_id = 0
	achievement_schema_version = 1
	_apply_initial_document()
	_sync_crop_bait_unlocks()
	if emit_event:
		_emit("game_reset")


# 读取 item_count，供调用方继续处理。
func get_item_count(item_id: String) -> int:
	return maxi(0, int(inventory.get(item_id, 0)))


# 读取 cottage_data，供调用方继续处理。
func get_cottage_data(level: int = 0) -> Dictionary:
	var registry := get_node_or_null("/root/DataRegistry")
	if registry == null:
		return {}
	return registry.get_entry("cottage_levels", str(cottage_level if level <= 0 else level))


# 读取 warehouse_capacity，供调用方继续处理。
func get_warehouse_capacity() -> int:
	return maxi(0, int(get_cottage_data().get("storage_capacity", 0)))


# 读取 warehouse_used，供调用方继续处理。
func get_warehouse_used() -> int:
	var total := 0
	for crop_id in _catalog_crop_ids():
		total += get_item_count(crop_id)
	return total


# 检查是否允许 store_crop 对应的条件。
func can_store_crop(amount: int) -> bool:
	return amount > 0 and get_warehouse_used() + amount <= get_warehouse_capacity()


# 读取 workbench_tier，供调用方继续处理。
func get_workbench_tier() -> int:
	return maxi(1, int(get_cottage_data().get("workbench_tier", 1)))


# 判断是否满足 workbench_construction_ready 对应的条件。
func is_workbench_construction_ready() -> bool:
	return not workbench_unlocked and not discovered_crops.is_empty()


# 判断是否满足 shop_construction_ready 对应的条件。
func is_shop_construction_ready() -> bool:
	return not shop_unlocked and not discovered_fish.is_empty()


# 读取 next_cottage_upgrade_cost，供调用方继续处理。
func get_next_cottage_upgrade_cost() -> int:
	var next_data := get_cottage_data(cottage_level + 1)
	return maxi(0, int(next_data.get("upgrade_cost", 0))) if not next_data.is_empty() else -1


# 读取 cottage_construction，供调用方继续处理。
func get_cottage_construction() -> Dictionary:
	var value: Variant = flags.get("cottage_construction", {})
	return value if value is Dictionary else {}


# 判断是否满足 cottage_construction_ready 对应的条件。
func is_cottage_construction_ready(now_unix: int = 0) -> bool:
	var construction := get_cottage_construction()
	if construction.is_empty():
		return false
	var current := int(Time.get_unix_time_from_system()) if now_unix <= 0 else now_unix
	return current >= int(construction.get("ready_at", 0))


# 添加 item，供调用方继续处理。
func add_item(item_id: String, amount: int) -> int:
	if item_id.is_empty() or amount <= 0:
		return get_item_count(item_id)
	var total := get_item_count(item_id) + amount
	inventory[item_id] = total
	_emit("inventory_changed", [item_id, amount, total])
	return total


# 封装 record_crop_harvest 的处理，供相关流程复用。
func record_crop_harvest(crop_id: String, amount: int) -> void:
	if crop_id.is_empty() or amount <= 0:
		return
	harvested_crop_totals[crop_id] = maxi(0, int(harvested_crop_totals.get(crop_id, 0))) + amount
	for unlocked_id in _unlock_crops_from_progress():
		_emit("crop_unlocked", [unlocked_id])


# 封装 consume_item 的处理，供相关流程复用。
func consume_item(item_id: String, amount: int) -> bool:
	if item_id.is_empty() or amount <= 0 or get_item_count(item_id) < amount:
		return false
	var total := get_item_count(item_id) - amount
	if total == 0:
		inventory.erase(item_id)
	else:
		inventory[item_id] = total
	_emit("inventory_changed", [item_id, -amount, total])
	return true


# 添加 fish，供调用方继续处理。
func add_fish(fish_id: String, amount: int = 1) -> int:
	if fish_id.is_empty() or amount <= 0:
		return get_fish_count(fish_id)
	var total := get_fish_count(fish_id) + amount
	fish_basket[fish_id] = total
	_emit("fish_basket_changed", [fish_id, amount, total])
	return total


# 读取 fish_count，供调用方继续处理。
func get_fish_count(fish_id: String) -> int:
	return maxi(0, int(fish_basket.get(fish_id, 0)))


# 移除 fish，供调用方继续处理。
func remove_fish(fish_id: String, amount: int) -> bool:
	if fish_id.is_empty() or amount <= 0 or get_fish_count(fish_id) < amount:
		return false
	var total := get_fish_count(fish_id) - amount
	if total == 0:
		fish_basket.erase(fish_id)
	else:
		fish_basket[fish_id] = total
	_emit("fish_basket_changed", [fish_id, -amount, total])
	return true


# 添加 coins，供调用方继续处理。
func add_coins(amount: int) -> int:
	if amount <= 0:
		return coins
	coins += amount
	_emit("resource_changed", ["coins", coins])
	return coins


# 封装 spend_coins 的处理，供相关流程复用。
func spend_coins(amount: int) -> bool:
	if amount < 0 or coins < amount:
		return false
	coins -= amount
	_emit("resource_changed", ["coins", coins])
	return true


# 添加 fertilizer，供调用方继续处理。
func add_fertilizer(amount: int) -> int:
	if amount <= 0:
		return fish_fertilizer
	fish_fertilizer += amount
	_emit("resource_changed", ["fish_fertilizer", fish_fertilizer])
	return fish_fertilizer


# 封装 spend_fertilizer 的处理，供相关流程复用。
func spend_fertilizer(amount: int) -> bool:
	if amount < 0 or fish_fertilizer < amount:
		return false
	fish_fertilizer -= amount
	_emit("resource_changed", ["fish_fertilizer", fish_fertilizer])
	return true


# 读取 plot，供调用方继续处理。
func get_plot(plot_id: Variant) -> Dictionary:
	var wanted := _normalize_plot_id(plot_id)
	for value in plots:
		if value is Dictionary and _normalize_plot_id(value.get("id", "")) == wanted:
			return value
	return {}


# 封装 discover 的处理，供相关流程复用。
func discover(entry_type: String, entry_id: String) -> bool:
	var target: Array
	match entry_type:
		"crop", "crops": target = discovered_crops
		"bait", "baits": target = crafted_baits
		"fish": target = discovered_fish
		_: return false
	if target.has(entry_id):
		return false
	target.append(entry_id)
	return true


# 封装 next_achievement_event_id 的处理，供相关流程复用。
func next_achievement_event_id() -> int:
	achievement_event_sequence += 1
	return achievement_event_sequence


# 封装 default_achievement_stats 的处理，供相关流程复用。
func _default_achievement_stats() -> Dictionary:
	return {
		"harvest_successes": 0,
		"bait_craft_successes": 0,
		"fish_catch_successes": 0,
		"fish_sale_successes": 0,
		"upgraded_rod_catches": 0,
		"crafted_bait_ids": []
	}


# 封装 to_save_data 的处理，供相关流程复用。
func to_save_data() -> Dictionary:
	# A cast only exists while the game is running. A save may happen mid-cast,
	# so return its paid bait in the snapshot without changing the live session.
	var saved_inventory: Dictionary = inventory.duplicate(true)
	_refund_unfinished_cast(saved_inventory, fishing_cast)
	return {
		"coins": coins,
		"fish_fertilizer": fish_fertilizer,
		"inventory": saved_inventory,
		"fish_basket": fish_basket.duplicate(true),
		"fish_size_records": fish_size_records.duplicate(true),
		"leaderboard_pending": leaderboard_pending.duplicate(true),
		"plots": plots.duplicate(true),
		"pond_level": pond_level,
		"cottage_level": cottage_level,
		"workbench_unlocked": workbench_unlocked,
		"shop_unlocked": shop_unlocked,
		"shop_level": shop_level,
		"shop_offers": shop_offers.duplicate(true),
		"shop_refresh_at": shop_refresh_at,
		"selected_bait": selected_bait,
		"selected_rod": selected_rod,
		"discovered_crops": discovered_crops.duplicate(),
		"crafted_baits": crafted_baits.duplicate(),
		"workbench_crafted_baits": workbench_crafted_baits.duplicate(),
		"discovered_fish": discovered_fish.duplicate(),
		"codex_milestones": codex_milestones.duplicate(true),
		"unlocked_crops": unlocked_crops.duplicate(),
		"harvested_crop_totals": harvested_crop_totals.duplicate(true),
		"unlocked_baits": unlocked_baits.duplicate(),
		"unlocked_rods": unlocked_rods.duplicate(),
		"owned_upgrades": owned_upgrades.duplicate(),
		"crafting_jobs": crafting_jobs.duplicate(true),
		"fishing_cast": {},
		"weather_state": weather_state.duplicate(true),
		"base_fish_interval_seconds": base_fish_interval_seconds,
		"last_save_unix": last_save_unix,
		"playtime_seconds": floori(playtime_seconds),
		"flags": _flags_without_fishing_session(flags),
		"settings": settings.duplicate(true),
		"achievement_stats": achievement_stats.duplicate(true),
		"achievement_unlocks": achievement_unlocks.duplicate(true),
		"achievement_event_sequence": achievement_event_sequence,
		"achievement_last_processed_event_id": achievement_last_processed_event_id,
		"achievement_schema_version": achievement_schema_version
	}


# 加载 save_data，供调用方继续处理。
func load_save_data(data: Dictionary) -> void:
	reset_to_defaults(false)
	playtime_seconds = maxf(0.0, float(data.get("playtime_seconds", 0)))
	coins = maxi(0, int(data.get("coins", coins)))
	fish_fertilizer = maxi(0, int(data.get("fish_fertilizer", fish_fertilizer)))
	inventory = _sanitize_count_dictionary(data.get("inventory", {}))
	fish_basket = _sanitize_count_dictionary(data.get("fish_basket", {}))
	fish_size_records = data.get("fish_size_records", {}).duplicate(true) if data.get("fish_size_records") is Dictionary else {}
	leaderboard_pending = data.get("leaderboard_pending", []).duplicate(true) if data.get("leaderboard_pending") is Array else []
	if data.get("plots") is Array:
		plots = _sanitize_plots(data["plots"])
	pond_level = maxi(1, int(data.get("pond_level", pond_level)))
	cottage_level = clampi(int(data.get("cottage_level", cottage_level)), 1, 4)
	shop_level = clampi(int(data.get("shop_level", 1)), 1, 3)
	shop_offers = data.get("shop_offers", []).duplicate(true) if data.get("shop_offers") is Array else []
	shop_refresh_at = maxi(0, int(data.get("shop_refresh_at", 0)))
	selected_bait = str(data.get("selected_bait", selected_bait))
	selected_rod = str(data.get("selected_rod", selected_rod))
	discovered_crops = _sanitize_string_array(data.get("discovered_crops", []))
	crafted_baits = _sanitize_string_array(data.get("crafted_baits", []))
	discovered_fish = _sanitize_string_array(data.get("discovered_fish", []))
	workbench_unlocked = bool(data.get("workbench_unlocked", false)) and not discovered_crops.is_empty()
	shop_unlocked = bool(data.get("shop_unlocked", false)) and not discovered_fish.is_empty()
	codex_milestones = data.get("codex_milestones", []).duplicate(true) if data.get("codex_milestones") is Array else []
	if codex_milestones.is_empty() and data.get("claimed_codex_milestones") is Array:
		codex_milestones = data["claimed_codex_milestones"].duplicate(true)
	unlocked_crops = _sanitize_string_array(data.get("unlocked_crops", unlocked_crops))
	_merge_initial_crop_unlocks()
	harvested_crop_totals = _sanitize_count_dictionary(data.get("harvested_crop_totals", {}))
	unlocked_baits = _sanitize_string_array(data.get("unlocked_baits", unlocked_baits))
	_sync_cottage_unlocks()
	_unlock_crops_from_progress()
	_sync_crop_bait_unlocks()
	unlocked_rods = _sanitize_string_array(data.get("unlocked_rods", unlocked_rods))
	owned_upgrades = _sanitize_string_array(data.get("owned_upgrades", []))
	crafting_jobs = data.get("crafting_jobs", []).duplicate(true) if data.get("crafting_jobs") is Array else []
	fishing_cast = data.get("fishing_cast", {}).duplicate(true) if data.get("fishing_cast") is Dictionary else {}
	weather_state = data.get("weather_state", {}).duplicate(true) if data.get("weather_state") is Dictionary else {}
	# Repair older saves which persisted a live cast and an active worker state.
	_refund_unfinished_cast(inventory, fishing_cast)
	fishing_cast.clear()
	base_fish_interval_seconds = maxi(1, int(data.get("base_fish_interval_seconds", base_fish_interval_seconds)))
	last_save_unix = maxi(0, int(data.get("last_save_unix", 0)))
	flags = _flags_without_fishing_session(data.get("flags", {}) if data.get("flags") is Dictionary else {})
	# 旧存档已卖过鱼时补认一次性开启已完成，保留其已有勾选；缺省设置按是否卖过鱼恢复。
	if not flags.has("idle_auto_fish_first_sale_done"):
		var old_stats: Dictionary = data.get("achievement_stats", {}) if data.get("achievement_stats") is Dictionary else {}
		flags["idle_auto_fish_first_sale_done"] = int(old_stats.get("fish_sale_successes", 0)) > 0 or bool(flags.get("tutorial_first_fish_sale_done", false))
	settings = data.get("settings", {}).duplicate(true) if data.get("settings") is Dictionary else {}
	if not settings.has("idle_auto_fish"):
		settings["idle_auto_fish"] = bool(flags.get("idle_auto_fish_first_sale_done", false))
	# Older saves inherited always_on_top=true from the original initial_state,
	# even if the player never selected it. Migrate those saves to the new default.
	if not settings.has("always_on_top_user_set"):
		settings["always_on_top"] = false
		settings["always_on_top_user_set"] = false
	if not settings.has("always_on_top"):
		settings["always_on_top"] = false
	if str(settings.get("weather_effect_mode", "standard")) not in ["standard", "low", "off"]:
		settings["weather_effect_mode"] = "standard"
	if not settings.has("weather_ambient_enabled"):
		settings["weather_ambient_enabled"] = true
	var saved_stats: Dictionary = data.get("achievement_stats", {}) if data.get("achievement_stats") is Dictionary else {}
	achievement_stats = _default_achievement_stats()
	for key in ["harvest_successes", "bait_craft_successes", "fish_catch_successes", "fish_sale_successes", "upgraded_rod_catches"]:
		achievement_stats[key] = maxi(0, int(saved_stats.get(key, 0)))
	achievement_stats["crafted_bait_ids"] = _sanitize_string_array(saved_stats.get("crafted_bait_ids", []))
	workbench_crafted_baits = _sanitize_string_array(data.get("workbench_crafted_baits", achievement_stats["crafted_bait_ids"]))
	achievement_unlocks = data.get("achievement_unlocks", {}).duplicate(true) if data.get("achievement_unlocks") is Dictionary else {}
	achievement_event_sequence = maxi(0, int(data.get("achievement_event_sequence", 0)))
	achievement_last_processed_event_id = clampi(int(data.get("achievement_last_processed_event_id", 0)), 0, achievement_event_sequence)
	achievement_schema_version = maxi(0, int(data.get("achievement_schema_version", 0)))


# 封装 refund_unfinished_cast 的处理，供相关流程复用。
func _refund_unfinished_cast(target_inventory: Dictionary, cast: Dictionary) -> void:
	if cast.is_empty():
		return
	var bait_id := str(cast.get("bait_id", ""))
	if not bait_id.is_empty():
		target_inventory[bait_id] = maxi(0, int(target_inventory.get(bait_id, 0))) + 1


# 封装 flags_without_fishing_session 的处理，供相关流程复用。
func _flags_without_fishing_session(source: Dictionary) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	result["fishing_active"] = false
	result["fishing_started_by_idle"] = false
	var pending: Variant = result.get("worker_commands", [])
	if pending is Array:
		var retained: Array = []
		for command in pending:
			if command is Dictionary and str(command.get("action", "")) in ["start_fishing", "stop_fishing", "select_bait"]:
				continue
			retained.append(command)
		result["worker_commands"] = retained
	return result


# 应用 initial_document，供调用方继续处理。
func _apply_initial_document() -> void:
	var registry = get_node_or_null("/root/DataRegistry")
	if registry == null or not registry.has_method("get_document"):
		return
	var initial: Dictionary = registry.get_document("initial_state")
	if initial.is_empty():
		return
	coins = maxi(0, int(initial.get("coins", coins)))
	inventory = _sanitize_count_dictionary(initial.get("inventory", inventory))
	fish_basket = _sanitize_count_dictionary(initial.get("fish_basket", fish_basket))
	if initial.get("plots") is Array:
		plots = _sanitize_plots(initial["plots"])
	pond_level = maxi(1, int(initial.get("pond_level", pond_level)))
	cottage_level = clampi(int(initial.get("cottage_level", cottage_level)), 1, 4)
	workbench_unlocked = bool(initial.get("workbench_unlocked", false))
	shop_unlocked = bool(initial.get("shop_unlocked", false))
	selected_bait = str(initial.get("selected_bait", selected_bait))
	selected_rod = str(initial.get("selected_rod", selected_rod))
	unlocked_crops = _initially_unlocked_crop_ids()
	unlocked_baits = _sanitize_string_array(initial.get("unlocked_baits", unlocked_baits))
	_sync_cottage_unlocks()
	unlocked_rods = _sanitize_string_array(initial.get("unlocked_rods", unlocked_rods))
	base_fish_interval_seconds = maxi(1, int(initial.get("base_fish_interval_seconds", base_fish_interval_seconds)))
	flags = initial.get("flags", {}).duplicate(true) if initial.get("flags") is Dictionary else {}
	settings = initial.get("settings", {}).duplicate(true) if initial.get("settings") is Dictionary else {}
	weather_state = initial.get("weather_state", {}).duplicate(true) if initial.get("weather_state") is Dictionary else {}
	if not settings.has("idle_auto_fish"):
		settings["idle_auto_fish"] = false
	if not settings.has("always_on_top"):
		settings["always_on_top"] = false
	if not settings.has("always_on_top_user_set"):
		settings["always_on_top_user_set"] = false
	if not settings.has("weather_effect_mode"):
		settings["weather_effect_mode"] = "standard"
	if not settings.has("weather_ambient_enabled"):
		settings["weather_ambient_enabled"] = true


# 封装 catalog_crop_ids 的处理，供相关流程复用。
func _catalog_crop_ids() -> Array[String]:
	var registry := get_node_or_null("/root/DataRegistry")
	var result: Array[String] = []
	if registry == null:
		for crop_id in CROP_IDS:
			result.append(crop_id)
		return result
	for crop in registry.get_all("crops"):
		if crop is Dictionary:
			result.append(str(crop.get("id", "")))
	return result


# 封装 initially_unlocked_crop_ids 的处理，供相关流程复用。
func _initially_unlocked_crop_ids() -> Array[String]:
	var registry := get_node_or_null("/root/DataRegistry")
	var result: Array[String] = []
	if registry == null:
		for crop_id in CROP_IDS:
			result.append(crop_id)
		return result
	for crop in registry.get_all("crops"):
		if crop is Dictionary and bool(crop.get("initially_unlocked", true)):
			result.append(str(crop.get("id", "")))
	return result


# 封装 merge_initial_crop_unlocks 的处理，供相关流程复用。
func _merge_initial_crop_unlocks() -> void:
	for crop_id in _initially_unlocked_crop_ids():
		if not unlocked_crops.has(crop_id):
			unlocked_crops.append(crop_id)


# 封装 unlock_crops_from_progress 的处理，供相关流程复用。
func _unlock_crops_from_progress() -> Array[String]:
	var result: Array[String] = []
	var registry := get_node_or_null("/root/DataRegistry")
	if registry == null:
		return result
	for crop_value in registry.get_all("crops"):
		if not crop_value is Dictionary:
			continue
		var crop: Dictionary = crop_value
		var crop_id := str(crop.get("id", ""))
		if crop_id.is_empty() or unlocked_crops.has(crop_id):
			continue
		var requirements: Array = crop.get("unlock_requirements", [])
		if requirements.is_empty():
			continue
		var ready := true
		for requirement_value in requirements:
			var requirement: Dictionary = requirement_value
			var source_id := str(requirement.get("crop_id", ""))
			if int(harvested_crop_totals.get(source_id, 0)) < int(requirement.get("harvest_amount", 0)):
				ready = false
				break
		if ready:
			unlocked_crops.append(crop_id)
			result.append(crop_id)
	_sync_crop_bait_unlocks()
	return result


# 同步 crop_bait_unlocks，供调用方继续处理。
func _sync_crop_bait_unlocks() -> void:
	var registry := get_node_or_null("/root/DataRegistry")
	if registry == null:
		return
	for crop_id in unlocked_crops:
		var crop: Dictionary = registry.get_crop(str(crop_id))
		for bait_id in crop.get("bait_links", []):
			if not unlocked_baits.has(str(bait_id)):
				unlocked_baits.append(str(bait_id))


# 同步 cottage_unlocks，供调用方继续处理。
func _sync_cottage_unlocks() -> void:
	for level in range(1, cottage_level + 1):
		var level_data := get_cottage_data(level)
		for bait_id in level_data.get("unlock_baits", []):
			if not unlocked_baits.has(str(bait_id)):
				unlocked_baits.append(str(bait_id))


# 封装 sanitize_count_dictionary 的处理，供相关流程复用。
func _sanitize_count_dictionary(value: Variant) -> Dictionary:
	var result := {}
	if not value is Dictionary:
		return result
	for key in value:
		var count := maxi(0, int(value[key]))
		if count > 0:
			result[str(key)] = count
	return result


# 封装 sanitize_string_array 的处理，供相关流程复用。
func _sanitize_string_array(value: Variant) -> Array:
	var result: Array = []
	if value is Array:
		for item in value:
			var text := str(item)
			if not text.is_empty() and not result.has(text):
				result.append(text)
	return result


# 封装 sanitize_plots 的处理，供相关流程复用。
func _sanitize_plots(value: Array) -> Array:
	var result: Array = []
	for index in range(mini(value.size(), DEFAULT_PLOT_COUNT)):
		if not value[index] is Dictionary:
			continue
		var source: Dictionary = value[index]
		result.append({
			"id": _normalize_plot_id(source.get("id", source.get("plot_id", index))),
			"unlocked": bool(source.get("unlocked", false)),
			"crop": str(source.get("crop", source.get("crop_id", ""))),
			"planted_at": maxi(0, int(source.get("planted_at", 0))),
			"mature_at": maxi(0, int(source.get("mature_at", 0))),
			"mutation": _sanitize_mutation(source.get("mutation", {})),
			"fertility": clampi(int(source.get("fertility", source.get("fertility_level", 0))), 0, GameConfig.get_int("farming", "max_fertility")),
			"planned_crop": str(source.get("planned_crop", "")),
			"cells": _sanitize_plot_cells(source)
		})
	for index in range(result.size(), DEFAULT_PLOT_COUNT):
		result.append({"id": str(index), "unlocked": _is_default_plot_unlocked(index), "crop": "", "planted_at": 0, "mature_at": 0, "mutation": {}, "fertility": 0, "planned_crop": "", "cells": _sanitize_plot_cells({})})
	return result


# 封装 sanitize_plot_cells 的处理，供相关流程复用。
func _sanitize_plot_cells(source: Dictionary) -> Array:
	var saved: Array = source.get("cells", []) if source.get("cells", []) is Array else []
	var cells: Array = []
	for index in range(9):
		var cell: Dictionary = saved[index] if index < saved.size() and saved[index] is Dictionary else source
		var planted_at := maxi(0, int(cell.get("planted_at", 0)))
		var mature_at := maxi(0, int(cell.get("mature_at", 0)))
		var legacy_midpoint := planted_at + maxi(1, floori(float(mature_at - planted_at) / 2.0)) if mature_at > planted_at else 0
		cells.append({
			"crop": str(cell.get("crop", cell.get("crop_id", ""))),
			"planted_at": planted_at,
			"leaf_at": maxi(0, int(cell.get("leaf_at", legacy_midpoint))),
			"mature_at": mature_at,
			"watered_seed": bool(cell.get("watered_seed", false)),
			"watered_leaf": bool(cell.get("watered_leaf", false)),
			"grouped": bool(cell.get("grouped", true)),
			"planned_crop": str(cell.get("planned_crop", source.get("planned_crop", "")))
		})
	return cells


# 封装 sanitize_mutation 的处理，供相关流程复用。
func _sanitize_mutation(value: Variant) -> Dictionary:
	if not value is Dictionary or not bool(value.get("active", false)):
		return {}
	return {"active": true, "column": clampi(int(value.get("column", 0)), 0, 2), "start_row": clampi(int(value.get("start_row", 0)), 0, 1)}


# 判断是否满足 default_plot_unlocked 对应的条件。
func _is_default_plot_unlocked(index: int) -> bool:
	return index >= DEFAULT_PLOT_COUNT - DEFAULT_UNLOCKED_PLOT_COUNT and index < DEFAULT_PLOT_COUNT


# 规范化 plot_id，供调用方继续处理。
func _normalize_plot_id(value: Variant) -> String:
	if value is int or value is float:
		return str(int(value))
	var text := str(value)
	if text.is_valid_float():
		return str(int(float(text)))
	return text


# 封装 emit 的处理，供相关流程复用。
func _emit(signal_name: String, arguments: Array = []) -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus != null and bus.has_signal(signal_name):
		_emit_variable(bus, signal_name, arguments)


# 发出 variable，供调用方继续处理。
func _emit_variable(bus: Node, signal_name: String, arguments: Array) -> void:
	match arguments.size():
		0: bus.emit_signal(signal_name)
		1: bus.emit_signal(signal_name, arguments[0])
		2: bus.emit_signal(signal_name, arguments[0], arguments[1])
		3: bus.emit_signal(signal_name, arguments[0], arguments[1], arguments[2])
