# 定义 DropToast 的状态和可用操作。
class_name DropToast
extends Node2D

signal finished

@export var reusable := false

var item_icon: Texture2D
var item_name: String = TextDB.text("ui.51fd93fb67")
var item_amount: int = 1
var fish_size_cm := 0
var fish_is_maximum := false
var _rest_position := Vector2.ZERO
var _motion: Tween


# 封装 configure 的处理，供相关流程复用。
func configure(icon: Texture2D, name: String, amount: int, size_cm: int = 0, is_maximum: bool = false) -> void:
	item_icon = icon
	item_name = name
	item_amount = amount
	fish_size_cm = size_cm
	fish_is_maximum = is_maximum


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	_rest_position = position
	if reusable:
		hide()
	else:
		present()


# 复用静态提示时从原位重新播放；动态掉落实例沿用播放后销毁的行为。
func present() -> void:
	dismiss()
	show()
	($ToastPanel/Contents/ItemRow/Icon as TextureRect).texture = item_icon
	($ToastPanel/Contents/ItemRow/Name as Label).text = item_name
	($ToastPanel/Contents/ItemRow/Amount as Label).text = "×%d" % item_amount
	var size_row := $ToastPanel/Contents/SizeRow as HBoxContainer
	size_row.visible = fish_size_cm > 0
	(size_row.get_node("Size") as Label).text = TextDB.text("fishing.size.value") % fish_size_cm
	(size_row.get_node("MaxBadge") as Label).visible = fish_is_maximum
	_motion = create_tween()
	_motion.tween_property(self, "position", _rest_position + Vector2(0, -38), 1.35).set_trans(Tween.TRANS_SINE)
	_motion.parallel().tween_property(self, "modulate:a", 0.0, 0.65).set_delay(0.70)
	_motion.tween_callback(_finish)


# 关闭或重播提示时清理旧动画，恢复静态节点的位置和透明度。
func dismiss() -> void:
	if _motion != null and _motion.is_running():
		_motion.kill()
	position = _rest_position
	modulate.a = 1.0
	hide()


# 通知宿主隐藏提示窗口；世界中的一次性飘字在结束后释放。
func _finish() -> void:
	hide()
	finished.emit()
	if not reusable:
		queue_free()
