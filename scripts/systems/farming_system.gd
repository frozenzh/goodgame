# 定义 FarmingSystem 的状态和可用操作。
class_name FarmingSystem
extends Node

## 植物使用运行期间的截止时间；读档时平移时间轴、菜单暂停时冻结，离线不推进。
## 成熟后保留在地里，收获指令结束后再安排重复种植。

@onready var GameConfig: Node = get_node("/root/GameConfig")
var _mutation_rng := RandomNumberGenerator.new()


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	_mutation_rng.randomize()
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.tick.connect(_on_growth_tick)
		bus.weather_changed.connect(_on_weather_changed)


# 响应 growth_tick 对应的事件或条件。
func _on_growth_tick(now_unix: int, _elapsed: int) -> void:
	refresh(now_unix)


# 响应 weather_changed 对应的事件或条件。
func _on_weather_changed(previous_id: String, current_id: String) -> void:
	if previous_id == current_id:
		return
	var state: Variant = _state()
	var now := int(state.weather_state.get("started_at", _now())) if state != null and previous_id in ["sunny", "rain", "snow", "wind"] else _now()
	if current_id in ["rain", "snow"]:
		_auto_water_for_weather(now)
	if previous_id not in ["sunny", "rain", "snow", "wind"]:
		return
	var weather := get_node_or_null("../WeatherSystem")
	var old_speed := float(weather.get_crop_growth_speed_for(previous_id)) if weather != null else 1.0
	var new_speed := float(weather.get_crop_growth_speed_for(current_id)) if weather != null else 1.0
	if is_equal_approx(old_speed, new_speed):
		return
	for plot_value in state.plots:
		if not plot_value is Dictionary:
			continue
		var plot: Dictionary = plot_value
		for cell_value in plot.get("cells", []):
			if cell_value is Dictionary:
				_rescale_cell_deadlines(cell_value, now, old_speed / new_speed)
		_sync_plot_summary(plot)
	_request_save()


# 封装 rescale_cell_deadlines 的处理，供相关流程复用。
func _rescale_cell_deadlines(cell: Dictionary, now: int, factor: float) -> void:
	if str(cell.get("crop", "")).is_empty() or int(cell.get("mature_at", 0)) <= now:
		return
	for key in ["leaf_at", "mature_at"]:
		var deadline := int(cell.get(key, 0))
		if deadline > now:
			cell[key] = now + maxi(1, ceili(float(deadline - now) * factor))


# 判断是否满足 weather_watering 对应的条件。
func is_weather_watering() -> bool:
	var state: Variant = _state()
	return state != null and str(state.weather_state.get("id", "sunny")) in ["rain", "snow"]


# 封装 auto_water_for_weather 的处理，供相关流程复用。
func _auto_water_for_weather(now_unix: int) -> void:
	if not is_weather_watering():
		return
	var state: Variant = _state()
	for plot in state.plots:
		if not plot is Dictionary:
			continue
		var plot_id := str(plot.get("id", ""))
		var cells: Array = plot.get("cells", [])
		for index in range(cells.size()):
			var cell: Dictionary = cells[index]
			# 种子补水可能立刻跨入幼苗阶段；同一轮也补上幼苗的水。
			for _stage_step in range(2):
				var stage := cell_stage(cell, now_unix)
				if stage not in ["seed", "leaf"] or bool(cell.get("watered_" + stage, false)):
					break
				water_cell(plot_id, index, now_unix)
	var jobs := get_tree().root.find_child("JobManager", true, false)
	if jobs != null:
		jobs.discard_weather_water_commands()


# 封装 cell_stage 的处理，供相关流程复用。
func cell_stage(cell: Dictionary, now_unix: int = 0) -> String:
	if str(cell.get("crop", "")).is_empty():
		return "empty"
	var now := _now() if now_unix <= 0 else now_unix
	if now >= int(cell.get("mature_at", 0)):
		return "mature"
	if now >= int(cell.get("leaf_at", 0)):
		return "leaf"
	return "seed"


