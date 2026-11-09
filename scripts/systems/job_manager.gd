# 定义 JobManager 的状态和可用操作。
class_name JobManager
extends Node

## Player orders are persisted but their effects begin only after the worker
## reaches the matching static target marker. Timed production remains owned by
## FarmingSystem, CraftingSystem and FishingSystem after that point.
signal command_finished(command: Dictionary, success: bool)

const QUEUE_KEY := "worker_commands"
const SERIAL_KEY := "worker_command_serial"
const MAX_COMMANDS := 10
const BUILDING_COMPLETION_ACTIONS := ["complete_cottage", "complete_workbench", "complete_shop"]
const TARGETS := {
	"plant": "plot", "harvest": "plot", "unlock_plot": "plot",
	"plant_cell": "plot", "harvest_cell": "plot", "water_cell": "plot",
	"craft_bait": "workbench", "select_bait": "pond", "select_rod": "workbench",
	"upgrade_rod": "workbench", "sell_common": "shop", "sell_all": "shop", "buy_bait": "shop",
	"convert_fish": "house", "upgrade_cottage": "house",
	"complete_cottage": "house", "complete_workbench": "workbench", "complete_shop": "shop",
	"upgrade_pond": "pond", "start_fishing": "pond", "stop_fishing": "pond",
	"feed_pasture": "pasture"
}

var _started_command_id := -1
var _labor_command_id := -1


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.connect("game_reset", Callable(self, "_on_game_reset"))
		bus.connect("game_loaded", Callable(self, "_on_game_loaded"))
	call_deferred("_claim_offline")


# 响应 game_loaded 对应的事件或条件。
func _on_game_loaded() -> void:
	_started_command_id = -1
	_labor_command_id = -1
	_migrate_legacy_tasks()
	_coalesce_plot_watering_tasks()
	_reserve_legacy_group_planting()
	var state := get_node_or_null("/root/GameState")
	if state != null:
		var queue := _queue()
		var urgent := queue.filter(_is_building_completion_command)
		urgent.append_array(queue.filter(func(value: Variant) -> bool: return not _is_building_completion_command(value)))
		state.flags[QUEUE_KEY] = urgent
	_emit("job_queue_changed")


# 响应 game_reset 对应的事件或条件。
func _on_game_reset() -> void:
	_started_command_id = -1
	_labor_command_id = -1
	_emit("job_queue_changed")


# 封装 enqueue_command 的处理，供相关流程复用。
func enqueue_command(action: String, target_id: String = "", args: Array = [], success_text: String = "", failure_text: String = "", task_id: int = -1, task_action: String = "", task_grouped: bool = false, task_args: Array = []) -> int:
	var state = get_node_or_null("/root/GameState")
	if state == null or not TARGETS.has(action):
		return -1
	if action == "plant_cell" and not args.is_empty():
		if task_grouped and (args.size() <= 2 or bool(args[2])):
			# 整组播种只能通过一次性预留金币的批量入口加入队列。
			return -1
		var registry := get_node_or_null("/root/DataRegistry")
		var crop: Dictionary = registry.get_crop(str(args[0])) if registry != null else {}
		if int(state.coins) < maxi(0, int(crop.get("plant_cost", 0))):
			return -1
	if action == "water_cell":
		var farming: Node = _find_system("FarmingSystem")
		if farming != null and bool(farming.call("is_weather_watering")):
			return -1
	var queue := _queue()
	var urgent := action in BUILDING_COMPLETION_ACTIONS
	if urgent and not _is_building_completion_ready(action, state):
		return -1
	for pending in queue:
		if pending is Dictionary and str(pending.get("action", "")) == action and str(pending.get("target_id", "")) == target_id and pending.get("args", []) == args:
			return int(pending.get("id", -1))
	var existing_task := false
	if task_id > 0:
		for pending in queue:
			if pending is Dictionary and _task_id(pending) == task_id:
				existing_task = true
				break
	if not urgent and not existing_task and _count_tasks(queue) >= MAX_COMMANDS:
		return -1
	var prepaid_cost := -1
	match action:
		"unlock_plot":
			var plot: Dictionary = state.get_plot(target_id)
			if plot.is_empty() or bool(plot.get("unlocked", false)):
				return -1
			var farming: Node = _find_system("FarmingSystem")
			if farming == null or not bool(farming.call("can_unlock_plot", target_id)):
				return -1
			var unlock_group_id := str(farming.call("get_plot_unlock_group_id", target_id))
			for pending in queue:
				if pending is Dictionary and str(pending.get("action", "")) == "unlock_plot" and str(farming.call("get_plot_unlock_group_id", str(pending.get("target_id", "")))) == unlock_group_id:
					return int(pending.get("id", -1))
			prepaid_cost = int(farming.get_plot_unlock_cost(target_id))
		"upgrade_cottage":
			if not state.get_cottage_construction().is_empty():
				return -1
			prepaid_cost = int(state.get_next_cottage_upgrade_cost())
			if prepaid_cost < 0:
				return -1
	if prepaid_cost >= 0 and not state.spend_coins(prepaid_cost):
		return -1
	var serial := int(state.flags.get(SERIAL_KEY, 0)) + 1
	state.flags[SERIAL_KEY] = serial
	var command := {
		"id": serial,
		"task_id": task_id if task_id > 0 else serial,
		"task_action": task_action if not task_action.is_empty() else action,
		"task_grouped": task_grouped,
		"task_args": task_args.duplicate(true) if not task_args.is_empty() else args.duplicate(true),
		"action": action,
		"target": str(TARGETS[action]),
		"target_id": target_id,
		"args": args.duplicate(true),
		"success_text": success_text,
		"failure_text": failure_text
	}
	if prepaid_cost >= 0:
		command["prepaid_cost"] = prepaid_cost
	if urgent:
		var insert_at := _building_completion_count(queue)
		queue.insert(insert_at, command)
		if insert_at == 0:
			_started_command_id = -1
			_labor_command_id = -1
	else:
		queue.append(command)
	state.flags[QUEUE_KEY] = queue
	_request_save()
	_emit("job_added", [command.duplicate(true)])
	_emit("job_queue_changed")
	return serial


