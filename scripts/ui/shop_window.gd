extends Window

@export_group("桌面定位")
@export var follow_shop: bool = true
@export var shop_offset: Vector2i = Vector2i.ZERO
@export var reward_offset := Vector2i.ZERO

@onready var _reward_window: Window = $SaleRewardWindow
@onready var _reward_toast: DropToast = $SaleRewardWindow/DropToast

const COIN_ICON := preload("res://assets/hd/ui/icon_coin_simple.png")


# 接入通用产出信号，出售全部时由 DropService 合并本轮金币收益。
func _ready() -> void:
	EventBus.item_dropped.connect(_on_item_dropped)
	visibility_changed.connect(_on_visibility_changed)
	_reward_toast.finished.connect(_reward_window.hide)


# 仅商店打开时展示商店来源的金币，避免其他产出被错误放到商店上方。
func _on_item_dropped(item_type: String, _item_id: String, amount: int, source_key: String) -> void:
	if not visible or source_key != "shop" or item_type != "coins" or amount <= 0:
		return
	var coin := AtlasTexture.new()
	coin.atlas = COIN_ICON
	coin.region = Rect2(700, 698, 1110, 1108)
	_reward_toast.configure(coin, TextDB.text("ui.61f608b0d9"), amount)
	var usable := DisplayServer.screen_get_usable_rect(current_screen)
	var desired := position + Vector2i(roundi(float(size.x - _reward_window.size.x) / 2.0), -_reward_window.size.y) + reward_offset
	_reward_window.position = Vector2i(
		clampi(desired.x, usable.position.x, maxi(usable.position.x, usable.end.x - _reward_window.size.x)),
		clampi(desired.y, usable.position.y, maxi(usable.position.y, usable.end.y - _reward_window.size.y))
	)
	_reward_window.show()
	_reward_window.transparent_bg = true
	_reward_window.transparent = true
	_reward_toast.present()


# 商店关闭时同步结束金币提示，避免残留在桌面。
func _on_visibility_changed() -> void:
	if not visible:
		_reward_toast.dismiss()
		_reward_window.hide()


# 处理未被界面消费的键盘事件。
func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()
