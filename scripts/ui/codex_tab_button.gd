extends Button
# 定义 CodexTabButton 的状态和可用操作。
class_name CodexTabButton

## 图鉴筛选按钮只负责点击；背景和文字由可编辑的子节点绘制。
@export var selected_background: Texture2D

@onready var background: TextureRect = $Background
@onready var caption: Label = $Label

var _normal_background: Texture2D
var _selected := false


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	_normal_background = background.texture
	mouse_entered.connect(_refresh_background)
	mouse_exited.connect(_refresh_background)
	button_down.connect(_refresh_background)
	button_up.connect(_refresh_background)
	_refresh_background()


# 设置 caption，供调用方继续处理。
func set_caption(value: String) -> void:
	caption.text = value


# 设置 selected，供调用方继续处理。
func set_selected(value: bool) -> void:
	_selected = value
	disabled = value
	if is_node_ready():
		_refresh_background()


# 刷新 background，供调用方继续处理。
func _refresh_background() -> void:
	if selected_background == null:
		return
	background.texture = selected_background if _selected or is_hovered() or button_pressed else _normal_background