# 验收资格在入队时检查，执行时由各建筑的完工方法再次检查。
func _is_building_completion_ready(action: String, state: Node) -> bool:
	match action:
		"complete_cottage": return state.is_cottage_construction_ready()
		"complete_workbench": return state.is_workbench_construction_ready()
		"complete_shop": return state.is_shop_construction_ready()
	return false


# 识别验收命令，包括旧存档里已有的工作台和鱼铺命令。
func _is_building_completion_command(command: Variant) -> bool:
	return command is Dictionary and str(command.get("action", "")) in BUILDING_COMPLETION_ACTIONS


# 优先队列保持验收命令的点击顺序，普通后续任务只能插在它们之后。
func _building_completion_count(queue: Array) -> int:
	var count := 0
	for command in queue:
		if not _is_building_completion_command(command):
			break
		count += 1
	return count


# 读取 next_command，供调用方继续处理。
func get_next_command() -> Dictionary:
	var queue := _queue()
	return queue[0].duplicate(true) if not queue.is_empty() and queue[0] is Dictionary else {}


# 读取 pending_commands，供调用方继续处理。
func get_pending_commands() -> Array:
	return _queue().duplicate(true)


# 读取 labor_command_id，供调用方继续处理。
func get_labor_command_id() -> int:
	return _labor_command_id


# 读取 plot_work_status，供调用方继续处理。
func get_plot_work_status(plot_id: String) -> Dictionary:
	return build_plot_work_status(_queue(), plot_id, _labor_command_id)


# 读取 facility_work_status，供调用方继续处理。
func get_facility_work_status() -> Dictionary:
	var status := {
		"craft": {"total_count": 0, "waiting_count": 0, "running_count": 0},
		"pasture": {}
	}
	for value in _queue():
		if not value is Dictionary:
			continue
		var command: Dictionary = value
		var action := str(command.get("action", ""))
		var entry: Dictionary
		if action == "craft_bait":
			entry = status["craft"]
		elif action == "feed_pasture":
			var target_parts := str(command.get("target_id", "")).split(":")
			if target_parts.size() != 2:
				continue
			var area_id := target_parts[0]
			var pasture_status: Dictionary = status["pasture"]
			if not pasture_status.has(area_id):
				pasture_status[area_id] = {"total_count": 0, "waiting_count": 0, "running_count": 0}
			entry = pasture_status[area_id]
		else:
			continue
		entry["total_count"] = int(entry["total_count"]) + 1
		if int(command.get("id", -1)) == _labor_command_id:
			entry["running_count"] = int(entry["running_count"]) + 1
		else:
			entry["waiting_count"] = int(entry["waiting_count"]) + 1
	return status


# 构建 plot_work_status，供调用方继续处理。
static func build_plot_work_status(commands: Array, plot_id: String, labor_command_id: int = -1) -> Dictionary:
	var status := {
		"plant": {"total_count": 0, "waiting_count": 0, "running_count": 0, "grouped_count": 0, "crop_counts": {}, "target_ids": []},
		"harvest": {"total_count": 0, "waiting_count": 0, "running_count": 0, "grouped_count": 0, "crop_counts": {}, "target_ids": []}
	}
	var seen := {"plant": {}, "harvest": {}}
	for value in commands:
		if not value is Dictionary:
			continue
		var command: Dictionary = value
		var action := str(command.get("action", ""))
		var kind := "plant" if action in ["plant", "plant_cell"] else "harvest" if action in ["harvest", "harvest_cell"] else ""
		if kind.is_empty():
			continue
		var target_id := str(command.get("target_id", ""))
		var cell_count := 9
		var target_key := plot_id + ":*"
		if action.ends_with("_cell"):
			var parts := target_id.split(":")
			if parts.size() != 2 or parts[0] != plot_id or not parts[1].is_valid_int():
				continue
			cell_count = 1
			target_key = target_id
		elif target_id != plot_id:
			continue
		var kind_seen: Dictionary = seen[kind]
		if kind_seen.has(target_key):
			continue
		kind_seen[target_key] = true
		var entry: Dictionary = status[kind]
		entry["total_count"] = int(entry["total_count"]) + cell_count
		(entry["target_ids"] as Array).append(target_key)
		if int(command.get("id", -1)) == labor_command_id:
			entry["running_count"] = int(entry["running_count"]) + cell_count
		else:
			entry["waiting_count"] = int(entry["waiting_count"]) + cell_count
		if kind == "plant":
			var args: Array = command.get("args", []) if command.get("args", []) is Array else []
			if action == "plant" or args.size() <= 2 or bool(args[2]):
				entry["grouped_count"] = int(entry["grouped_count"]) + cell_count
			var crop_id := str(args[0]) if not args.is_empty() else ""
			if not crop_id.is_empty():
				var crop_counts: Dictionary = entry["crop_counts"]
				crop_counts[crop_id] = int(crop_counts.get(crop_id, 0)) + cell_count
	return status


