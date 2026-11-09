extends SceneTree

## Run in a separate project copy so the user's save is never touched.
var failures: Array[String] = []
var unlock_batches: Array = []


# 封装 initialize 的处理，供相关流程复用。
func _initialize() -> void:
	call_deferred("_run")


# 封装 run 的处理，供相关流程复用。
func _run() -> void:
	var state := root.get_node("GameState")
	var bus := root.get_node("EventBus")
	var registry := root.get_node("DataRegistry")
	var service := load("res://scripts/systems/achievement_system.gd").new() as Node
	root.add_child(service)
	bus.achievements_unlocked.connect(func(ids: Array, migrated: bool): unlock_batches.append({"ids": ids.duplicate(), "migrated": migrated}))
	state.reset_to_defaults(false)
	service._reconcile_from_state()
	_check(service.get_entries().size() == 12, "12 configured achievements")
	_check(state.achievement_unlocks.is_empty(), "fresh game has no completed achievements")
	_action(state, bus, "harvest", {"crop_id":"wheat", "amount":2})
	_check(state.achievement_unlocks.has("ACH_FIRST_HARVEST"), "harvest unlocks after successful result")
	var old_count: int = int(state.achievement_stats.get("harvest_successes", 0))
	bus.achievement_action.emit(int(state.achievement_event_sequence), "harvest", {"crop_id":"wheat", "amount":2})
	_check(int(state.achievement_stats.get("harvest_successes", 0)) == old_count and unlock_batches.size() == 1, "duplicate event id is ignored")
	for bait_id in ["wheat_bait", "corn_bait", "carrot_bait"]:
		_action(state, bus, "bait_crafted", {"bait_id":bait_id, "charges":10})
		if bait_id == "corn_bait":
			_check(not state.achievement_unlocks.has("ACH_BAIT_VARIETY_3"), "two crafted bait types do not reach three")
	_check(state.achievement_unlocks.has("ACH_FIRST_BAIT") and state.achievement_unlocks.has("ACH_BAIT_VARIETY_3"), "three distinct crafted baits unlock both achievements")
	_check(int(state.achievement_stats.get("bait_craft_successes", 0)) == 3, "craft completion count")
	for index in range(5):
		var fish_id := "fish_%03d" % (index + 1)
		state.discover("fish", fish_id)
		_action(state, bus, "fish_caught", {"fish_id":fish_id, "rod_id":"basic_rod"})
		if index == 3:
			_check(not state.achievement_unlocks.has("ACH_FISH_SPECIES_5"), "four fish species do not reach five")
	_check(state.achievement_unlocks.has("ACH_FIRST_FISH") and state.achievement_unlocks.has("ACH_FISH_SPECIES_5"), "five discovered fish")
	_check(not state.achievement_unlocks.has("ACH_UPGRADED_ROD_CATCH"), "basic rod does not qualify")
	state.unlocked_rods.append("good_rod")
	state.selected_rod = "basic_rod"
	_action(state, bus, "fish_caught", {"fish_id":"fish_001", "rod_id":"good_rod"})
	_check(state.achievement_unlocks.has("ACH_UPGRADED_ROD_CATCH"), "cast rod snapshot qualifies even after selected rod changes")
	_action(state, bus, "fish_sold", {"fish_id":"fish_001", "amount":1, "coins":5})
	_check(state.achievement_unlocks.has("ACH_FIRST_SALE"), "successful fish sale qualifies")
	for index in range(3):
		state.plots[index]["unlocked"] = true
	_action(state, bus, "plot_unlocked", {"plot_id":"2"})
	_check(state.achievement_unlocks.has("ACH_PLOTS_5") and not state.achievement_unlocks.has("ACH_PLOTS_7"), "five open plots")
	state.cottage_level = 3
	_action(state, bus, "cottage_completed", {"level":3})
	_check(state.achievement_unlocks.has("ACH_COTTAGE_LEVEL_2") and state.achievement_unlocks.has("ACH_COTTAGE_LEVEL_3"), "level three completion also recognizes level two")
	for index in range(5, 15):
		var fish_id := "fish_%03d" % (index + 1)
		state.discover("fish", fish_id)
		_action(state, bus, "fish_caught", {"fish_id":fish_id, "rod_id":"basic_rod"})
	_check(state.achievement_unlocks.has("ACH_FISH_SPECIES_15"), "fifteen fish species")
	for index in range(3, 5):
		state.plots[index]["unlocked"] = true
	_action(state, bus, "plot_unlocked", {"plot_id":"4"})
	_check(state.achievement_unlocks.size() == 12, "all twelve achievements reachable")
	var saved: Dictionary = state.to_save_data()
	var batch_count := unlock_batches.size()
	state.load_save_data(saved)
	service._reconcile_from_state()
	_check(state.achievement_unlocks.size() == 12 and unlock_batches.size() == batch_count, "reload preserves unlocks without repeat notice")
	var legacy: Dictionary = saved.duplicate(true)
	for key in ["achievement_stats", "achievement_unlocks", "achievement_event_sequence", "achievement_last_processed_event_id", "achievement_schema_version"]:
		legacy.erase(key)
	legacy["discovered_crops"] = ["wheat"]
	legacy["crafted_baits"] = ["wheat_bait", "corn_bait", "carrot_bait"]
	legacy["harvested_crop_totals"] = {"wheat": 3}
	state.load_save_data(legacy)
	service._reconcile_from_state()
	_check(bool(state.achievement_unlocks.get("ACH_FIRST_HARVEST", {}).get("migrated", false)), "old harvest is marked migrated")
	_check(state.achievement_unlocks.has("ACH_BAIT_VARIETY_3") and state.achievement_unlocks.has("ACH_FISH_SPECIES_15"), "legacy sets backfill")
	_check(not state.achievement_unlocks.has("ACH_FIRST_SALE") and not state.achievement_unlocks.has("ACH_UPGRADED_ROD_CATCH"), "unprovable legacy sale and rod catch stay locked")
	_check(int(state.achievement_unlocks.get("ACH_FIRST_HARVEST", {}).get("unlocked_at", -1)) == 0, "legacy unlock does not invent a timestamp")
	batch_count = unlock_batches.size()
	service._reconcile_from_state()
	_check(unlock_batches.size() == batch_count, "legacy recognition is idempotent")
	var fish: Array = registry.get_all("fish")
	var common_count := 0
	for entry in fish:
		if str(entry.get("rarity", "")) == "common" and float(entry.get("base_weight", 0.0)) > 0.0:
			common_count += 1
	_check(common_count >= 15, "fifteen fish attainable with the basic rod")
	if failures.is_empty():
		print("ACHIEVEMENT_SYSTEM_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


# 封装 action 的处理，供相关流程复用。
func _action(state: Node, bus: Node, action: String, payload: Dictionary) -> void:
	bus.achievement_action.emit(state.next_achievement_event_id(), action, payload)


# 封装 check 的处理，供相关流程复用。
func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
