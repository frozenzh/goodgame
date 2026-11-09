extends Node

## Run as a scene so the project autoloads are available.
var _failures: Array[String] = []


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	call_deferred("_check_rules")


# 检查 rules，供调用方继续处理。
func _check_rules() -> void:
	var registry := get_node("/root/DataRegistry")
	var fish: Array = registry.get_all("fish")
	var basic: Dictionary = registry.get_rod("basic_rod")
	var epic: Dictionary = registry.get_rod("epic_rod")
	var wheat: Dictionary = registry.get_bait("wheat_bait")
	var barley: Dictionary = registry.get_bait("barley_bait")
	var wheat_basic: Array = FishingSystem.build_candidate_pool(fish, basic, wheat, 1.5)
	var barley_basic: Array = FishingSystem.build_candidate_pool(fish, basic, barley, 1.5)
	var wheat_epic: Array = FishingSystem.build_candidate_pool(fish, epic, wheat, 1.5)
	_check(_weight(wheat_basic, "fish_001") > 0.0, "grain bait admits grain fish")
	_check(_weight(wheat_basic, "fish_002") == 0.0, "grain bait excludes root fish")
	_check(_weight(wheat_basic, "fish_013") == 0.0, "basic rod excludes good fish")
	_check(_weight(barley_basic, "fish_001") > 0.0 and _weight(barley_basic, "fish_002") > 0.0, "dual bait admits both tags")
	_check(_weight(barley_basic, "fish_003") == 0.0, "dual bait excludes unrelated tag")
	_check(_weight(wheat_epic, "fish_002") == 0.0, "epic rod cannot bypass bait tag")
	_check(is_equal_approx(_weight(wheat_basic, "fish_001"), _weight(wheat_basic, "fish_004") * 1.5), "favorite bait applies bonus within eligible fish")
	for entry in wheat_epic:
		var data: Dictionary = registry.get_fish(str(entry.get("fish_id", "")))
		_check(str(data.get("preferred_bait_type", "")) == "grain", "all drawn fish match the selected bait tag")
	if _failures.is_empty():
		print("FISHING_TAG_POOL_OK")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		get_tree().quit(1)


# 封装 weight 的处理，供相关流程复用。
func _weight(pool: Array, fish_id: String) -> float:
	for entry in pool:
		if str(entry.get("fish_id", "")) == fish_id:
			return float(entry.get("weight", 0.0))
	return 0.0


# 封装 check 的处理，供相关流程复用。
func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