# 封装 enqueue_task_batch 的处理，供相关流程复用。
func enqueue_task_batch(action: String, target_ids: Array, args: Array = [], success_text: String = "", failure_text: String = "", join_existing_plot_task: bool = false, grouped: bool = true, task_id_override: int = -1, task_action_override: String = "", task_args_override: Array = []) -> int:
	if target_ids.is_empty():
		return -1
	if action == "plant_cell" and grouped and (args.size() <= 2 or bool(args[2])):
		return _enqueue_prepaid_plant_batch(target_ids, args, success_text, failure_text, task_id_override, task_action_override, task_args_override)
	var task_id := -1
	if join_existing_plot_task and action == "water_cell":
		task_id = _find_plot_watering_task(str(target_ids[0]))
	if task_id < 0 and get_available_command_slots() <= 0:
		return -1
	var joined_existing := task_id > 0
	var added := false
	for target in target_ids:
		var duplicate := false
		for pending in _queue():
			if pending is Dictionary and str(pending.get("action", "")) == action and str(pending.get("target_id", "")) == str(target) and pending.get("args", []) == args:
				duplicate = true
				break
		if duplicate:
			continue
		var command_id := enqueue_command(action, str(target), args, success_text, failure_text, task_id, action, grouped, args)
		if command_id < 0:
			break
		added = true
		if task_id < 0:
			task_id = command_id
	if joined_existing and added:
		var state := get_node_or_null("/root/GameState")
		if state != null:
			state.flags[QUEUE_KEY] = _group_commands_by_task(_queue())
			_request_save()
			_emit("job_queue_changed")
	return task_id


# 封装 enqueue_prepaid_plant_batch 的处理，供相关流程复用。
func _enqueue_prepaid_plant_batch(target_ids: Array, args: Array, success_text: String, failure_text: String, task_id_override: int = -1, task_action_override: String = "", task_args_override: Array = []) -> int:
	var state := get_node_or_null("/root/GameState")
	var registry := get_node_or_null("/root/DataRegistry")
	if state == null or registry == null or args.is_empty():
		return -1
	var crop_id := str(args[0])
	var crop: Dictionary = registry.get_crop(crop_id)
	if crop.is_empty() or not state.unlocked_crops.has(crop_id):
		return -1
	var queue := _queue()
	var existing_task := false
	if task_id_override > 0:
		for value in queue:
			if value is Dictionary and _task_id(value) == task_id_override:
				existing_task = true
				break
	if task_id_override < 0 and not existing_task and _count_tasks(queue) >= MAX_COMMANDS:
		return -1
	var seen_targets: Dictionary = {}
	for target in target_ids:
		var target_id := str(target)
		var parts := target_id.split(":")
		if parts.size() != 2 or not parts[1].is_valid_int() or seen_targets.has(target_id):
			return -1
		seen_targets[target_id] = true
		var index := int(parts[1])
		var plot: Dictionary = state.get_plot(parts[0])
		var cells: Array = plot.get("cells", [])
		if not bool(plot.get("unlocked", false)) or cells.size() != 9 or index < 0 or index >= 9 or not str((cells[index] as Dictionary).get("crop", "")).is_empty():
			return -1
		for value in queue:
			if value is Dictionary and str(value.get("action", "")) == "plant_cell" and str(value.get("target_id", "")) == target_id:
				return -1
	var unit_cost := maxi(0, int(crop.get("plant_cost", 0)))
	var total_cost := unit_cost * target_ids.size()
	if total_cost > 0 and not state.spend_coins(total_cost):
		return -1
	var serial := int(state.flags.get(SERIAL_KEY, 0))
	var task_id := task_id_override if task_id_override > 0 else serial + 1
	var added: Array[Dictionary] = []
	for target in target_ids:
		serial += 1
		added.append({
			"id": serial,
			"task_id": task_id,
			"task_action": task_action_override if not task_action_override.is_empty() else "plant_cell",
			"task_grouped": true,
			"task_args": task_args_override.duplicate(true) if not task_args_override.is_empty() else args.duplicate(true),
			"action": "plant_cell",
			"target": "plot",
			"target_id": str(target),
			"args": args.duplicate(true),
			"success_text": success_text,
			"failure_text": failure_text,
			"plant_prepaid": true,
			"prepaid_cost": unit_cost
		})
	state.flags[SERIAL_KEY] = serial
	if task_id_override > 0:
		var insert_at := _building_completion_count(queue)
		for index in range(queue.size()):
			if queue[index] is Dictionary and _task_id(queue[index]) == task_id:
				insert_at = index + 1
		for command in added:
			queue.insert(insert_at, command)
			insert_at += 1
	else:
		queue.append_array(added)
	state.flags[QUEUE_KEY] = queue
	_request_save()
	for command in added:
		_emit("job_added", [command.duplicate(true)])
	_emit("job_queue_changed")
	return task_id


# 读取 pending_tasks，供调用方继续处理。
func get_pending_tasks() -> Array:
	var tasks: Array = []
	var seen: Dictionary = {}
	for value in _queue():
		if not value is Dictionary:
			continue
		var command: Dictionary = value
		var group_id := _task_id(command)
		if seen.has(group_id):
			var index: int = int(seen[group_id])
			(tasks[index] as Dictionary)["remaining_steps"] = int((tasks[index] as Dictionary)["remaining_steps"]) + 1
			continue
		seen[group_id] = tasks.size()
		var task := command.duplicate(true)
		task["id"] = group_id
		task["action"] = str(command.get("task_action", command.get("action", "")))
		task["args"] = command.get("task_args", command.get("args", [])).duplicate(true)
		task["remaining_steps"] = 1
		tasks.append(task)
	# 开始钓鱼指令到达鱼塘后就完成；持续钓鱼由 FishingSystem 维护。
	# 队列为空时用一条只展示的任务保持列表与角色当前工作一致。
	var state := get_node_or_null("/root/GameState")
	if tasks.is_empty() and state != null and bool(state.flags.get("fishing_active", false)):
		tasks.append({"id": -1, "action": "fishing", "target_id": "", "args": [], "virtual": true, "remaining_steps": 1})
	return tasks


