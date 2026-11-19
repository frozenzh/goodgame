extends Window

signal new_game_confirmed
signal slot_load_requested(slot: int)

var _selected_slot := 0
var _pending_operation := ""
var _pending_slot := -1

@onready var _save_panel: PanelContainer = $SavePanel
@onready var _confirmation: ColorRect = $SaveConfirm

## 开始窗口按屏幕固定定位；Desktop Offset 为相对屏幕中心的桌面像素偏移。
@export_group("桌面定位")
@export var desktop_offset: Vector2i = Vector2i(0, 64)


# 所有存档行和操作都是静态节点；脚本只绑定信号、填入摘要及切换选择。
func _ready() -> void:
	$SavesButton.pressed.connect(_show_save_panel)
	$ExitButton.pressed.connect(_quit_game)
	$ButtonRow/NewGameButton.pressed.connect(_request_new_game)
	$SavePanel/Content/Actions/Back.pressed.connect(reset_view)
	$SavePanel/Content/Actions/Load.pressed.connect(_load_selected)
	$SavePanel/Content/Actions/Save.pressed.connect(_request_save)
	$SavePanel/Content/Actions/Delete.pressed.connect(_request_delete)
	$SaveConfirm/Panel/Margin/Content/Buttons/Confirm.pressed.connect(_confirm_operation)
	$SaveConfirm/Panel/Margin/Content/Buttons/Cancel.pressed.connect(func(): _confirmation.hide())
	for slot in range(SaveManager.MANUAL_SLOT_COUNT + 1):
		($SavePanel/Content/Rows.get_node("Slot%02d" % slot) as Button).pressed.connect(_select_slot.bind(slot))


# 回到开始菜单，保留本轮游戏暂停；返回菜单本身不进行存档替换。
func reset_view() -> void:
	_confirmation.hide()
	_save_panel.hide()
	$ButtonRow.show()
	$SavesButton.show()
	$ExitButton.show()
	$LogoZH.visible = TextDB.language == "zh"
	$LogoEN.visible = TextDB.language == "en"


# 打开固定六行的存档面板，自动槽永远位于第一行。
func _show_save_panel() -> void:
	$ButtonRow.hide()
	$SavesButton.hide()
	$ExitButton.hide()
	$LogoZH.hide()
	$LogoEN.hide()
	_save_panel.show()
	$SavePanel/Content/Message.text = ""
	_refresh_slots()


# 退出当前游戏；已有运行中的进度先写入自动存档，启动菜单尚未开始游戏时不覆盖存档。
func _quit_game() -> void:
	if SaveManager.startup_choice_done:
		SaveManager.save_game()
	get_tree().quit()


# 累计运行秒数格式化为时:分:秒，离线和暂停时间不计入。
func _runtime_text(seconds: int) -> String:
	return "%02d:%02d:%02d" % [floori(float(seconds) / 3600.0), floori(float(seconds % 3600) / 60.0), seconds % 60]


# 读取摘要；老存档没有本地时间字符串时，按当前电脑时区转换保存时间。
func _refresh_slots() -> void:
	for slot in range(SaveManager.MANUAL_SLOT_COUNT + 1):
		var row := $SavePanel/Content/Rows.get_node("Slot%02d" % slot) as Button
		var data := SaveManager.read_slot(slot)
		row.button_pressed = slot == _selected_slot
		(row.get_node("Columns/Name") as Label).text = TextDB.text("save_slots.auto") if slot == 0 else TextDB.text("save_slots.manual") % slot
		var local_time := str(data.get("saved_local_time", ""))
		if local_time.is_empty() and int(data.get("last_save_unix", 0)) > 0:
			local_time = Time.get_datetime_string_from_unix_time(int(data["last_save_unix"]) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60).replace("T", " ")
		(row.get_node("Columns/SavedAt") as Label).text = local_time if not data.is_empty() else TextDB.text("save_slots.empty")
		(row.get_node("Columns/Playtime") as Label).text = _runtime_text(int(data.get("playtime_seconds", 0))) if not data.is_empty() else "—"
		(row.get_node("Columns/Coins") as Label).text = str(int(data.get("coins", 0))) if not data.is_empty() else "—"
	var selected := SaveManager.read_slot(_selected_slot)
	$SavePanel/Content/Actions/Load.disabled = selected.is_empty()
	$SavePanel/Content/Actions/Delete.disabled = _selected_slot == 0 or selected.is_empty()
	$SavePanel/Content/Actions/Save.disabled = _selected_slot == 0 or not (SaveManager.startup_choice_done or SaveManager.has_saved_game())


# 改变选择后刷新三个操作按钮，自动槽无法进入替换或删除流程。
func _select_slot(slot: int) -> void:
	_selected_slot = slot
	_refresh_slots()


# 读取交由主界面重建场景；不把旧角色和队列的运行缓存带入所选存档。
func _load_selected() -> void:
	if not SaveManager.read_slot(_selected_slot).is_empty():
		slot_load_requested.emit(_selected_slot)


# 手动保存包括空槽首次写入和已用槽替换，都先确认并锁定本次操作槽号。
func _request_save() -> void:
	if _selected_slot > 0:
		_show_confirmation("save", _selected_slot, TextDB.text("save_slots.confirm_save") % _selected_slot)


# 删除仅支持手动槽，确认前再次验证存在数据。
func _request_delete() -> void:
	if _selected_slot > 0 and not SaveManager.read_slot(_selected_slot).is_empty():
		_show_confirmation("delete", _selected_slot, TextDB.text("save_slots.confirm_delete") % _selected_slot)


# 新游戏是替换自动存档的唯一手动入口；已有自动存档时必须二次确认，手动槽保留。
func _request_new_game() -> void:
	if SaveManager.has_saved_game():
		_show_confirmation("new", 0, TextDB.text("save_slots.confirm_new"))
	else:
		new_game_confirmed.emit()


# 静态遮罩阻止确认时继续点击底下的槽位和菜单。
func _show_confirmation(operation: String, slot: int, message: String) -> void:
	_pending_operation = operation
	_pending_slot = slot
	$SaveConfirm/Panel/Margin/Content/Message.text = message
	_confirmation.show()
	_confirmation.move_to_front()
	$SaveConfirm/Panel/Margin/Content/Buttons/Confirm.grab_focus()


# 确认后只执行记录的操作和槽号，失败保留原存档并在存档面板提示。
func _confirm_operation() -> void:
	_confirmation.hide()
	if _pending_operation == "new":
		new_game_confirmed.emit()
		return
	var succeeded := SaveManager.save_manual_slot(_pending_slot) if _pending_operation == "save" else SaveManager.delete_manual_slot(_pending_slot)
	$SavePanel/Content/Message.text = TextDB.text("save_slots.success" if succeeded else "save_slots.failed")
	_pending_operation = ""
	_pending_slot = -1
	_refresh_slots()
