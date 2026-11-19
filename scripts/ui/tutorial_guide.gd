extends CanvasLayer

## 六步保留独立静态布局；每步以手工布局为基准跟随目标，控制器负责步骤进度和文本。

@export_file("*.json") var steps_file := "res://data/tutorial/intro.json"
@export var auto_start_for_new_save := true

@onready var _root: Control = $OverlayRoot
var _active_step: Control
var _focus: Panel
var _dialog: PanelContainer

var _steps: Array[Dictionary] = []
var _index := -1


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	for view in _root.get_children():
		var skip := view.get_node_or_null("Dialog/Content/Actions/Skip") as Button
		if skip != null:
			skip.pressed.connect(_finish_guide)
	get_viewport().size_changed.connect(_refresh_layout)
	_root.visible = false
	var bus := get_node("/root/EventBus")
	bus.connect("game_loaded", Callable(self, "_resume_saved_guide"))
	bus.connect("game_reset", Callable(self, "_hide_for_reset"))
	bus.connect("fish_sold", Callable(self, "_on_fish_sold"))
	for event_name in ["crop_harvested", "workbench_unlocked", "bait_crafted", "fish_caught", "shop_unlocked"]:
		bus.connect(event_name, Callable(self, "_on_progress_event"))
	call_deferred("_resume_saved_guide")


# 处理未被界面消费的键盘事件。
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F1:
		if _index >= 0:
			_finish_guide()
		else:
			start_guide()
		get_viewport().set_input_as_handled()


# 随渲染帧更新状态，时间增量以秒计。
func _process(_delta: float) -> void:
	if _index >= 0:
		_check_progress()
	if _root.visible:
		_refresh_layout()


# 首次点击当前聚焦区域即收起整层指引，不吞掉点击；隐藏期间仍等待实际操作完成，不提前跳步。
func _input(event: InputEvent) -> void:
	if not _root.visible or _index < 0 or _focus == null or _dialog == null or not _focus.is_visible_in_tree():
		return
	var click := event as InputEventMouseButton
	if click == null or click.button_index != MOUSE_BUTTON_LEFT or not click.pressed:
		return
	_refresh_layout()
	var focus_point := _focus.get_global_transform_with_canvas().affine_inverse() * click.position
	var dialog_point := _dialog.get_global_transform_with_canvas().affine_inverse() * click.position
	if Rect2(Vector2.ZERO, _focus.size).has_point(focus_point) and not Rect2(Vector2.ZERO, _dialog.size).has_point(dialog_point):
		_root.hide()
		get_node("/root/GameState").flags["tutorial_intro_waiting_step"] = _index
		get_node("/root/SaveManager").request_save()


# 启动 guide，供调用方继续处理。
func start_guide() -> void:
	if not _load_steps():
		return
	_index = 0
	var state: Variant = get_node("/root/GameState")
	state.flags["tutorial_intro_active"] = true
	state.flags["tutorial_intro_completed"] = false
	state.flags["tutorial_intro_step"] = 0
	state.flags["tutorial_intro_waiting_step"] = -1
	state.flags["tutorial_initial_harvest_before"] = int(Time.get_unix_time_from_system())
	state.flags["tutorial_first_fish_sale_done"] = false
	show()
	_root.visible = true
	_show_step()
	_check_progress()
	get_node("/root/SaveManager").request_save()


# 只恢复已由新游戏明确启动的指引，旧存档不因存档目录迁移而误弹出；步骤跟随完整存档保存。
func _resume_saved_guide() -> void:
	var state: Variant = get_node("/root/GameState")
	if not auto_start_for_new_save or not bool(state.flags.get("tutorial_intro_active", false)) or bool(state.flags.get("tutorial_intro_completed", false)):
		_hide_for_reset()
		return
	if _load_steps():
		_index = clampi(int(state.flags.get("tutorial_intro_step", 0)), 0, _steps.size() - 1)
		show()
		_root.show()
		_show_step(int(state.flags.get("tutorial_intro_waiting_step", -1)) != _index)
		_check_progress()


# 清理旧游戏的可见指引，但不改写即将加载或重置的存档标记。
func _hide_for_reset() -> void:
	_root.hide()
	_index = -1


# 在事件后的下一帧检查，以便业务系统先完成库存、收获统计等状态更新。
func _on_progress_event(_a: Variant = null, _b: Variant = null) -> void:
	call_deferred("_check_progress")


# 真实出售事件记录首笔成交，不能用打开商店或仅选择鱼类代替。
func _on_fish_sold(_fish_id: String, amount: int, coins: int) -> void:
	var state: Variant = get_node("/root/GameState")
	if amount > 0 and coins > 0 and bool(state.flags.get("tutorial_intro_active", false)):
		state.flags["tutorial_first_fish_sale_done"] = true
		call_deferred("_check_progress")