# 封装 plant_cell 的处理，供相关流程复用。
func plant_cell(plot_id: Variant, cell_index: int, crop_id: String, repeat_crop: bool = false, now_unix: int = 0, grouped: bool = true, prepaid: bool = false) -> bool:
	var state: Variant = _state()
	var registry: Variant = _registry()
	if state == null or registry == null or cell_index < 0 or cell_index >= 9:
		return false
	var plot: Dictionary = state.get_plot(plot_id)
	var crop: Dictionary = registry.get_crop(crop_id)
	if plot.is_empty() or crop.is_empty() or not bool(plot.get("unlocked", false)):
		return false
	var cells: Array = plot.get("cells", [])
	if cells.size() != 9 or not str((cells[cell_index] as Dictionary).get("crop", "")).is_empty():
		return false
	if not state.unlocked_crops.has(crop_id):
		return false
	var cost := maxi(0, int(crop.get("plant_cost", 0)))
	if cost > 0 and not prepaid and not state.spend_coins(cost):
		return false
	var now := _now() if now_unix <= 0 else now_unix
	var half := maxi(1, ceili(float(_adjusted_grow_seconds(crop, int(plot.get("fertility", 0)))) / 2.0))
	var dry_multiplier := maxf(1.0, GameConfig.get_float("farming", "unwatered_growth_multiplier"))
	var cell: Dictionary = cells[cell_index]
	cell["crop"] = crop_id
	cell["planted_at"] = now
	cell["leaf_at"] = now + ceili(float(half) * dry_multiplier)
	cell["mature_at"] = int(cell["leaf_at"]) + ceili(float(half) * dry_multiplier)
	cell["watered_seed"] = false
	cell["watered_leaf"] = false
	cell["grouped"] = grouped
	cell["planned_crop"] = crop_id if repeat_crop else ""
	_sync_plot_summary(plot)
	var all_same := true
	for value in cells:
		if str((value as Dictionary).get("crop", "")) != crop_id:
			all_same = false
			break
	if all_same:
		plot["mutation"] = _roll_mutation(crop)
	_emit("crop_planted", [str(plot.get("id", plot_id)), crop_id, int(cell["mature_at"])])
	if is_weather_watering():
		_auto_water_for_weather(now)
	if str(state.weather_state.get("id", "")) in ["snow", "wind"]:
		var weather := get_node_or_null("../WeatherSystem")
		var speed := float(weather.get_crop_growth_speed_multiplier()) if weather != null else 1.0
		_rescale_cell_deadlines(cell, now, 1.0 / speed)
		_sync_plot_summary(plot)
	_request_save()
	return true


# 为本轮作物补水，now_unix 单位为秒；首次浇水覆盖种子和叶片两阶段，未浇水作物仍可在叶片期首次补水。
func water_cell(plot_id: Variant, cell_index: int, now_unix: int = 0) -> bool:
	var state: Variant = _state()
	if state == null or cell_index < 0 or cell_index >= 9:
		return false
	var plot: Dictionary = state.get_plot(plot_id)
	var cells: Array = plot.get("cells", [])
	if cells.size() != 9:
		return false
	var cell: Dictionary = cells[cell_index]
	var now := _now() if now_unix <= 0 else now_unix
	var stage := cell_stage(cell, now)
	if stage not in ["seed", "leaf"] or bool(cell.get("watered_" + stage, false)):
		return false
	var dry_multiplier := maxf(1.0, GameConfig.get_float("farming", "unwatered_growth_multiplier"))
	cell["watered_" + stage] = true
	if stage == "seed":
		var future_leaf_seconds := maxi(1, int(cell.get("mature_at", now)) - int(cell.get("leaf_at", now)))
		cell["leaf_at"] = now + maxi(1, ceili(float(int(cell.get("leaf_at", now)) - now) / dry_multiplier))
		# 原先叶片阶段等待第二次浇水才加速，暂时停用并保留原式。
		# cell["mature_at"] = int(cell["leaf_at"]) + future_leaf_seconds
		cell["mature_at"] = int(cell["leaf_at"]) + maxi(1, ceili(float(future_leaf_seconds) / dry_multiplier))
	else:
		cell["mature_at"] = now + maxi(1, ceili(float(int(cell.get("mature_at", now)) - now) / dry_multiplier))
	cell["watered_seed"] = true
	cell["watered_leaf"] = true
	_sync_plot_summary(plot)
	_emit("crop_watered", [str(plot.get("id", plot_id)), cell_index, stage])
	_request_save()
	return true


