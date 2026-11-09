extends CanvasLayer

## 主窗口聚焦引导。四片遮罩留出真实可点击的空洞，步骤从 JSON 读取。

@export_file("*.json") var steps_file := "res://data/tutorial/intro.json"
@export var auto_start_for_new_save := true
@export var focus_padding := 5.0

@onready var _root: Control = $OverlayRoot
@onready var _top: ColorRect = $OverlayRoot/MaskTop
@onready var _left: ColorRect = $OverlayRoot/MaskLeft
@onready var _right: ColorRect = $OverlayRoot/MaskRight
@onready var _bottom: ColorRect = $OverlayRoot/MaskBottom
@onready var _focus: Panel = $OverlayRoot/FocusFrame
@onready var _dialog: PanelContainer = $OverlayRoot/Dialog
@onready var _title: Label = $OverlayRoot/Dialog/Content/Title
@onready var _message: Label = $OverlayRoot/Dialog/Content/Message
@onready var _step_count: Label = $OverlayRoot/Dialog/Content/Actions/StepCount
@onready var _next: Button = $OverlayRoot/Dialog/Content/Actions/Next
@onready var _skip: Button = $OverlayRoot/Dialog/Content/Actions/Skip

var _steps: Array[Dictionary] = []
var _index := -1
var _default_dialog_position := Vector2.ZERO


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	_default_dialog_position = _dialog.position
	_next.pressed.connect(_advance)
	_skip.pressed.connect(_finish_guide)
	get_viewport().size_changed.connect(_refresh_layout)
	_root.visible = false
	var is_new_save := not FileAccess.file_exists("user://save.json")
	if auto_start_for_new_save and is_new_save:
		call_deferred("start_guide")


# 处理未被界面消费的键盘事件。
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F1:
		if _root.visible:
			_finish_guide()
		else:
			start_guide()
		get_viewport().set_input_as_handled()


# 随渲染帧更新状态，时间增量以秒计。
func _process(_delta: float) -> void:
	if _root.visible:
		_refresh_layout()


# 启动 guide，供调用方继续处理。
func start_guide() -> void:
	if not _load_steps():
		return
	_index = 0
	_root.visible = true
	_show_step()


# 显示 step，供调用方继续处理。
func show_step(step_id: String) -> void:
	if not _load_steps():
		return
	for index in range(_steps.size()):
		if str(_steps[index].get("id", "")) == step_id:
			_index = index
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


# 显示 step，供调用方继续处理。
func _show_step() -> void:
	if _index < 0 or _index >= _steps.size():
		_finish_guide()
		return
	var step: Dictionary = _steps[_index]
	_title.text = TextDB.text(str(step.get("title_id", "tutorial.resources.title")))
	_message.text = TextDB.text(str(step.get("text_id", "tutorial.resources.text")))
	_step_count.text = "%d / %d" % [_index + 1, _steps.size()]
	_next.text = TextDB.text("ui.33246f6a5e") if _index == _steps.size() - 1 else TextDB.text("ui.ea0ef2ae72")
	_dialog.position = _default_dialog_position
	var requested_position: Variant = step.get("dialog_position", [])
	if requested_position is Array and requested_position.size() >= 2:
		_dialog.position = Vector2(float(requested_position[0]), float(requested_position[1]))
	_refresh_layout()


# 封装 advance 的处理，供相关流程复用。
func _advance() -> void:
	_index += 1
	_show_step()


# 结束 guide，供调用方继续处理。
func _finish_guide() -> void:
	_root.visible = false
	_index = -1
	var state := get_node_or_null("/root/GameState")
	if state != null:
		state.flags["tutorial_intro_completed"] = true
		var saver := get_node_or_null("/root/SaveManager")
		if saver != null:
			saver.request_save()


# 刷新 layout，供调用方继续处理。
func _refresh_layout() -> void:
	if _index < 0 or _index >= _steps.size():
		return
	var step: Dictionary = _steps[_index]
	var target_path := NodePath(str(step.get("target_path", "")))
	var target := get_parent().get_node_or_null(target_path) as CanvasItem
	if target == null or not target.is_visible_in_tree():
		return
	var target_rect := _canvas_item_rect(target)
	if target_rect.size == Vector2.ZERO:
		return
	var padding := maxf(0.0, float(step.get("padding", focus_padding)))
	var viewport_rect := Rect2(Vector2.ZERO, _root.size)
	var hole := target_rect.grow(padding).intersection(viewport_rect)
	if hole.size.x <= 0.0 or hole.size.y <= 0.0:
		return
	_set_rect(_top, Rect2(0.0, 0.0, _root.size.x, hole.position.y))
	_set_rect(_left, Rect2(0.0, hole.position.y, hole.position.x, hole.size.y))
	_set_rect(_right, Rect2(hole.end.x, hole.position.y, _root.size.x - hole.end.x, hole.size.y))
	_set_rect(_bottom, Rect2(0.0, hole.end.y, _root.size.x, _root.size.y - hole.end.y))
	_set_rect(_focus, hole)


# 封装 canvas_item_rect 的处理，供相关流程复用。
func _canvas_item_rect(item: CanvasItem) -> Rect2:
	var local_rect := Rect2()
	if item is Control:
		local_rect = Rect2(Vector2.ZERO, (item as Control).size)
	elif item is Sprite2D:
		local_rect = (item as Sprite2D).get_rect()
	else:
		return local_rect
	var transform_to_overlay := _root.get_global_transform_with_canvas().affine_inverse() * item.get_global_transform_with_canvas()
	var corners := [
		transform_to_overlay * local_rect.position,
		transform_to_overlay * Vector2(local_rect.end.x, local_rect.position.y),
		transform_to_overlay * local_rect.end,
		transform_to_overlay * Vector2(local_rect.position.x, local_rect.end.y),
	]
	var minimum: Vector2 = corners[0]
	var maximum: Vector2 = corners[0]
	for corner in corners:
		minimum = minimum.min(corner)
		maximum = maximum.max(corner)
	return Rect2(minimum, maximum - minimum)


# 设置 rect，供调用方继续处理。
func _set_rect(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size.max(Vector2.ZERO)
