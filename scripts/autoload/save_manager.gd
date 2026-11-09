extends Node

## Single-slot JSON save with Excel-configured debounce and autosave timing.

const SAVE_VERSION := 10
const PLOT_COUNT := 7
const DEFAULT_UNLOCKED_START_INDEX := 5
const SAVE_PATH := "user://save.json"
@onready var GameConfig: Node = get_node("/root/GameConfig")
var _autosave_timer: Timer
var _debounce_timer: Timer
var _is_bootstrapped := false
var startup_choice_done := false


# 判断是否具有 saved_game 对应的条件。
func has_saved_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	return file != null and JSON.parse_string(file.get_as_text()) is Dictionary


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	_autosave_timer = Timer.new()
	_autosave_timer.name = "AutosaveTimer"
	_autosave_timer.wait_time = GameConfig.get_float("time_save", "autosave_seconds")
	_autosave_timer.autostart = true
	_autosave_timer.timeout.connect(save_game)
	add_child(_autosave_timer)

	_debounce_timer = Timer.new()
	_debounce_timer.name = "SaveDebounceTimer"
	_debounce_timer.wait_time = GameConfig.get_float("time_save", "debounce_seconds")
	_debounce_timer.one_shot = true
	_debounce_timer.timeout.connect(save_game)
	add_child(_debounce_timer)
	call_deferred("_bootstrap")


# 封装 bootstrap 的处理，供相关流程复用。
func _bootstrap() -> void:
	if _is_bootstrapped:
		return
	_is_bootstrapped = true
	load_game()


# 请求 save，供调用方继续处理。
func request_save(delay_seconds: float = -1.0) -> void:
	if _debounce_timer == null:
		return
	var requested: float = GameConfig.get_float("time_save", "debounce_seconds") if delay_seconds < 0.0 else delay_seconds
	_debounce_timer.start(maxf(GameConfig.get_float("time_save", "minimum_debounce_seconds"), requested))


# 保存 game，供调用方继续处理。
func save_game() -> bool:
	var state = get_node_or_null("/root/GameState")
	if state == null or not state.has_method("to_save_data"):
		return false
	var now := int(Time.get_unix_time_from_system())
	state.last_save_unix = now
	var data: Dictionary = state.to_save_data()
	data["save_version"] = SAVE_VERSION
	data["last_save_unix"] = now
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Unable to open save file: %s" % SAVE_PATH)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	_emit("game_saved")
	return true


# 加载 game，供调用方继续处理。
func load_game() -> bool:
	var state = get_node_or_null("/root/GameState")
	if state == null:
		push_error("GameState must be loaded before SaveManager")
		return false
	var loaded := false
	if FileAccess.file_exists(SAVE_PATH):
		var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if file != null:
			var parsed = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				var data := _migrate_save(parsed)
				state.load_save_data(data)
				loaded = true
			else:
				push_error("Save file is not valid JSON; defaults kept")
	var time_manager = get_node_or_null("/root/TimeManager")
	if loaded and int(state.last_save_unix) > 0 and time_manager != null and time_manager.has_method("prepare_offline"):
		time_manager.prepare_offline(int(state.last_save_unix))
	_emit("game_loaded")
	return loaded


# 删除 save_and_reset，供调用方继续处理。
func delete_save_and_reset() -> bool:
	if FileAccess.file_exists(SAVE_PATH):
		var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		if error != OK:
			return false
	var state = get_node_or_null("/root/GameState")
	if state != null and state.has_method("reset_to_defaults"):
		state.reset_to_defaults()
	return save_game()


# 迁移 save，供调用方继续处理。
func _migrate_save(source: Dictionary) -> Dictionary:
	var data := source.duplicate(true)
	var version := int(data.get("save_version", 1))
	if version < 2:
		if not data.has("fish_basket"):
			data["fish_basket"] = {}
		if not data.has("shop_unlocked"):
			data["shop_unlocked"] = false
	if version < 3:
		if not data.has("fish_fertilizer"):
			data["fish_fertilizer"] = 0
		if not data.has("crafted_baits"):
			data["crafted_baits"] = data.get("discovered_baits", [])
		if not data.has("crafting_jobs"):
			data["crafting_jobs"] = []
	if version < 4:
		data["plots"] = _migrate_eight_plot_layout(data.get("plots", []))
		var upgrades_v4: Array = data.get("owned_upgrades", []) if data.get("owned_upgrades", []) is Array else []
		data["owned_upgrades"] = upgrades_v4.filter(func(id): return not str(id).begins_with("unlock_plot"))
	if version < 5:
		data["plots"] = _migrate_seven_plot_layout()
		var upgrades_v5: Array = data.get("owned_upgrades", []) if data.get("owned_upgrades", []) is Array else []
		data["owned_upgrades"] = upgrades_v5.filter(func(id): return not str(id).begins_with("unlock_plot"))
	if version < 6:
		_migrate_fishing_catalog(data)
	if version < 7 and data.get("shop_offers", []) is Array and not data.get("shop_offers", []).is_empty():
		# Existing offers were created with a four-hour expiry. Keep the same
		# offers but extend their original deadline to the new six-hour cycle.
		var previous_refresh := int(data.get("shop_refresh_at", 0))
		if previous_refresh > 0:
			data["shop_refresh_at"] = previous_refresh + 2 * 3600
	if version < 8:
		var known_crops: Array = data.get("discovered_crops", []) if data.get("discovered_crops") is Array else []
		var known_fish: Array = data.get("discovered_fish", []) if data.get("discovered_fish") is Array else []
		# Existing players keep facilities they could already use, once their
		# corresponding first discovery is present in the old save.
		data["workbench_unlocked"] = not known_crops.is_empty()
		data["shop_unlocked"] = bool(data.get("shop_unlocked", false)) and not known_fish.is_empty()
	if version < 9:
		data["weather_state"] = {}
		var saved_settings: Dictionary = data.get("settings", {}) if data.get("settings") is Dictionary else {}
		if not saved_settings.has("weather_effect_mode"):
			saved_settings["weather_effect_mode"] = "standard"
		if not saved_settings.has("weather_ambient_enabled"):
			saved_settings["weather_ambient_enabled"] = true
		data["settings"] = saved_settings
	data["save_version"] = SAVE_VERSION
	return data