# 读取 available_command_slots，供调用方继续处理。
func get_available_command_slots() -> int:
	return maxi(0, MAX_COMMANDS - _count_tasks(_queue()))


# 读取 started_command_id，供调用方继续处理。
func get_started_command_id() -> int:
	return _started_command_id


# 读取 started_task_id，供调用方继续处理。
func get_started_task_id() -> int:
	for value in _queue():
		if value is Dictionary and int(value.get("id", -1)) == _started_command_id:
			return _task_id(value)
	return -1


# 判断是否具有 uninterruptible_plant_task 对应的条件。
func has_uninterruptible_plant_task() -> bool:
	for value in _queue():
		if value is Dictionary and str(value.get("action", "")) == "plant_cell" and bool(value.get("task_grouped", false)):
			return true
	return false


# 移动 command，供调用方继续处理。
func move_command(command_id: int, direction: int) -> bool:
	return move_task(command_id, direction)


# 移动 task，供调用方继续处理。
func move_task(task_id: int, direction: int) -> bool:
	if direction not in [-1, 1]:
		return false
	var queue := _queue()
	var task_order: Array[int] = []
	var grouped: Dictionary = {}
	for value in queue:
		if not value is Dictionary:
			continue
		var group_id := _task_id(value)
		if not grouped.has(group_id):
			grouped[group_id] = []
			task_order.append(group_id)
		(grouped[group_id] as Array).append(value)
	var index := task_order.find(task_id)
	var destination := index + direction
	if index < 0 or destination < 0 or destination >= task_order.size():
		return false
	if _is_building_completion_command(grouped[task_id][0]) or _is_building_completion_command(grouped[task_order[destination]][0]):
		return false
	var started_task := get_started_task_id()
	var first: Dictionary = queue[0] if not queue.is_empty() and queue[0] is Dictionary else {}
	var locked_plant_task := _task_id(first) if str(first.get("action", "")) == "plant_cell" and bool(first.get("task_grouped", false)) else -1
	if task_id == started_task or task_order[destination] == started_task or task_id == locked_plant_task or task_order[destination] == locked_plant_task:
		return false
	var moving := task_order[index]
	task_order[index] = task_order[destination]
	task_order[destination] = moving
	var reordered: Array = []
	for group_id in task_order:
		reordered.append_array(grouped[group_id])
	var state = get_node_or_null("/root/GameState")
	if state == null:
		return false
	state.flags[QUEUE_KEY] = reordered
	_request_save()
	_emit("job_queue_changed")
	return true


# 封装 task_id 的处理，供相关流程复用。
func _task_id(command: Dictionary) -> int:
	return int(command.get("task_id", command.get("id", -1)))


# 封装 count_tasks 的处理，供相关流程复用。
func _count_tasks(queue: Array) -> int:
	var ids: Dictionary = {}
	for value in queue:
		if value is Dictionary:
			ids[_task_id(value)] = true
	return ids.size()


# 查找 plot_watering_task，供调用方继续处理。
func _find_plot_watering_task(target_id: String) -> int:
	var plot_id := target_id.get_slice(":", 0)
	for value in _queue():
		if not value is Dictionary:
			continue
		var command: Dictionary = value
		if str(command.get("action", "")) == "water_cell" and bool(command.get("task_grouped", false)) and str(command.get("target_id", "")).get_slice(":", 0) == plot_id:
			return _task_id(command)
	return -1


# 封装 group_commands_by_task 的处理，供相关流程复用。
func _group_commands_by_task(queue: Array) -> Array:
	var order: Array[int] = []
	var groups: Dictionary = {}
	for value in queue:
		if not value is Dictionary:
			continue
		var task_id := _task_id(value)
		if not groups.has(task_id):
			groups[task_id] = []
			order.append(task_id)
		(groups[task_id] as Array).append(value)
	var result: Array = []
	for task_id in order:
		result.append_array(groups[task_id])
	return result


# 封装 coalesce_plot_watering_tasks 的处理，供相关流程复用。
func _coalesce_plot_watering_tasks() -> void:
	var queue := _queue()
	var first_task_by_plot: Dictionary = {}
	var changed := false
	for value in queue:
		if not value is Dictionary:
			continue
		var command: Dictionary = value
		if str(command.get("action", "")) != "water_cell" or not bool(command.get("task_grouped", false)):
			continue
		var plot_id := str(command.get("target_id", "")).get_slice(":", 0)
		if first_task_by_plot.has(plot_id):
			var first_id := int(first_task_by_plot[plot_id])
			if _task_id(command) != first_id:
				command["task_id"] = first_id
				changed = true
		else:
			first_task_by_plot[plot_id] = _task_id(command)
	if changed:
		var state := get_node_or_null("/root/GameState")
		if state != null:
			state.flags[QUEUE_KEY] = _group_commands_by_task(queue)
			_request_save()
			_emit("job_queue_changed")