# 封装 harvest_cell 的处理，供相关流程复用。
func harvest_cell(plot_id: Variant, cell_index: int, now_unix: int = 0) -> bool:
	var state: Variant = _state()
	if state == null or cell_index < 0 or cell_index >= 9:
		return false
	var plot: Dictionary = state.get_plot(plot_id)
	var cells: Array = plot.get("cells", [])
	if cells.size() != 9:
		return false
	var cell: Dictionary = cells[cell_index]
	if cell_stage(cell, now_unix) != "mature":
		return false
	var crop_id := str(cell.get("crop", ""))
	var amount := get_cell_harvest_amount(plot_id, cell_index)
	if not state.can_store_crop(amount):
		return false
	DropService.grant_item(crop_id, amount, "plot:%s" % str(plot.get("id", plot_id)), "crop")
	cell["crop"] = ""
	cell["planted_at"] = 0
	cell["leaf_at"] = 0
	cell["mature_at"] = 0
	cell["watered_seed"] = false
	cell["watered_leaf"] = false
	_sync_plot_summary(plot)
	_emit("crop_harvested", [crop_id, amount])
	state.record_crop_harvest(crop_id, amount)
	_emit("achievement_action", [state.next_achievement_event_id(), "harvest", {"crop_id": crop_id, "amount": amount}])
	_request_save()
	return true


# 读取 cell_harvest_amount，供调用方继续处理。
func get_cell_harvest_amount(plot_id: Variant, cell_index: int) -> int:
	var state: Variant = _state()
	if state == null or cell_index < 0 or cell_index >= 9:
		return 0
	var plot: Dictionary = state.get_plot(plot_id)
	var cells: Array = plot.get("cells", [])
	if cells.size() != 9:
		return 0
	var crop_id := str((cells[cell_index] as Dictionary).get("crop", ""))
	if crop_id.is_empty():
		return 0
	var crop: Dictionary = _registry().get_crop(crop_id)
	var amount := maxi(1, int(crop.get("harvest_amount", 1)))
	var mutation: Dictionary = plot.get("mutation", {}) if plot.get("mutation", {}) is Dictionary else {}
	if bool(mutation.get("active", false)) and cell_index % 3 == int(mutation.get("column", -1)) and floori(float(cell_index) / 3.0) in [int(mutation.get("start_row", -1)), int(mutation.get("start_row", -1)) + 1]:
		amount *= 2
	return amount


# 同步 plot_summary，供调用方继续处理。
func _sync_plot_summary(plot: Dictionary) -> void:
	plot["crop"] = ""
	plot["planted_at"] = 0
	plot["mature_at"] = 0
	for value in plot.get("cells", []):
		var cell: Dictionary = value
		if str(cell.get("crop", "")).is_empty():
			continue
		if str(plot["crop"]).is_empty():
			plot["crop"] = str(cell["crop"])
			plot["planted_at"] = int(cell.get("planted_at", 0))
		plot["mature_at"] = maxi(int(plot["mature_at"]), int(cell.get("mature_at", 0)))


