extends Window

## This window owns GM actions; MainUI only decides when and where to show it.
@export_group("桌面定位")
@export var follow_main: bool = true
@export var desktop_offset: Vector2i = Vector2i.ZERO

@onready var resource_option: OptionButton = $GMPopup/ContentSurface/ResourceOption
@onready var amount_spin: SpinBox = $GMPopup/ContentSurface/AmountSpin
@onready var status_label: Label = $GMPopup/ContentSurface/Status


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	$GMPopup/ContentSurface/AddButton.pressed.connect(_add_resource)
	$GMPopup/ContentSurface/MatureButton.pressed.connect(_mature_all_crops)
	$GMPopup/ContentSurface/ResetFishCodexButton.pressed.connect(_reset_fish_codex)
	$GMPopup/ContentSurface/SunnyButton.pressed.connect(_set_weather.bind("sunny"))
	$GMPopup/ContentSurface/RainButton.pressed.connect(_set_weather.bind("rain"))
	$GMPopup/ContentSurface/SnowButton.pressed.connect(_set_weather.bind("snow"))
	$GMPopup/ContentSurface/WindButton.pressed.connect(_set_weather.bind("wind"))
	$GMPopup/ContentSurface/AmbientFaunaButton.pressed.connect(_trigger_ambient_fauna)
	$GMPopup/ContentSurface/BuildingLevelsButton.pressed.connect(_open_building_levels)
	visibility_changed.connect(_sync_building_window_visibility)
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.game_loaded.connect(_populate_resources)
	_populate_resources()


# 封装 populate_resources 的处理，供相关流程复用。
func _populate_resources() -> void:
	resource_option.clear()
	_add_option(TextDB.text("ui.61f608b0d9"), "coins", "coins")
	_add_option(TextDB.text("ui.b8d943f914"), "fertilizer", "fish_fertilizer")
	var registry := get_node_or_null("/root/DataRegistry")
	if registry == null:
		return
	for category in ["crops", "baits", "fish", "pasture_products"]:
		resource_option.add_separator(str({"crops": TextDB.text("ui.b3aa8ab320"), "baits": TextDB.text("ui.9be962ae57"), "fish": TextDB.text("ui.cf7c3cc87a"), "pasture_products": TextDB.text("shop.products.tab")}[category]))
		for value in registry.get_all(category):
			if value is Dictionary:
				var item: Dictionary = value
				_add_option(str(item.get("display_name", item.get("id", ""))), category, str(item.get("id", "")))
	resource_option.select(0)


# 打开静态建筑等级子窗口，窗口自己管理下拉选择、应用和保存。
func _open_building_levels() -> void:
	$BuildingLevelsWindow.open_editor()


# 父GM窗口关闭时一并收起子窗口，避免菜单切换后留下独立窗口。
func _sync_building_window_visibility() -> void:
	if not visible:
		$BuildingLevelsWindow.hide()


# 添加 option，供调用方继续处理。
func _add_option(title: String, category: String, item_id: String) -> void:
	resource_option.add_item(title)
	resource_option.set_item_metadata(resource_option.item_count - 1, {"category": category, "id": item_id})


# 添加 resource，供调用方继续处理。
func _add_resource() -> void:
	var index := resource_option.selected
	if index < 0:
		_set_status(TextDB.text("ui.15606f6238"))
		return
	var data: Variant = resource_option.get_item_metadata(index)
	if not data is Dictionary:
		_set_status(TextDB.text("ui.2218e1f4dd"))
		return
	var category := str(data.get("category", ""))
	var item_id := str(data.get("id", ""))
	var amount := maxi(1, int(amount_spin.value))
	match category:
		"coins": DropService.grant_coins(amount, "gm")
		"fertilizer": DropService.grant_fertilizer(amount, "gm")
		"crops": DropService.grant_item(item_id, amount, "gm", "crop")
		"baits": DropService.grant_item(item_id, amount, "gm", "bait")
		"fish": DropService.grant_fish(item_id, amount, "gm")
		"pasture_products": DropService.grant_item(item_id, amount, "gm", "pasture_product")
		_:
			_set_status(TextDB.text("ui.1e89a4f00f"))
			return
	if category == "baits":
		var state := get_node_or_null("/root/GameState")
		if state != null and str(state.selected_bait).is_empty():
			state.selected_bait = item_id
			EventBus.bait_changed.emit(item_id)
	_request_save()
	_set_status(TextDB.text("ui.2fe00b94de") % [resource_option.get_item_text(index), amount])