# 迁移 legacy_tasks，供调用方继续处理。
func _migrate_legacy_tasks() -> void:
	var queue := _queue()
	var changed := false
	var previous_action := ""
	var previous_plot := ""
	var previous_cell := -1
	var previous_task_id := -1
	var previous_index := -1
	for index in range(queue.size()):
		if not queue[index] is Dictionary:
			continue
		var command: Dictionary = queue[index]
		if command.has("task_id"):
			previous_action = ""
			continue
		var action := str(command.get("action", ""))
		var parts := str(command.get("target_id", "")).split(":")
		var groupable := action in ["plant_cell", "water_cell", "harvest_cell"] and parts.size() == 2
		var plot_id := parts[0] if groupable else ""
		var cell_index := int(parts[1]) if groupable else -1
		var same_group := groupable and action == previous_action and plot_id == previous_plot and cell_index > previous_cell and cell_index < 9
		command["task_id"] = previous_task_id if same_group else int(command.get("id", -1))
		command["task_action"] = action
		command["task_args"] = (command.get("args", []) as Array).duplicate(true)
		command["task_grouped"] = same_group
		if same_group and previous_index >= 0:
			(queue[previous_index] as Dictionary)["task_grouped"] = true
		previous_action = action if groupable else ""
		previous_plot = plot_id
		previous_cell = cell_index
		previous_task_id = int(command["task_id"])
		previous_index = index
		changed = true
	if changed:
		var state := get_node_or_null("/root/GameState")
		if state != null:
			state.flags[QUEUE_KEY] = queue
			_request_save()
			_emit("job_queue_changed")


# 封装 reserve_legacy_group_planting 的处理，供相关流程复用。
func _reserve_legacy_group_planting() -> void:
	var state := get_node_or_null("/root/GameState")
	var registry := get_node_or_null("/root/DataRegistry")
	if state == null or registry == null:
		return
	var queue := _queue()
	var groups: Dictionary = {}
	for index in range(queue.size()):
		if not queue[index] is Dictionary:
			continue
		var command: Dictionary = queue[index]
		if str(command.get("action", "")) != "plant_cell" or not bool(command.get("task_grouped", false)) or bool(command.get("plant_prepaid", false)):
			continue
		var args: Array = command.get("args", []) if command.get("args", []) is Array else []
		if args.is_empty() or args.size() > 2 and not bool(args[2]):
			continue
		var group_id := _task_id(command)
		if not groups.has(group_id):
			groups[group_id] = []
		(groups[group_id] as Array).append(index)
	var removed: Dictionary = {}
	var changed := false
	for group_id in groups:
		var indexes: Array = groups[group_id]
		var total_cost := 0
		for index in indexes:
			var command: Dictionary = queue[index]
			var args: Array = command.get("args", [])
			var crop: Dictionary = registry.get_crop(str(args[0]))
			total_cost += maxi(0, int(crop.get("plant_cost", 0)))
		if total_cost > int(state.coins):
			for index in indexes:
				removed[index] = true
			changed = true
			continue
		if total_cost > 0:
			state.spend_coins(total_cost)
		for index in indexes:
			var command: Dictionary = queue[index]
			var args: Array = command.get("args", [])
			var crop: Dictionary = registry.get_crop(str(args[0]))
			command["plant_prepaid"] = true
			command["prepaid_cost"] = maxi(0, int(crop.get("plant_cost", 0)))
			changed = true
	if changed:
		var kept: Array = []
		for index in range(queue.size()):
			if not removed.has(index):
				kept.append(queue[index])
		state.flags[QUEUE_KEY] = kept
		_started_command_id = -1
		_request_save()
		_emit("job_queue_changed")


# 封装 cancel_pending_commands 的处理，供相关流程复用。
func cancel_pending_commands() -> int:
	var state = get_node_or_null("/root/GameState")
	if state == null:
		return 0
	if has_uninterruptible_plant_task():
		return 0
	var count := _queue().size()
	if count == 0:
		return 0
	for command_value in _queue():
		if command_value is Dictionary:
			var command: Dictionary = command_value
			if command.has("prepaid_cost") and int(command["prepaid_cost"]) > 0:
				state.add_coins(int(command["prepaid_cost"]))
	state.flags[QUEUE_KEY] = []
	_started_command_id = -1
	_labor_command_id = -1
	_request_save()
	_emit("job_queue_changed")
	return count


# 封装 discard_weather_water_commands 的处理，供相关流程复用。
func discard_weather_water_commands() -> int:
	var state = get_node_or_null("/root/GameState")
	if state == null:
		return 0
	var queue := _queue()
	var kept: Array = []
	var discarded := 0
	for value in queue:
		if value is Dictionary and str(value.get("action", "")) == "water_cell":
			if int(value.get("id", -1)) == _started_command_id:
				_started_command_id = -1
			if int(value.get("id", -1)) == _labor_command_id:
				_labor_command_id = -1
			discarded += 1
		else:
			kept.append(value)
	if discarded > 0:
		state.flags[QUEUE_KEY] = kept
		_request_save()
		_emit("job_queue_changed")
	return discarded


# 封装 begin_next_command 的处理，供相关流程复用。
func begin_next_command(command_id: int) -> bool:
	var queue := _queue()
	if queue.is_empty() or not queue[0] is Dictionary or int(queue[0].get("id", -1)) != command_id:
		return false
	if _started_command_id != command_id:
		_started_command_id = command_id
		_emit("job_started", [queue[0].duplicate(true)])
	return true


# 封装 begin_command_labor 的处理，供相关流程复用。
func begin_command_labor(command_id: int) -> bool:
	var queue := _queue()
	if queue.is_empty() or not queue[0] is Dictionary or int(queue[0].get("id", -1)) != command_id:
		return false
	begin_next_command(command_id)
	if _labor_command_id != command_id:
		_labor_command_id = command_id
		_emit("job_labor_started", [queue[0].duplicate(true)])
		_emit("job_queue_changed")
	return true