# 封装 plant 的处理，供相关流程复用。
func plant(plot_id: Variant, crop_id: String, now_unix: int = 0, repeat_crop: bool = false) -> bool:
	var state: Variant = _state()
	var registry: Variant = _registry()
	if state == null or registry == null:
		return false
	var plot: Dictionary = state.get_plot(plot_id)
	var cells: Array = plot.get("cells", [])
	if cells.size() == 9:
		var planted := false
		for index in range(9):
			if str((cells[index] as Dictionary).get("crop", "")).is_empty():
				planted = plant_cell(plot_id, index, crop_id, repeat_crop, now_unix) or planted
		return planted
	var crop: Dictionary = registry.get_crop(crop_id)
	if plot.is_empty() or crop.is_empty() or not bool(plot.get("unlocked", false)):
		return false
	if not state.unlocked_crops.has(crop_id):
		return false
	if not str(plot.get("crop", "")).is_empty():
		return false
	var cost := maxi(0, int(crop.get("plant_cost", 0)))
	if cost > 0 and not state.spend_coins(cost):
		return false
	var current := _now() if now_unix <= 0 else now_unix
	var grow_seconds := _adjusted_grow_seconds(crop, int(plot.get("fertility", 0)))
	plot["crop"] = crop_id
	plot["planted_at"] = current
	plot["mature_at"] = current + grow_seconds
	plot["planned_crop"] = crop_id if repeat_crop else ""
	plot["mutation"] = _roll_mutation(crop)
	_emit("crop_planted", [str(plot.get("id", plot_id)), crop_id, int(plot["mature_at"])])
	_request_save()
	return true


# 设置 planned_crop，供调用方继续处理。
func set_planned_crop(plot_id: Variant, crop_id: String) -> bool:
	var state: Variant = _state()
	if state == null:
		return false
	var plot: Dictionary = state.get_plot(plot_id)
	if plot.is_empty() or not bool(plot.get("unlocked", false)):
		return false
	plot["planned_crop"] = crop_id
	for value in plot.get("cells", []):
		(value as Dictionary)["planned_crop"] = crop_id
	_request_save()
	return true


# 读取 plot_unlock_cost，供调用方继续处理。
func get_plot_unlock_cost(plot_id: Variant) -> int:
	var state: Variant = _state()
	if state == null:
		return 0
	var plot: Dictionary = state.get_plot(plot_id)
	if plot.is_empty():
		return 0
	var wanted_id := str(plot.get("id", plot_id))
	var upgrade := _plot_upgrade(wanted_id)
	var plot_data := _plot_data(wanted_id)
	return maxi(0, int(upgrade.get("cost", plot_data.get("unlock_cost", plot.get("unlock_cost", 0)))))


# 读取 plot_unlock_group_id，供调用方继续处理。
func get_plot_unlock_group_id(plot_id: Variant) -> String:
	var state: Variant = _state()
	if state == null:
		return ""
	var plot: Dictionary = state.get_plot(plot_id)
	if plot.is_empty():
		return ""
	var wanted_id := str(plot.get("id", plot_id))
	var upgrade := _plot_upgrade(wanted_id)
	return str(upgrade.get("id", "plot:%s" % wanted_id))


# 检查是否允许 unlock_plot 对应的条件。
func can_unlock_plot(plot_id: Variant) -> bool:
	var state: Variant = _state()
	if state == null:
		return false
	var plot: Dictionary = state.get_plot(plot_id)
	if plot.is_empty() or bool(plot.get("unlocked", false)):
		return false
	var upgrade := _plot_upgrade(str(plot.get("id", plot_id)))
	if upgrade.is_empty():
		return false
	if int(state.cottage_level) < maxi(1, int(upgrade.get("required_cottage_level", 1))):
		return false
	for prerequisite in upgrade.get("prerequisites", []):
		if not _plot_prerequisite_met(str(prerequisite), state):
			return false
	return true


# 封装 unlock_plot 的处理，供相关流程复用。
func unlock_plot(plot_id: Variant, prepaid: bool = false) -> bool:
	var state: Variant = _state()
	if state == null or not can_unlock_plot(plot_id):
		return false
	var plot: Dictionary = state.get_plot(plot_id)
	var wanted_id := str(plot.get("id", plot_id))
	var upgrade := _plot_upgrade(wanted_id)
	var cost := get_plot_unlock_cost(plot_id)
	if not prepaid and not state.spend_coins(cost):
		return false
	if not state.owned_upgrades.has(str(upgrade.get("id", ""))):
		state.owned_upgrades.append(str(upgrade.get("id", "")))
	plot["unlocked"] = true
	_emit("plot_unlocked", [wanted_id])
	_emit("achievement_action", [state.next_achievement_event_id(), "plot_unlocked", {"plot_id": wanted_id}])
	_request_save()
	return true


