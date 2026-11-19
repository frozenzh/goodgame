@tool
extends Control

## 六步各自保存静态布局；运行时以编辑器布局为基准跟随目标的显示变换。
## 编辑器仍直接拖动 FocusFrame、Dialog，运行时的换算结果不会写回场景。

@export_group("目标跟随")
@export_node_path("Node2D", "Control") var target_path: NodePath
@export var follow_target := true
@export_group("窗口边界")
@export var keep_dialog_on_screen := true
@export var screen_margin := Vector2(6.0, 6.0)
@export_group("文本框高度")
@export var auto_fit_dialog_height := true

var _target: CanvasItem
var _reference_transform := Transform2D.IDENTITY
var _reference_valid := false
var _authored_focus_position := Vector2.ZERO
var _authored_focus_size := Vector2.ZERO
var _authored_dialog_position := Vector2.ZERO


# 显示档位在 Main 的延迟初始化中应用；此处先保存场景原始布局及原始目标坐标，作为各档位共用基准。
func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var focus := get_node("FocusFrame") as Control
	var dialog := get_node("Dialog") as Control
	_authored_focus_position = focus.position
	_authored_focus_size = focus.size
	_authored_dialog_position = dialog.position
	if not target_path.is_empty():
		_target = get_node_or_null(target_path) as CanvasItem
	if _target != null:
		_reference_transform = get_global_transform_with_canvas().affine_inverse() * _target.get_global_transform_with_canvas()
		_reference_valid = not is_zero_approx(_reference_transform.determinant())


# 同时换算世界和指引画布坐标，保留每步手工设置的相对偏移；始终从原始布局计算，避免逐帧累积漂移。
func sync_layout() -> void:
	_fit_dialog_height()
	if Engine.is_editor_hint():
		sync_masks()
		return
	var focus := get_node("FocusFrame") as Control
	var dialog := get_node("Dialog") as Control
	var delta_transform := Transform2D.IDENTITY
	if follow_target and _reference_valid and is_instance_valid(_target):
		var current_transform := get_global_transform_with_canvas().affine_inverse() * _target.get_global_transform_with_canvas()
		delta_transform = current_transform * _reference_transform.affine_inverse()
	focus.position = delta_transform * _authored_focus_position
	var relative_scale := delta_transform.get_scale().abs()
	focus.size = _authored_focus_size * relative_scale
	var desired_dialog_position := delta_transform * _authored_dialog_position
	dialog.position = _fit_dialog(dialog, desired_dialog_position, focus) if keep_dialog_on_screen else desired_dialog_position
	sync_masks()


# 文本框限制在当前画布内；若边缘裁正导致原本分开的文本框盖住高亮框，优先放到高亮框另一侧。
func _fit_dialog(dialog: Control, desired: Vector2, focus: Control) -> Vector2:
	var margin := screen_margin.max(Vector2.ZERO)
	var maximum := (size - dialog.size - margin).max(Vector2.ZERO)
	var minimum := margin.min(maximum)
	var fitted := Vector2(clampf(desired.x, minimum.x, maximum.x), clampf(desired.y, minimum.y, maximum.y))
	var hole := focus.get_transform() * Rect2(Vector2.ZERO, focus.size)
	if Rect2(fitted, dialog.size).intersects(hole) and not Rect2(desired, dialog.size).intersects(hole):
		var right_side := hole.end.x + 12.0
		var left_side := hole.position.x - dialog.size.x - 12.0
		if right_side <= maximum.x:
			fitted.x = maxf(minimum.x, right_side)
		elif left_side >= minimum.x:
			fitted.x = minf(maximum.x, left_side)
	return fitted


# 编辑器可实时预览拖动高亮框后的遮罩；运行时由总指引控制器刷新当前步骤。
func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and is_visible_in_tree():
		_fit_dialog_height()
		sync_masks()


# 宽度沿用每步静态设置，高度取内容的自然最小高度；包含标题、换行正文、操作行和背景内边距。
func _fit_dialog_height() -> void:
	if not auto_fit_dialog_height:
		return
	var dialog := get_node_or_null("Dialog") as Control
	if dialog == null:
		return
	var natural_height := ceilf(dialog.get_combined_minimum_size().y)
	if natural_height > 0.0 and not is_equal_approx(dialog.size.y, natural_height):
		dialog.size = Vector2(dialog.size.x, natural_height)


# 遮罩同步当前高亮矩形，包含高亮节点本身的缩放；移到画面外时完整遮住背景。
func sync_masks() -> void:
	var focus := get_node_or_null("FocusFrame") as Control
	if focus == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var focus_rect := focus.get_transform() * Rect2(Vector2.ZERO, focus.size)
	var hole := focus_rect.intersection(Rect2(Vector2.ZERO, size))
	if not hole.has_area():
		_apply_mask("MaskTop", Rect2(Vector2.ZERO, size))
		for name in ["MaskLeft", "MaskRight", "MaskBottom"]:
			_apply_mask(name, Rect2())
		return
	_apply_mask("MaskTop", Rect2(0.0, 0.0, size.x, hole.position.y))
	_apply_mask("MaskLeft", Rect2(0.0, hole.position.y, hole.position.x, hole.size.y))
	_apply_mask("MaskRight", Rect2(hole.end.x, hole.position.y, size.x - hole.end.x, hole.size.y))
	_apply_mask("MaskBottom", Rect2(0.0, hole.end.y, size.x, size.y - hole.end.y))


# 仅修改确实变化的遮罩范围，避免编辑器持续产生无效改动；节点均来自静态场景。
func _apply_mask(node_name: String, rect: Rect2) -> void:
	var mask := get_node_or_null(NodePath(node_name)) as Control
	if mask == null:
		return
	if not mask.position.is_equal_approx(rect.position):
		mask.position = rect.position
	var desired_size := rect.size.max(Vector2.ZERO)
	if not mask.size.is_equal_approx(desired_size):
		mask.size = desired_size