# 封装 execute_next_command 的处理，供相关流程复用。
func execute_next_command(command_id: int) -> bool:
	var queue := _queue()
	if queue.is_empty() or not queue[0] is Dictionary or int(queue[0].get("id", -1)) != command_id:
		return false
	begin_next_command(command_id)
	var command: Dictionary = queue.pop_front()
	_started_command_id = -1
	_labor_command_id = -1
	var state = get_node_or_null("/root/GameState")
	if state != null:
		state.flags[QUEUE_KEY] = queue
	_request_save()
	var success := _execute(command)
	if not success and state != null and command.has("prepaid_cost") and int(command["prepaid_cost"]) > 0:
		state.add_coins(int(command["prepaid_cost"]))
		_request_save()
	if not success and state != null and bool(command.get("plant_prepaid", false)):
		_refund_failed_prepaid_plant_group(command, state)
	if success and str(command.get("action", "")) == "harvest" and state != null:
		var harvested_plot: Dictionary = state.get_plot(str(command.get("target_id", "")))
		var repeat_crop := str(harvested_plot.get("planned_crop", ""))
		if not repeat_crop.is_empty():
			enqueue_command("plant", str(command.get("target_id", "")), [repeat_crop, true], TextDB.text("ui.9dc05ba20d") % repeat_crop, TextDB.text("ui.7d11efada2"), _task_id(command), str(command.get("task_action", "harvest")), bool(command.get("task_grouped", false)), command.get("task_args", []))
	var farming: Node = _find_system("FarmingSystem")
	var weather_watering := farming != null and bool(farming.call("is_weather_watering"))
	if success and str(command.get("action", "")) == "plant_cell" and not weather_watering:
		var plant_parts := str(command.get("target_id", "")).split(":")
		var plant_args: Array = command.get("args", []) if command.get("args", []) is Array else []
		var grouped := bool(plant_args[2]) if plant_args.size() > 2 else true
		_enqueue_cell_followup("water_cell", str(command.get("target_id", "")), [], TextDB.text("ui.1d21339af2"), TextDB.text("ui.eadd8c7b22"), plant_parts[0] if not plant_parts.is_empty() else "", grouped, _task_id(command), str(command.get("task_action", "plant_cell")), bool(command.get("task_grouped", false)), command.get("task_args", []))
	if success and str(command.get("action", "")) == "plant" and not weather_watering:
		for cell_index in range(9):
			enqueue_command("water_cell", "%s:%d" % [str(command.get("target_id", "")), cell_index], [], TextDB.text("ui.1d21339af2"), TextDB.text("ui.eadd8c7b22"), _task_id(command), str(command.get("task_action", "plant")), bool(command.get("task_grouped", false)), command.get("task_args", []))
	if success and str(command.get("action", "")) == "harvest_cell" and state != null:
		var parts := str(command.get("target_id", "")).split(":")
		if parts.size() == 2:
			var plot: Dictionary = state.get_plot(parts[0])
			var cells: Array = plot.get("cells", [])
			var index := int(parts[1])
			if index >= 0 and index < cells.size():
				var cell: Dictionary = cells[index]
				var repeat_crop := str(cell.get("planned_crop", ""))
				if bool(cell.get("grouped", true)):
					if not _has_pending_group_harvest(_task_id(command), parts[0]) and not _enqueue_group_repeat_planting(command, parts[0], state):
						command["success_text"] = TextDB.text("ui.f2461601db")
						command["repeat_plant_failed"] = true
				elif not repeat_crop.is_empty():
					_enqueue_cell_followup("plant_cell", str(command.get("target_id", "")), [repeat_crop, true, false], TextDB.text("ui.5df430297f"), TextDB.text("ui.0486d936b3"), parts[0], false, _task_id(command), str(command.get("task_action", "harvest_cell")), bool(command.get("task_grouped", false)), command.get("task_args", []))
	command_finished.emit(command.duplicate(true), success)
	var completed := command.duplicate(true)
	completed["success"] = success
	_emit("job_completed", [completed])
	_emit("job_queue_changed")
	return true


# 封装 refund_failed_prepaid_plant_group 的处理，供相关流程复用。
func _refund_failed_prepaid_plant_group(command: Dictionary, state: Node) -> void:
	var queue := _queue()
	var kept: Array = []
	var refund := 0
	for value in queue:
		if value is Dictionary and _task_id(value) == _task_id(command) and str(value.get("action", "")) == "plant_cell" and bool(value.get("plant_prepaid", false)):
			refund += maxi(0, int(value.get("prepaid_cost", 0)))
		else:
			kept.append(value)
	if kept.size() == queue.size():
		return
	state.flags[QUEUE_KEY] = kept
	if refund > 0:
		state.add_coins(refund)
	_request_save()


# 判断是否具有 pending_group_harvest 对应的条件。
func _has_pending_group_harvest(task_id: int, plot_id: String) -> bool:
	for value in _queue():
		if value is Dictionary and _task_id(value) == task_id and str(value.get("action", "")) == "harvest_cell" and str(value.get("target_id", "")).begins_with(plot_id + ":"):
			return true
	return false


# 封装 enqueue_group_repeat_planting 的处理，供相关流程复用。
func _enqueue_group_repeat_planting(command: Dictionary, plot_id: String, state: Node) -> bool:
	var plot: Dictionary = state.get_plot(plot_id)
	var targets_by_crop: Dictionary = {}
	for index in range((plot.get("cells", []) as Array).size()):
		var cell: Dictionary = (plot["cells"] as Array)[index]
		var crop_id := str(cell.get("planned_crop", ""))
		if crop_id.is_empty() or not bool(cell.get("grouped", true)) or not str(cell.get("crop", "")).is_empty():
			continue
		if not targets_by_crop.has(crop_id):
			targets_by_crop[crop_id] = []
		(targets_by_crop[crop_id] as Array).append("%s:%d" % [plot_id, index])
	if targets_by_crop.is_empty():
		return true
	var registry := get_node_or_null("/root/DataRegistry")
	var total_cost := 0
	for crop_id in targets_by_crop:
		var crop: Dictionary = registry.get_crop(str(crop_id)) if registry != null else {}
		if crop.is_empty() or not state.unlocked_crops.has(str(crop_id)):
			return false
		total_cost += maxi(0, int(crop.get("plant_cost", 0))) * (targets_by_crop[crop_id] as Array).size()
	if int(state.coins) < total_cost:
		return false
	for crop_id in targets_by_crop:
		var targets: Array = targets_by_crop[crop_id]
		if _enqueue_prepaid_plant_batch(targets, [str(crop_id), true, true], TextDB.text("ui.5df430297f"), TextDB.text("ui.0486d936b3"), _task_id(command), str(command.get("task_action", "harvest_cell")), command.get("task_args", [])) < 0:
			return false
	return true