# 读取 plot_required_cottage_level，供调用方继续处理。
func get_plot_required_cottage_level(plot_id: Variant) -> int:
	var state: Variant = _state()
	if state == null:
		return 1
	var plot: Dictionary = state.get_plot(plot_id)
	if plot.is_empty():
		return 1
	var upgrade := _plot_upgrade(str(plot.get("id", plot_id)))
	return maxi(1, int(upgrade.get("required_cottage_level", 1)))


# 应用 fertilizer，供调用方继续处理。
func apply_fertilizer(plot_id: Variant, levels: int = 1) -> bool:
	var state: Variant = _state()
	if state == null or levels <= 0:
		return false
	var plot: Dictionary = state.get_plot(plot_id)
	if plot.is_empty() or not bool(plot.get("unlocked", false)):
		return false
	var current := clampi(int(plot.get("fertility", 0)), 0, GameConfig.get_int("farming", "max_fertility"))
	var max_level := _max_fertility_level()
	var applied := mini(levels, max_level - current)
	var fertilizer_cost := 0
	var registry: Variant = _registry()
	for level in range(current + 1, current + applied + 1):
		var level_data: Dictionary = registry.get_entry("fertility_levels", str(level)) if registry != null else {}
		fertilizer_cost += maxi(1, int(level_data.get("fertilizer_cost", 1)))
	if applied <= 0 or not state.spend_fertilizer(fertilizer_cost):
		return false
	plot["fertility"] = current + applied
	_emit("plot_fertilized", [str(plot.get("id", plot_id)), int(plot["fertility"])])
	_request_save()
	return true


# 读取 plot_status，供调用方继续处理。
func get_plot_status(plot_id: Variant, now_unix: int = 0) -> Dictionary:
	var state: Variant = _state()
	if state == null:
		return {}
	var plot: Dictionary = state.get_plot(plot_id)
	if plot.is_empty():
		return {}
	var result := plot.duplicate(true)
	var current := _now() if now_unix <= 0 else now_unix
	result["remaining_seconds"] = maxi(0, int(plot.get("mature_at", 0)) - current)
	result["state"] = _plot_state(plot, current)
	result["harvest_amount"] = _harvest_amount(plot)
	result["cells"] = plot.get("cells", []).duplicate(true)
	return result


# 读取 harvest_amount，供调用方继续处理。
func get_harvest_amount(plot_id: Variant) -> int:
	var state: Variant = _state()
	if state == null:
		return 0
	var plot: Dictionary = state.get_plot(plot_id)
	var cells: Array = plot.get("cells", [])
	if cells.is_empty():
		return _harvest_amount(plot)
	var amount := 0
	for index in range(cells.size()):
		var value: Dictionary = cells[index]
		var cell: Dictionary = value
		if cell_stage(cell) == "mature":
			amount += get_cell_harvest_amount(plot_id, index)
	return amount


# 封装 harvest_plot 的处理，供相关流程复用。
func harvest_plot(plot_id: Variant, now_unix: int = 0) -> bool:
	var state: Variant = _state()
	if state == null:
		return false
	var plot: Dictionary = state.get_plot(plot_id)
	var cells: Array = plot.get("cells", [])
	if cells.size() == 9:
		var harvested := false
		for index in range(9):
			if cell_stage(cells[index] as Dictionary, now_unix) == "mature":
				harvested = harvest_cell(plot_id, index, now_unix) or harvested
		return harvested
	var current := _now() if now_unix <= 0 else now_unix
	if plot.is_empty() or _plot_state(plot, current) != "mature":
		return false
	if not state.can_store_crop(_harvest_amount(plot)):
		return false
	_harvest_plot(plot, {"crops": {}, "harvested_plots": []})
	return true