# 迁移 fishing_catalog，供调用方继续处理。
func _migrate_fishing_catalog(data: Dictionary) -> void:
	var bait_ids := {
		"dough_bait": "wheat_bait", "garden_mash_bait": "cabbage_bait",
		"sweet_corn_bait": "corn_bait", "starlight_worm_bait": "strawberry_bait"
	}
	var fish_ids := {
		"crucian": "fish_001", "loach": "fish_002", "carp": "fish_004",
		"perch": "fish_012", "catfish": "fish_015", "grass_carp": "fish_008",
		"koi": "fish_022", "golden_carp": "fish_027", "eel": "fish_024",
		"trout": "fish_016", "moonfish": "fish_021", "sturgeon": "fish_028"
	}
	for field in ["inventory", "fish_basket"]:
		var counts: Dictionary = data.get(field, {}) if data.get(field) is Dictionary else {}
		var mapping: Dictionary = bait_ids if field == "inventory" else fish_ids
		for old_id in mapping:
			if counts.has(old_id):
				var new_id := str(mapping[old_id])
				counts[new_id] = int(counts.get(new_id, 0)) + int(counts[old_id])
				counts.erase(old_id)
		data[field] = counts
	for field in ["crafted_baits", "discovered_fish"]:
		var entries: Array = data.get(field, []) if data.get(field) is Array else []
		var mapping: Dictionary = bait_ids if field == "crafted_baits" else fish_ids
		var migrated: Array = []
		for entry in entries:
			var new_id := str(mapping.get(str(entry), str(entry)))
			if not migrated.has(new_id):
				migrated.append(new_id)
		data[field] = migrated
	data["selected_bait"] = str(bait_ids.get(str(data.get("selected_bait", "")), data.get("selected_bait", "")))
	if str(data.get("selected_rod", "")) == "improved_rod":
		data["selected_rod"] = "good_rod"
	var owned_rods: Array = data.get("unlocked_rods", []) if data.get("unlocked_rods") is Array else []
	if owned_rods.has("improved_rod"):
		owned_rods.erase("improved_rod")
		if not owned_rods.has("good_rod"):
			owned_rods.append("good_rod")
	data["unlocked_rods"] = owned_rods
	data["unlocked_crops"] = ["wheat", "corn", "carrot", "white_radish", "strawberry", "tomato", "cabbage", "lettuce"]
	data["unlocked_baits"] = ["wheat_bait", "corn_bait", "carrot_bait", "white_radish_bait", "strawberry_bait", "tomato_bait", "cabbage_bait", "lettuce_bait"]
	var jobs: Array = data.get("crafting_jobs", []) if data.get("crafting_jobs") is Array else []
	for job in jobs:
		if job is Dictionary:
			job["bait_id"] = str(bait_ids.get(str(job.get("bait_id", "")), job.get("bait_id", "")))
	var cast: Dictionary = data.get("fishing_cast", {}) if data.get("fishing_cast") is Dictionary else {}
	if not cast.is_empty():
		cast["bait_id"] = str(bait_ids.get(str(cast.get("bait_id", "")), cast.get("bait_id", "")))
	var flags: Dictionary = data.get("flags", {}) if data.get("flags") is Dictionary else {}
	var commands: Array = flags.get("worker_commands", []) if flags.get("worker_commands") is Array else []
	for command in commands:
		if not command is Dictionary:
			continue
		var args: Array = command.get("args", []) if command.get("args") is Array else []
		if args.is_empty():
			continue
		match str(command.get("action", "")):
			"craft_bait", "select_bait": args[0] = str(bait_ids.get(str(args[0]), args[0]))
			"select_rod":
				if str(args[0]) == "improved_rod":
					args[0] = "good_rod"


# 迁移 eight_plot_layout，供调用方继续处理。
func _migrate_eight_plot_layout(_legacy_plots: Variant) -> Array:
	var plots: Array = []
	for index in range(PLOT_COUNT):
		var unlocked := index >= DEFAULT_UNLOCKED_START_INDEX
		plots.append({
			"id": str(index),
			"unlocked": unlocked,
			"crop": "",
			"planted_at": 0,
			"mature_at": 0,
			"fertility": 0,
			"planned_crop": ""
		})
	return plots


# 迁移 seven_plot_layout，供调用方继续处理。
func _migrate_seven_plot_layout() -> Array:
	var plots: Array = []
	for index in range(PLOT_COUNT):
		var unlocked := index >= DEFAULT_UNLOCKED_START_INDEX
		plots.append({
			"id": str(index),
			"unlocked": unlocked,
			"crop": "",
			"planted_at": 0,
			"mature_at": 0,
			"fertility": 0,
			"planned_crop": ""
		})
	return plots


# 封装 notification 的处理，供相关流程复用。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		var fishing := get_tree().root.find_child("FishingSystem", true, false)
		if fishing != null and fishing.has_method("stop_fishing"):
			fishing.stop_fishing("shutdown")
		save_game()


# 封装 emit 的处理，供相关流程复用。
func _emit(signal_name: String) -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus != null and bus.has_signal(signal_name):
		bus.emit_signal(signal_name)