# 封装 enqueue_cell_followup 的处理，供相关流程复用。
func _enqueue_cell_followup(action: String, target_id: String, args: Array, success_text: String, failure_text: String, plot_id: String, grouped: bool, task_id: int, task_action: String, task_grouped: bool, task_args: Array) -> void:
	var before := _queue()
	for pending in before:
		if pending is Dictionary and str(pending.get("action", "")) == action and str(pending.get("target_id", "")) == target_id and pending.get("args", []) == args:
			return
	if enqueue_command(action, target_id, args, success_text, failure_text, task_id, task_action, task_grouped, task_args) < 0:
		return
	var queue := _queue()
	var followup: Dictionary = queue.pop_back()
	var insert_at := _building_completion_count(queue)
	if grouped:
		for index in range(queue.size()):
			var pending: Dictionary = queue[index]
			if _task_id(pending) == task_id and str(pending.get("target_id", "")).begins_with(plot_id + ":") and str(pending.get("action", "")) in ["harvest_cell", "plant_cell", "water_cell"]:
				insert_at = index + 1
	queue.insert(insert_at, followup)
	var state = get_node_or_null("/root/GameState")
	if state != null:
		state.flags[QUEUE_KEY] = queue
	_request_save()
	_emit("job_queue_changed")


# 封装 execute 的处理，供相关流程复用。
func _execute(command: Dictionary) -> bool:
	var action := str(command.get("action", ""))
	var target_id := str(command.get("target_id", ""))
	var args: Array = command.get("args", []) if command.get("args", []) is Array else []
	match action:
		"plant":
			return _call_system("FarmingSystem", "plant", [target_id, str(args[0]), 0, bool(args[1]) if args.size() > 1 else true]) if not args.is_empty() else false
		"harvest":
			return _call_system("FarmingSystem", "harvest_plot", [target_id])
		"plant_cell", "harvest_cell", "water_cell":
			var parts := target_id.split(":")
			if parts.size() != 2:
				return false
			match action:
				"plant_cell":
					return _call_system("FarmingSystem", "plant_cell", [parts[0], int(parts[1]), str(args[0]), bool(args[1]) if args.size() > 1 else true, 0, bool(args[2]) if args.size() > 2 else true, bool(command.get("plant_prepaid", false))]) if not args.is_empty() else false
				"harvest_cell":
					return _call_system("FarmingSystem", "harvest_cell", [parts[0], int(parts[1])])
				"water_cell":
					return _call_system("FarmingSystem", "water_cell", [parts[0], int(parts[1])])
		"unlock_plot":
			return _call_system("FarmingSystem", "unlock_plot", [target_id, command.has("prepaid_cost")])
		"craft_bait":
			return _call_system("CraftingSystem", "craft_bait", [str(args[0]), maxi(1, int(args[1])) if args.size() > 1 else 1, 0, true]) if not args.is_empty() else false
		"select_bait":
			return _call_system("CraftingSystem", "select_bait", [str(args[0])]) if not args.is_empty() else false
		"select_rod":
			return _call_system("CraftingSystem", "select_rod", [str(args[0])]) if not args.is_empty() else false
		"upgrade_rod":
			return _call_system("CraftingSystem", "upgrade_rod", [])
		"sell_common":
			var sold: Variant = _call_system_raw("ShopSystem", "sell_all_common", [])
			return sold is Dictionary and int(sold.get("coins", 0)) > 0
		"sell_all":
			var sold: Variant = _call_system_raw("ShopSystem", "sell_all_fish", [])
			return sold is Dictionary and int(sold.get("coins", 0)) > 0
		"buy_bait":
			return _call_system("ShopSystem", "buy_bait", [str(args[0]), 1]) if not args.is_empty() else false
		"convert_fish":
			var converted: Variant = _call_system_raw("ShopSystem", "convert_all_duplicates", [1])
			return converted is Dictionary and int(converted.get("fertilizer", 0)) > 0
		"upgrade_cottage":
			return _upgrade_cottage(command.has("prepaid_cost"))
		"complete_cottage":
			return complete_cottage_construction()
		"complete_workbench":
			return _complete_workbench()
		"complete_shop":
			return _complete_shop()
		"upgrade_pond":
			return _upgrade("pond_level", 250)
		"start_fishing":
			return _start_fishing()
		"stop_fishing":
			return _stop_fishing()
		"feed_pasture":
			var parts := target_id.split(":")
			if parts.size() != 2 or args.is_empty():
				return false
			var pasture := get_tree().root.find_child("PastureAreas", true, false) as PastureManager
			return pasture != null and pasture.add_food_from_command(int(parts[0]), int(parts[1]), str(args[0]), maxi(1, int(args[1])) if args.size() > 1 else 1)
	return false