# 完成条件读取真实进度；初始地块全部收获后才进入工坊，钓鱼步骤等待第一条鱼入库。
func _step_completed() -> bool:
	if _index < 0 or _index >= _steps.size():
		return false
	var state: Variant = get_node("/root/GameState")
	match str(_steps[_index].get("completion", "")):
		"initial_harvest":
			var plot: Dictionary = state.get_plot(str(_steps[_index].get("plot_id", "6")))
			if plot.is_empty() or state.harvested_crop_totals.is_empty():
				return false
			var initial_before := int(state.flags.get("tutorial_initial_harvest_before", Time.get_unix_time_from_system()))
			for cell in plot.get("cells", []):
				if not str(cell.get("crop", "")).is_empty() and int(cell.get("planted_at", 0)) <= initial_before:
					return false
			return true
		"workbench_built":
			return bool(state.workbench_unlocked)
		"bait_crafted":
			return not state.workbench_crafted_baits.is_empty()
		"fish_caught":
			return not state.discovered_fish.is_empty()
		"shop_built":
			return bool(state.shop_unlocked)
		"fish_sold":
			return bool(state.flags.get("tutorial_first_fish_sale_done", false)) or int(state.achievement_stats.get("fish_sale_successes", 0)) > 0
	return false


# 连续补认已经达成的步骤，写入当前步骤，防止读档或重复事件导致回退；完成后自动收起。
func _check_progress() -> void:
	if _index < 0:
		return
	while _index < _steps.size() and _step_completed():
		_index += 1
		if _index >= _steps.size():
			_finish_guide()
			return
		var state: Variant = get_node("/root/GameState")
		state.flags["tutorial_intro_step"] = _index
		_show_step()
		get_node("/root/SaveManager").request_save()


# 显示 step，供调用方继续处理。
func show_step(step_id: String) -> void:
	if not _load_steps():
		return
	for index in range(_steps.size()):
		if str(_steps[index].get("id", "")) == step_id:
			_index = index
			show()
			_root.visible = true
			_show_step()
			return
	push_warning("Unknown tutorial step: %s" % step_id)


# 加载 steps，供调用方继续处理。
func _load_steps() -> bool:
	_steps.clear()
	var file := FileAccess.open(steps_file, FileAccess.READ)
	if file == null:
		push_warning("Tutorial config missing: %s" % steps_file)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_warning("Tutorial config is not a JSON object")
		return false
	var values: Variant = (parsed as Dictionary).get("steps", [])
	if not values is Array:
		return false
	for value in values:
		if value is Dictionary:
			_steps.append(value)
	return not _steps.is_empty()


# 切换对应静态步骤，reveal 为 false 时恢复点击后等待；显示坐标由本步骤的目标跟随组件换算。
func _show_step(reveal: bool = true) -> void:
	if _index < 0 or _index >= _steps.size():
		_finish_guide()
		return
	var step: Dictionary = _steps[_index]
	_active_step = _root.get_node_or_null(NodePath(str(step.get("view_node", "")))) as Control
	for view in _root.get_children():
		if view is Control:
			view.visible = view == _active_step
	if _active_step == null:
		push_error("Tutorial step has no static layout: %s" % str(step.get("id", "")))
		_root.hide()
		return
	_focus = _active_step.get_node("FocusFrame") as Panel
	_dialog = _active_step.get_node("Dialog") as PanelContainer
	_root.visible = reveal
	if reveal:
		get_node("/root/GameState").flags["tutorial_intro_waiting_step"] = -1
	(_dialog.get_node("Content/Title") as Label).text = TextDB.text(str(step["title_id"]))
	(_dialog.get_node("Content/Message") as Label).text = TextDB.text(str(step["text_id"]))
	(_dialog.get_node("Content/Actions/StepCount") as Label).text = "%d / %d" % [_index + 1, _steps.size()]
	_refresh_layout()


# 结束 guide，供调用方继续处理。
func _finish_guide() -> void:
	_root.visible = false
	_index = -1
	var state := get_node_or_null("/root/GameState")
	if state != null:
		state.flags["tutorial_intro_completed"] = true
		state.flags["tutorial_intro_active"] = false
		state.flags["tutorial_intro_step"] = _steps.size()
		state.flags["tutorial_intro_waiting_step"] = -1
		var saver := get_node_or_null("/root/SaveManager")
		if saver != null:
			saver.request_save()


# 按当前目标相对编辑器基准的变换更新显示位置，再同步遮罩；手工布局仍保存在各步骤场景节点中。
func _refresh_layout() -> void:
	if _active_step != null and is_instance_valid(_active_step):
		_active_step.call("sync_layout")