# 刷新成熟状态，并让旧存档已完成的首次浇水覆盖叶片期；第二次浇水的自动入队代码注释保留。
func refresh(now_unix: int = 0) -> Dictionary:
	var state: Variant = _state()
	var summary := {"crops": {}, "harvested_plots": [], "mature_plots": []}
	if state == null:
		return summary
	var current := _now() if now_unix <= 0 else now_unix
	var weather_watering := is_weather_watering()
	var watering_inherited := false
	if weather_watering:
		_auto_water_for_weather(current)
	for value in state.plots:
		if not value is Dictionary:
			continue
		var plot: Dictionary = value
		var cells: Array = plot.get("cells", [])
		var has_mature := false
		# var leaf_watering_targets: Array[String] = []
		for index in range(cells.size()):
			var cell: Dictionary = cells[index]
			if bool(cell.get("watered_seed", false)) and not bool(cell.get("watered_leaf", false)):
				cell["watered_leaf"] = true
				watering_inherited = true
				if not str(cell.get("crop", "")).is_empty() and int(cell.get("mature_at", 0)) > current:
					var leaf_start := maxi(current, int(cell.get("leaf_at", current)))
					var dry_multiplier := maxf(1.0, GameConfig.get_float("farming", "unwatered_growth_multiplier"))
					cell["mature_at"] = leaf_start + maxi(1, ceili(float(int(cell["mature_at"]) - leaf_start) / dry_multiplier))
					_sync_plot_summary(plot)
			var stage := cell_stage(cell, current)
			if stage == "mature":
				has_mature = true
			# 叶片阶段不再自动追加第二次浇水，原实现保留供恢复。
			# elif stage == "leaf" and not weather_watering and not bool(cell.get("watered_leaf", false)):
			# 	leaf_watering_targets.append("%s:%d" % [str(plot.get("id", "")), index])
		# if not leaf_watering_targets.is_empty():
		# 	var jobs := get_tree().root.find_child("JobManager", true, false)
		# 	if jobs != null:
		# 		jobs.enqueue_task_batch("water_cell", leaf_watering_targets, [], TextDB.text("ui.1d21339af2"), TextDB.text("ui.eadd8c7b22"), true)
		if has_mature or cells.is_empty() and _plot_state(plot, current) == "mature":
			summary["mature_plots"].append(str(plot.get("id", "")))
	if watering_inherited:
		_request_save()
	return summary


# 植物只在游戏运行时推进；保留兼容入口，离线结算不得刷新生长或自动浇水。
func settle_offline(_seconds: int, _from_unix: int, _to_unix: int) -> Dictionary:
	return {}


# 封装 harvest_plot 的处理，供相关流程复用。
func _harvest_plot(plot: Dictionary, summary: Dictionary) -> void:
	var state: Variant = _state()
	if state == null:
		return
	var crop_id := str(plot.get("crop", ""))
	var amount := _harvest_amount(plot)
	DropService.grant_item(crop_id, amount, "plot:%s" % str(plot.get("id", "")), "crop")
	plot["crop"] = ""
	plot["planted_at"] = 0
	plot["mature_at"] = 0
	plot["mutation"] = {}
	var crops: Dictionary = summary["crops"]
	crops[crop_id] = int(crops.get(crop_id, 0)) + amount
	summary["harvested_plots"].append(str(plot.get("id", "")))
	_emit("crop_harvested", [crop_id, amount])
	state.record_crop_harvest(crop_id, amount)
	_emit("achievement_action", [state.next_achievement_event_id(), "harvest", {"crop_id": crop_id, "amount": amount}])
	_request_save()


# 封装 harvest_amount 的处理，供相关流程复用。
func _harvest_amount(plot: Dictionary) -> int:
	var registry: Variant = _registry()
	if registry == null or plot.is_empty() or str(plot.get("crop", "")).is_empty():
		return 0
	var crop: Dictionary = registry.get_crop(str(plot.get("crop", "")))
	var normal_amount := maxi(1, int(crop.get("harvest_amount", 1)))
	var mutation: Dictionary = plot.get("mutation", {}) if plot.get("mutation", {}) is Dictionary else {}
	if not bool(mutation.get("active", false)):
		return normal_amount
	# 7 ordinary cells + one two-cell giant yielding four cell equivalents = 11/9.
	return normal_amount + maxi(1, ceili(float(normal_amount) * 2.0 / 9.0))


