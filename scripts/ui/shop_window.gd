extends Window

@export_group("桌面定位")
@export var follow_shop: bool = true
@export var shop_offset: Vector2i = Vector2i.ZERO


# 处理未被界面消费的键盘事件。
func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()
