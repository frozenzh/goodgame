extends Window

## GM建筑等级窗口：复用静态下拉框，应用时直接设置等级，不扣金币；既有资源和已解锁内容不因降级而删除。
@onready var cottage: OptionButton = $Frame/ContentSurface/CottageLevel
@onready var shop: OptionButton = $Frame/ContentSurface/ShopLevel
@onready var workshop: Label = $Frame/ContentSurface/WorkbenchLevel
@onready var status: Label = $Frame/ContentSurface/Status


# 只绑定静态控件；关闭子窗口不关闭父级GM面板。
func _ready() -> void:
	close_requested.connect(hide)
	$Frame/ContentSurface/CloseButton.pressed.connect(hide)
	$Frame/ContentSurface/CancelButton.pressed.connect(hide)
	$Frame/ContentSurface/ApplyButton.pressed.connect(_apply_levels)
	cottage.item_selected.connect(_preview_workbench)


# 每次打开都读取实际存档状态；选项从现有配置取值，不另造工坊独立等级字段。
func open_editor() -> void:
	cottage.clear()
	for level in range(1, 5):
		cottage.add_item(TextDB.text("gm.buildings.level") % level, level)
	shop.clear()
	shop.add_item(TextDB.text("gm.buildings.unbuilt"), 0)
	for level in range(1, 4):
		shop.add_item(TextDB.text("gm.buildings.level") % level, level)
	cottage.select(clampi(GameState.cottage_level - 1, 0, 3))
	shop.select(clampi(GameState.shop_level, 1, 3) if GameState.shop_unlocked else 0)
	status.text = ""
	_preview_workbench(cottage.selected)
	var parent_window := get_parent() as Window
	if parent_window != null:
		position = parent_window.position + (parent_window.size - size) / 2
	popup()


# 预览所选小屋对应的工坊等级，不提前写入状态；未建成工坊也只预览其等级配置。
func _preview_workbench(index: int) -> void:
	var data: Dictionary = GameState.get_cottage_data(index + 1)
	workshop.text = TextDB.text("gm.buildings.level") % maxi(1, int(data.get("workbench_tier", 1)))


# 避免正在施工或排队中的旧升级任务在GM设置后再次改写等级；只检查将要修改的建筑。
func _has_building_job(cottage_changed: bool, shop_changed: bool) -> bool:
	if cottage_changed and not GameState.get_cottage_construction().is_empty():
		return true
	var jobs := get_parent().get_parent().get_node_or_null("Systems/JobManager")
	if jobs == null:
		return false
	for command in jobs.call("get_pending_commands"):
		var action := str(command.get("action", ""))
		if cottage_changed and action in ["upgrade_cottage", "complete_cottage"]:
			return true
		if shop_changed and action == "complete_shop":
			return true
	return false


# 原子应用两项选择，刷新外观、云层、牧场及相关窗口并保存；降级只改变等级，不回收已有库存或解锁。
func _apply_levels() -> void:
	var cottage_level := cottage.get_selected_id()
	var shop_level := shop.get_selected_id()
	var cottage_changed := cottage_level != GameState.cottage_level
	var shop_changed := (shop_level > 0) != GameState.shop_unlocked or (shop_level > 0 and shop_level != GameState.shop_level)
	if _has_building_job(cottage_changed, shop_changed):
		status.text = TextDB.text("gm.buildings.busy")
		return
	var previous_shop_unlocked := GameState.shop_unlocked
	GameState.cottage_level = clampi(cottage_level, 1, 4)
	GameState.shop_level = clampi(shop_level, 1, 3)
	GameState.shop_unlocked = shop_level > 0
	# 使用与正常小屋升级一致的饵料解锁配置，补齐跨级设置时经过的各级内容。
	for level in range(1, GameState.cottage_level + 1):
		for bait_id in GameState.get_cottage_data(level).get("unlock_baits", []):
			if not GameState.unlocked_baits.has(str(bait_id)):
				GameState.unlocked_baits.append(str(bait_id))
	var main := get_parent().get_parent()
	var world := main.get_node_or_null("StaticWorldStrip")
	if world != null:
		world.call("set_cottage_level", GameState.cottage_level, false)
		world.call("set_shop_level", GameState.shop_level)
		world.call("set_building_unlock_states")
	if cottage_changed:
		EventBus.cottage_upgrade_completed.emit(GameState.cottage_level)
	if GameState.shop_unlocked and not previous_shop_unlocked:
		EventBus.shop_unlocked.emit()
	var shop_system := main.get_node_or_null("Systems/ShopSystem")
	if shop_changed and GameState.shop_unlocked and shop_system != null:
		GameState.shop_refresh_at = 0
		shop_system.call("refresh_offers_if_due")
	if main.has_method("_refresh"):
		main.call("_refresh")
	SaveManager.request_save()
	status.text = TextDB.text("gm.buildings.applied")