# 封装 roll_mutation 的处理，供相关流程复用。
func _roll_mutation(crop: Dictionary) -> Dictionary:
	var chance := clampf(float(crop.get("mutation_chance", 0.0)), 0.0, 1.0)
	if _mutation_rng.randf() >= chance:
		return {}
	return {
		"active": true,
		"column": _mutation_rng.randi_range(0, 2),
		"start_row": _mutation_rng.randi_range(0, 1)
	}


# 封装 plot_state 的处理，供相关流程复用。
func _plot_state(plot: Dictionary, now_unix: int) -> String:
	if not bool(plot.get("unlocked", false)):
		return "locked"
	var cells: Array = plot.get("cells", [])
	if cells.size() == 9:
		var growing := false
		for value in cells:
			var stage := cell_stage(value as Dictionary, now_unix)
			if stage == "mature":
				return "mature"
			if stage in ["seed", "leaf"]:
				growing = true
		return "growing" if growing else "empty"
	if str(plot.get("crop", "")).is_empty():
		return "empty"
	if now_unix >= int(plot.get("mature_at", 0)):
		return "mature"
	return "growing"


# 封装 adjusted_grow_seconds 的处理，供相关流程复用。
func _adjusted_grow_seconds(crop: Dictionary, fertility: int) -> int:
	var base := maxf(1.0, float(crop.get("grow_seconds", GameConfig.get_float("farming", "default_grow_seconds"))))
	var registry: Variant = _registry()
	var level_data: Dictionary = registry.get_entry("fertility_levels", str(fertility)) if registry != null else {}
	var max_fertility: int = GameConfig.get_int("farming", "max_fertility")
	var fallback_reduction := minf(GameConfig.get_float("farming", "fallback_max_reduction"), float(clampi(fertility, 0, max_fertility)) * GameConfig.get_float("farming", "fallback_reduction_per_level"))
	var multiplier := float(level_data.get("grow_time_multiplier", 1.0 - fallback_reduction))
	return maxi(1, int(ceil(base * maxf(0.1, multiplier))))


# 封装 max_fertility_level 的处理，供相关流程复用。
func _max_fertility_level() -> int:
	var registry: Variant = _registry()
	if registry == null:
		return GameConfig.get_int("farming", "max_fertility")
	var result := 0
	for value in registry.get_all("fertility_levels"):
		result = maxi(result, int(value.get("level", 0)))
	return mini(result, GameConfig.get_int("farming", "max_fertility")) if result > 0 else GameConfig.get_int("farming", "max_fertility")


# 封装 plot_upgrade 的处理，供相关流程复用。
func _plot_upgrade(plot_id: String) -> Dictionary:
	var registry: Variant = _registry()
	if registry == null:
		return {}
	for value in registry.get_all("upgrades"):
		var upgrade: Dictionary = value
		for effect_value in upgrade.get("effects", []):
			if not effect_value is Dictionary or str(effect_value.get("type", "")) != "unlock_plots":
				continue
			for candidate in effect_value.get("plot_ids", []):
				# JSON 数字会被 Godot 读成 4.0；地块 ID 在存档中是 "4"。
				if str(int(candidate)) == plot_id:
					return upgrade
	return {}


# 封装 plot_prerequisite_met 的处理，供相关流程复用。
func _plot_prerequisite_met(upgrade_id: String, state: Variant) -> bool:
	# 旧存档可能拥有原来的双地块升级 ID；已开垦状态才是可靠依据。
	var registry: Variant = _registry()
	var prerequisite: Dictionary = registry.get_entry("upgrades", upgrade_id) if registry != null else {}
	if prerequisite.is_empty():
		return state.owned_upgrades.has(upgrade_id)
	var has_plot_effect := false
	for effect_value in prerequisite.get("effects", []):
		if not effect_value is Dictionary or str(effect_value.get("type", "")) != "unlock_plots":
			continue
		has_plot_effect = true
		for candidate in effect_value.get("plot_ids", []):
			if not bool(state.get_plot(candidate).get("unlocked", false)):
				return false
	return has_plot_effect


# 封装 plot_data 的处理，供相关流程复用。
func _plot_data(plot_id: String) -> Dictionary:
	var registry: Variant = _registry()
	return registry.get_entry("plots", plot_id) if registry != null else {}


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