# 启动 fishing，供调用方继续处理。
func _start_fishing() -> bool:
	var state = get_node_or_null("/root/GameState")
	var fishing = _find_system("FishingSystem")
	if state == null or fishing == null or not fishing.can_fish():
		return false
	state.flags["fishing_active"] = true
	state.flags["fishing_manual_pause"] = false
	state.flags["fishing_started_by_idle"] = false
	_request_save()
	if not state.fishing_cast.is_empty():
		return true
	var started := bool(fishing.start_cast())
	if not started:
		state.flags["fishing_active"] = false
		_request_save()
	return started


# 停止 fishing，供调用方继续处理。
func _stop_fishing() -> bool:
	var state = get_node_or_null("/root/GameState")
	var fishing = _find_system("FishingSystem")
	if state == null or fishing == null:
		return false
	state.flags["fishing_active"] = false
	state.flags["fishing_manual_pause"] = true
	state.flags["fishing_started_by_idle"] = false
	fishing.stop_fishing("manual")
	_request_save()
	return true


# 封装 upgrade 的处理，供相关流程复用。
func _upgrade(property: String, cost: int) -> bool:
	var state = get_node_or_null("/root/GameState")
	if state == null or int(state.get(property)) >= 2 or not state.spend_coins(cost):
		return false
	state.set(property, 2)
	_request_save()
	return true


# 封装 upgrade_cottage 的处理，供相关流程复用。
func _upgrade_cottage(prepaid: bool = false) -> bool:
	var state = get_node_or_null("/root/GameState")
	if state == null or not state.get_cottage_construction().is_empty():
		return false
	var next_level := int(state.cottage_level) + 1
	var next_data: Dictionary = state.get_cottage_data(next_level)
	if next_data.is_empty():
		return false
	var cost := maxi(0, int(next_data.get("upgrade_cost", 0)))
	if not prepaid and not state.spend_coins(cost):
		return false
	var ready_at := int(Time.get_unix_time_from_system()) + maxi(1, int(next_data.get("build_seconds", 60)))
	state.flags["cottage_construction"] = {"target_level": next_level, "ready_at": ready_at}
	_emit("cottage_construction_started", [next_level, ready_at])
	_request_save()
	return true


# 封装 complete_cottage_construction 的处理，供相关流程复用。
func complete_cottage_construction() -> bool:
	var state = get_node_or_null("/root/GameState")
	if state == null or not state.is_cottage_construction_ready():
		return false
	var construction: Dictionary = state.get_cottage_construction()
	var target_level := int(construction.get("target_level", 0))
	if target_level != int(state.cottage_level) + 1:
		return false
	var next_data: Dictionary = state.get_cottage_data(target_level)
	if next_data.is_empty():
		return false
	state.flags.erase("cottage_construction")
	state.cottage_level = target_level
	for bait_id in next_data.get("unlock_baits", []):
		if not state.unlocked_baits.has(str(bait_id)):
			state.unlocked_baits.append(str(bait_id))
	_emit("cottage_upgrade_completed", [target_level])
	_emit("achievement_action", [state.next_achievement_event_id(), "cottage_completed", {"level": target_level}])
	_request_save()
	return true


# 封装 complete_workbench 的处理，供相关流程复用。
func _complete_workbench() -> bool:
	var state = get_node_or_null("/root/GameState")
	if state == null or not state.is_workbench_construction_ready():
		return false
	state.workbench_unlocked = true
	_emit("workbench_unlocked")
	_request_save()
	return true


# 封装 complete_shop 的处理，供相关流程复用。
func _complete_shop() -> bool:
	var state = get_node_or_null("/root/GameState")
	if state == null or not state.is_shop_construction_ready():
		return false
	state.shop_unlocked = true
	_emit("shop_unlocked")
	_request_save()
	return true


# 封装 call_system 的处理，供相关流程复用。
func _call_system(system_name: String, method: String, args: Array) -> bool:
	var result: Variant = _call_system_raw(system_name, method, args)
	if result is bool:
		return result
	if result is Dictionary or result is Array:
		return not result.is_empty()
	if result is int:
		return result > 0
	return result != null


# 封装 call_system_raw 的处理，供相关流程复用。
func _call_system_raw(system_name: String, method: String, args: Array) -> Variant:
	var system = _find_system(system_name)
	return system.callv(method, args) if system != null and system.has_method(method) else null


# 封装 queue 的处理，供相关流程复用。
func _queue() -> Array:
	var state = get_node_or_null("/root/GameState")
	if state == null:
		return []
	var value: Variant = state.flags.get(QUEUE_KEY, [])
	return value.duplicate(true) if value is Array else []


# 封装 settle_offline 的处理，供相关流程复用。
func settle_offline(seconds: int, from_unix: int, to_unix: int) -> Dictionary:
	var result := {
		"seconds": seconds, "from_unix": from_unix, "to_unix": to_unix,
		"farming": {}, "crafting": {}, "fishing": {}
	}
	for system_name in ["FarmingSystem", "CraftingSystem", "FishingSystem"]:
		var system = _find_system(system_name)
		if system != null and system.has_method("settle_offline"):
			result[system_name.trim_suffix("System").to_lower()] = system.settle_offline(seconds, from_unix, to_unix)
	return result


# 封装 claim_offline 的处理，供相关流程复用。
func _claim_offline() -> void:
	var time_manager = get_node_or_null("/root/TimeManager")
	if time_manager == null or not time_manager.has_pending_offline():
		return
	var pending: Dictionary = time_manager.consume_pending_offline()
	var result := settle_offline(int(pending.get("seconds", 0)), int(pending.get("from_unix", 0)), int(pending.get("to_unix", 0)))
	time_manager.publish_offline_result(result)
	_request_save()


# 查找 system，供调用方继续处理。
func _find_system(node_name: String):
	if get_parent() != null:
		var sibling := get_parent().get_node_or_null(node_name)
		if sibling != null:
			return sibling
	return get_tree().root.find_child(node_name, true, false)


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
