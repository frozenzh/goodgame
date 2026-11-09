extends SceneTree

## Catalog and pure draw-rule check. Does not start a game or change a save.
var failures: Array[String] = []


# 封装 initialize 的处理，供相关流程复用。
func _initialize() -> void:
	call_deferred("_run")


# 封装 run 的处理，供相关流程复用。
func _run() -> void:
	var registry := root.get_node("DataRegistry")
	var fish: Array = registry.get_all("fish")
	var crops: Array = registry.get_all("crops")
	var baits: Array = registry.get_all("baits")
	_check(fish.size() >= 30, "at least 30 fish")
	_check(crops.size() >= 8 and baits.size() >= 8, "at least 8 crops and 8 concrete baits")
	var expected_counts := {"common": 12, "good": 8, "rare": 6, "epic": 4}
	for rarity in expected_counts:
		var count := 0
		for entry in fish:
			if str(entry.get("rarity", "")) == rarity:
				count += 1
		_check(count >= int(expected_counts[rarity]), "%s baseline rarity count" % rarity)
	for bait in baits:
		var crop: Dictionary = registry.get_crop(str(bait.get("source_crop", "")))
		_check(not crop.is_empty(), "bait source crop exists: %s" % str(bait.get("id", "")))
	var grain_bait: Dictionary = registry.get_bait("wheat_bait")
	var corn_bait: Dictionary = registry.get_bait("corn_bait")
	for rod_id in ["basic_rod", "good_rod", "rare_rod", "epic_rod"]:
		var rod: Dictionary = registry.get_rod(rod_id)
		var pool := FishingSystem.build_candidate_pool(fish, rod, grain_bait)
		_check(pool.size() == _fish_count_matching(fish, str(rod.get("max_fish_rarity", "common")), ["grain"]), "grain candidate pool for %s" % rod_id)
	var basic: Dictionary = registry.get_rod("basic_rod")
	var wheat_pool := FishingSystem.build_candidate_pool(fish, basic, grain_bait)
	var corn_pool := FishingSystem.build_candidate_pool(fish, basic, corn_bait)
	_check(wheat_pool.size() == corn_pool.size(), "same bait tag gives the same eligible fish")
	_check(_weight(wheat_pool, "fish_002") == 0.0, "non-matching root fish cannot be caught with grain bait")
	_check(is_equal_approx(_weight(wheat_pool, "fish_001"), _weight(wheat_pool, "fish_004") * 1.5), "favorite bait adds x1.5 weight")
	var dual_bait: Dictionary = registry.get_bait("barley_bait")
	var dual_pool := FishingSystem.build_candidate_pool(fish, basic, dual_bait)
	_check(_weight(dual_pool, "fish_001") > 0.0 and _weight(dual_pool, "fish_002") > 0.0, "dual-tag bait admits both fish types")
	_check(_weight(dual_pool, "fish_003") == 0.0, "dual-tag bait still excludes unrelated fish")
	_check(_weight(wheat_pool, "fish_013") == 0.0, "common rod excludes good fish")
	var save_manager := root.get_node("SaveManager")
	var migrated: Dictionary = save_manager._migrate_save({
		"save_version": 5,
		"inventory": {"dough_bait": 7},
		"fish_basket": {"crucian": 2},
		"discovered_fish": ["crucian"],
		"selected_bait": "dough_bait",
		"selected_rod": "improved_rod",
		"unlocked_rods": ["basic_rod", "improved_rod"]
	})
	_check(str(migrated.get("selected_bait", "")) == "wheat_bait" and str(migrated.get("selected_rod", "")) == "good_rod", "legacy bait and rod migrate")
	_check(int(migrated["inventory"].get("wheat_bait", 0)) == 7 and int(migrated["fish_basket"].get("fish_001", 0)) == 2, "legacy inventory migrates")
	if failures.is_empty():
		print("FISHING_MVP_RULES_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


# 封装 weight 的处理，供相关流程复用。
func _weight(pool: Array, fish_id: String) -> float:
	for entry in pool:
		if str(entry.get("fish_id", "")) == fish_id:
			return float(entry.get("weight", 0.0))
	return 0.0


# 封装 fish_count_matching 的处理，供相关流程复用。
func _fish_count_matching(fish: Array, max_rarity: String, bait_types: Array[String]) -> int:
	var rarity_order := ["common", "good", "rare", "epic"]
	var maximum := rarity_order.find(max_rarity)
	var count := 0
	for entry in fish:
		if entry is Dictionary and rarity_order.find(str(entry.get("rarity", ""))) <= maximum and bait_types.has(str(entry.get("preferred_bait_type", ""))):
			count += 1
	return count


# 封装 check 的处理，供相关流程复用。
func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