# 封装 mature_all_crops 的处理，供相关流程复用。
func _mature_all_crops() -> void:
	var state := get_node_or_null("/root/GameState")
	if state == null:
		return
	var now_unix := int(Time.get_unix_time_from_system())
	var count := 0
	for value in state.plots:
		if not value is Dictionary:
			continue
		var plot: Dictionary = value
		if not bool(plot.get("unlocked", false)) or str(plot.get("crop", "")).is_empty():
			continue
		var cells: Array = plot.get("cells", [])
		for value_cell in cells:
			var cell: Dictionary = value_cell
			if not str(cell.get("crop", "")).is_empty() and int(cell.get("mature_at", 0)) > now_unix:
				cell["leaf_at"] = mini(int(cell.get("leaf_at", 0)), now_unix)
				cell["mature_at"] = now_unix
				count += 1
		plot["mature_at"] = now_unix
	var world := get_parent().get_node_or_null("StaticWorldStrip")
	if world != null:
		world.call("set_plot_states", state.plots)
	var main := get_parent()
	if main != null and main.has_method("_refresh"):
		main.call("_refresh")
	if count > 0:
		_request_save()
	_set_status(TextDB.text("ui.eaa88c8451") % count)


# 重置 fish_codex，供调用方继续处理。
func _reset_fish_codex() -> void:
	var state := get_node_or_null("/root/GameState")
	if state == null:
		return
	state.discovered_fish.clear()
	state.fish_size_records.clear()
	_request_save()
	var main := get_parent()
	if main != null and main.has_method("_refresh"):
		main.call("_refresh")
	_set_status(TextDB.text("gm.fish_codex_reset"))


# 设置 weather，供调用方继续处理。
func _set_weather(weather_id: String) -> void:
	var weather := get_tree().get_first_node_in_group("weather_system")
	if weather == null or not weather.has_method("force_weather"):
		_set_status(TextDB.text("ui.a2c3bf0305"))
		return
	if not bool(weather.call("force_weather", weather_id)):
		_set_status(TextDB.text("ui.32a5be901d"))
		return
	var names := {"sunny": TextDB.text("ui.5656dc6e75"), "rain": TextDB.text("ui.d23564dfaf"), "snow": TextDB.text("ui.51ea8f26e9"), "wind": TextDB.text("weather.wind.name")}
	_set_status(TextDB.text("ui.c0aaacdc1c") % str(names.get(weather_id, weather_id)))


# 设置 status，供调用方继续处理。
func _set_status(message: String) -> void:
	status_label.text = message


# 手动触发环境生物，不更改天气和存档；显示本次新增数量，已有活动或安全条件不足时允许为零。
func _trigger_ambient_fauna() -> void:
	var fauna := get_parent().get_node_or_null("StaticWorldStrip/AmbientFauna")
	if fauna == null or not fauna.has_method("trigger_activity"):
		_set_status(TextDB.text("gm.ambient_unavailable"))
		return
	var result: Dictionary = fauna.call("trigger_activity")
	if not bool(result.get("weather_allowed", false)):
		_set_status(TextDB.text("gm.ambient_sunny_required"))
		return
	_set_status(TextDB.text("gm.ambient_triggered") % [int(result.get("butterflies", 0)), int(result.get("birds", 0))])


# 请求 save，供调用方继续处理。
func _request_save() -> void:
	var saver := get_node_or_null("/root/SaveManager")
	if saver != null:
		saver.request_save()


# 处理未被界面消费的键盘事件。
func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()
