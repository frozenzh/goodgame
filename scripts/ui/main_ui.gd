# 定义 MainUI 的状态和可用操作。
class_name MainUI
extends Control

const COLOR_INK := Color("#3f3028")
const COLOR_INSUFFICIENT_COINS := Color("#c73732")
const COLOR_BORDER := Color("#6f4c3b")
const DESIGN_SIZE := Vector2i(1280, 168)
enum DisplaySize { SMALL, MEDIUM, LARGE }
const PLOT_COUNT := 7
const DEFAULT_UNLOCKED_START_INDEX := 5
const CROP_IDS := ["wheat", "corn", "carrot", "white_radish", "strawberry", "tomato", "cabbage", "lettuce"]
const BAIT_TYPE_NAMES := {"grain": "ui.f0fc5e948c", "root": "ui.cf83151a3d", "fruit": "ui.a809d937da", "leaf": "ui.2acc1836c1"}
const FISH_RARITY_NAMES := {"common": "ui.7cda072d45", "good": "ui.3e61f36792", "rare": "ui.543cfd5dfd", "epic": "ui.a18ebc607f"}
const TASK_ACTION_NAMES := {
	"plant": "ui.f1e8a3ee6a", "plant_cell": "ui.f1e8a3ee6a", "water_cell": "ui.af3171150b",
	"harvest": "ui.08b8a9d6d1", "harvest_cell": "ui.08b8a9d6d1", "unlock_plot": "ui.4bcb5cb405",
	"craft_bait": "ui.05d54e5224", "select_bait": "ui.bd97d61ee7", "select_rod": "ui.4ecf15b05d",
	"upgrade_rod": "ui.5903b4eb21", "sell_common": "ui.cd9bea0fcf", "sell_all": "ui.1cc5015349",
	"buy_bait": "ui.e5306b7786", "convert_fish": "ui.a368fedf80", "upgrade_cottage": "ui.5fcb4d3c26",
	"complete_cottage": "ui.f08fd28247", "complete_workbench": "ui.1a50a4a733", "complete_shop": "ui.763676b954",
	"upgrade_pond": "ui.65ce952d5b", "start_fishing": "ui.763fbaf79a", "stop_fishing": "ui.077553e28d", "fishing": "ui.8124830197",
	"feed_pasture": "ui.f6feea46f4"
}


# 封装 bait_type_label 的处理，供相关流程复用。
func _bait_type_label(raw_types: String) -> String:
	var labels := PackedStringArray()
	for raw_type in raw_types.split(";"):
		var label := _localized_name(BAIT_TYPE_NAMES, raw_type.strip_edges(), "")
		if not label.is_empty():
			labels.append(label)
	return " / ".join(labels) if not labels.is_empty() else TextDB.text("ui.5dbd015496")


# 封装 localized_name 的处理，供相关流程复用。
func _localized_name(names: Dictionary, key: String, fallback: String) -> String:
	var id := str(names.get(key, ""))
	return TextDB.text(id) if not id.is_empty() else fallback
const FISH_PLACEHOLDER_ICON := preload("res://assets/hd/ui/icon_fish_simple.png")
const CROP_PLACEHOLDER_ICON := preload("res://assets/hd/ui/icon_crop_simple.png")
const BAIT_PLACEHOLDER_ICON := preload("res://assets/hd/ui/icon_bait_simple.png")
const ROD_PLACEHOLDER_ICON := preload("res://assets/hd/ui/icon_rod_simple.svg")
const COIN_ICON := preload("res://assets/hd/ui/icon_coin_simple.png")
const WOOD_CURSOR := preload("res://assets/ui/cursor_wood_arrow.png")
const FISH_GRAYSCALE_SHADER := preload("res://shaders/fish_grayscale.gdshader")
const FISH_SILHOUETTE_SHADER := preload("res://shaders/fish_silhouette.gdshader")
const ACHIEVEMENT_SILHOUETTE_SHADER := preload("res://shaders/achievement_silhouette.gdshader")
const CROP_CHOICE_CARD := preload("res://scenes/ui/CropChoiceCard.tscn")
const CROP_CODEX_CARD := preload("res://scenes/ui/CropCodexCard.tscn")
const BAIT_CODEX_CARD := preload("res://scenes/ui/BaitCodexCard.tscn")
const FISH_CODEX_CARD := preload("res://scenes/ui/FishCodexCard.tscn")
const SHOP_OFFER_CARD := preload("res://scenes/ui/ShopOfferCard.tscn")
const SHOP_OWNED_CARD := preload("res://scenes/ui/ShopOwnedCard.tscn")
const PRIMARY_BUTTON := preload("res://scenes/ui/PrimaryButton.tscn")
const SECONDARY_BUTTON := preload("res://scenes/ui/SecondaryButton.tscn")
const WORKBENCH_ITEM_CARD := preload("res://scenes/ui/WorkbenchItemCard.tscn")
const POND_BAIT_CARD := preload("res://scenes/ui/PondBaitCard.tscn")
const POPUP_NODE_NAMES := ["PlotPopup", "CottagePopup", "WorkbenchPopup", "PondPopup", "ShopPopup", "CodexPopup", "SettingsPopup", "GMPopup", "ResetPopup"]
const CODEX_WINDOW_POPUPS := ["CodexPopup"]
const FISH_RARITY_TABS := [
	{"id": "common", "label": "ui.7cda072d45"},
	{"id": "good", "label": "ui.3e61f36792"},
	{"id": "rare", "label": "ui.543cfd5dfd"},
	{"id": "epic", "label": "ui.a18ebc607f"},
]

@onready var GameConfig: Node = get_node("/root/GameConfig")
@onready var static_world: StaticWorldStrip = $StaticWorldStrip
@onready var codex_window: Window = $CodexWindow
@onready var shop_window: Window = $ShopWindow
@onready var _shop_content: Control = $ShopWindow/ShopPopup/ContentSurface/ContentScroll/Content/Body/ShopContent
@onready var _shop_timer: Timer = $ShopWindow/ShopPopup/ContentSurface/ContentScroll/Content/Body/ShopContent/CountdownTimer
@onready var settings_window: Window = $SettingsWindow
@onready var gm_window: Window = $GMWindow
@onready var task_window: Window = $TaskQueueWindow
@onready var plant_window: Window = $PlantWindow
@onready var cottage_window: Window = $CottageWindow
@onready var start_window: Window = $StartWindow
@onready var pasture_window: Window = $PastureWindow
@onready var pasture_feed_window: Window = $PastureFeedWindow
@onready var pasture: PastureManager = $StaticWorldStrip/PastureAreas
@onready var workbench_window: Window = $WorkbenchWindow
@onready var pond_window: Window = $PondWindow
@onready var overlay: Control = $Overlay
@onready var _toast: PanelContainer = $Notification
@onready var _toast_message: Label = $Notification/Message
@onready var _toast_timer: Timer = $Notification/Timer
@onready var _achievement_toast: PanelContainer = $AchievementToast
@onready var _achievement_toast_icon: TextureRect = $AchievementToast/Content/Icon
@onready var _achievement_toast_title: Label = $AchievementToast/Content/Text/Title
@onready var _achievement_toast_names: Label = $AchievementToast/Content/Text/Names
@onready var _achievement_toast_timer: Timer = $AchievementToast/Timer
@onready var plot_progress_anchor: Control = $PlotProgressAnchor
@onready var plot_progress_title: Label = $PlotProgressAnchor/Panel/Content/Title
@onready var plot_progress_bar: ProgressBar = $PlotProgressAnchor/Panel/Content/StageProgress
@onready var plot_progress_time: Label = $PlotProgressAnchor/Panel/Content/Time
@onready var plot_pending_plant: Label = $PlotProgressAnchor/Panel/Content/PendingPlant
@onready var plot_pending_harvest: Label = $PlotProgressAnchor/Panel/Content/PendingHarvest
@onready var plot_harvest_all: Button = $PlotProgressAnchor/Panel/Content/HarvestAll
@onready var plot_water_cell: Button = $PlotProgressAnchor/Panel/Content/WaterCell
@onready var plot_progress_timer: Timer = $PlotProgressAnchor/UpdateTimer

var _state: Node
var _event_bus: Node
var _services: Dictionary = {}
var _resource_labels: Dictionary = {}
var _modal: PanelContainer
var _modal_body: HBoxContainer
var _popups: Dictionary = {}
var _current_codex_tab := "fish"
var _current_fish_rarity := "common"
var _shop_selected_fish := ""
var _shop_tab := "fish"
var _shop_selected_product := ""
var _shop_selected_crop := ""
var _workbench_tab := "bait"
var _pond_tab := "bait"
var _leaderboard_ranks: Dictionary = {}
var _leaderboard_player_id := ""
var _pasture_pen := 4
var _pasture_selected_kind := "chicken"
var _feed_area := 3
var _feed_slot_index := 0
var _feed_page := 0
var _feed_selected_crop := ""
var _feed_quantity := 1
var _feed_crop_ids: Array[String] = []
var _workbench_selected_bait := ""
var _workbench_selected_rod := ""
var _workbench_quantity := 1
var _selected_crop_id := ""
var _selected_plot_index := -1
var _selected_cell_index := -1
var _crop_scroll_position := 0
var _always_on_top := false
var _stick_to_bottom := true
var _display_names: Array = []
var _plot_progress_index := -1
var _plot_progress_cell_index := -1
var _main_focus_was_lost := false
var _focus_activation_until_msec := 0
var _consume_activation_release := false
var _world_pan_active := false
var _world_pan_last_x := 0.0
var _world_pan_origin_x := 0.0
var _world_pan_max_offset := 0.0
var _large_view_pan := 0.0
var _display_size: int = DisplaySize.LARGE
var _display_width := DESIGN_SIZE.x
var _pending_crop_unlock_names := PackedStringArray()
var _crop_unlock_notice_queued := false
var _achievement_toast_queue: Array[Dictionary] = []
var _achievement_toast_tween: Tween
var _startup_has_save := false
var _coin_requirement_labels: Array[Label] = []
var _task_icon_click_count := 0
@onready var _task_icon_click_timer: Timer = $TaskButton/ClickTimer


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	# _apply_custom_cursor()   引用鼠标样式
	_world_pan_origin_x = static_world.position.x
	var landscape := static_world.get_node("StaticBackground/Landscape") as Sprite2D
	if landscape != null and landscape.texture != null:
		_world_pan_max_offset = minf(720.0, maxf(0.0, float(landscape.texture.get_width()) * absf(landscape.scale.x) - float(DESIGN_SIZE.x)))
	theme = _build_theme()
	codex_window.theme = theme
	shop_window.theme = theme
	settings_window.theme = theme
	gm_window.theme = theme
	task_window.theme = theme
	plant_window.theme = theme
	cottage_window.theme = theme
	start_window.theme = theme
	pasture_window.theme = theme
	pasture_feed_window.theme = theme
	workbench_window.theme = theme
	pond_window.theme = theme
	_build_hud()
	_build_modal()
	_toast_timer.timeout.connect(func(): _toast.visible = false)
	_toast_timer.wait_time = GameConfig.get_float("ui", "toast_seconds")
	_achievement_toast_timer.timeout.connect(_on_achievement_toast_timeout)
	plot_progress_timer.timeout.connect(_update_plot_progress)
	plot_harvest_all.pressed.connect(_harvest_all_mature)
	plot_water_cell.pressed.connect(_water_selected_cell)
	get_viewport().size_changed.connect(_layout_overlays)
	_main_focus_was_lost = not get_window().has_focus()
	get_window().focus_entered.connect(_on_main_window_focus_entered)
	get_window().focus_exited.connect(_on_main_window_focus_exited)
	mouse_exited.connect(func(): static_world.set_building_hover(""))
	_setup_pasture_window()
	_setup_pasture_feed_window()
	_setup_task_window()
	_task_icon_click_timer.timeout.connect(_on_task_icon_click_timeout)
	_connect_game()
	_startup_has_save = SaveManager.has_saved_game()
	(start_window.get_node("ButtonRow/ContinueButton") as Button).pressed.connect(_continue_game_from_start)
	(start_window.get_node("ButtonRow/NewGameButton") as Button).pressed.connect(_new_game_from_start)
	call_deferred("_apply_desktop_window")
	call_deferred("_layout_overlays")
	if not SaveManager.startup_choice_done:
		call_deferred("_show_start_window")


# func _apply_custom_cursor() -> void:
# 	var hotspot := Vector2(2, 2)
# 	Input.set_custom_mouse_cursor(WOOD_CURSOR, Input.CURSOR_ARROW, hotspot)
# 	Input.set_custom_mouse_cursor(WOOD_CURSOR, Input.CURSOR_POINTING_HAND, hotspot)
# 	Input.set_custom_mouse_cursor(WOOD_CURSOR, Input.CURSOR_DRAG, hotspot)
# 	Input.set_custom_mouse_cursor(WOOD_CURSOR, Input.CURSOR_CAN_DROP, hotspot)
# 	Input.set_custom_mouse_cursor(WOOD_CURSOR, Input.CURSOR_FORBIDDEN, hotspot)


# 显示 start_window，供调用方继续处理。
func _show_start_window() -> void:
	if SaveManager.startup_choice_done:
		return
	(start_window.get_node("ButtonRow/ContinueButton") as Button).visible = _startup_has_save
	(start_window.get_node("LogoZH") as TextureRect).visible = TextDB.language == "zh"
	(start_window.get_node("LogoEN") as TextureRect).visible = TextDB.language == "en"
	_position_building_window(start_window, "House")
	var final_position: Vector2i = start_window.position
	start_window.position = final_position + Vector2i(0, -24)
	_set_start_window_opacity(0.5)
	start_window.show()
	# 原生子窗口显示时会重置透明标志，必须在 show() 后重新设置。
	start_window.transparent_bg = true
	start_window.transparent = true
	get_tree().paused = true
	start_window.grab_focus()
	var entrance := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	entrance.set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	entrance.tween_property(start_window, "position", final_position, 0.38)
	entrance.tween_method(_set_start_window_opacity, 0.5, 1.0, 0.38)


# 设置 start_window_opacity，供调用方继续处理。
func _set_start_window_opacity(alpha: float) -> void:
	for node_name in ["LogoZH", "LogoEN", "ButtonRow"]:
		var visual := start_window.get_node(node_name) as CanvasItem
		var tint := visual.modulate
		tint.a = alpha
		visual.modulate = tint


# 封装 continue_game_from_start 的处理，供相关流程复用。
func _continue_game_from_start() -> void:
	SaveManager.startup_choice_done = true
	start_window.hide()
	get_tree().paused = false


# 封装 new_game_from_start 的处理，供相关流程复用。
func _new_game_from_start() -> void:
	if not SaveManager.delete_save_and_reset():
		push_error("Could not create a new game save")
		return
	SaveManager.startup_choice_done = true
	start_window.hide()
	get_tree().paused = false


# 封装 gui_input 的处理，供相关流程复用。
func _gui_input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouse
	if mouse_event == null:
		return
	# 弹窗由自己的 Control 处理输入；不要把内部点击继续当作世界点击。
	if (_modal != null and _modal.visible) or plot_progress_anchor.visible:
		static_world.set_building_hover("")
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		return
	var world_point := get_global_transform() * mouse_event.position
	if event is InputEventMouseMotion:
		if pasture.is_dragging():
			pasture.drag_to(world_point)
			accept_event()
			return
		if static_world.is_world_point_covered_by_cloud(world_point):
			static_world.set_building_hover("")
			mouse_default_cursor_shape = Control.CURSOR_ARROW
			return
		var building_zone := static_world.hit_test_building(world_point)
		static_world.set_building_hover(building_zone)
		var over_building := not building_zone.is_empty()
		var over_plot := static_world.hit_test_plot(world_point) >= 0
		var over_feed_slot := not pasture.hit_test_feed_slot(world_point).is_empty()
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if over_building or over_plot or over_feed_slot else Control.CURSOR_ARROW
		return
	var click := event as InputEventMouseButton
	if click == null or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if not click.pressed and pasture.is_dragging():
		pasture.end_drag(world_point)
		accept_event()
		return
	if not click.pressed:
		return
	if static_world.is_world_point_covered_by_cloud(world_point):
		accept_event()
		return
	var feed_slot := pasture.hit_test_feed_slot(world_point)
	if not feed_slot.is_empty():
		accept_event()
		_open_pasture_feed_window(int(feed_slot["area"]), int(feed_slot["slot"]))
		return
	if pasture.begin_drag(world_point):
		accept_event()
		return
	var zone := static_world.hit_test_building(world_point)
	if not zone.is_empty():
		static_world.set_building_hover("")
		accept_event()
		_on_zone_pressed(zone)
		return
	var plot_index := static_world.hit_test_plot(world_point)
	if plot_index >= 0:
		accept_event()
		_on_plot_pressed(plot_index, static_world.hit_test_plot_cell(plot_index, world_point))
		return
	if not _hud_backplate_hit(world_point) and static_world.hit_test_ground(world_point):
		var worker := static_world.get_node_or_null("DynamicAnchors/Worker") as WorkerActor
		if worker != null and worker.request_manual_move(world_point):
			static_world.show_ground_click_ripple(world_point)
			accept_event()


# 封装 hud_backplate_hit 的处理，供相关流程复用。
func _hud_backplate_hit(global_point: Vector2) -> bool:
	for group_name in ["CoinGroup", "CropGroup", "FishGroup", "BaitGroup"]:
		var board := overlay.get_node_or_null("%s/Board" % group_name) as Sprite2D
		if board != null and board.texture != null and board.is_visible_in_tree() and board.is_pixel_opaque(board.to_local(global_point)):
			return true
	return false


# 接收视口输入并处理本节点关注的事件。
func _input(event: InputEvent) -> void:
	if _handle_world_pan_input(event):
		return
	var click := event as InputEventMouseButton
	if click == null or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if not click.pressed:
		if _consume_activation_release:
			_consume_activation_release = false
			get_viewport().set_input_as_handled()
		return
	_consume_activation_release = false
	# 激活窗口的这一次点击只负责获得焦点，不执行地面移动或工作指令。
	if _main_focus_was_lost or Time.get_ticks_msec() < _focus_activation_until_msec:
		_main_focus_was_lost = false
		_focus_activation_until_msec = 0
		_consume_activation_release = true
		get_viewport().set_input_as_handled()
		return
	if _modal != null and _modal.visible:
		var modal_window: Window = _modal.get_window()
		if modal_window != get_window() or not _modal.get_global_rect().has_point(click.position):
			_close_modal()
			get_viewport().set_input_as_handled()
			return
	if plot_progress_anchor.visible:
		var progress_panel := plot_progress_anchor.get_node("Panel") as Control
		if not progress_panel.get_global_rect().has_point(click.position):
			_hide_plot_progress()
			get_viewport().set_input_as_handled()
			var world_point := get_global_transform() * click.position
			if not static_world.is_world_point_covered_by_cloud(world_point):
				var zone := static_world.hit_test_building(world_point)
				if zone in ["finish_cottage", "finish_workbench", "finish_shop"]:
					_on_zone_pressed(zone)


# 处理 world_pan_input，供调用方继续处理。
func _handle_world_pan_input(event: InputEvent) -> bool:
	if _display_size != DisplaySize.LARGE:
		return false
	var click := event as InputEventMouseButton
	if click != null and click.button_index == MOUSE_BUTTON_RIGHT:
		if click.pressed:
			_world_pan_active = (_modal == null or not _modal.visible) and get_window().has_focus() and Time.get_ticks_msec() >= _focus_activation_until_msec
			_world_pan_last_x = click.position.x
		else:
			_world_pan_active = false
		get_viewport().set_input_as_handled()
		return true
	var motion := event as InputEventMouseMotion
	if motion == null or not _world_pan_active:
		return false
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_world_pan_active = false
		return false
	var delta_x := motion.position.x - _world_pan_last_x
	_world_pan_last_x = motion.position.x
	var old_x := static_world.position.x
	var new_x := clampf(old_x + delta_x, _world_pan_origin_x, _world_pan_origin_x + _world_pan_max_offset)
	_set_world_view_x(new_x)
	get_viewport().set_input_as_handled()
	return true


# 平移场景时同步角色正在使用的世界坐标路径。x 为主画布坐标。
func _set_world_view_x(x: float) -> void:
	var delta_x := x - static_world.position.x
	if is_zero_approx(delta_x):
		return
	static_world.position.x = x
	var worker := static_world.get_node_or_null("DynamicAnchors/Worker") as WorkerActor
	if worker != null:
		worker.shift_world_coordinates(Vector2(delta_x, 0.0))
	if plot_progress_anchor.visible:
		_update_plot_progress()


# 读取保存的显示档位，旧存档默认为大。
func _saved_display_size() -> int:
	return clampi(int(_state.settings.get("display_size", DisplaySize.LARGE)), DisplaySize.SMALL, DisplaySize.LARGE)


# 大档保留原横移位置；中档显示至第一块开放牧场中心，小档显示完整的现有横移范围。
func _apply_display_size() -> void:
	var selected_size := _saved_display_size()
	if selected_size == _display_size:
		return
	if _display_size == DisplaySize.LARGE:
		_large_view_pan = static_world.position.x - _world_pan_origin_x
	_display_size = selected_size
	_world_pan_active = false
	var extra_width := 0.0
	if selected_size == DisplaySize.SMALL:
		extra_width = _world_pan_max_offset
	elif selected_size == DisplaySize.MEDIUM:
		var first_fence := static_world.get_node("PastureAreas/PastureArea03/Fence") as Node2D
		var fence_x := static_world.to_local(first_fence.global_position).x + _world_pan_origin_x
		extra_width = clampf(-fence_x, 0.0, _world_pan_max_offset)
	_display_width = DESIGN_SIZE.x + ceili(extra_width)
	_set_world_view_x(_world_pan_origin_x + (_large_view_pan if selected_size == DisplaySize.LARGE else extra_width))


# 根据逻辑画幅和所选屏幕计算实际窗口尺寸，保持原场景比例。
func _apply_desktop_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var window := get_window()
	_apply_display_size()
	var scale_factor_base := window.content_scale_factor
	window.content_scale_size = Vector2i(roundi(_display_width * scale_factor_base), roundi(DESIGN_SIZE.y * scale_factor_base))
	var screen := clampi(int(_state.settings.get("display_screen", DisplayServer.window_get_current_screen())), 0, maxi(0, DisplayServer.get_screen_count() - 1))
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var width_scale := float(usable.size.x) / float(_display_width)
	var height_scale: float = float(usable.size.y) / float(DESIGN_SIZE.y)
	var scale_factor: float = minf(width_scale, height_scale)
	var scaled_size := Vector2i(
		maxi(1, roundi(float(_display_width) * scale_factor)),
		maxi(1, roundi(float(DESIGN_SIZE.y) * scale_factor))
	)
	window.transparent_bg = true
	window.transparent = true
	window.borderless = true
	_always_on_top = bool(_dict_prop(_state, "settings").get("always_on_top", false))
	window.always_on_top = _always_on_top
	window.unresizable = true
	window.size = scaled_size
	window.position = Vector2i(
		usable.position.x + (usable.size.x - window.size.x) / 2,
		clampi(usable.end.y - window.size.y - int(_state.settings.get("display_raise", 0)), usable.position.y, maxi(usable.position.y, usable.end.y - window.size.y))
	)


# 处理未被界面消费的键盘事件。
func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _modal.visible:
		_close_modal()
		get_viewport().set_input_as_handled()


# 绑定 game，供调用方继续处理。
func _connect_game() -> void:
	_state = get_node_or_null("/root/GameState")
	_event_bus = get_node_or_null("/root/EventBus")
	for service_name in ["FarmingSystem", "CraftingSystem", "FishingSystem", "LeaderboardService", "ShopSystem", "CodexSystem", "AchievementSystem", "JobManager"]:
		_services[service_name] = _find_service(service_name)
	var jobs: Node = _services.get("JobManager")
	if jobs != null and jobs.has_signal("command_finished"):
		jobs.connect("command_finished", Callable(self, "_on_command_finished"))
	if _event_bus:
		_event_bus.game_loaded.connect(_apply_desktop_window, CONNECT_DEFERRED)
		_event_bus.game_reset.connect(_apply_desktop_window, CONNECT_DEFERRED)
		_event_bus.leaderboard_updated.connect(_on_leaderboard_updated)
		if _event_bus.has_signal("job_queue_changed"):
			_event_bus.connect("job_queue_changed", Callable(self, "_on_job_queue_changed"))
		if _event_bus.has_signal("job_started"):
			_event_bus.connect("job_started", func(_command: Dictionary): _refresh_task_window())
		_event_bus.connect("fish_cast_started", func(_bait_id: String, _ready_at: int): _refresh_task_window())
		_event_bus.connect("fishing_stopped", func(_reason: String): _refresh_task_window())
		for signal_name in [
			"game_loaded", "game_reset", "resource_changed", "inventory_changed", "fish_basket_changed",
			"crop_planted", "crop_harvested", "crop_unlocked", "crop_watered", "plot_unlocked", "plot_fertilized", "bait_crafted", "bait_changed",
			"rod_changed", "fish_cast_started", "fish_caught", "fishing_stopped", "codex_entry_unlocked",
			"workbench_unlocked", "shop_unlocked", "fish_sold", "bait_purchased", "fish_converted_to_fertilizer", "offline_result_ready",
			"cottage_construction_started", "cottage_upgrade_completed"
		]:
			if _event_bus.has_signal(signal_name):
				_event_bus.connect(signal_name, Callable(self, "_on_external_event"))
		_connect_event_notice("shop_unlocked", Callable(self, "_on_shop_unlocked"))
		_connect_event_notice("workbench_unlocked", Callable(self, "_on_workbench_unlocked"))
		_connect_event_notice("codex_entry_unlocked", Callable(self, "_on_first_codex_entry_unlocked"))
		_connect_event_notice("crop_unlocked", Callable(self, "_on_crop_unlocked"))
		_connect_event_notice("achievements_unlocked", Callable(self, "_on_achievements_unlocked"))
	_refresh()


# 响应 job_queue_changed 对应的事件或条件。
func _on_job_queue_changed() -> void:
	_refresh_task_window()
	_refresh_building_action_buttons()
	if plant_window.visible:
		_refresh_plant_coin_requirements()
	if plot_progress_anchor.visible:
		_update_plot_progress()


# 查找 service，供调用方继续处理。
func _find_service(service_name: String) -> Node:
	var root_service := get_node_or_null("/root/%s" % service_name)
	if root_service:
		return root_service
	var local_service := find_child(service_name, true, false)
	if local_service:
		return local_service
	var snake_group := service_name.trim_suffix("System").to_snake_case() + "_system"
	return get_tree().get_first_node_in_group(snake_group)


# 响应 external_event 对应的事件或条件。
func _on_external_event(_a = null, _b = null, _c = null, _d = null, _e = null) -> void:
	_refresh()


# 绑定 event_notice，供调用方继续处理。
func _connect_event_notice(signal_name: String, callable: Callable) -> void:
	if _event_bus and _event_bus.has_signal(signal_name) and not _event_bus.is_connected(signal_name, callable):
		_event_bus.connect(signal_name, callable)


# 响应 shop_unlocked 对应的事件或条件。
func _on_shop_unlocked() -> void:
	notify(TextDB.text("ui.5306a03a77"))


# 响应 workbench_unlocked 对应的事件或条件。
func _on_workbench_unlocked() -> void:
	notify(TextDB.text("ui.a993a36586"))


# 响应 achievements_unlocked 对应的事件或条件。
func _on_achievements_unlocked(ids: Array, migrated: bool) -> void:
	if ids.is_empty():
		return
	var registry := get_node_or_null("/root/DataRegistry")
	var names := PackedStringArray()
	var first_icon: Texture2D
	for id_value in ids:
		var id := str(id_value)
		var entry: Dictionary = registry.get_entry("achievements", id) if registry != null else {}
		names.append(str(entry.get("name", id)))
		if first_icon == null:
			var icon_path := str(entry.get("icon_unlocked", ""))
			if ResourceLoader.exists(icon_path):
				first_icon = load(icon_path) as Texture2D
	_sync_unlock_dots()
	_enqueue_achievement_toast(names, first_icon, migrated)
	if codex_window.visible and _current_codex_tab == "achievement":
		var content := codex_window.get_node_or_null("CodexPopup/ContentSurface/CodexContent") as Control
		if content != null:
			_build_achievement_codex(content)


# 封装 enqueue_achievement_toast 的处理，供相关流程复用。
func _enqueue_achievement_toast(names: PackedStringArray, icon: Texture2D, migrated: bool) -> void:
	_achievement_toast_queue.append({"names": names, "icon": icon, "migrated": migrated})
	if not _achievement_toast.visible:
		_show_next_achievement_toast()


# 显示 next_achievement_toast，供调用方继续处理。
func _show_next_achievement_toast() -> void:
	if _achievement_toast_queue.is_empty():
		_achievement_toast.visible = false
		_achievement_toast.modulate.a = 1.0
		return
	var item: Dictionary = _achievement_toast_queue.pop_front()
	var names: PackedStringArray = item.get("names", PackedStringArray())
	var count := names.size()
	_achievement_toast_title.text = TextDB.text("ui.6f8c049b65") % count if bool(item.get("migrated", false)) else (TextDB.text("ui.24a1e60aa3") % count if count > 1 else TextDB.text("ui.eec68cce90"))
	_achievement_toast_names.text = "、".join(names.slice(0, 2)) + (TextDB.text("ui.93ac7be2bc") if count > 2 else "")
	var icon: Texture2D = item.get("icon") as Texture2D
	if icon != null:
		_achievement_toast_icon.texture = icon
	_achievement_toast.visible = true
	_achievement_toast.modulate.a = 0.0
	if _achievement_toast_tween != null and _achievement_toast_tween.is_running():
		_achievement_toast_tween.kill()
	_achievement_toast_tween = create_tween()
	_achievement_toast_tween.tween_property(_achievement_toast, "modulate:a", 1.0, 0.22)
	_achievement_toast_timer.start()


# 响应 achievement_toast_timeout 对应的事件或条件。
func _on_achievement_toast_timeout() -> void:
	if _achievement_toast_tween != null and _achievement_toast_tween.is_running():
		_achievement_toast_tween.kill()
	_achievement_toast_tween = create_tween()
	_achievement_toast_tween.tween_property(_achievement_toast, "modulate:a", 0.0, 0.22)
	_achievement_toast_tween.tween_callback(_show_next_achievement_toast)


# 响应 first_codex_entry_unlocked 对应的事件或条件。
func _on_first_codex_entry_unlocked(entry_type: String, _entry_id: String) -> void:
	if _state == null:
		return
	if entry_type == "crop" and not _state.workbench_unlocked and _state.discovered_crops.size() == 1:
		notify(TextDB.text("ui.f91b1d06c2"))
	elif entry_type == "fish" and not _state.shop_unlocked and _state.discovered_fish.size() == 1:
		notify(TextDB.text("ui.cceb881aeb"))


# 响应 crop_unlocked 对应的事件或条件。
func _on_crop_unlocked(crop_id: String) -> void:
	_pending_crop_unlock_names.append(_display_id(crop_id))
	if not _crop_unlock_notice_queued:
		_crop_unlock_notice_queued = true
		call_deferred("_flush_crop_unlock_notice")


# 封装 flush_crop_unlock_notice 的处理，供相关流程复用。
func _flush_crop_unlock_notice() -> void:
	_crop_unlock_notice_queued = false
	if not _pending_crop_unlock_names.is_empty():
		notify(TextDB.text("ui.9cb9192f69") % "、".join(_pending_crop_unlock_names))
		_pending_crop_unlock_names.clear()


# 封装 refresh 的处理，供相关流程复用。
func _refresh() -> void:
	_sync_unlock_dots()
	_refresh_building_action_buttons()
	var inventory: Dictionary = _dict_prop(_state, "inventory")
	var basket: Dictionary = _dict_prop(_state, "fish_basket")
	var coins := int(_prop(_state, "coins", 0))
	var bait_id := String(_prop(_state, "selected_bait", ""))
	var bait_count := int(inventory.get(bait_id, 0)) if not bait_id.is_empty() else 0
	(_resource_labels["coins"] as Label).text = str(coins)
	(_resource_labels["crop"] as Label).text = str(_sum_dictionary(inventory, _catalog_crop_ids()))
	(_resource_labels["fish"] as Label).text = str(_sum_values(basket))
	(_resource_labels["bait"] as Label).text = str(bait_count)
	var plots_value = _prop(_state, "plots", [])
	var plots: Array = plots_value if plots_value is Array else []
	static_world.set_plot_states(plots)
	static_world.set_cottage_level(int(_prop(_state, "cottage_level", 1)))
	static_world.set_building_unlock_states()
	var construction: Dictionary = _state.call("get_cottage_construction") if _state != null else {}
	static_world.set_construction_state(construction)
	if _plot_progress_index >= 0:
		_update_plot_progress()
	if pond_window.visible and _modal != null and _modal.name == "PondPopup":
		_render_pond_content()
	if workbench_window.visible and _modal != null and _modal.name == "WorkbenchPopup":
		_render_workbench()
	if plant_window.visible:
		_refresh_plant_coin_requirements()
	_refresh_coin_requirement_colors()


# 为既有费用节点登记所需金币；负数表示当前不消耗金币，恢复节点原有字体颜色。
func _set_coin_requirement(label: Label, required_coins: int) -> void:
	if not label.has_meta("coin_requirement_default_color"):
		label.set_meta("coin_requirement_default_color", label.get_theme_color("font_color"))
	if not _coin_requirement_labels.has(label):
		_coin_requirement_labels.append(label)
	label.set_meta("required_coins", required_coins)
	var insufficient := required_coins > int(_prop(_state, "coins", 0))
	label.add_theme_color_override("font_color", COLOR_INSUFFICIENT_COINS if insufficient else label.get_meta("coin_requirement_default_color"))


# 金币变化后刷新已登记费用，移除释放的动态溢出条目；可复用同一节点而不残留红色。
func _refresh_coin_requirement_colors() -> void:
	var live_labels: Array[Label] = []
	for label in _coin_requirement_labels:
		if not is_instance_valid(label) or label.is_queued_for_deletion():
			continue
		live_labels.append(label)
		var required := int(label.get_meta("required_coins", -1))
		var insufficient := required > int(_prop(_state, "coins", 0))
		label.add_theme_color_override("font_color", COLOR_INSUFFICIENT_COINS if insufficient else label.get_meta("coin_requirement_default_color"))
	_coin_requirement_labels = live_labels


# 构建 hud，供调用方继续处理。
func _build_hud() -> void:
	_resource_labels = {
		"coins": overlay.get_node("CoinGroup/Amount"),
		"crop": overlay.get_node("CropGroup/Amount"),
		"fish": overlay.get_node("FishGroup/Amount"),
		"bait": overlay.get_node("BaitGroup/Amount"),
	}
	var codex_button := overlay.find_child("CodexHitArea", true, false) as Button
	if codex_button != null:
		codex_button.pressed.connect(_open_codex_from_icon)
	else:
		push_error(TextDB.text("ui.6598b63de2"))
	var settings_button := overlay.find_child("SettingsHitArea", true, false) as Button
	if settings_button != null:
		settings_button.pressed.connect(_open_settings)
	else:
		push_error(TextDB.text("ui.99810e5a04"))
	var gm_button := get_node_or_null("GMButton") as Button
	if gm_button != null:
		gm_button.hide()
		gm_button.pressed.connect(_open_gm)
	else:
		push_error(TextDB.text("ui.fb75045912"))
	var task_button := get_node_or_null("TaskButton/HitArea") as Button
	if task_button != null:
		task_button.pressed.connect(_on_task_icon_pressed)
	else:
		push_error(TextDB.text("ui.88867fc978"))


# 构建 modal，供调用方继续处理。
func _build_modal() -> void:
	# 场景编辑时可能临时显示原生子窗口预览，运行时先关掉。
	codex_window.hide()
	shop_window.hide()
	settings_window.hide()
	gm_window.hide()
	task_window.hide()
	plant_window.hide()
	cottage_window.hide()
	workbench_window.hide()
	pond_window.hide()
	for popup_name in POPUP_NODE_NAMES:
		var popup_path: String = popup_name
		if CODEX_WINDOW_POPUPS.has(popup_name):
			popup_path = "CodexWindow/%s" % popup_name
		elif popup_name == "ShopPopup":
			popup_path = "ShopWindow/ShopPopup"
		elif popup_name == "SettingsPopup":
			popup_path = "SettingsWindow/SettingsPopup"
		elif popup_name == "GMPopup":
			popup_path = "GMWindow/GMPopup"
		elif popup_name == "PlotPopup":
			popup_path = "PlantWindow/PlotPopup"
		elif popup_name == "CottagePopup":
			popup_path = "CottageWindow/CottagePopup"
		elif popup_name == "WorkbenchPopup":
			popup_path = "WorkbenchWindow/WorkbenchPopup"
		elif popup_name == "PondPopup":
			popup_path = "PondWindow/PondPopup"
		var popup := get_node_or_null(popup_path) as PanelContainer
		if popup == null:
			push_error(TextDB.text("ui.577283ac3e") % popup_name)
			continue
		_popups[popup_name] = popup
		popup.visible = false
		var close := popup.get_node_or_null("ContentSurface/CloseButton") as Button
		if close != null:
			close.pressed.connect(_close_modal)
	if _shop_timer != null:
		_shop_timer.timeout.connect(_on_shop_timer_tick)
	codex_window.close_requested.connect(_close_modal)
	shop_window.close_requested.connect(_close_modal)
	settings_window.close_requested.connect(_close_modal)
	gm_window.close_requested.connect(_close_modal)
	gm_window.get_node("GMPopup/ContentSurface/ResetProgressButton").pressed.connect(_open_reset_confirmation)
	plant_window.close_requested.connect(_close_modal)
	cottage_window.close_requested.connect(_close_modal)
	workbench_window.close_requested.connect(_close_modal)
	pond_window.close_requested.connect(_close_modal)
	_connect_subwindow_dismiss(codex_window)
	_connect_subwindow_dismiss(shop_window)
	_connect_subwindow_dismiss(settings_window)
	_connect_subwindow_dismiss(gm_window)
	_connect_subwindow_dismiss(plant_window)
	_connect_subwindow_dismiss(cottage_window)
	_connect_subwindow_dismiss(workbench_window)
	_connect_subwindow_dismiss(pond_window)
	pasture_window.focus_exited.connect(_on_pasture_window_focus_exited)
	_modal = _popups.get("PlotPopup") as PanelContainer


# 绑定 subwindow_dismiss，供调用方继续处理。
func _connect_subwindow_dismiss(popup_window: Window) -> void:
	popup_window.focus_exited.connect(_on_subwindow_focus_exited.bind(popup_window))


# 响应 subwindow_focus_exited 对应的事件或条件。
func _on_subwindow_focus_exited(popup_window: Window) -> void:
	call_deferred("_dismiss_unfocused_subwindow", popup_window)


# 响应 pasture_window_focus_exited 对应的事件或条件。
func _on_pasture_window_focus_exited() -> void:
	call_deferred("_dismiss_unfocused_pasture_window")


# 封装 dismiss_unfocused_pasture_window 的处理，供相关流程复用。
func _dismiss_unfocused_pasture_window() -> void:
	if pasture_window.visible and not pasture_window.has_focus():
		pasture_window.hide()


# 封装 dismiss_unfocused_subwindow 的处理，供相关流程复用。
func _dismiss_unfocused_subwindow(popup_window: Window) -> void:
	if popup_window == settings_window:
		return
	if _modal == null or not popup_window.visible or _modal.get_window() != popup_window:
		return
	if popup_window.has_focus():
		return
	for descendant in popup_window.find_children("*", "Window", true, false):
		var child_window := descendant as Window
		if child_window != null and child_window.visible:
			return
	_close_modal()


# 响应 main_window_focus_exited 对应的事件或条件。
func _on_main_window_focus_exited() -> void:
	_main_focus_was_lost = true
	_world_pan_active = false
	_focus_activation_until_msec = 0
	static_world.set_building_hover("")
	call_deferred("_dismiss_unfocused_main_popup")


# 响应 main_window_focus_entered 对应的事件或条件。
func _on_main_window_focus_entered() -> void:
	if _main_focus_was_lost:
		_focus_activation_until_msec = Time.get_ticks_msec() + 180
	_main_focus_was_lost = false


# 封装 dismiss_unfocused_main_popup 的处理，供相关流程复用。
func _dismiss_unfocused_main_popup() -> void:
	if get_window().has_focus():
		return
	if _modal != null and _modal.visible and _modal.get_window() == get_window():
		_close_modal()
	elif plot_progress_anchor.visible:
		_hide_plot_progress()


# 封装 layout_overlays 的处理，供相关流程复用。
func _layout_overlays() -> void:
	# 弹窗的位置和尺寸由 Main.tscn 的各 Popup 节点决定。
	# 保留此入口，兼容旧版调试工具；运行时不再覆盖编辑器拼接结果。
	pass


# 点击地块只打开种植或进度面板；cell_index 为 -1 时查看整块地。
func _on_plot_pressed(index: int, cell_index: int = -1) -> void:
	var plots_value = _prop(_state, "plots", [])
	var plots: Array = plots_value if plots_value is Array else []
	var plot: Dictionary = plots[index] if index >= 0 and index < plots.size() and plots[index] is Dictionary else {}
	var unlocked := bool(plot.get("unlocked", index >= DEFAULT_UNLOCKED_START_INDEX and index < PLOT_COUNT))
	var cells: Array = plot.get("cells", [])
	var selected_cell: Dictionary = cells[cell_index] if cell_index >= 0 and cell_index < cells.size() and cells[cell_index] is Dictionary else {}
	var selected_crop := str(selected_cell.get("crop", ""))
	var jobs: Node = _services.get("JobManager")
	var plot_id := str(plot.get("id", index))
	var work_status: Dictionary = jobs.call("get_plot_work_status", plot_id) if jobs != null and jobs.has_method("get_plot_work_status") else {}
	var has_plot_work := false
	var selected_target_queued := false
	for kind in ["plant", "harvest"]:
		if not work_status.get(kind, {}) is Dictionary:
			continue
		var entry: Dictionary = work_status.get(kind, {})
		if int(entry.get("total_count", 0)) > 0:
			has_plot_work = true
		if cell_index >= 0:
			var queued_targets: Array = entry.get("target_ids", []) if entry.get("target_ids", []) is Array else []
			selected_target_queued = selected_target_queued or queued_targets.has("%s:%d" % [plot_id, cell_index]) or queued_targets.has(plot_id + ":*")
	var show_progress := selected_target_queued or not selected_crop.is_empty()
	if cell_index < 0:
		show_progress = has_plot_work or not str(plot.get("crop", plot.get("crop_id", ""))).is_empty()
	if unlocked and show_progress:
		_close_modal()
		var grouped := bool(selected_cell.get("grouped", true))
		_show_plot_progress(index, -1 if grouped else cell_index)
	else:
		_hide_plot_progress()
		_open_plot(index, cell_index)


# 响应 zone_pressed 对应的事件或条件。
func _on_zone_pressed(zone: String) -> void:
	_hide_plot_progress()
	match zone:
		"cottage": _open_cottage()
		"workbench": _open_workbench()
		"pond": _open_pond()
		"shop": _open_shop()
		"pasture": _open_pasture()
		"finish_cottage": _finish_cottage_construction()
		"finish_workbench": _finish_building("workbench")
		"finish_shop": _finish_building("shop")


# 封装 setup_task_window 的处理，供相关流程复用。
func _setup_task_window() -> void:
	(task_window.get_node("Panel/Content/Header/Close") as Button).pressed.connect(func(): task_window.hide())
	task_window.close_requested.connect(func(): task_window.hide())
	task_window.focus_exited.connect(func(): call_deferred("_dismiss_unfocused_task_window"))
	for index in range(10):
		var row := task_window.get_node("Panel/Content/TaskRows/Row%02d" % (index + 1)) as Control
		(row.get_node("Content/Up") as Button).pressed.connect(_move_task_row.bind(index, -1))
		(row.get_node("Content/Down") as Button).pressed.connect(_move_task_row.bind(index, 1))
	_refresh_task_window()


# 封装 dismiss_unfocused_task_window 的处理，供相关流程复用。
func _dismiss_unfocused_task_window() -> void:
	if task_window.visible and not task_window.has_focus():
		task_window.hide()


# 队列图标在计时器间隔内连续三次点击打开 GM；稍后处理普通点击，避免首击弹窗抢走后续点击焦点。
func _on_task_icon_pressed() -> void:
	_task_icon_click_count += 1
	if _task_icon_click_count >= 3:
		_task_icon_click_timer.stop()
		_task_icon_click_count = 0
		_open_gm()
	else:
		_task_icon_click_timer.start()


# 单击或双击未组成三连击时，清空计数并沿用原有队列入口。
func _on_task_icon_click_timeout() -> void:
	_task_icon_click_count = 0
	_open_task_window()


# 打开 task_window，供调用方继续处理。
func _open_task_window() -> void:
	_close_modal()
	_refresh_task_window()
	_position_task_window()
	task_window.show()
	task_window.transparent_bg = true
	task_window.transparent = true


# 定位 task_window，供调用方继续处理。
func _position_task_window() -> void:
	if not bool(task_window.get("follow_main")) or DisplayServer.get_name() == "headless":
		return
	var main_window := get_window()
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var button := get_node("TaskButton") as Control
	var offset: Vector2i = task_window.get("desktop_offset")
	var button_x := button.position.x + button.size.x * 0.5
	var desired_x := _desktop_x_for_view_x(button_x) - task_window.size.x / 2 + offset.x
	var desired_y := main_window.position.y - task_window.size.y + offset.y
	task_window.position = Vector2i(
		clampi(desired_x, usable.position.x, maxi(usable.position.x, usable.end.x - task_window.size.x)),
		clampi(desired_y, usable.position.y, maxi(usable.position.y, usable.end.y - task_window.size.y))
	)


# 刷新 task_window，供调用方继续处理。
func _refresh_task_window() -> void:
	if task_window == null:
		return
	var jobs: Node = _services.get("JobManager") if _services.has("JobManager") else null
	if jobs == null:
		jobs = _find_service("JobManager")
	var tasks: Array = jobs.get_pending_tasks() if jobs != null else []
	var started_id := int(jobs.get_started_task_id()) if jobs != null else -1
	(task_window.get_node("Panel/Content/Header/Title") as Label).text = TextDB.text("ui.50d6ca4681") % tasks.size()
	(task_window.get_node("Panel/Content/EmptyHint") as Label).visible = tasks.is_empty()
	for index in range(10):
		var row := task_window.get_node("Panel/Content/TaskRows/Row%02d" % (index + 1)) as Control
		row.visible = index < tasks.size()
		if not row.visible:
			continue
		var command: Dictionary = tasks[index]
		var command_id := int(command.get("id", -1))
		var virtual_task := bool(command.get("virtual", false))
		var status := TextDB.text("ui.28febba225") if virtual_task or command_id == started_id else (TextDB.text("ui.23926d6146") if index == 0 else TextDB.text("ui.25d23b92b2"))
		(row.get_node("Content/TaskText") as Label).text = "%d. [%s] %s" % [index + 1, status, _task_command_label(command)]
		var up := row.get_node("Content/Up") as Button
		var down := row.get_node("Content/Down") as Button
		up.disabled = virtual_task or index == 0 or command_id == started_id or (index > 0 and int((tasks[index - 1] as Dictionary).get("id", -1)) == started_id)
		down.disabled = virtual_task or index >= tasks.size() - 1 or command_id == started_id or (index < tasks.size() - 1 and int((tasks[index + 1] as Dictionary).get("id", -1)) == started_id)
		if str(command.get("action", "")) in JobManager.BUILDING_COMPLETION_ACTIONS:
			up.disabled = true
			down.disabled = true
		elif index > 0 and str((tasks[index - 1] as Dictionary).get("action", "")) in JobManager.BUILDING_COMPLETION_ACTIONS:
			up.disabled = true


# 封装 task_command_label 的处理，供相关流程复用。
func _task_command_label(command: Dictionary) -> String:
	var action := str(command.get("action", ""))
	var label := _localized_name(TASK_ACTION_NAMES, action, action)
	var target_id := str(command.get("target_id", ""))
	var args: Array = command.get("args", []) if command.get("args", []) is Array else []
	if action in ["plant", "plant_cell"] and not args.is_empty():
		var registry := get_node_or_null("/root/DataRegistry")
		var crop: Dictionary = registry.get_crop(str(args[0])) if registry != null else {}
		label += " %s" % str(crop.get("name", args[0]))
	if action == "feed_pasture" and not args.is_empty():
		var registry := get_node_or_null("/root/DataRegistry")
		var crop: Dictionary = registry.get_crop(str(args[0])) if registry != null else {}
		label += " %s ×%d" % [str(crop.get("display_name", args[0])), maxi(1, int(args[1])) if args.size() > 1 else 1]
	if action in ["plant", "plant_cell", "harvest", "harvest_cell", "water_cell", "unlock_plot"]:
		label += TextDB.text("ui.f7a3d534bf") % _plot_display_number(int(target_id.get_slice(":", 0)))
		if target_id.contains(":") and not bool(command.get("task_grouped", false)):
			label += "-%d" % (int(target_id.get_slice(":", 1)) + 1)
	return label


# 移动 task_row，供调用方继续处理。
func _move_task_row(index: int, direction: int) -> void:
	var jobs: Node = _services.get("JobManager") if _services.has("JobManager") else null
	if jobs == null:
		jobs = _find_service("JobManager")
	if jobs == null:
		return
	var tasks: Array = jobs.get_pending_tasks()
	if index < tasks.size() and not bool((tasks[index] as Dictionary).get("virtual", false)):
		jobs.move_task(int((tasks[index] as Dictionary).get("id", -1)), direction)
	_refresh_task_window()


# 封装 setup_pasture_window 的处理，供相关流程复用。
func _setup_pasture_window() -> void:
	var surface := pasture_window.get_node("PasturePopup/ContentSurface") as Control
	(surface.get_node("CloseButton") as Button).pressed.connect(func(): pasture_window.hide())
	pasture_window.close_requested.connect(func(): pasture_window.hide())
	(surface.get_node("Pen3") as Button).pressed.connect(func(): _select_pasture_pen(3))
	(surface.get_node("Pen4") as Button).pressed.connect(func(): _select_pasture_pen(4))
	for kind in ["chicken", "pig", "sheep", "cow"]:
		var card := surface.get_node("AnimalGrid/%sCard" % kind.capitalize()) as Control
		(card.get_node("ClickArea") as Button).pressed.connect(_select_pasture_animal.bind(kind))
	(surface.get_node("DetailPanel/BuyButton") as Button).pressed.connect(func(): _buy_pasture_animal(_pasture_selected_kind))
	(surface.get_node("DetailPanel/Feed") as Button).pressed.connect(_feed_pasture)


# 打开 pasture，供调用方继续处理。
func _open_pasture() -> void:
	if not pasture.is_unlocked():
		notify(TextDB.text("ui.60972b2362"))
		return
	_close_modal()
	_refresh_pasture_window()
	_position_pasture_window()
	pasture_window.show()
	pasture_window.transparent_bg = true
	pasture_window.transparent = true


# 定位 pasture_window，供调用方继续处理。
func _position_pasture_window() -> void:
	if not bool(pasture_window.get("follow_main")) or DisplayServer.get_name() == "headless":
		return
	var main_window := get_window()
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var barn := pasture.get_node("PastureBarn") as Node2D
	var offset: Vector2i = pasture_window.get("desktop_offset")
	var desired_x := _desktop_x_for_view_x(barn.global_position.x) - pasture_window.size.x / 2 + offset.x
	var desired_y := main_window.position.y - pasture_window.size.y + offset.y
	pasture_window.position = Vector2i(
		clampi(desired_x, usable.position.x, maxi(usable.position.x, usable.end.x - pasture_window.size.x)),
		clampi(desired_y, usable.position.y, maxi(usable.position.y, usable.end.y - pasture_window.size.y))
	)


# 选择 pasture_pen，供调用方继续处理。
func _select_pasture_pen(id: int) -> void:
	_pasture_pen = id
	_refresh_pasture_window()


# 选择 pasture_animal，供调用方继续处理。
func _select_pasture_animal(kind: String) -> void:
	_pasture_selected_kind = kind
	_refresh_pasture_window()


# 刷新 pasture_window，供调用方继续处理。
func _refresh_pasture_window() -> void:
	var surface := pasture_window.get_node("PasturePopup/ContentSurface") as Control
	var count := pasture.get_animal_count(_pasture_pen)
	var capacity := pasture.get_pen_capacity()
	(surface.get_node("Status") as Label).text = TextDB.text("ui.7f9c2df93d") % [TextDB.text("ui.2480d664f0") if _pasture_pen == 3 else TextDB.text("ui.6b3e4e0f6a"), count, capacity]
	(surface.get_node("Pen3") as Button).text = ("✓ " if _pasture_pen == 3 else "") + TextDB.text("ui.2480d664f0")
	(surface.get_node("Pen4") as Button).text = ("✓ " if _pasture_pen == 4 else "") + TextDB.text("ui.6b3e4e0f6a")
	for kind in ["chicken", "pig", "sheep", "cow"]:
		var card := surface.get_node("AnimalGrid/%sCard" % kind.capitalize()) as Control
		(card.get_node("Name") as Label).text = TextDB.text(str(PastureManager.NAMES[kind]))
		(card.get_node("Price") as Label).text = TextDB.text("ui.71acb83c92") % pasture.get_price(kind)
		_set_coin_requirement(card.get_node("Price") as Label, pasture.get_price(kind))
		(card.get_node("SelectedFrame") as Control).visible = kind == _pasture_selected_kind
	var detail := surface.get_node("DetailPanel") as Control
	var selected_card := surface.get_node("AnimalGrid/%sCard" % _pasture_selected_kind.capitalize()) as Control
	(detail.get_node("AnimalIcon") as TextureRect).texture = (selected_card.get_node("Icon") as TextureRect).texture
	(detail.get_node("AnimalName") as Label).text = TextDB.text(str(PastureManager.NAMES[_pasture_selected_kind]))
	(detail.get_node("AnimalPrice") as Label).text = TextDB.text("ui.fab742762b") % pasture.get_price(_pasture_selected_kind)
	_set_coin_requirement(detail.get_node("AnimalPrice") as Label, pasture.get_price(_pasture_selected_kind))
	(detail.get_node("AnimalInfo") as Label).text = TextDB.text("ui.61e8d1fd78") % [count, capacity]
	(detail.get_node("BuyButton") as Button).disabled = count >= capacity


# 封装 buy_pasture_animal 的处理，供相关流程复用。
func _buy_pasture_animal(kind: String) -> void:
	if pasture.buy_animal(kind, _pasture_pen):
		notify(TextDB.text("ui.770c993a87") % TextDB.text(str(PastureManager.NAMES[kind])))
	else:
		notify(TextDB.text("ui.dce8e58c81"))
	_refresh_pasture_window()


# 封装 feed_pasture 的处理，供相关流程复用。
func _feed_pasture() -> void:
	_open_pasture_feed_window(_pasture_pen, 0)


# 封装 setup_pasture_feed_window 的处理，供相关流程复用。
func _setup_pasture_feed_window() -> void:
	var surface := pasture_feed_window.get_node("FeedPopup/ContentSurface") as Control
	(surface.get_node("CloseButton") as Button).pressed.connect(func(): pasture_feed_window.hide())
	pasture_feed_window.close_requested.connect(func(): pasture_feed_window.hide())
	pasture_feed_window.focus_exited.connect(func(): call_deferred("_dismiss_unfocused_pasture_feed_window"))
	(surface.get_node("Previous") as Button).pressed.connect(func(): _change_pasture_feed_page(-1))
	(surface.get_node("Next") as Button).pressed.connect(func(): _change_pasture_feed_page(1))
	var quantity_control := surface.get_node("DetailPanel/QuantityControl") as HBoxContainer
	(quantity_control.get_node("Minus") as Button).pressed.connect(func(): _change_pasture_feed_quantity(-1))
	(quantity_control.get_node("Plus") as Button).pressed.connect(func(): _change_pasture_feed_quantity(1))
	(quantity_control.get_node("Max") as Button).pressed.connect(_set_pasture_feed_max)
	(surface.get_node("DetailPanel/AddButton") as Button).pressed.connect(_confirm_pasture_feed)
	for index in range(8):
		var card := surface.get_node("CardGrid/Crop%02d" % (index + 1)) as Control
		(card.get_node("ClickArea") as Button).pressed.connect(_select_pasture_feed_card.bind(index))


# 封装 dismiss_unfocused_pasture_feed_window 的处理，供相关流程复用。
func _dismiss_unfocused_pasture_feed_window() -> void:
	if pasture_feed_window.visible and not pasture_feed_window.has_focus():
		pasture_feed_window.hide()


# 打开 pasture_feed_window，供调用方继续处理。
func _open_pasture_feed_window(area_id: int, _slot_index: int) -> void:
	if not pasture.is_unlocked():
		return
	_close_modal()
	_feed_area = area_id
	_feed_slot_index = 0
	_feed_page = 0
	_feed_selected_crop = ""
	_feed_quantity = 1
	_refresh_pasture_feed_window()
	_position_pasture_feed_window()
	pasture_feed_window.show()
	pasture_feed_window.transparent_bg = true
	pasture_feed_window.transparent = true


# 定位 pasture_feed_window，供调用方继续处理。
func _position_pasture_feed_window() -> void:
	if not bool(pasture_feed_window.get("follow_main")) or DisplayServer.get_name() == "headless":
		return
	var main_window := get_window()
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var slot := pasture.get_node("PastureArea%02d/FeedSlots/Slot%d" % [_feed_area, _feed_slot_index + 1]) as Node2D
	var offset: Vector2i = pasture_feed_window.get("desktop_offset")
	var desired_x := _desktop_x_for_view_x(slot.global_position.x) - pasture_feed_window.size.x / 2 + offset.x
	var desired_y := main_window.position.y - pasture_feed_window.size.y + offset.y
	pasture_feed_window.position = Vector2i(
		clampi(desired_x, usable.position.x, maxi(usable.position.x, usable.end.x - pasture_feed_window.size.x)),
		clampi(desired_y, usable.position.y, maxi(usable.position.y, usable.end.y - pasture_feed_window.size.y))
	)


# 封装 change_pasture_feed_page 的处理，供相关流程复用。
func _change_pasture_feed_page(direction: int) -> void:
	var page_count := maxi(1, ceili(float(_feed_crop_ids.size()) / 8.0))
	_feed_page = clampi(_feed_page + direction, 0, page_count - 1)
	_refresh_pasture_feed_window()


# 选择 pasture_feed_card，供调用方继续处理。
func _select_pasture_feed_card(index: int) -> void:
	var catalog_index := _feed_page * 8 + index
	if catalog_index < _feed_crop_ids.size():
		_feed_selected_crop = _feed_crop_ids[catalog_index]
		_feed_quantity = 1
		_refresh_pasture_feed_window()


# 封装 change_pasture_feed_quantity 的处理，供相关流程复用。
func _change_pasture_feed_quantity(delta: int) -> void:
	_feed_quantity = clampi(_feed_quantity + delta, 1, maxi(1, pasture.get_max_feed_quantity(_feed_selected_crop)))
	_refresh_pasture_feed_window()


# 设置 pasture_feed_max，供调用方继续处理。
func _set_pasture_feed_max() -> void:
	_feed_quantity = maxi(1, pasture.get_max_feed_quantity(_feed_selected_crop))
	_refresh_pasture_feed_window()


# 刷新 pasture_feed_window，供调用方继续处理。
func _refresh_pasture_feed_window() -> void:
	var surface := pasture_feed_window.get_node("FeedPopup/ContentSurface") as Control
	var registry := get_node_or_null("/root/DataRegistry")
	_feed_crop_ids.clear()
	if registry != null and _state != null:
		for crop_value in registry.get_all("crops"):
			var crop := crop_value as Dictionary
			var crop_id := str(crop.get("id", ""))
			if int(_state.inventory.get(crop_id, 0)) >= GameConfig.get_int("pasture", "feed_crop_count"):
				_feed_crop_ids.append(crop_id)
	if not _feed_crop_ids.has(_feed_selected_crop):
		_feed_selected_crop = _feed_crop_ids[0] if not _feed_crop_ids.is_empty() else ""
	var max_quantity := pasture.get_max_feed_quantity(_feed_selected_crop)
	_feed_quantity = clampi(_feed_quantity, 1, maxi(1, max_quantity))
	var page_count := maxi(1, ceili(float(_feed_crop_ids.size()) / 8.0))
	_feed_page = clampi(_feed_page, 0, page_count - 1)
	(surface.get_node("SlotStatus") as Label).text = TextDB.text("ui.23041e37a8") % (TextDB.text("ui.2480d664f0") if _feed_area == 3 else TextDB.text("ui.6b3e4e0f6a"))
	(surface.get_node("PageStatus") as Label).text = TextDB.text("ui.b54c5d5a3c") % [_feed_page + 1, page_count]
	(surface.get_node("Previous") as Button).disabled = _feed_page == 0
	(surface.get_node("Next") as Button).disabled = _feed_page >= page_count - 1
	for index in range(8):
		var card := surface.get_node("CardGrid/Crop%02d" % (index + 1)) as Control
		var catalog_index := _feed_page * 8 + index
		card.visible = catalog_index < _feed_crop_ids.size()
		if not card.visible:
			continue
		var crop_id := _feed_crop_ids[catalog_index]
		var crop: Dictionary = registry.get_crop(crop_id)
		(card.get_node("Name") as Label).text = str(crop.get("display_name", crop_id))
		(card.get_node("Amount") as Label).text = TextDB.text("ui.7abc3f23d8") % int(_state.inventory.get(crop_id, 0))
		(card.get_node("SelectedFrame") as Control).visible = crop_id == _feed_selected_crop
		var icon_path := str(crop.get("icon_resource", ""))
		(card.get_node("Icon") as TextureRect).texture = load(icon_path) as Texture2D if ResourceLoader.exists(icon_path) else CROP_PLACEHOLDER_ICON
	var detail := surface.get_node("DetailPanel") as Control
	var chosen: Dictionary = registry.get_crop(_feed_selected_crop) if registry != null else {}
	var chosen_path := str(chosen.get("icon_resource", ""))
	(detail.get_node("SelectedIcon") as TextureRect).texture = load(chosen_path) as Texture2D if ResourceLoader.exists(chosen_path) else CROP_PLACEHOLDER_ICON
	(detail.get_node("SelectedName") as Label).text = str(chosen.get("display_name", TextDB.text("ui.bf1fabfad5")))
	var stock := pasture.get_food_slot_summary(_feed_area, _feed_slot_index)
	var crop_cost := maxi(1, GameConfig.get_int("pasture", "feed_crop_count")) * _feed_quantity
	var food_gain := maxi(1, GameConfig.get_int("pasture", "food_per_crop")) * _feed_quantity
	(detail.get_node("StockInfo") as Label).text = TextDB.text("ui.ac176a3793") % [int(stock.get("count", 0)), max_quantity, crop_cost, food_gain]
	var quantity_control := detail.get_node("QuantityControl") as HBoxContainer
	(quantity_control.get_node("Amount") as Label).text = str(_feed_quantity)
	(quantity_control.get_node("Minus") as Button).disabled = max_quantity <= 0 or _feed_quantity <= 1
	(quantity_control.get_node("Plus") as Button).disabled = max_quantity <= 0 or _feed_quantity >= max_quantity
	(quantity_control.get_node("Max") as Button).disabled = max_quantity <= 0 or _feed_quantity >= max_quantity
	var add_button := detail.get_node("AddButton") as Button
	add_button.text = TextDB.text("ui.350a789d49") % _feed_quantity
	add_button.disabled = max_quantity <= 0


# 封装 confirm_pasture_feed 的处理，供相关流程复用。
func _confirm_pasture_feed() -> void:
	if _feed_selected_crop.is_empty():
		return
	if pasture.request_feed_crop(_feed_area, _feed_slot_index, _feed_selected_crop, _feed_quantity):
		pasture_feed_window.hide()
		notify(TextDB.text("ui.1c92eebc13"))
	else:
		notify(TextDB.text("ui.d23be3df49"))
		_refresh_pasture_feed_window()


# 结束 building，供调用方继续处理。
func _finish_building(kind: String) -> void:
	if _state == null:
		return
	if kind == "workbench":
		if not _state.is_workbench_construction_ready():
			notify(TextDB.text("ui.021691ba2e"))
			return
		_queue_action("complete_workbench", "", [], TextDB.text("ui.e2708271d5"), TextDB.text("ui.3d5fb32f0a"))
	elif kind == "shop":
		if not _state.is_shop_construction_ready():
			notify(TextDB.text("ui.a82bffe248"))
			return
		_queue_action("complete_shop", "", [], TextDB.text("ui.b862d1b701"), TextDB.text("ui.9ea1e7a8ee"))


# 打开 plot，供调用方继续处理。
func _open_plot(index: int, cell_index: int = -1) -> void:
	(plant_window.get_node("CropInfoPanel") as Control).hide()
	var plots_value = _prop(_state, "plots", [])
	var plots: Array = plots_value if plots_value is Array else []
	var plot: Dictionary = plots[index] if index < plots.size() and plots[index] is Dictionary else {}
	var unlocked := bool(plot.get("unlocked", index >= DEFAULT_UNLOCKED_START_INDEX and index < PLOT_COUNT))
	var cells: Array = plot.get("cells", [])
	var selected_empty := cell_index >= 0 and cell_index < cells.size() and str((cells[cell_index] as Dictionary).get("crop", "")).is_empty()
	_new_modal(TextDB.text("ui.a14da1b3da") % _plot_display_number(index) if not unlocked else "", "PlotPopup")
	var plot_content := _modal.get_node("ContentSurface/PlotContent") as Control
	(_modal.get_node("ContentSurface/TitlePlank/TitleText") as Label).text = TextDB.text("ui.1009f1add7") if not unlocked else TextDB.text("ui.b8c71ea2d9")
	var locked_content := plot_content.get_node("LockedContent") as Control
	var selection_board := plot_content.get_node("SelectionBoard") as Control
	locked_content.visible = not unlocked
	selection_board.visible = unlocked
	if not unlocked:
		var info := locked_content.get_node("Info") as Label
		info.text = TextDB.text("ui.cce5faf2ce")
		var farming: Node = _services.get("FarmingSystem")
		var required_level := int(farming.call("get_plot_required_cottage_level", str(index))) if farming != null else 1
		if int(_prop(_state, "cottage_level", 1)) < required_level:
			info.text += "\n" + TextDB.text("ui.4faaa0fa9f") % required_level
		var unlock := locked_content.get_node("Unlock") as Button
		_clear_press_connections(unlock)
		unlock.set_meta("plot_index", index)
		unlock.disabled = not _can_queue_building_action("unlock_plot", str(index))
		unlock.text = TextDB.text("ui.1009f1add7")
		(locked_content.get_node("UnlockCostRow/Amount") as Label).text = str(_unlock_cost(index))
		_set_coin_requirement(locked_content.get_node("UnlockCostRow/Amount") as Label, _unlock_cost(index))
		unlock.pressed.connect(_unlock_plot.bind(index))
	else:
		var crop_row := selection_board.get_node("CropContainer/CropViewport/CropRow") as HBoxContainer
		var repeat_choice := selection_board.get_node("RepeatChoice") as CheckBox
		repeat_choice.button_pressed = false
		var fill_empty_cells := selection_board.get_node("FillEmptyCells") as CheckBox
		fill_empty_cells.button_pressed = true
		var scope_hint := selection_board.get_node_or_null("PlantScopeHint") as Label
		if scope_hint != null:
			scope_hint.text = TextDB.text("ui.d417e319b6") % (cell_index + 1) if selected_empty else TextDB.text("ui.46e3961ee3")
		_selected_plot_index = index
		_selected_cell_index = cell_index
		_selected_crop_id = ""
		var crop_viewport := selection_board.get_node("CropContainer/CropViewport") as ScrollContainer
		var previous := selection_board.get_node("PreviousCrops") as Button
		var next := selection_board.get_node("NextCrops") as Button
		_clear_press_connections(previous)
		_clear_press_connections(next)
		previous.pressed.connect(_scroll_crop_choices.bind(crop_viewport, -1))
		next.pressed.connect(_scroll_crop_choices.bind(crop_viewport, 1))
		var confirm := selection_board.get_node("ConfirmPlant") as Button
		_clear_press_connections(confirm)
		confirm.pressed.connect(_confirm_crop_choice.bind(repeat_choice, fill_empty_cells))
		confirm.disabled = true
		confirm.set_meta("plant_targets_available", _has_available_plant_targets(index, cell_index, fill_empty_cells.button_pressed))
		for connection in fill_empty_cells.toggled.get_connections():
			fill_empty_cells.toggled.disconnect(connection["callable"])
		fill_empty_cells.toggled.connect(_update_plant_confirm_availability.bind(index, cell_index, confirm))
		var unlocked_value: Variant = _prop(_state, "unlocked_crops", [])
		var unlocked_crops: Array = unlocked_value if unlocked_value is Array else []
		var registry := get_node_or_null("/root/DataRegistry")
		var crop_choices: Array = registry.get_all("crops") if registry != null else []
		var crop_slots := _data_slots(crop_row, CROP_CHOICE_CARD, crop_choices.size())
		for slot_index in range(crop_choices.size()):
			var crop: Dictionary = crop_choices[slot_index]
			var crop_id := str(crop["id"])
			var crop_button := crop_slots[slot_index] as Button
			_populate_crop_option(crop_button, crop)
			var is_unlocked := unlocked_crops.has(crop_id)
			crop_button.disabled = false
			crop_button.modulate = Color.WHITE
			var crop_icon := crop_button.get_node("MatureCropIcon") as TextureRect
			crop_icon.material = null
			if not is_unlocked:
				var silhouette := ShaderMaterial.new()
				silhouette.shader = FISH_SILHOUETTE_SHADER
				crop_icon.material = silhouette
			_clear_press_connections(crop_button)
			for connection in crop_button.mouse_entered.get_connections():
				crop_button.mouse_entered.disconnect(connection["callable"])
			for connection in crop_button.mouse_exited.get_connections():
				crop_button.mouse_exited.disconnect(connection["callable"])
			if not is_unlocked:
				crop_button.mouse_entered.connect(_show_crop_unlock_requirements.bind(crop))
			crop_button.mouse_exited.connect(_hide_crop_unlock_requirements)
			if is_unlocked:
				crop_button.pressed.connect(_select_crop_choice.bind(crop_id, crop_row, confirm))
			(crop_button.get_node("SelectedMark") as Label).visible = false
			(crop_button.get_node("SelectedBorder") as Panel).visible = false
			if _selected_crop_id.is_empty() and is_unlocked:
				_selected_crop_id = crop_id
				(crop_button.get_node("SelectedMark") as Label).visible = true
				(crop_button.get_node("SelectedBorder") as Panel).visible = true
				confirm.disabled = not bool(confirm.get_meta("plant_targets_available", false))
	_refresh_plant_coin_requirements()
	_show_modal()


# 封装 populate_crop_option 的处理，供相关流程复用。
func _populate_crop_option(card: Button, crop: Dictionary) -> void:
	var crop_id := str(crop.get("id", ""))
	var crop_name := str(crop.get("display_name", crop_id))
	card.set_meta("crop_id", crop_id)
	var icon := card.get_node("MatureCropIcon") as TextureRect
	var icon_path := str(crop.get("icon_resource", crop.get("mature_resource", "")))
	icon.texture = load(icon_path) as Texture2D if ResourceLoader.exists(icon_path) else null
	var name_label := card.get_node("CropName") as Label
	name_label.text = crop_name
	var grow_seconds := int(crop.get("grow_seconds", 0))
	var grow_text := TextDB.text("ui.0c138b5f48") % grow_seconds if grow_seconds < 60 else (TextDB.text("ui.b76be40607") % ceili(float(grow_seconds) / 60.0) if grow_seconds < 3600 else TextDB.text("ui.caa67410cc") % [floori(float(grow_seconds) / 3600.0), floori(float(grow_seconds % 3600) / 60.0)])
	(card.get_node("GrowTime") as Label).text = TextDB.text("ui.34d10f565c") % grow_text
	(card.get_node("PlantCost") as Label).text = TextDB.text("ui.a8dceaba64") % int(crop.get("plant_cost", 0))


# 选择 crop_choice，供调用方继续处理。
func _select_crop_choice(crop_id: String, crop_row: HBoxContainer, confirm: Button) -> void:
	_selected_crop_id = crop_id
	confirm.disabled = not bool(confirm.get_meta("plant_targets_available", false))
	for child in crop_row.get_children():
		if child is Button:
			var selected := str(child.get_meta("crop_id", "")) == crop_id
			(child.get_node("SelectedMark") as Label).visible = selected
			(child.get_node("SelectedBorder") as Panel).visible = selected


# 更新 plant_confirm_availability，供调用方继续处理。
func _update_plant_confirm_availability(grouped: bool, index: int, cell_index: int, confirm: Button) -> void:
	var available := _has_available_plant_targets(index, cell_index, grouped)
	confirm.set_meta("plant_targets_available", available)
	confirm.disabled = _selected_crop_id.is_empty() or not available
	_refresh_plant_coin_requirements()


# 播种费用按本次范围中的空格计算，排除已排队格子；更新已有卡片的费用文本和颜色。
func _refresh_plant_coin_requirements() -> void:
	var content := plant_window.get_node("PlotPopup/ContentSurface/PlotContent") as Control
	var board := content.get_node("SelectionBoard") as Control
	if not board.visible or _selected_plot_index < 0 or _state == null:
		return
	var plot: Dictionary = _state.get_plot(str(_selected_plot_index))
	var plot_id := str(plot.get("id", _selected_plot_index))
	var cells: Array = plot.get("cells", [])
	var grouped := (board.get_node("FillEmptyCells") as CheckBox).button_pressed
	var queued := _queued_plot_targets(_services.get("JobManager"), plot_id, "plant")
	var target_count := 0
	if not queued.has(plot_id + ":*"):
		for index in range(cells.size()):
			if str((cells[index] as Dictionary).get("crop", "")).is_empty() and not queued.has("%s:%d" % [plot_id, index]):
				if grouped:
					target_count += 1
				elif _selected_cell_index < 0 or index == _selected_cell_index:
					target_count = 1
					break
	var registry := get_node_or_null("/root/DataRegistry")
	var row := board.get_node("CropContainer/CropViewport/CropRow") as HBoxContainer
	for card in row.get_children():
		if not card is Button or not card.has_meta("crop_id"):
			continue
		var crop: Dictionary = registry.get_crop(str(card.get_meta("crop_id"))) if registry != null else {}
		var total_cost := maxi(0, int(crop.get("plant_cost", 0))) * target_count
		var label := card.get_node("PlantCost") as Label
		label.text = TextDB.text("ui.a8dceaba64") % total_cost
		_set_coin_requirement(label, total_cost)


# 判断是否具有 available_plant_targets 对应的条件。
func _has_available_plant_targets(index: int, cell_index: int, grouped: bool) -> bool:
	var plot: Dictionary = _state.get_plot(str(index))
	var plot_id := str(plot.get("id", index))
	var jobs: Node = _services.get("JobManager")
	var queued_targets := _queued_plot_targets(jobs, plot_id, "plant")
	if queued_targets.has(plot_id + ":*"):
		return false
	var cells: Array = plot.get("cells", [])
	for candidate in range(cells.size()):
		if not grouped and candidate != cell_index:
			continue
		if str((cells[candidate] as Dictionary).get("crop", "")).is_empty() and not queued_targets.has("%s:%d" % [plot_id, candidate]):
			return true
	return false


# 隐藏 crop_unlock_requirements，供调用方继续处理。
func _hide_crop_unlock_requirements() -> void:
	(plant_window.get_node("CropInfoPanel") as Control).hide()


# 显示 crop_unlock_requirements，供调用方继续处理。
func _show_crop_unlock_requirements(crop: Dictionary) -> void:
	var panel := plant_window.get_node("CropInfoPanel") as PanelContainer
	var registry := get_node_or_null("/root/DataRegistry")
	var totals := _dict_prop(_state, "harvested_crop_totals")
	var requirements: Array = crop.get("unlock_requirements", [])
	(panel.get_node("Content/Title") as Label).text = TextDB.text("ui.c4785a1b2f") % str(crop.get("display_name", crop.get("id", TextDB.text("ui.b3aa8ab320"))))
	for index in range(3):
		var row := panel.get_node("Content/Requirement%d" % (index + 1)) as HBoxContainer
		row.visible = index < requirements.size()
		if not row.visible:
			continue
		var requirement: Dictionary = requirements[index]
		var source_id := str(requirement.get("crop_id", ""))
		var source: Dictionary = registry.get_crop(source_id) if registry != null else {}
		var icon_path := str(source.get("icon_resource", source.get("mature_resource", "")))
		(row.get_node("Icon") as TextureRect).texture = load(icon_path) as Texture2D if ResourceLoader.exists(icon_path) else null
		(row.get_node("Progress") as Label).text = "%s %d/%d" % [str(source.get("display_name", source_id)), int(totals.get(source_id, 0)), int(requirement.get("harvest_amount", 0))]
	panel.show()


# 封装 confirm_crop_choice 的处理，供相关流程复用。
func _confirm_crop_choice(repeat_choice: CheckBox, fill_empty_cells: CheckBox) -> void:
	if _selected_plot_index >= 0 and not _selected_crop_id.is_empty():
		_plant_crop(_selected_plot_index, _selected_crop_id, repeat_choice.button_pressed, fill_empty_cells.button_pressed)


# 封装 scroll_crop_choices 的处理，供相关流程复用。
func _scroll_crop_choices(viewport: ScrollContainer, direction: int) -> void:
	var row := viewport.get_node("CropRow") as HBoxContainer
	var step := 113
	if row != null and row.get_child_count() > 0:
		var card := row.get_child(0) as Control
		if card != null:
			step = roundi(card.size.x) + row.get_theme_constant("separation")
	viewport.scroll_horizontal = maxi(0, viewport.scroll_horizontal + direction * step)


# 封装 remember_crop_scroll 的处理，供相关流程复用。
func _remember_crop_scroll() -> void:
	if not plant_window.visible:
		return
	var selection_board := plant_window.get_node("PlotPopup/ContentSurface/PlotContent/SelectionBoard") as Control
	if not selection_board.visible:
		return
	var viewport := selection_board.get_node("CropContainer/CropViewport") as ScrollContainer
	_crop_scroll_position = viewport.scroll_horizontal


# 恢复 crop_scroll，供调用方继续处理。
func _restore_crop_scroll() -> void:
	if not plant_window.visible:
		return
	var selection_board := plant_window.get_node("PlotPopup/ContentSurface/PlotContent/SelectionBoard") as Control
	if not selection_board.visible:
		return
	var viewport := selection_board.get_node("CropContainer/CropViewport") as ScrollContainer
	viewport.scroll_horizontal = _crop_scroll_position


# 显示 plot_progress，供调用方继续处理。
func _show_plot_progress(index: int, cell_index: int = -1) -> void:
	_plot_progress_index = index
	_plot_progress_cell_index = cell_index
	plot_progress_anchor.visible = true
	_update_plot_progress()
	if plot_progress_anchor.visible:
		plot_progress_timer.start()


# 隐藏 plot_progress，供调用方继续处理。
func _hide_plot_progress() -> void:
	_plot_progress_index = -1
	_plot_progress_cell_index = -1
	plot_progress_timer.stop()
	plot_progress_anchor.visible = false


# 更新 plot_progress，供调用方继续处理。
func _update_plot_progress() -> void:
	if _plot_progress_index < 0:
		return
	var plots_value = _prop(_state, "plots", [])
	var plots: Array = plots_value if plots_value is Array else []
	if _plot_progress_index >= plots.size() or not plots[_plot_progress_index] is Dictionary:
		_hide_plot_progress()
		return
	var plot: Dictionary = plots[_plot_progress_index]
	var jobs: Node = _services.get("JobManager")
	var plot_id := str(plot.get("id", _plot_progress_index))
	var work_status: Dictionary = jobs.call("get_plot_work_status", plot_id) if jobs != null and jobs.has_method("get_plot_work_status") else {}
	_update_plot_work_details(work_status)
	var crop_id := str(plot.get("crop", plot.get("crop_id", "")))
	var selected_cells: Array = plot.get("cells", [])
	var selected_cell: Dictionary = selected_cells[_plot_progress_cell_index] if _plot_progress_cell_index >= 0 and _plot_progress_cell_index < selected_cells.size() else {}
	if not selected_cell.is_empty():
		crop_id = str(selected_cell.get("crop", ""))
	var centers := static_world.get_plot_centers()
	if _plot_progress_index >= centers.size() or not centers[_plot_progress_index] is Vector2:
		_hide_plot_progress()
		return
	var center: Vector2 = get_global_transform().affine_inverse() * (centers[_plot_progress_index] as Vector2)
	var panel := plot_progress_anchor.get_node("Panel") as Control
	# Keep the editable panel offset beside the plot, then clamp the whole panel
	# into the visible 1280×168 strip (scene-local Y 62..230).
	var visible_top := size.y - float(DESIGN_SIZE.y)
	plot_progress_anchor.position = Vector2(
		clampf(center.x, -panel.position.x, float(_display_width) - panel.position.x - panel.size.x),
		clampf(center.y, visible_top - panel.position.y, size.y - panel.position.y - panel.size.y)
	)
	plot_progress_bar.visible = true
	plot_progress_time.visible = true
	var now := int(Time.get_unix_time_from_system())
	var cells: Array = plot.get("cells", [])
	var mature_count := 0
	var mature_target_ids: Array[String] = []
	var planted_count := 0
	var planted_at := 0
	var mature_at := 0
	for cell_index in range(cells.size()):
		var cell: Dictionary = cells[cell_index]
		if _plot_progress_cell_index >= 0 and cell_index != _plot_progress_cell_index or _plot_progress_cell_index < 0 and not bool(cell.get("grouped", true)):
			continue
		if str(cell.get("crop", "")).is_empty():
			continue
		planted_count += 1
		if planted_at == 0 or int(cell.get("planted_at", 0)) < planted_at:
			planted_at = int(cell.get("planted_at", 0))
		mature_at = maxi(mature_at, int(cell.get("mature_at", 0)))
		if _plot_progress_cell_index < 0 and planted_count == 1:
			crop_id = str(cell.get("crop", ""))
		if now >= int(cell.get("mature_at", 0)):
			mature_count += 1
			mature_target_ids.append("%s:%d" % [plot_id, cell_index])
	if planted_count == 0:
		if not (plot_pending_plant.visible or plot_pending_harvest.visible):
			_hide_plot_progress()
			return
		plot_progress_title.text = TextDB.text("plot.work.detail.title")
		plot_progress_bar.visible = false
		plot_progress_time.visible = false
		plot_harvest_all.visible = false
		plot_water_cell.visible = false
		return
	var midpoint := planted_at + maxi(1, floori(float(mature_at - planted_at) / 2.0))
	if not selected_cell.is_empty() and int(selected_cell.get("leaf_at", 0)) > 0:
		midpoint = int(selected_cell["leaf_at"])
	var phase_start := planted_at
	var phase_end := midpoint
	var stage_label := TextDB.text("ui.38259d6804")
	var dry_multiplier: float = GameConfig.get_float("farming", "unwatered_growth_multiplier")
	if not selected_cell.is_empty() and not bool(selected_cell.get("watered_seed", false)):
		stage_label = TextDB.text("ui.0a73f94fd3") % str(dry_multiplier)
	var group_plant_pending := false
	if _plot_progress_cell_index < 0:
		group_plant_pending = int((work_status.get("plant", {}) as Dictionary).get("grouped_count", 0)) > 0 if work_status.get("plant", {}) is Dictionary else false
	if mature_count == planted_count and not group_plant_pending:
		var farming: Node = _services.get("FarmingSystem")
		var harvest_amount := 0
		if farming != null:
			for cell_index in range(cells.size()):
				var cell: Dictionary = cells[cell_index]
				if _plot_progress_cell_index >= 0 and cell_index != _plot_progress_cell_index or _plot_progress_cell_index < 0 and not bool(cell.get("grouped", true)):
					continue
				if not str(cell.get("crop", "")).is_empty():
					harvest_amount += int(farming.call("get_cell_harvest_amount", str(plot.get("id", _plot_progress_index)), cell_index))
		plot_progress_title.text = TextDB.text("ui.1971f40ab6") % [_display_id(crop_id), mature_count]
		plot_progress_time.text = TextDB.text("ui.8203aa74c8") % harvest_amount
		plot_progress_bar.value = 100.0
		plot_harvest_all.visible = true
		plot_harvest_all.disabled = _targets_all_queued(work_status, "harvest", mature_target_ids)
		plot_water_cell.visible = false
		return
	plot_harvest_all.visible = mature_count > 0
	plot_harvest_all.disabled = _targets_all_queued(work_status, "harvest", mature_target_ids)
	var needs_water := false
	var farming: Node = _services.get("FarmingSystem")
	var weather_watering := farming != null and bool(farming.call("is_weather_watering"))
	for cell_index in range(cells.size()):
		var cell: Dictionary = cells[cell_index]
		if _plot_progress_cell_index >= 0 and cell_index != _plot_progress_cell_index or _plot_progress_cell_index < 0 and not bool(cell.get("grouped", true)):
			continue
		if str(cell.get("crop", "")).is_empty() or now >= int(cell.get("mature_at", 0)):
			continue
		var stage_key := "watered_seed" if now < int(cell.get("leaf_at", 0)) else "watered_leaf"
		if not weather_watering and not bool(cell.get(stage_key, false)):
			needs_water = true
			break
	plot_water_cell.visible = needs_water
	if now >= midpoint:
		phase_start = midpoint
		phase_end = mature_at
		stage_label = TextDB.text("ui.afadaee394") % str(dry_multiplier) if not weather_watering and not selected_cell.is_empty() and not bool(selected_cell.get("watered_leaf", false)) else TextDB.text("ui.16670bfde4")
	var phase_seconds := maxi(1, phase_end - phase_start)
	var elapsed := clampi(now - phase_start, 0, phase_seconds)
	var remaining := maxi(0, phase_end - now)
	plot_progress_title.text = "%s · %s" % [_display_id(crop_id), stage_label]
	plot_progress_time.text = TextDB.text("ui.a80996fa34") % [floori(float(remaining) / 60.0), remaining % 60]
	plot_progress_bar.value = 100.0 * float(elapsed) / float(phase_seconds)


# 更新 plot_work_details，供调用方继续处理。
func _update_plot_work_details(status: Dictionary) -> void:
	var plant: Dictionary = status.get("plant", {}) if status.get("plant", {}) is Dictionary else {}
	var harvest: Dictionary = status.get("harvest", {}) if status.get("harvest", {}) is Dictionary else {}
	plot_pending_plant.visible = int(plant.get("total_count", 0)) > 0
	plot_pending_harvest.visible = int(harvest.get("total_count", 0)) > 0
	if plot_pending_plant.visible:
		plot_pending_plant.text = _plot_work_detail("plant", plant)
	if plot_pending_harvest.visible:
		plot_pending_harvest.text = _plot_work_detail("harvest", harvest)


# 封装 plot_work_detail 的处理，供相关流程复用。
func _plot_work_detail(kind: String, entry: Dictionary) -> String:
	var running := int(entry.get("running_count", 0))
	var waiting := int(entry.get("waiting_count", 0))
	var state_id := "plot.work.%s_%s" % [kind, "running" if running > 0 else "waiting"]
	var state_text := TextDB.text(state_id)
	if running > 0:
		return TextDB.text("plot.work.detail.running") % [state_text, running, waiting]
	if kind == "harvest":
		return TextDB.text("plot.work.detail.harvest") % [state_text, int(entry.get("total_count", 0))]
	var crop_counts: Dictionary = entry.get("crop_counts", {}) if entry.get("crop_counts", {}) is Dictionary else {}
	if crop_counts.size() == 1:
		return TextDB.text("plot.work.detail.plant_single") % [state_text, _display_id(str(crop_counts.keys()[0])), int(entry.get("total_count", 0))]
	return TextDB.text("plot.work.detail.plant_mixed") % [state_text, crop_counts.size(), int(entry.get("total_count", 0))]


# 封装 targets_all_queued 的处理，供相关流程复用。
func _targets_all_queued(status: Dictionary, kind: String, valid_targets: Array[String]) -> bool:
	if valid_targets.is_empty():
		return false
	var entry: Dictionary = status.get(kind, {}) if status.get(kind, {}) is Dictionary else {}
	var queued: Dictionary = {}
	for value in entry.get("target_ids", []):
		queued[str(value)] = true
	for target_id in valid_targets:
		var plot_id := target_id.get_slice(":", 0)
		if not queued.has(target_id) and not queued.has(plot_id + ":*"):
			return false
	return true


# 封装 queued_plot_targets 的处理，供相关流程复用。
func _queued_plot_targets(jobs: Node, plot_id: String, kind: String) -> Dictionary:
	var result: Dictionary = {}
	if jobs == null or not jobs.has_method("get_plot_work_status"):
		return result
	var status: Dictionary = jobs.call("get_plot_work_status", plot_id)
	var entry: Dictionary = status.get(kind, {}) if status.get(kind, {}) is Dictionary else {}
	for value in entry.get("target_ids", []):
		result[str(value)] = true
	return result


# 从进度面板提交收获，沿用面板当前选中的单格或分组。
func _harvest_all_mature() -> void:
	_enqueue_mature_plot_cells(_plot_progress_index, _plot_progress_cell_index, _plot_progress_cell_index < 0)


# 确认收获后提交成熟作物；cell_index 或 grouped_only 可缩小收获范围。
func _enqueue_mature_plot_cells(plot_index: int, cell_index: int = -1, grouped_only: bool = false) -> void:
	var plots_value = _prop(_state, "plots", [])
	var plots: Array = plots_value if plots_value is Array else []
	var farming: Node = _services.get("FarmingSystem")
	var jobs: Node = _services.get("JobManager")
	if farming == null or jobs == null or plot_index < 0 or plot_index >= plots.size() or not plots[plot_index] is Dictionary:
		return
	var plot: Dictionary = plots[plot_index]
	if not bool(plot.get("unlocked", false)):
		return
	var ready_ids: Array[String] = []
	var total_amount := 0
	var now := int(Time.get_unix_time_from_system())
	var plot_id := str(plot.get("id", plot_index))
	var queued_targets := _queued_plot_targets(jobs, plot_id, "harvest")
	var cells: Array = plot.get("cells", [])
	for candidate in range(cells.size()):
		if not cells[candidate] is Dictionary:
			continue
		var cell: Dictionary = cells[candidate]
		if (cell_index >= 0 and candidate != cell_index) or (grouped_only and not bool(cell.get("grouped", true))):
			continue
		if str(cell.get("crop", "")).is_empty() or int(cell.get("mature_at", 0)) > now:
			continue
		var target_id := "%s:%d" % [plot_id, candidate]
		if queued_targets.has(target_id) or queued_targets.has(plot_id + ":*"):
			continue
		total_amount += int(farming.call("get_cell_harvest_amount", plot_id, candidate))
		ready_ids.append(target_id)
	if ready_ids.is_empty():
		notify(TextDB.text("ui.8eef0efe43"))
		return
	if not bool(_state.call("can_store_crop", total_amount)):
		notify(TextDB.text("ui.4e5157e444"))
		return
	if int(jobs.call("get_available_command_slots")) <= 0:
		notify(TextDB.text("ui.ef2c39ee99"))
		return
	jobs.call("enqueue_task_batch", "harvest_cell", ready_ids, [], TextDB.text("ui.f6327bbbfb"), TextDB.text("ui.35b288f5ae"))
	_hide_plot_progress()
	# notify("已派角色依次收获 %d 个成熟小格" % ready_ids.size())


# 封装 water_selected_cell 的处理，供相关流程复用。
func _water_selected_cell() -> void:
	if _plot_progress_index < 0:
		return
	var farming: Node = _services.get("FarmingSystem")
	if farming != null and bool(farming.call("is_weather_watering")):
		_hide_plot_progress()
		return
	var jobs: Node = _services.get("JobManager")
	var plot: Dictionary = _state.get_plot(str(_plot_progress_index))
	var cells: Array = plot.get("cells", [])
	var now := int(Time.get_unix_time_from_system())
	var target_ids: Array[String] = []
	if jobs != null:
		for cell_index in range(cells.size()):
			var cell: Dictionary = cells[cell_index]
			if _plot_progress_cell_index >= 0 and cell_index != _plot_progress_cell_index or _plot_progress_cell_index < 0 and not bool(cell.get("grouped", true)):
				continue
			if str(cell.get("crop", "")).is_empty() or now >= int(cell.get("mature_at", 0)):
				continue
			var stage_key := "watered_seed" if now < int(cell.get("leaf_at", 0)) else "watered_leaf"
			if bool(cell.get(stage_key, false)):
				continue
			target_ids.append("%d:%d" % [_plot_progress_index, cell_index])
		if not target_ids.is_empty() and int(jobs.call("get_available_command_slots")) <= 0:
			notify(TextDB.text("ui.6024866ef0"))
			return
		jobs.call("enqueue_task_batch", "water_cell", target_ids, [], TextDB.text("ui.1d21339af2"), TextDB.text("ui.eadd8c7b22"))
	_hide_plot_progress()
	# notify("已安排角色依次给 %d 个小格浇水" % queued)


# 小屋升级展示当前与下一级数值；施工与满级状态沿用同一组静态控件。
func _open_cottage() -> void:
	var level := int(_prop(_state, "cottage_level", 1))
	_new_modal("", "CottagePopup")
	var content := _modal.get_node("ContentSurface") as Control
	var construction: Dictionary = _state.call("get_cottage_construction")
	var used := int(_state.call("get_warehouse_used"))
	var capacity := int(_state.call("get_warehouse_capacity"))
	var tier := int(_state.call("get_workbench_tier"))
	var next_cost := int(_state.call("get_next_cottage_upgrade_cost"))
	var next_data: Dictionary = _state.call("get_cottage_data", level + 1)
	var has_next := not next_data.is_empty()
	(content.get_node("NextUnlocks") as Label).text = _cottage_next_unlocks(level) if has_next else TextDB.text("cottage.compare.no_next")
	(content.get_node("TitlePlank/TitleText") as Label).text = TextDB.text("cottage.compare.heading")
	(content.get_node("LevelComparison") as Label).text = TextDB.text("cottage.compare.levels") % [level, level + 1] if has_next else TextDB.text("cottage.compare.current_level") % level
	(content.get_node("Storage/Current") as Label).text = str(capacity)
	(content.get_node("Storage/Next") as Label).text = str(int(next_data.get("storage_capacity", capacity)))
	(content.get_node("Workbench/Current") as Label).text = str(tier)
	(content.get_node("Workbench/Next") as Label).text = str(int(next_data.get("workbench_tier", tier)))
	(content.get_node("Storage/Name") as Label).text = TextDB.text("cottage.compare.storage")
	(content.get_node("Workbench/Name") as Label).text = TextDB.text("cottage.compare.workbench")
	for row_name in ["Storage", "Workbench"]:
		(content.get_node(row_name + "/Arrow") as Label).visible = has_next
		(content.get_node(row_name + "/Next") as Label).visible = has_next
	(content.get_node("WarehouseUsage") as Label).text = TextDB.text("cottage.compare.usage") % [used, capacity]
	var upgrade := content.get_node("Upgrade") as Button
	_clear_press_connections(upgrade)
	upgrade.visible = true
	upgrade.text = TextDB.text("ui.067503a5bf") if next_cost < 0 else TextDB.text("ui.50fcaea577")
	upgrade.disabled = not _can_queue_building_action("upgrade_cottage")
	if not construction.is_empty():
		var remaining := maxi(0, int(construction.get("ready_at", 0)) - int(Time.get_unix_time_from_system()))
		upgrade.text = TextDB.text("cottage.compare.building") + " " + _format_duration(remaining)
	var cost_row := content.get_node("UpgradeCostRow") as HBoxContainer
	cost_row.visible = next_cost >= 0 and construction.is_empty()
	(cost_row.get_node("Amount") as Label).text = str(next_cost)
	_set_coin_requirement(cost_row.get_node("Amount") as Label, next_cost)
	upgrade.pressed.connect(_upgrade_cottage)
	var finish := content.get_node("Finish") as Button
	_clear_press_connections(finish)
	finish.visible = not construction.is_empty() and bool(_state.call("is_cottage_construction_ready"))
	upgrade.visible = not finish.visible
	if finish.visible:
		finish.text = TextDB.text("ui.8184ee25f5")
		finish.pressed.connect(_finish_cottage_construction)
	_show_modal()

# 按实际地块门槛统计下一级新开放的数量；养殖随四级小屋完工开放。
func _cottage_next_unlocks(level: int) -> String:
	var entries: Array[String] = []
	var farming: Node = _services.get("FarmingSystem")
	var plots: Array = _prop(_state, "plots", [])
	var count := 0
	if farming != null:
		for index in range(plots.size()):
			var plot: Dictionary = plots[index]
			if int(farming.call("get_plot_required_cottage_level", str(plot.get("id", index)))) == level + 1:
				count += 1
	if count > 0:
		entries.append(TextDB.text("cottage.compare.unlock_plots") % count)
	if level + 1 == 4:
		entries.append(TextDB.text("cottage.compare.unlock_pasture"))
	var details := " / ".join(entries) if not entries.is_empty() else TextDB.text("cottage.compare.unlock_none")
	return TextDB.text("cottage.compare.unlocks") % details


# 打开 workbench，供调用方继续处理。
func _open_workbench() -> void:
	if _state == null or not bool(_state.workbench_unlocked):
		notify(TextDB.text("ui.cced0bc709"))
		return
	_new_modal(TextDB.text("ui.8483cd2b08"), "WorkbenchPopup")
	if _workbench_selected_bait.is_empty():
		_workbench_selected_bait = str(_prop(_state, "selected_bait", ""))
	if _workbench_selected_rod.is_empty():
		_workbench_selected_rod = str(_prop(_state, "selected_rod", "basic_rod"))
	_render_workbench()
	_show_modal()


# 封装 workbench_content 的处理，供相关流程复用。
func _workbench_content() -> Control:
	return get_node("WorkbenchWindow/WorkbenchPopup/ContentSurface/WorkbenchContent") as Control


# 封装 workbench_switch_tab 的处理，供相关流程复用。
func _workbench_switch_tab(tab: String) -> void:
	_workbench_tab = tab
	_workbench_quantity = 1
	_render_workbench()


# 封装 workbench_choose_item 的处理，供相关流程复用。
func _workbench_choose_item(item_id: String) -> void:
	if _workbench_tab == "rod":
		_workbench_selected_rod = item_id
	else:
		_workbench_selected_bait = item_id
	_workbench_quantity = 1
	_render_workbench()


# 封装 workbench_change_quantity 的处理，供相关流程复用。
func _workbench_change_quantity(delta: int) -> void:
	_workbench_quantity = maxi(1, _workbench_quantity + delta)
	_render_workbench()


# 封装 workbench_set_max_quantity 的处理，供相关流程复用。
func _workbench_set_max_quantity(max_batches: int) -> void:
	_workbench_quantity = maxi(1, max_batches)
	_render_workbench()


# 封装 workbench_rod_before 的处理，供相关流程复用。
func _workbench_rod_before(first: Dictionary, second: Dictionary) -> bool:
	return int(first.get("upgrade_cost", 0)) < int(second.get("upgrade_cost", 0))


# 封装 workbench_item_icon 的处理，供相关流程复用。
func _workbench_item_icon(item: Dictionary, is_bait: bool) -> Texture2D:
	var icon_path := str(item.get("icon_resource", ""))
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		return load(icon_path) as Texture2D
	return BAIT_PLACEHOLDER_ICON if is_bait else ROD_PLACEHOLDER_ICON


# 设置 card_rarity，供调用方继续处理。
func _set_card_rarity(card: Control, item: Dictionary, wide: bool = false) -> void:
	var background := card.get_node_or_null("RarityBack") as TextureRect
	if background != null:
		background.texture = RarityPalette.texture_for(str(item.get("rarity", "common")), wide)


# 封装 workbench_visual_material 的处理，供相关流程复用。
func _workbench_visual_material(display_state: String) -> ShaderMaterial:
	if display_state == "lit":
		return null
	var effect := ShaderMaterial.new()
	effect.shader = FISH_GRAYSCALE_SHADER if display_state == "gray" else FISH_SILHOUETTE_SHADER
	return effect


# 设置 workbench_name_color，供调用方继续处理。
func _set_workbench_name_color(label: Label, dimmed: bool) -> void:
	if not label.has_meta("original_workbench_color"):
		label.set_meta("original_workbench_color", label.get_theme_color("font_color"))
	var original: Color = label.get_meta("original_workbench_color")
	label.add_theme_color_override("font_color", Color("#777777") if dimmed else original)


# 封装 style_workbench_card 的处理，供相关流程复用。
func _style_workbench_card(card: PanelContainer, display_state: String) -> void:
	var icon := card.get_node("Content/Icon") as TextureRect
	var rarity := card.get_node("RarityBack") as TextureRect
	var name_label := card.get_node("Content/Name") as Label
	icon.material = _workbench_visual_material(display_state)
	var backing_material: ShaderMaterial = null
	if display_state != "lit":
		backing_material = ShaderMaterial.new()
		backing_material.shader = FISH_GRAYSCALE_SHADER
	card.material = backing_material
	rarity.material = backing_material
	_set_workbench_name_color(name_label, display_state != "lit")


# 封装 style_workbench_target 的处理，供相关流程复用。
func _style_workbench_target(content: Control, display_state: String) -> void:
	(content.get_node("DetailPanel/TargetIcon") as TextureRect).material = _workbench_visual_material(display_state)
	_set_workbench_name_color(content.get_node("DetailPanel/TargetName") as Label, display_state != "lit")


# 渲染 workbench，供调用方继续处理。
func _render_workbench() -> void:
	var content := _workbench_content()
	var registry := get_node_or_null("/root/DataRegistry")
	if registry == null:
		return
	var is_bait := _workbench_tab == "bait"
	var bait_tab := content.get_node("CategoryTabs/BaitTab") as CodexTabButton
	var rod_tab := content.get_node("CategoryTabs/RodTab") as CodexTabButton
	_clear_press_connections(bait_tab)
	_clear_press_connections(rod_tab)
	bait_tab.set_selected(is_bait)
	rod_tab.set_selected(not is_bait)
	bait_tab.pressed.connect(_workbench_switch_tab.bind("bait"))
	rod_tab.pressed.connect(_workbench_switch_tab.bind("rod"))
	var category := "baits" if is_bait else "rods"
	var entries: Array = registry.get_all(category)
	var crafting: Node = _services.get("CraftingSystem")
	var next_rod: Dictionary = crafting.call("get_next_rod_upgrade") if crafting != null and not is_bait else {}
	if not is_bait:
		entries.sort_custom(Callable(self, "_workbench_rod_before"))
	var selected_id := _workbench_selected_bait if is_bait else _workbench_selected_rod
	if selected_id.is_empty() or not bool(registry.has_entry(category, selected_id)):
		selected_id = str(entries[0].get("id", "")) if not entries.is_empty() else ""
		if is_bait:
			_workbench_selected_bait = selected_id
		else:
			_workbench_selected_rod = selected_id
	var grid := content.get_node("ItemsViewport/ItemGrid") as GridContainer
	var slots := _data_slots(grid, WORKBENCH_ITEM_CARD, entries.size())
	for index in range(entries.size()):
		var item: Dictionary = entries[index]
		var item_id := str(item.get("id", ""))
		var slot := slots[index] as PanelContainer
		_set_card_rarity(slot, item)
		(slot.get_node("Content/Icon") as TextureRect).texture = _workbench_item_icon(item, is_bait)
		(slot.get_node("Content/Name") as Label).text = str(item.get("display_name", item_id))
		var display_state := "silhouette"
		if is_bait:
			var craftable := crafting != null and bool(crafting.call("can_craft", item_id, 1))
			display_state = "lit" if craftable else "gray" if _state.workbench_crafted_baits.has(item_id) else "silhouette"
		else:
			var owned: bool = _state.unlocked_rods.has(item_id)
			var affordable_next := item_id == str(next_rod.get("id", "")) and int(_state.coins) >= int(item.get("upgrade_cost", 0))
			display_state = "lit" if owned or affordable_next else "silhouette"
		_style_workbench_card(slot, display_state)
		(slot.get_node("SelectedFrame") as Panel).visible = item_id == selected_id
		var click := slot.get_node("ClickArea") as Button
		_clear_press_connections(click)
		click.pressed.connect(_workbench_choose_item.bind(item_id))
	var selected: Dictionary = registry.get_entry(category, selected_id)
	if is_bait:
		_render_workbench_bait_detail(content, registry, selected)
	else:
		_render_workbench_rod_detail(content, selected)


# 封装 workbench_material_data 的处理，供相关流程复用。
func _workbench_material_data(registry: Node, item_id: String) -> Dictionary:
	for category in ["crops", "baits", "fish"]:
		var item: Dictionary = registry.get_entry(category, item_id)
		if not item.is_empty():
			return item
	return {}


# 渲染 workbench_bait_detail，供调用方继续处理。
func _render_workbench_bait_detail(content: Control, registry: Node, bait: Dictionary) -> void:
	var bait_id := str(bait.get("id", ""))
	var tier := int(_state.call("get_workbench_tier"))
	var unlocked_value: Variant = _prop(_state, "unlocked_baits", [])
	var unlocked: Array = unlocked_value if unlocked_value is Array else []
	var available := tier >= maxi(1, int(bait.get("required_workbench_tier", 1))) and (unlocked.is_empty() or unlocked.has(bait_id))
	var recipe_data: Dictionary = registry.get_recipe(bait_id)
	var recipe_value: Variant = recipe_data.get("recipe", recipe_data.get("ingredients", {}))
	var ingredients: Dictionary = recipe_value if recipe_value is Dictionary else {}
	var ingredient_ids := ingredients.keys()
	var max_batches := 99 if not ingredients.is_empty() else 0
	for item_id_value in ingredient_ids:
		var item_id := str(item_id_value)
		var required := int(ingredients[item_id_value])
		if required > 0:
			max_batches = mini(max_batches, floori(float(_state.call("get_item_count", item_id)) / float(required)))
	_workbench_quantity = clampi(_workbench_quantity, 1, maxi(1, max_batches))
	(content.get_node("DetailPanel/TargetIcon") as TextureRect).texture = _workbench_item_icon(bait, true)
	(content.get_node("DetailPanel/TargetName") as Label).text = str(bait.get("display_name", bait_id))
	var crafting: Node = _services.get("CraftingSystem")
	var craftable := available and crafting != null and bool(crafting.call("can_craft", bait_id, 1))
	var display_state := "lit" if craftable else "gray" if _state.workbench_crafted_baits.has(bait_id) else "silhouette"
	_style_workbench_target(content, display_state)
	(content.get_node("DetailPanel/TargetInfo") as Label).text = TextDB.text("ui.6c1d39029a") % _bait_type_label(str(bait.get("bait_type", "")))
	(content.get_node("DetailPanel/MaterialsTitle") as Label).text = TextDB.text("ui.4af67d14ea") % _workbench_quantity
	var material_row := content.get_node("DetailPanel/MaterialRow") as HBoxContainer
	for index in range(3):
		var material := material_row.get_child(index) as PanelContainer
		_set_coin_requirement(material.get_node("Content/Count") as Label, -1)
		material.visible = index < ingredient_ids.size()
		if not material.visible:
			(material.get_node("Content/Icon") as TextureRect).texture = null
			(material.get_node("Content/Name") as Label).text = ""
			(material.get_node("Content/Count") as Label).text = "0/0"
			continue
		var item_id := str(ingredient_ids[index])
		var item: Dictionary = _workbench_material_data(registry, item_id)
		var icon_path := str(item.get("icon_resource", item.get("mature_resource", "")))
		(material.get_node("Content/Icon") as TextureRect).texture = load(icon_path) as Texture2D if ResourceLoader.exists(icon_path) else null
		(material.get_node("Content/Name") as Label).text = str(item.get("display_name", _display_id(item_id)))
		(material.get_node("Content/Count") as Label).text = "%d/%d" % [
			int(_state.call("get_item_count", item_id)), int(ingredients[item_id]) * _workbench_quantity]
	var quantity_control := content.get_node("DetailPanel/QuantityControl") as HBoxContainer
	quantity_control.visible = true
	(quantity_control.get_node("Amount") as Label).text = str(_workbench_quantity)
	var minus := quantity_control.get_node("Minus") as Button
	var plus := quantity_control.get_node("Plus") as Button
	var max_button := quantity_control.get_node("Max") as Button
	_clear_press_connections(minus)
	_clear_press_connections(plus)
	_clear_press_connections(max_button)
	minus.disabled = _workbench_quantity <= 1
	plus.disabled = _workbench_quantity >= max_batches
	max_button.disabled = max_batches <= 1 or _workbench_quantity >= max_batches
	minus.pressed.connect(_workbench_change_quantity.bind(-1))
	plus.pressed.connect(_workbench_change_quantity.bind(1))
	max_button.pressed.connect(_workbench_set_max_quantity.bind(max_batches))
	var craft := content.get_node("DetailPanel/CraftButton") as Button
	_clear_press_connections(craft)
	craft.text = TextDB.text("ui.7d394484ec")
	craft.disabled = not available or crafting == null or not bool(crafting.call("can_craft", bait_id, _workbench_quantity))
	craft.pressed.connect(_craft_bait.bind(bait_id, _workbench_quantity))


# 渲染 workbench_rod_detail，供调用方继续处理。
func _render_workbench_rod_detail(content: Control, rod: Dictionary) -> void:
	var rod_id := str(rod.get("id", ""))
	var current_id := str(_prop(_state, "selected_rod", "basic_rod"))
	var unlocked_value: Variant = _prop(_state, "unlocked_rods", [])
	var unlocked: Array = unlocked_value if unlocked_value is Array else []
	var crafting: Node = _services.get("CraftingSystem")
	var next_rod: Dictionary = crafting.call("get_next_rod_upgrade") if crafting != null else {}
	var owned := unlocked.has(rod_id)
	var is_next := rod_id == str(next_rod.get("id", ""))
	var cost := int(rod.get("upgrade_cost", 0))
	var coins := int(_prop(_state, "coins", 0))
	(content.get_node("DetailPanel/TargetIcon") as TextureRect).texture = _workbench_item_icon(rod, false)
	(content.get_node("DetailPanel/TargetName") as Label).text = str(rod.get("display_name", rod_id))
	_style_workbench_target(content, "lit" if owned or is_next and coins >= cost else "silhouette")
	(content.get_node("DetailPanel/TargetInfo") as Label).text = TextDB.text("ui.45a3667a6b") % _localized_name(FISH_RARITY_NAMES, str(rod.get("max_fish_rarity", "common")), TextDB.text("ui.7cda072d45"))
	(content.get_node("DetailPanel/MaterialsTitle") as Label).text = TextDB.text("ui.52cbe5931b")
	var material_row := content.get_node("DetailPanel/MaterialRow") as HBoxContainer
	var coin_card := material_row.get_node("Material1") as PanelContainer
	coin_card.visible = true
	(coin_card.get_node("Content/Icon") as TextureRect).texture = COIN_ICON
	(coin_card.get_node("Content/Name") as Label).text = TextDB.text("ui.61f608b0d9")
	(coin_card.get_node("Content/Count") as Label).text = "%d/%d" % [coins, cost]
	_set_coin_requirement(coin_card.get_node("Content/Count") as Label, cost if not owned else -1)
	(material_row.get_node("Material2") as PanelContainer).visible = false
	(material_row.get_node("Material3") as PanelContainer).visible = false
	(content.get_node("DetailPanel/QuantityControl") as HBoxContainer).visible = false
	var action := content.get_node("DetailPanel/CraftButton") as Button
	_clear_press_connections(action)
	if owned:
		action.text = TextDB.text("ui.7a7f26a100") if current_id == rod_id else TextDB.text("ui.4ecf15b05d")
		action.disabled = current_id == rod_id
		if not action.disabled:
			action.pressed.connect(_select_rod.bind(rod_id))
	elif is_next:
		action.text = TextDB.text("ui.5903b4eb21")
		action.disabled = coins < cost
		action.pressed.connect(_upgrade_rod)
	else:
		action.text = TextDB.text("ui.2f2af2a5a9")
		action.disabled = true


# 打开 pond，供调用方继续处理。
func _open_pond() -> void:
	_new_modal(TextDB.text("ui.8124830197"), "PondPopup")
	_render_pond_content()
	_show_modal()


# 渲染 pond_content，供调用方继续处理。
func _render_pond_content() -> void:
	var content := pond_window.get_node("PondPopup/ContentSurface/PondContent") as Control
	var bait_tab := content.get_node("CategoryTabs/BaitTab") as CodexTabButton
	var rod_tab := content.get_node("CategoryTabs/RodTab") as CodexTabButton
	var leaderboard_tab := content.get_node("CategoryTabs/LeaderboardTab") as CodexTabButton
	_clear_press_connections(bait_tab)
	_clear_press_connections(rod_tab)
	_clear_press_connections(leaderboard_tab)
	bait_tab.pressed.connect(_select_pond_tab.bind("bait"))
	rod_tab.pressed.connect(_select_pond_tab.bind("rod"))
	leaderboard_tab.pressed.connect(_select_pond_tab.bind("leaderboard"))
	bait_tab.set_selected(_pond_tab == "bait")
	rod_tab.set_selected(_pond_tab == "rod")
	leaderboard_tab.set_selected(_pond_tab == "leaderboard")
	(content.get_node("BaitViewport") as ScrollContainer).visible = _pond_tab == "bait"
	(content.get_node("RodViewport") as ScrollContainer).visible = _pond_tab == "rod"
	(content.get_node("LeaderboardPage") as Control).visible = _pond_tab == "leaderboard"
	(content.get_node("BaitTitle") as Control).visible = false
	for node_name in ["Status", "IdleAutoFish", "FishingButton", "outline", "outline2"]:
		(content.get_node(node_name) as Control).visible = _pond_tab != "leaderboard"
	if _pond_tab == "leaderboard":
		_render_pond_leaderboard(content)
	if _pond_tab == "rod":
		_render_pond_rod_cards(content)
	var inventory := _dict_prop(_state, "inventory")
	var bait_id := String(_prop(_state, "selected_bait", ""))
	var bait_count := int(inventory.get(bait_id, 0)) if not bait_id.is_empty() else 0
	var registry := get_node_or_null("/root/DataRegistry")
	var entries: Array = registry.get_all("baits") if registry != null else []
	var available_baits: Array[Dictionary] = []
	for value in entries:
		var bait: Dictionary = value
		if int(inventory.get(str(bait.get("id", "")), 0)) > 0:
			available_baits.append(bait)
	(content.get_node("BaitTitle") as Label).text = TextDB.text("ui.bd97d61ee7") if not available_baits.is_empty() else TextDB.text("ui.6303d0c6b9")
	var grid := content.get_node("BaitViewport/BaitGrid") as GridContainer
	var slots := _data_slots(grid, POND_BAIT_CARD, available_baits.size())
	for index in range(available_baits.size()):
		var bait: Dictionary = available_baits[index]
		var item_id := str(bait.get("id", ""))
		var count := int(inventory.get(item_id, 0))
		var slot := slots[index] as PanelContainer
		_set_card_rarity(slot, bait)
		var icon_path := str(bait.get("icon_resource", ""))
		(slot.get_node("Content/Icon") as TextureRect).texture = load(icon_path) as Texture2D if ResourceLoader.exists(icon_path) else BAIT_PLACEHOLDER_ICON
		(slot.get_node("Content/Name") as Label).text = str(bait.get("display_name", item_id))
		(slot.get_node("Content/Count") as Label).text = "×%d" % count
		(slot.get_node("SelectedCheck") as Node2D).visible = item_id == bait_id
		var click := slot.get_node("ClickArea") as Button
		_clear_press_connections(click)
		click.disabled = item_id == bait_id
		if not click.disabled:
			click.pressed.connect(_select_pond_bait.bind(item_id))
	var current_cast := _dict_prop(_state, "fishing_cast")
	var current_bait_id := str(current_cast.get("bait_id", bait_id))
	var current_bait_count := int(inventory.get(current_bait_id, 0))
	var bait_data: Dictionary = registry.get_bait(current_bait_id) if registry != null else {}
	var bait_type_name := _bait_type_label(str(bait_data.get("bait_type", "")))
	var seconds := -1
	var fishing: Node = _services.get("FishingSystem")
	if fishing and fishing.has_method("get_seconds_until_catch"):
		seconds = int(fishing.call("get_seconds_until_catch"))
	var status := content.get_node("Status") as Label
	var fishing_active := bool(_dict_prop(_state, "flags").get("fishing_active", false))
	status.text = TextDB.text("ui.639ca69e55") % [
		(TextDB.text("ui.c4ca1cd665") if fishing_active else TextDB.text("ui.cd9a1c6428")),
		(_display_id(current_bait_id) if not current_bait_id.is_empty() else TextDB.text("ui.53e2db7016")),
		("（%s）" % bait_type_name if not bait_type_name.is_empty() else ""), current_bait_count,
		(TextDB.text("ui.9d6fe0f3ba") % seconds if seconds >= 0 else "")]
	if available_baits.is_empty() and not fishing_active:
		status.text = TextDB.text("ui.86826b0142")
	var idle_auto_fish := content.get_node("IdleAutoFish") as CheckBox
	for connection in idle_auto_fish.toggled.get_connections():
		idle_auto_fish.toggled.disconnect(connection["callable"])
	idle_auto_fish.button_pressed = bool(_dict_prop(_state, "settings").get("idle_auto_fish", false))
	idle_auto_fish.toggled.connect(_set_idle_auto_fishing)
	var fishing_button := content.get_node("FishingButton") as Button
	_clear_press_connections(fishing_button)
	fishing_button.text = TextDB.text("ui.130448bce6") if fishing_active else TextDB.text("ui.8124830197")
	fishing_button.disabled = not fishing_active and bait_count <= 0
	fishing_button.pressed.connect(_stop_fishing if fishing_active else _start_fishing)


# 点击后更新选择和勾选标记，复用通用提示；本轮仍按快照结算，有进行中抛竿时告知下一轮生效。
func _select_pond_bait(bait_id: String) -> void:
	var crafting: Node = _services.get("CraftingSystem")
	if crafting == null or not bool(crafting.call("select_bait", bait_id)):
		notify(TextDB.text("ui.807f4a9979"))
		return
	_render_pond_content()
	var message_id := "fishing.bait_switch_next_cast" if not _dict_prop(_state, "fishing_cast").is_empty() else "fishing.bait_switched"
	notify(TextDB.text(message_id) % _display_id(bait_id))


# 选择 pond_tab，供调用方继续处理。
func _select_pond_tab(tab: String) -> void:
	_pond_tab = tab
	if tab == "leaderboard":
		_leaderboard_notice().hide()
	_render_pond_content()
	if tab == "leaderboard":
		var service := _services.get("LeaderboardService") as LeaderboardService
		if service != null:
			service.refresh()


# 封装 leaderboard_notice 的处理，供相关流程复用。
func _leaderboard_notice() -> Control:
	return pond_window.get_node("PondPopup/ContentSurface/PondContent/CategoryTabs/LeaderboardTab/NewUnlockDot") as Control


# 响应 leaderboard_updated 对应的事件或条件。
func _on_leaderboard_updated() -> void:
	var service := _services.get("LeaderboardService") as LeaderboardService
	if service == null:
		return
	var viewing := pond_window.visible and _pond_tab == "leaderboard"
	var entry := service.get_self_entry()
	var player_id := str(entry.get("player_id", ""))
	if player_id != _leaderboard_player_id:
		_leaderboard_player_id = player_id
		_leaderboard_ranks.clear()
		_leaderboard_notice().hide()
	var rank := int(entry.get("rank", 0)) if int(entry.get("size_cm", 0)) > 0 else 0
	var previous := int(_leaderboard_ranks.get(service.status, rank))
	_leaderboard_ranks[service.status] = rank
	if not viewing and rank != previous:
		_leaderboard_notice().show()
	if viewing:
		_render_pond_leaderboard(pond_window.get_node("PondPopup/ContentSurface/PondContent") as Control)


# 渲染 pond_leaderboard，供调用方继续处理。
func _render_pond_leaderboard(content: Control) -> void:
	var page := content.get_node("LeaderboardPage") as Control
	var service := _services.get("LeaderboardService") as LeaderboardService
	if service == null:
		(page.get_node("Status") as Label).text = TextDB.text("fishing.leaderboard.offline")
		return
	var status_ids := {
		"unconfigured": "fishing.leaderboard.unconfigured",
		"offline": "fishing.leaderboard.offline",
		"loading": "fishing.leaderboard.loading",
		"error": "fishing.leaderboard.error",
		"ready": "fishing.leaderboard.empty",
		"local": "fishing.leaderboard.local",
	}
	(page.get_node("Status") as Label).text = TextDB.text(str(status_ids.get(service.status, "fishing.leaderboard.offline"))) if service.status != "ready" or service.entries.is_empty() else ""
	(page.get_node("Week") as Label).text = TextDB.text("fishing.leaderboard.week") % service.week_start if not service.week_start.is_empty() else ""
	var rows := page.get_node("RowsViewport/Rows") as VBoxContainer
	var registry := get_node_or_null("/root/DataRegistry")
	var player_id := str(_state.settings.get("leaderboard_player_id", ""))
	for index in range(rows.get_child_count()):
		var row := rows.get_child(index) as PanelContainer
		row.visible = service.status in ["ready", "local"] and index < mini(service.entries.size(), 50)
		if not row.visible:
			continue
		var entry: Dictionary = service.entries[index]
		_fill_leaderboard_row(row, entry, index + 1, registry, false)
		var player_label := row.get_node("Columns/Player") as Label
		if str(entry.get("player_id", "")) == player_id:
			player_label.add_theme_color_override("font_color", Color(0.26, 0.38, 0.13))
		else:
			player_label.remove_theme_color_override("font_color")
	var self_row := page.get_node("SelfRow") as PanelContainer
	self_row.visible = true
	_fill_leaderboard_row(self_row, service.get_self_entry(), 0, registry, true)


# 填充榜单与本人行；鱼名按目录品质着色，每次重填均重设颜色，无鱼或无目录记录时使用普通墨色。
func _fill_leaderboard_row(row: PanelContainer, entry: Dictionary, fallback_rank: int, registry: Node, is_self: bool) -> void:
	var rank := int(entry.get("rank", fallback_rank))
	(row.get_node("Columns/Rank") as Label).text = str(rank) if rank > 0 else "—"
	var display_name := str(entry.get("display_name", ""))
	(row.get_node("Columns/Player") as Label).text = TextDB.text("fishing.leaderboard.self_name") % display_name if is_self else display_name
	var fish_id := str(entry.get("fish_id", ""))
	var fish: Dictionary = registry.call("get_fish", fish_id) if registry != null and not fish_id.is_empty() else {}
	var fish_label := row.get_node("Columns/Fish") as Label
	fish_label.text = str(fish.get("display_name", fish_id)) if not fish_id.is_empty() else "—"
	fish_label.add_theme_color_override("font_color", RarityPalette.text_color_for(str(fish.get("rarity", "common"))) if not fish.is_empty() else COLOR_INK)
	var size_cm := int(entry.get("size_cm", 0))
	(row.get_node("Columns/Size") as Label).text = TextDB.text("fishing.size.value") % size_cm if size_cm > 0 else "—"


# 渲染 pond_rod_cards，供调用方继续处理。
func _render_pond_rod_cards(content: Control) -> void:
	var registry := get_node_or_null("/root/DataRegistry")
	var entries: Array = registry.get_all("rods") if registry != null else []
	var owned_value: Variant = _prop(_state, "unlocked_rods", [])
	var owned: Array = owned_value if owned_value is Array else []
	var selected_id := str(_prop(_state, "selected_rod", "basic_rod"))
	var available: Array[Dictionary] = []
	for value in entries:
		var rod: Dictionary = value
		if owned.has(str(rod.get("id", ""))) or str(rod.get("id", "")) == selected_id:
			available.append(rod)
	var grid := content.get_node("RodViewport/RodGrid") as GridContainer
	var slots := _data_slots(grid, POND_BAIT_CARD, available.size())
	for index in range(available.size()):
		var rod: Dictionary = available[index]
		var rod_id := str(rod.get("id", ""))
		var slot := slots[index] as PanelContainer
		_set_card_rarity(slot, rod)
		(slot.get_node("Content/Icon") as TextureRect).texture = _workbench_item_icon(rod, false)
		(slot.get_node("Content/Name") as Label).text = str(rod.get("display_name", rod_id))
		(slot.get_node("Content/Count") as Label).text = _localized_name(FISH_RARITY_NAMES, str(rod.get("rarity", "common")), TextDB.text("ui.7cda072d45"))
		(slot.get_node("SelectedCheck") as Node2D).visible = rod_id == selected_id
		var click := slot.get_node("ClickArea") as Button
		_clear_press_connections(click)
		click.disabled = rod_id == selected_id
		if not click.disabled:
			click.pressed.connect(_select_pond_rod.bind(rod_id))


# 选择 pond_rod，供调用方继续处理。
func _select_pond_rod(rod_id: String) -> void:
	var crafting: Node = _services.get("CraftingSystem")
	if crafting == null or not bool(crafting.call("select_rod", rod_id)):
		notify(TextDB.text("ui.f804c5920d"))
		return
	_render_pond_content()


# 设置 idle_auto_fishing，供调用方继续处理。
func _set_idle_auto_fishing(enabled: bool) -> void:
	if _state == null:
		return
	_state.settings["idle_auto_fish"] = enabled
	if enabled:
		_state.flags["fishing_manual_pause"] = false
	var saver := get_node_or_null("/root/SaveManager")
	if saver != null:
		saver.request_save()
	notify(TextDB.text("ui.3365a34da5") % (TextDB.text("ui.256783b7d4") if enabled else TextDB.text("ui.d028bbe586")))


# 打开 shop，供调用方继续处理。
func _open_shop() -> void:
	_hide_offer_bait_hover()
	if _state == null or not bool(_state.shop_unlocked):
		notify(TextDB.text("ui.6770fcfd0c"))
		return
	_new_modal(TextDB.text("ui.a3a42b792c"), "ShopPopup")
	if _modal == null or _shop_content == null or _shop_timer == null:
		push_error("ShopWindow is missing ShopPopup, ShopContent or CountdownTimer.")
		return
	var shop: ShopSystem = _services.get("ShopSystem") as ShopSystem
	if shop == null:
		return
	shop.refresh_offers_if_due()
	var basket := _dict_prop(_state, "fish_basket")
	var content := _shop_content
	var menu := _modal.get_node("ContentSurface/PrimaryMenu") as Control
	for entry in [
		{"node": "FishTab", "id": "fish", "caption": TextDB.text("ui.92468fdf7c")},
		{"node": "BaitTab", "id": "products", "caption": TextDB.text("shop.products.tab")},
		{"node": "CropTab", "id": "crops", "caption": TextDB.text("ui.58f12b65f7")},
	]:
		var tab := menu.get_node(str(entry.node)) as CodexTabButton
		tab.set_caption(str(entry.caption))
		tab.set_selected(_shop_tab == str(entry.id))
		_clear_press_connections(tab)
		tab.pressed.connect(_select_shop_tab.bind(str(entry.id)))
	(content.get_node("ProductSection") as Control).visible = _shop_tab != "fish"
	(content.get_node("HighPriceSection") as Control).visible = _shop_tab == "fish"
	(content.get_node("OwnedSection/Content/HeadingBoard") as Control).visible = _shop_tab == "fish"
	var stock_scroll := content.get_node("OwnedSection/Content/OwnedScroll")
	(stock_scroll.get_node("OwnedGrid") as Control).visible = _shop_tab == "fish"
	(stock_scroll.get_node("ProductGrid") as Control).visible = _shop_tab == "products"
	(stock_scroll.get_node("CropGrid") as Control).visible = _shop_tab == "crops"
	if _shop_tab != "fish":
		_render_shop_products(content)
		_show_modal()
		return
	_set_shop_page_label(content.get_node("ShopTitle") as Label, "ui.a3a42b792c")
	_set_shop_page_label(content.get_node("OwnedSection/Content/HeadingBoard/OwnedTitle") as Label, "ui.945799e023")
	(content.get_node("OwnedSection/Content/SelectionHint") as Label).visible = true
	_set_shop_page_label(content.get_node("OwnedSection/Content/SelectionHint") as Label, "ui.969fe7f634")
	(content.get_node("OwnedSection/Content/OwnedCount") as Label).text = TextDB.text("ui.279e7621b9") % _sum_values(basket)
	var owned_grid := content.get_node("OwnedSection/Content/OwnedScroll/OwnedGrid") as GridContainer
	var registry := get_node_or_null("/root/DataRegistry")
	var owned_ids: Array[String] = []
	for fish_id in basket.keys():
		if int(basket[fish_id]) > 0:
			owned_ids.append(str(fish_id))
	var owned_slots := _shop_stock_slots(owned_grid, owned_ids.size())
	for slot_index in range(owned_ids.size()):
		var fish_id := owned_ids[slot_index]
		var owned := int(basket[fish_id])
		var fish: Dictionary = registry.get_fish(str(fish_id)) if registry != null else {}
		var card := owned_slots[slot_index]
		_set_card_rarity(card, fish)
		(card.get_node("Content/FishName") as Label).text = str(fish.get("display_name", fish_id))
		(card.get_node("Content/FishIcon") as TextureRect).texture = _fish_icon_texture(fish)
		(card.get_node("Content/StockBoard/StockCount") as Label).text = "×%d" % owned
		(card.get_node("Content/PriceRow/Price") as Label).text = str(shop.get_unit_price(str(fish_id)))
		if str(fish_id) == _shop_selected_fish:
			card.modulate = Color(0.85, 1.0, 0.79, 1.0)
		var owned_click := card.get_node("ClickArea") as Button
		_clear_press_connections(owned_click)
		owned_click.pressed.connect(_select_shop_fish.bind(str(fish_id)))
	var offers_row := content.get_node("HighPriceSection/Content/OffersScroll/OffersRow") as Container
	var offer_values: Array[Dictionary] = []
	for value in _state.shop_offers:
		if value is Dictionary:
			offer_values.append(value)
	var offer_slots := _data_slots(offers_row, SHOP_OFFER_CARD, offer_values.size(), true)
	for slot_index in range(offer_values.size()):
		var value: Dictionary = offer_values[slot_index]
		var fish: Dictionary = registry.get_fish(str(value.get("fish_id", ""))) if registry != null else {}
		var card := offer_slots[slot_index]
		_set_card_rarity(card, fish, true)
		(card.get_node("Content/FishName") as Label).text = str(fish.get("display_name", value.get("fish_id", "")))
		(card.get_node("Content/FishIcon") as TextureRect).texture = _fish_icon_texture(fish)
		(card.get_node("Content/PriceRow/Price") as Label).text = str(shop.get_unit_price(str(value.get("fish_id", ""))))
		(card.get_node("Content/MultiplierBoard/Multiplier") as Label).text = "×%.1f" % float(value.get("multiplier", 1.0))
		for connection in card.mouse_entered.get_connections():
			card.mouse_entered.disconnect(connection["callable"])
		for connection in card.mouse_exited.get_connections():
			card.mouse_exited.disconnect(connection["callable"])
		card.mouse_entered.connect(_show_offer_bait_hover.bind(fish, card))
		card.mouse_exited.connect(_hide_offer_bait_hover)
	var countdown := content.get_node("HighPriceSection/Content/CountdownRow/Countdown") as Label
	_update_shop_countdown(countdown)
	_shop_timer.start()
	var has_selected := not _shop_selected_fish.is_empty() and int(basket.get(_shop_selected_fish, 0)) > 0
	var sell_selected := content.get_node("HighPriceSection/Content/ActionRow/SellSelected") as Button
	_clear_press_connections(sell_selected)
	sell_selected.disabled = not has_selected
	sell_selected.modulate = Color.WHITE if has_selected else Color(1, 1, 1, 0.55)
	if has_selected:
		sell_selected.pressed.connect(_sell_selected_shop_fish)
	var sell_all := content.get_node("HighPriceSection/Content/ActionRow/SellAll") as Button
	_clear_press_connections(sell_all)
	sell_all.disabled = _sum_values(basket) <= 0
	sell_all.modulate = Color(1, 1, 1, 0.55) if sell_all.disabled else Color.WHITE
	sell_all.pressed.connect(_sell_all_shop_fish)
	_show_modal()


# 选择 shop_tab，供调用方继续处理。
func _select_shop_tab(tab_id: String) -> void:
	_shop_tab = tab_id
	_open_shop()


# 设置 shop_page_label，供调用方继续处理。
func _set_shop_page_label(label: Label, text_id: String) -> void:
	label.set_meta("l10n_text", text_id)
	label.text = TextDB.text(text_id)


# 显示 offer_bait_hover，供调用方继续处理。
func _show_offer_bait_hover(fish: Dictionary, card: Control) -> void:
	if not (card.get_node("Content") as Control).visible:
		return
	var panel := shop_window.get_node("OfferBaitHover") as PanelContainer
	var bait := _bait_preference_for_fish(fish)
	if bait.is_empty():
		panel.hide()
		return
	(panel.get_node("Content/BaitRow/BaitType") as Label).text = str(bait["display_name"])
	panel.show()


# 隐藏 offer_bait_hover，供调用方继续处理。
func _hide_offer_bait_hover() -> void:
	(shop_window.get_node("OfferBaitHover") as Control).hide()


# 渲染 shop_products，供调用方继续处理。
func _render_shop_products(content: Control) -> void:
	var registry := get_node_or_null("/root/DataRegistry")
	if registry == null:
		return
	var crops := _shop_tab == "crops"
	var products: Array = registry.get_all("crops" if crops else "pasture_products")
	products = products.filter(func(entry: Dictionary) -> bool:
		return int(_state.inventory.get(str(entry.get("id", "")), 0)) > 0
	)
	var title_id := "ui.58f12b65f7" if crops else "shop.products.title"
	_set_shop_page_label(content.get_node("ShopTitle") as Label, title_id)
	var hint := content.get_node("OwnedSection/Content/SelectionHint") as Label
	hint.visible = not crops
	_set_shop_page_label(hint, "shop.products.hint")
	var total := 0
	for value in products:
		var entry: Dictionary = value
		total += int(_state.inventory.get(str(entry.get("id", "")), 0))
	(content.get_node("OwnedSection/Content/OwnedCount") as Label).text = TextDB.text("shop.products.count") % total
	var grid_name := "CropGrid" if crops else "ProductGrid"
	var grid := content.get_node("OwnedSection/Content/OwnedScroll/" + grid_name) as GridContainer
	var slots := _shop_stock_slots(grid, products.size())
	var selected: Dictionary = {}
	var selection_id := _shop_selected_crop if crops else _shop_selected_product
	if products.is_empty():
		selection_id = ""
	elif not products.any(func(entry: Dictionary) -> bool: return str(entry.get("id", "")) == selection_id):
		selection_id = str(products[0].get("id", ""))
	if crops:
		_shop_selected_crop = selection_id
	else:
		_shop_selected_product = selection_id
	for index in range(products.size()):
		var entry: Dictionary = products[index]
		var id := str(entry.get("id", ""))
		var card := slots[index]
		_set_card_rarity(card, entry)
		(card.get_node("Content/FishName") as Label).text = str(entry.get("display_name", id))
		var icon_path := str(entry.get("icon_resource", ""))
		(card.get_node("Content/FishIcon") as TextureRect).texture = load(icon_path) as Texture2D if ResourceLoader.exists(icon_path) else null
		(card.get_node("Content/StockBoard/StockCount") as Label).text = "×%d" % int(_state.inventory.get(id, 0))
		(card.get_node("Content/PriceRow/Price") as Label).text = str(int(entry.get("sell_price", 0)))
		if id == selection_id:
			selected = entry
			card.modulate = Color(0.85, 1.0, 0.79, 1.0)
		var click := card.get_node("ClickArea") as Button
		_clear_press_connections(click)
		click.pressed.connect(_select_shop_product.bind(id))
	var section := content.get_node("ProductSection") as Control
	var selected_id := str(selected.get("id", ""))
	var stock := int(_state.inventory.get(selected_id, 0))
	var selected_icon_path := str(selected.get("icon_resource", ""))
	var product_icon := section.get_node("ProductIcon") as TextureRect
	var crop_icon := section.get_node("CropIcon") as TextureRect
	product_icon.hide()
	crop_icon.hide()
	var detail_icon := crop_icon if crops else product_icon
	detail_icon.texture = load(selected_icon_path) as Texture2D if not selected.is_empty() and ResourceLoader.exists(selected_icon_path) else null
	detail_icon.visible = detail_icon.texture != null
	(section.get_node("ProductName") as Label).text = str(selected.get("display_name", ""))
	(section.get_node("ProductSummary") as Label).text = TextDB.text("ui.bf1fabfad5") if crops and selected.is_empty() else TextDB.text("shop.products.summary") % [stock, int(selected.get("sell_price", 0))]
	var quantity := section.get_node("CropQuantity") as SpinBox
	quantity.visible = crops
	quantity.editable = stock > 0
	quantity.max_value = maxi(1, stock)
	quantity.value = 1
	var sell_selected := section.get_node("SellSelected") as Button
	_clear_press_connections(sell_selected)
	sell_selected.disabled = stock <= 0
	if stock > 0:
		if crops:
			sell_selected.pressed.connect(_sell_selected_shop_crop.bind(quantity))
		else:
			sell_selected.pressed.connect(_sell_selected_shop_product)
	var sell_all := section.get_node("SellAll") as Button
	_clear_press_connections(sell_all)
	sell_all.disabled = total <= 0
	if total > 0:
		sell_all.pressed.connect(_sell_all_shop_crops if crops else _sell_all_shop_products)


# 选择 shop_product，供调用方继续处理。
func _select_shop_product(product_id: String) -> void:
	if _shop_tab == "crops":
		_shop_selected_crop = product_id
	else:
		_shop_selected_product = product_id
	_open_shop()


# 出售 selected_shop_crop，供调用方继续处理。
func _sell_selected_shop_crop(quantity: SpinBox) -> void:
	var shop := _services.get("ShopSystem") as ShopSystem
	if shop != null:
		shop.sell_crop(_shop_selected_crop, int(quantity.value))
	_open_shop()


# 出售 selected_shop_product，供调用方继续处理。
func _sell_selected_shop_product() -> void:
	var shop := _services.get("ShopSystem") as ShopSystem
	if shop != null:
		shop.sell_pasture_product(_shop_selected_product, int(_state.inventory.get(_shop_selected_product, 0)))
	_open_shop()


# 出售 all_shop_crops，供调用方继续处理。
func _sell_all_shop_crops() -> void:
	var shop := _services.get("ShopSystem") as ShopSystem
	if shop != null:
		shop.sell_all_crops()
	_open_shop()


# 出售 all_shop_products，供调用方继续处理。
func _sell_all_shop_products() -> void:
	var shop := _services.get("ShopSystem") as ShopSystem
	if shop != null:
		shop.sell_all_pasture_products()
	_open_shop()


# 响应 shop_timer_tick 对应的事件或条件。
func _on_shop_timer_tick() -> void:
	var countdown := _shop_content.get_node_or_null("HighPriceSection/Content/CountdownRow/Countdown") as Label
	if countdown != null:
		_update_shop_countdown(countdown)


# 封装 shop_stock_slots 的处理，供相关流程复用。
func _shop_stock_slots(grid: GridContainer, count: int) -> Array[Control]:
	var viewport := grid.get_parent() as ScrollContainer
	var slot := grid.get_child(0) as Control
	var row_height := maxf(1.0, slot.get_combined_minimum_size().y)
	var gap := float(grid.get_theme_constant("v_separation"))
	var row_stride := maxf(1.0, row_height + gap)
	var visible_rows := maxi(1, floori((viewport.size.y + gap) / row_stride))
	var columns := maxi(1, grid.columns)
	var rows := maxi(visible_rows, ceili(float(count) / columns))
	return _data_slots(grid, SHOP_OWNED_CARD, count, true, rows * columns)


# 优先复用静态槽位；超出数量时补建卡片，商店卡片统一初始化为空槽或有货状态。
func _data_slots(container: Node, template: PackedScene, count: int, keep_empty_shop_slots: bool = false, min_shop_slots: int = 0) -> Array[Control]:
	# 场景内的卡片是可编辑的固定槽；配置超出槽位时才补充运行时实例。
	for child in container.get_children():
		if bool(child.get_meta("runtime_extra", false)):
			container.remove_child(child)
			child.queue_free()
	var result: Array[Control] = []
	var static_index := 0
	for child in container.get_children():
		var slot := child as Control
		if slot == null:
			continue
		var occupied := static_index < count
		slot.visible = occupied or (keep_empty_shop_slots and (min_shop_slots == 0 or static_index < min_shop_slots))
		if slot.visible:
			slot.modulate = Color.WHITE
			slot.material = null
		if keep_empty_shop_slots:
			_set_shop_slot_occupied(slot, occupied)
		if occupied:
			result.append(slot)
		static_index += 1
	while result.size() < count:
		var extra := template.instantiate() as Control
		extra.set_meta("runtime_extra", true)
		if keep_empty_shop_slots:
			_set_shop_slot_occupied(extra, true)
		container.add_child(extra)
		result.append(extra)
	for index in range(maxi(static_index, count), min_shop_slots):
		var empty_slot := template.instantiate() as Control
		empty_slot.set_meta("runtime_extra", true)
		_set_shop_slot_occupied(empty_slot, false)
		container.add_child(empty_slot)
	return result


# 设置 shop_slot_occupied，供调用方继续处理。
func _set_shop_slot_occupied(slot: Control, occupied: bool) -> void:
	(slot.get_node("BackgroundLayers/EmptySlotBackground") as Control).visible = not occupied
	(slot.get_node("Content") as Control).visible = occupied
	(slot.get_node("RarityBack") as Control).visible = occupied
	var click := slot.get_node_or_null("ClickArea") as Button
	if click != null:
		click.visible = occupied
		if not occupied:
			_clear_press_connections(click)


# 清理 press_connections，供调用方继续处理。
func _clear_press_connections(button: Button) -> void:
	for connection in button.pressed.get_connections():
		button.pressed.disconnect(connection["callable"])


# 选择 shop_fish，供调用方继续处理。
func _select_shop_fish(fish_id: String) -> void:
	_shop_selected_fish = fish_id
	_open_shop()


# 更新 shop_countdown，供调用方继续处理。
func _update_shop_countdown(label: Label) -> void:
	if not is_instance_valid(label):
		return
	var remaining := maxi(0, int(_state.shop_refresh_at) - int(Time.get_unix_time_from_system()))
	label.text = "%02d:%02d:%02d" % [remaining / 3600, (remaining % 3600) / 60, remaining % 60]
	if remaining == 0:
		var shop: ShopSystem = _services.get("ShopSystem") as ShopSystem
		if shop != null:
			shop.refresh_offers_if_due()
		call_deferred("_open_shop")


# 出售 selected_shop_fish，供调用方继续处理。
func _sell_selected_shop_fish() -> void:
	var shop: ShopSystem = _services.get("ShopSystem") as ShopSystem
	var earned := shop.sell_all_of_type(_shop_selected_fish) if shop != null else 0
	if earned <= 0:
		notify(TextDB.text("ui.b5ba499089"))
	_shop_selected_fish = ""
	_open_shop()


# 出售 all_shop_fish，供调用方继续处理。
func _sell_all_shop_fish() -> void:
	var shop: ShopSystem = _services.get("ShopSystem") as ShopSystem
	var result: Dictionary = shop.sell_all_fish() if shop != null else {}
	if int(result.get("coins", 0)) <= 0:
		notify(TextDB.text("ui.b5ba499089"))
	_open_shop()


# 打开 codex，供调用方继续处理。
func _open_codex(tab: String = "fish") -> void:
	_current_codex_tab = tab
	_new_modal(TextDB.text("ui.cdec333f69"), "CodexPopup")
	var content := _modal.get_node("ContentSurface/CodexContent") as Control
	(content.get_node("PreviewPanel/PreviewStatus") as Label).hide()
	(content.get_node("PreviewPanel/AchievementDate") as Label).hide()
	(content.get_node("PreviewPanel/BaitTypeLabel") as Label).hide()
	for entry in [{"id":"fish", "name":TextDB.text("ui.92468fdf7c")}, {"id":"bait", "name":TextDB.text("ui.9be962ae57")}, {"id":"crop", "name":TextDB.text("ui.b3aa8ab320")}, {"id":"achievement", "name":TextDB.text("ui.5dc7d7ba71")}]:
		var tab_button := content.get_node("PrimaryMenu/%sTab" % str(entry.id).capitalize()) as CodexTabButton
		tab_button.set_caption(str(entry.name))
		tab_button.set_selected(entry.id == tab)
		_clear_press_connections(tab_button)
		tab_button.pressed.connect(_open_codex.bind(entry.id))
	var secondary_menu := content.get_node("SecondaryMenu") as Control
	var entries_viewport := content.get_node("EntriesViewport") as ScrollContainer
	var entries_bounds := content.get_node("FishEntriesBounds" if tab == "fish" else "PlainEntriesBounds") as ReferenceRect
	secondary_menu.visible = tab == "fish"
	entries_viewport.offset_left = entries_bounds.offset_left
	entries_viewport.offset_top = entries_bounds.offset_top
	entries_viewport.offset_right = entries_bounds.offset_right
	entries_viewport.offset_bottom = entries_bounds.offset_bottom
	(content.get_node("EntriesViewport/Pages/FishPage") as Control).visible = tab == "fish"
	(content.get_node("EntriesViewport/Pages/CropPage") as Control).visible = tab == "crop"
	(content.get_node("EntriesViewport/Pages/BaitPage") as Control).visible = tab == "bait"
	entries_viewport.visible = tab != "achievement"
	(content.get_node("AchievementPage") as ScrollContainer).visible = tab == "achievement"
	entries_viewport.scroll_vertical = 0
	entries_viewport.set_deferred("scroll_vertical", 0)
	if tab == "fish":
		_build_fish_codex(content)
	elif tab == "crop":
		_build_crop_codex(content)
	elif tab == "bait":
		_build_bait_codex(content)
	else:
		_build_achievement_codex(content)
	_show_modal()
	if tab != "achievement":
		call_deferred("_sync_codex_entries_layout", entries_viewport, tab)


# 同步 codex_entries_layout，供调用方继续处理。
func _sync_codex_entries_layout(entries_viewport: ScrollContainer, tab: String) -> void:
	if not is_instance_valid(entries_viewport) or not entries_viewport.is_inside_tree():
		return
	var pages := entries_viewport.get_node_or_null("Pages") as Control
	if pages == null:
		return
	var page_name := "FishPage" if tab == "fish" else "CropPage" if tab == "crop" else "BaitPage"
	var grid := pages.get_node_or_null(page_name) as GridContainer
	if grid == null:
		return
	# GridContainer 的最小高度会随卡片数量变化；只向下扩展滚动内容。
	var content_height := ceilf(grid.get_combined_minimum_size().y * grid.scale.y) + 12.0
	pages.custom_minimum_size = Vector2(335.0, maxf(entries_viewport.size.y, content_height))
	entries_viewport.scroll_vertical = 0


# 构建 achievement_codex，供调用方继续处理。
func _build_achievement_codex(content: Control) -> void:
	var service: Node = _services.get("AchievementSystem")
	var entries: Array = service.call("get_entries") if service != null else []
	var page := content.get_node("AchievementPage") as ScrollContainer
	var list := page.get_node("List") as VBoxContainer
	var completed := 0
	for index in range(12):
		var card := list.get_node("Slot%02d" % (index + 1)) as Control
		card.visible = index < entries.size()
		if not card.visible:
			continue
		var entry: Dictionary = entries[index]
		var unlocked := bool(entry.get("unlocked", false))
		if unlocked:
			completed += 1
		var icon_path := str(entry.get("icon_unlocked" if unlocked else "icon_locked", ""))
		var icon := card.get_node("Content/Icon") as TextureRect
		icon.texture = load(icon_path) as Texture2D if ResourceLoader.exists(icon_path) else null
		icon.material = null
		if not unlocked:
			var silhouette := ShaderMaterial.new()
			silhouette.shader = ACHIEVEMENT_SILHOUETTE_SHADER
			icon.material = silhouette
		(card.get_node("Content/Details/TitleRow/Name") as Label).text = str(entry.get("name", ""))
		var status_label := card.get_node("Content/Details/TitleRow/Status") as Label
		status_label.text = TextDB.text("ui.33246f6a5e") if unlocked else TextDB.text("ui.b61b08aec3")
		status_label.add_theme_color_override("font_color", Color("#5e8a45") if unlocked else Color("#7b6b5b"))
		(card.get_node("Content/Details/Condition") as Label).text = str(entry.get("description", ""))
		var progress := card.get_node("Content/Details/ProgressRow/Progress") as ProgressBar
		progress.max_value = float(maxi(1, int(entry.get("target", 1))))
		progress.value = float(entry.get("progress", 0))
		(card.get_node("Content/Details/ProgressRow/ProgressText") as Label).text = "%d/%d" % [int(entry.get("progress", 0)), int(entry.get("target", 1))]
		(card.get_node("SelectedFrame") as Panel).visible = false
		var click := card.get_node("ClickArea") as Button
		_clear_press_connections(click)
		click.pressed.connect(_select_achievement_codex.bind(content, list, card, entry))
		if index == 0:
			_select_achievement_codex(content, list, card, entry)
	(list.get_node("Summary") as Label).text = TextDB.text("ui.5570c9aba6") % [completed, entries.size()]


# 选择 achievement_codex，供调用方继续处理。
func _select_achievement_codex(content: Control, list: VBoxContainer, selected_card: Control, entry: Dictionary) -> void:
	for node in list.get_children():
		if node is Control and node.has_node("SelectedFrame"):
			(node.get_node("SelectedFrame") as Panel).visible = node == selected_card
	var unlocked := bool(entry.get("unlocked", false))
	var stage_names := {"beginner":TextDB.text("ui.339681e312"), "development":TextDB.text("ui.468e24b50f"), "formed":TextDB.text("ui.f826b3e07c")}
	var stage := str(stage_names.get(str(entry.get("stage", "")), ""))
	var info := TextDB.text("ui.1bfded771f") % [stage, str(entry.get("description", "")), int(entry.get("progress", 0)), int(entry.get("target", 1))]
	var icon_path := str(entry.get("icon_unlocked" if unlocked else "icon_locked", ""))
	var icon := load(icon_path) as Texture2D if ResourceLoader.exists(icon_path) else null
	_set_codex_preview(content, str(entry.get("name", "")), icon, info, unlocked)
	if not unlocked:
		var preview_icon := content.get_node("PreviewPanel/PreviewIcon") as TextureRect
		var silhouette := ShaderMaterial.new()
		silhouette.shader = ACHIEVEMENT_SILHOUETTE_SHADER
		preview_icon.material = silhouette
	var date_label := content.get_node("PreviewPanel/AchievementDate") as Label
	var unlocked_at := int(entry.get("unlocked_at", 0))
	date_label.visible = unlocked and unlocked_at > 0
	if date_label.visible:
		var timezone_offset := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
		date_label.text = Time.get_date_string_from_unix_time(unlocked_at + timezone_offset)


# 打开 codex_from_icon，供调用方继续处理。
func _open_codex_from_icon() -> void:
	var unread: Dictionary = _state.settings.get("unlock_dot_unread", {})
	if not unread.is_empty():
		unread.clear()
		(overlay.get_node("RightIcons/CodexIcon/NewUnlockDot") as Control).hide()
		SaveManager.request_save()
	_open_codex("fish")


# 打开 fish_rarity，供调用方继续处理。
func _open_fish_rarity(rarity: String) -> void:
	_current_fish_rarity = rarity
	_open_codex("fish")


# 构建 fish_codex，供调用方继续处理。
func _build_fish_codex(content: Control) -> void:
	var codex: Node = _services.get("CodexSystem")
	var entries: Array = codex.call("get_entries", "fish") if codex != null else []
	var registry := get_node_or_null("/root/DataRegistry")
	for rarity_data in FISH_RARITY_TABS:
		var rarity_id := str(rarity_data["id"])
		var total := 0
		var known_count := 0
		for value in entries:
			if value is Dictionary and str(value.get("rarity", "")) == rarity_id:
				total += 1
				if bool(value.get("discovered", false)):
					known_count += 1
		var tab_button := content.get_node("SecondaryMenu/%sTab" % rarity_id.capitalize()) as CodexTabButton
		tab_button.set_caption(TextDB.text(str(rarity_data["label"])))
		# 这里是图鉴二级按钮文本
		tab_button.set_selected(rarity_id == _current_fish_rarity)
		_clear_press_connections(tab_button)
		tab_button.pressed.connect(_open_fish_rarity.bind(rarity_id))
	var grid := content.get_node("EntriesViewport/Pages/FishPage") as GridContainer
	var visible_fish: Array[Dictionary] = []
	var undiscovered_fish: Array[Dictionary] = []
	for value in entries:
		if value is Dictionary and str(value.get("rarity", "")) == _current_fish_rarity:
			if bool(value.get("discovered", false)):
				visible_fish.append(value)
			else:
				undiscovered_fish.append(value)
	# Stable partition: keep the catalog order within both groups.
	visible_fish.append_array(undiscovered_fish)
	var fish_slots := _data_slots(grid, FISH_CODEX_CARD, visible_fish.size())
	var preview_set := false
	for slot_index in range(visible_fish.size()):
		var entry: Dictionary = visible_fish[slot_index]
		var fish_id := str(entry.get("id", ""))
		var catalog: Dictionary = registry.get_fish(fish_id) if registry != null else {}
		var known := bool(entry.get("discovered", false))
		var fish_name := str(entry.get("display_name", fish_id if known else "???"))
		var card := fish_slots[slot_index] as Control
		_set_card_rarity(card, catalog)
		var icon := card.get_node("Content/FishIcon") as TextureRect
		_reset_codex_card(card, icon)
		icon.texture = _fish_icon_texture(catalog)
		(card.get_node("SelectedFrame") as Panel).visible = false
		var label := card.get_node("Content/FishName") as Label
		label.text = fish_name
		var size_record: Dictionary = _state.fish_size_records.get(fish_id, {})
		# (card.get_node("MinBadge") as Label).visible = known and bool(size_record.get("caught_minimum", false))
		(card.get_node("MinBadge") as Label).visible = false
		(card.get_node("MaxBadge") as Label).visible = known and bool(size_record.get("caught_maximum", false))
		label.add_theme_color_override("font_color", COLOR_INK if known else Color("#303030"))
		if not known:
			_gray_out_codex_card(card, icon, true)
		var hit_area := card.get_node("ClickArea") as Button
		var bait_preference := _bait_preference_for_fish(catalog)
		var preview_info := _fish_preview_info(catalog)
		var fishing := _services.get("FishingSystem") as FishingSystem
		var size_limits := fishing.get_size_limits(str(catalog.get("rarity", "common"))) if fishing != null else Vector2i.ZERO
		_clear_press_connections(hit_area)
		hit_area.pressed.connect(_select_fish_codex_card.bind(content, grid, card, fish_name, icon.texture, preview_info, known, bait_preference, size_record, size_limits))
		if not preview_set:
			_select_fish_codex_card(content, grid, card, fish_name, icon.texture, preview_info, known, bait_preference, size_record, size_limits)
			preview_set = true


# 封装 bait_preference_for_fish 的处理，供相关流程复用。
func _bait_preference_for_fish(fish: Dictionary) -> Dictionary:
	var bait_type := str(fish.get("preferred_bait_type", ""))
	if bait_type.is_empty():
		return {}
	return {"display_name": _bait_type_label(bait_type)}


# 封装 fish_preview_info 的处理，供相关流程复用。
func _fish_preview_info(fish: Dictionary) -> String:
	return TextDB.text("ui.de33101caa") % [
		_localized_name(FISH_RARITY_NAMES, str(fish.get("rarity", "common")), TextDB.text("ui.7cda072d45")),
		_bait_type_label(str(fish.get("preferred_bait_type", ""))),
		int(fish.get("sell_price", 0)),
	]


# 选择 fish_codex_card，供调用方继续处理。
func _select_fish_codex_card(content: Control, grid: GridContainer, selected_card: Control, fish_name: String, icon: Texture2D, info: String, known: bool, bait_preference: Dictionary, size_record: Dictionary, size_limits: Vector2i = Vector2i.ZERO) -> void:
	for card in grid.get_children():
		(card.get_node("SelectedFrame") as Panel).visible = card == selected_card
	_set_codex_preview(content, fish_name, icon, info, known, true)
	var row := content.get_node("PreviewPanel/FavoriteBaitRow") as Control
	row.visible = not bait_preference.is_empty()
	(content.get_node("PreviewPanel/PreviewStatus") as Label).visible = not row.visible
	if row.visible:
		(row.get_node("BaitIcon") as TextureRect).texture = BAIT_PLACEHOLDER_ICON
		(row.get_node("BaitName") as Label).text = str(bait_preference.get("display_name", TextDB.text("ui.5dbd015496")))
	var size_row := content.get_node("PreviewPanel/SizeRecordRow") as Control
	size_row.visible = known and not size_record.is_empty()
	if size_row.visible:
		(size_row.get_node("Value") as Label).text = TextDB.text("fishing.size.value") % int(size_record.get("largest_cm", 0))
		(size_row.get_node("MaxTag") as Control).visible = bool(size_record.get("caught_maximum", false))
		# (size_row.get_node("MinTag") as Control).visible = bool(size_record.get("caught_minimum", false))
		(size_row.get_node("MinTag") as Control).visible = false
	_update_fish_size_ruler(size_row, size_limits, int(size_record.get("largest_cm", 0)))


# limits 和 record_cm 均以厘米计；红线使用玩家最大记录，等长范围固定标在左端。
func _update_fish_size_ruler(size_row: Control, limits: Vector2i, record_cm: int) -> void:
	var ruler := size_row.get_node("SizeRuler") as Control
	ruler.visible = size_row.visible and record_cm > 0 and limits.x > 0 and limits.y >= limits.x
	if not ruler.visible:
		return
	(ruler.get_node("Minimum") as Label).text = TextDB.text("fishing.size.value") % limits.x
	(ruler.get_node("Maximum") as Label).text = TextDB.text("fishing.size.value") % limits.y
	var ratio := 0.0
	if limits.y > limits.x:
		ratio = clampf(float(record_cm - limits.x) / float(limits.y - limits.x), 0.0, 1.0)
	var marker := ruler.get_node("RecordMarker") as ColorRect
	marker.anchor_left = ratio
	marker.anchor_right = ratio


# 构建 crop_codex，供调用方继续处理。
func _build_crop_codex(content: Control) -> void:
	var codex: Node = _services.get("CodexSystem")
	var entries: Array = codex.call("get_entries", "crop") if codex != null else []
	var registry := get_node_or_null("/root/DataRegistry")
	var grid := content.get_node("EntriesViewport/Pages/CropPage") as GridContainer
	var crop_entries: Array[Dictionary] = []
	for value in entries:
		if value is Dictionary:
			crop_entries.append(value)
	var crop_slots := _data_slots(grid, CROP_CODEX_CARD, crop_entries.size())
	var preview_set := false
	for slot_index in range(crop_entries.size()):
		var entry: Dictionary = crop_entries[slot_index]
		var crop_id := str(entry.get("id", ""))
		var crop: Dictionary = registry.get_crop(crop_id) if registry != null else {}
		var known := bool(entry.get("discovered", false))
		var card := crop_slots[slot_index] as Control
		_set_card_rarity(card, crop)
		var icon := card.get_node("Content/CropIcon") as TextureRect
		_reset_codex_card(card, icon)
		var icon_path := str(crop.get("icon_resource", ""))
		if icon_path.is_empty():
			icon_path = str(crop.get("mature_resource", ""))
		icon.texture = load(icon_path) as Texture2D if ResourceLoader.exists(icon_path) else null
		var label := card.get_node("Content/CropName") as Label
		label.text = str(entry.get("display_name", crop_id if known else "???"))
		label.add_theme_color_override("font_color", COLOR_INK if known else Color("#303030"))
		if not known:
			_gray_out_codex_card(card, icon, true)
		var info := TextDB.text("ui.4e6d2a69c1") % [_localized_name(BAIT_TYPE_NAMES, str(crop.get("bait_type", "")), TextDB.text("ui.58f12b65f7")), _format_duration(int(crop.get("grow_seconds", 0))), maxi(1, int(crop.get("harvest_amount", 1))), int(crop.get("plant_cost", 0))]
		var crop_click := card.get_node("ClickArea") as Button
		_clear_press_connections(crop_click)
		crop_click.pressed.connect(_set_codex_preview.bind(content, label.text, icon.texture, info, known, true))
		if not preview_set:
			_set_codex_preview(content, label.text, icon.texture, info, known, true)
			preview_set = true


# 构建 bait_codex，供调用方继续处理。
func _build_bait_codex(content: Control) -> void:
	var grid := content.get_node("EntriesViewport/Pages/BaitPage") as GridContainer
	var codex: Node = _services.get("CodexSystem")
	var entries: Array = codex.call("get_entries", "bait") if codex != null else []
	var registry := get_node_or_null("/root/DataRegistry")
	var bait_entries: Array[Dictionary] = []
	for value in entries:
		if value is Dictionary:
			bait_entries.append(value)
	var bait_slots := _data_slots(grid, BAIT_CODEX_CARD, bait_entries.size())
	var preview_set := false
	for slot_index in range(bait_entries.size()):
		var entry: Dictionary = bait_entries[slot_index]
		var bait_id := str(entry.get("id", ""))
		var bait: Dictionary = registry.get_bait(bait_id) if registry != null else {}
		var known := bool(entry.get("discovered", false))
		var cell := bait_slots[slot_index] as Control
		_set_card_rarity(cell, bait)
		var icon := cell.get_node("Content/BaitIcon") as TextureRect
		_reset_codex_card(cell, icon)
		var icon_path := str(bait.get("icon_resource", ""))
		icon.texture = load(icon_path) as Texture2D if ResourceLoader.exists(icon_path) else BAIT_PLACEHOLDER_ICON
		var label := cell.get_node("Content/BaitName") as Label
		label.text = str(entry.get("display_name", bait_id if known else "???"))
		label.add_theme_color_override("font_color", COLOR_INK if known else Color("#303030"))
		if not known:
			_gray_out_codex_card(cell, icon, true)
		var info := TextDB.text("ui.b62d0ce055") % [_bait_type_label(str(bait.get("bait_type", ""))), _display_id(str(bait.get("source_crop", ""))), int(bait.get("charges_per_batch", 0))]
		var bait_click := cell.get_node("ClickArea") as Button
		_clear_press_connections(bait_click)
		bait_click.pressed.connect(_set_codex_preview.bind(content, label.text, icon.texture, info, known, true, str(bait.get("bait_type", ""))))
		if not preview_set:
			_set_codex_preview(content, label.text, icon.texture, info, known, true, str(bait.get("bait_type", "")))
			preview_set = true


# 填充共用图鉴详情；bait_types 为分号分隔的鱼饵类型，默认空值隐藏类型行，未解锁鱼饵也隐藏。
func _set_codex_preview(content: Control, name: String, texture: Texture2D, info: String, known: bool, fish_silhouette: bool = false, bait_types: String = "") -> void:
	var preview := content.get_node("PreviewPanel") as Control
	(preview.get_node("FavoriteBaitRow") as Control).visible = false
	(preview.get_node("SizeRecordRow") as Control).visible = false
	(preview.get_node("PreviewName") as Label).text = name
	var bait_type_label := preview.get_node("BaitTypeLabel") as Label
	bait_type_label.visible = known and not bait_types.is_empty()
	bait_type_label.text = _bait_type_label(bait_types) if bait_type_label.visible else ""
	var preview_icon := preview.get_node("PreviewIcon") as TextureRect
	preview_icon.texture = texture
	preview_icon.material = null
	if not known:
		var unknown_material := ShaderMaterial.new()
		unknown_material.shader = FISH_SILHOUETTE_SHADER if fish_silhouette else FISH_GRAYSCALE_SHADER
		preview_icon.material = unknown_material
	(preview.get_node("PreviewInfo") as Label).text = info
	(preview.get_node("PreviewStatus") as Label).text = TextDB.text("ui.a5b813e2aa") if known else TextDB.text("ui.b3bd8c0da5")


# 重置 codex_card，供调用方继续处理。
func _reset_codex_card(card: Control, icon: TextureRect) -> void:
	card.material = null
	icon.material = null
	var rarity_back := card.get_node_or_null("RarityBack") as TextureRect
	if rarity_back != null:
		rarity_back.material = null
	var selected_frame := card.get_node_or_null("SelectedFrame") as Panel
	if selected_frame != null:
		selected_frame.material = null
		if selected_frame.has_meta("original_panel_style"):
			selected_frame.add_theme_stylebox_override("panel", selected_frame.get_meta("original_panel_style") as StyleBox)
	var hit_area := card.get_node_or_null("ClickArea") as Button
	if hit_area != null and hit_area.has_meta("original_focus_style"):
		hit_area.add_theme_stylebox_override("focus", hit_area.get_meta("original_focus_style") as StyleBox)


# 封装 gray_out_codex_card 的处理，供相关流程复用。
func _gray_out_codex_card(card: Control, icon: TextureRect, fish_silhouette: bool = false) -> void:
	# Unknown entries keep gray frames and rarity backing, with black icon silhouettes.
	var grayscale_material := ShaderMaterial.new()
	grayscale_material.shader = FISH_GRAYSCALE_SHADER
	card.material = grayscale_material
	var rarity_back := card.get_node_or_null("RarityBack") as TextureRect
	if rarity_back != null:
		rarity_back.material = grayscale_material
	var selected_frame := card.get_node_or_null("SelectedFrame") as Panel
	if selected_frame != null:
		var frame_style := selected_frame.get_theme_stylebox("panel") as StyleBoxFlat
		if frame_style != null:
			if not selected_frame.has_meta("original_panel_style"):
				selected_frame.set_meta("original_panel_style", frame_style)
			var gray_frame := frame_style.duplicate() as StyleBoxFlat
			gray_frame.bg_color = Color.TRANSPARENT
			gray_frame.border_color = Color("#777777")
			selected_frame.add_theme_stylebox_override("panel", gray_frame)
	if fish_silhouette:
		var silhouette_material := ShaderMaterial.new()
		silhouette_material.shader = FISH_SILHOUETTE_SHADER
		icon.material = silhouette_material
	else:
		icon.material = grayscale_material
	var hit_area := card.get_node_or_null("ClickArea") as Button
	if hit_area != null:
		var focus_style := hit_area.get_theme_stylebox("focus") as StyleBoxFlat
		if focus_style != null:
			if not hit_area.has_meta("original_focus_style"):
				hit_area.set_meta("original_focus_style", focus_style)
			var gray_focus := focus_style.duplicate() as StyleBoxFlat
			gray_focus.border_color = Color("#777777")
			hit_area.add_theme_stylebox_override("focus", gray_focus)


# 打开 settings，供调用方继续处理。
func _open_settings() -> void:
	_new_modal(TextDB.text("ui.7debf9cb03"), "SettingsPopup")
	var content := _modal.get_node("ContentSurface/SettingsContent") as Control
	var display_size_label := content.get_node("DisplaySizeLabel") as Label
	var display_size_choice := content.get_node("DisplaySizeChoice") as OptionButton
	if TextDB.language == "en":
		display_size_label.text = "Display Size"
		for index in range(display_size_choice.item_count):
			display_size_choice.set_item_text(index, ["Small", "Medium", "Large"][index])
	display_size_choice.select(_saved_display_size())
	if not display_size_choice.item_selected.is_connected(_select_display_size):
		display_size_choice.item_selected.connect(_select_display_size)
	var screen_choice := content.get_node("ScreenChoice") as OptionButton
	screen_choice.clear()
	for index in range(DisplayServer.get_screen_count()):
		screen_choice.add_item(_display_device_name(index), index)
	screen_choice.select(clampi(int(_state.settings.get("display_screen", DisplayServer.window_get_current_screen())), 0, maxi(0, screen_choice.item_count - 1)))
	for connection in screen_choice.item_selected.get_connections():
		screen_choice.item_selected.disconnect(connection["callable"])
	screen_choice.item_selected.connect(func(index: int): _change_display(index, int(_state.settings.get("display_raise", 0))))
	for item in [{"node": "MoveUp", "step": 10}, {"node": "MoveDown", "step": -10}]:
		var button := content.get_node(str(item.node)) as Button
		_clear_press_connections(button)
		button.pressed.connect(_move_display_vertical.bind(int(item.step)))
	_update_display_offset_label()
	var effects := content.get_node("EffectsToggle") as Button
	effects.text = TextDB.text("ui.256783b7d4") if bool(_state.settings.get("sfx_enabled", true)) else TextDB.text("ui.6c14bd7f6f")
	_clear_press_connections(effects)
	effects.pressed.connect(_toggle_effects)
	var sound := content.get_node("SoundToggle") as Button
	sound.text = TextDB.text("ui.256783b7d4") if get_node("/root/MusicManager").is_enabled() else TextDB.text("ui.6c14bd7f6f")
	_clear_press_connections(sound)
	sound.pressed.connect(_toggle_mute)
	var dock := content.get_node("DockToggle") as Button
	dock.text = TextDB.text("ui.256783b7d4") if _stick_to_bottom else TextDB.text("ui.6c14bd7f6f")
	_clear_press_connections(dock)
	dock.pressed.connect(_toggle_dock)
	var top := content.get_node("TopToggle") as Button
	top.text = TextDB.text("ui.256783b7d4") if _always_on_top else TextDB.text("ui.6c14bd7f6f")
	_clear_press_connections(top)
	top.pressed.connect(_toggle_always_on_top)
	var language_choice := content.get_node("LanguageValue") as OptionButton
	language_choice.select(1 if TextDB.language == "en" else 0)
	for connection in language_choice.item_selected.get_connections():
		language_choice.item_selected.disconnect(connection["callable"])
	language_choice.item_selected.connect(_select_language)
	var help := content.get_node("HelpButton") as Button
	_clear_press_connections(help)
	help.pressed.connect(func(): notify(TextDB.text("ui.38df199f47")))
	_show_modal()


# 保存显示档位并重新定位设置窗口，保持面板可继续操作。
func _select_display_size(index: int) -> void:
	_state.settings["display_size"] = index
	_apply_desktop_window()
	_position_pond_relative_window(settings_window)
	_update_display_offset_label()
	SaveManager.save_game()


# 选择 language，供调用方继续处理。
func _select_language(index: int) -> void:
	var language := "en" if index == 1 else "zh"
	if TextDB.language == language:
		return
	get_node("/root/SaveManager").call("save_game")
	TextDB.set_language(language)
	get_tree().call_deferred("reload_current_scene")


# 打开 gm，供调用方继续处理。
func _open_gm() -> void:
	_new_modal(TextDB.text("ui.bd808fcb90"), "GMPopup")
	_show_modal()


# 打开 reset_confirmation，供调用方继续处理。
func _open_reset_confirmation() -> void:
	var body := _new_modal(TextDB.text("ui.e13d564d41"), "ResetPopup")
	var content := _prepare_info_actions(body)
	var warning := content.get_node("Info") as Label
	warning.text = TextDB.text("ui.6282d0664b")
	var cancel := content.get_node("Actions/Action2") as Button
	cancel.visible = true
	cancel.text = TextDB.text("ui.4d0b4688c7")
	cancel.pressed.connect(_close_modal)
	var confirm := content.get_node("Actions/Action1") as Button
	confirm.visible = true
	confirm.text = TextDB.text("ui.30a6079ce3")
	confirm.pressed.connect(_confirm_reset_progress)
	_show_modal()


# 封装 confirm_reset_progress 的处理，供相关流程复用。
func _confirm_reset_progress() -> void:
	var saver := get_node_or_null("/root/SaveManager")
	var succeeded := false
	if saver != null and saver.has_method("delete_save_and_reset"):
		succeeded = bool(saver.call("delete_save_and_reset"))
	_close_modal()
	if succeeded:
		_refresh()
		notify(TextDB.text("ui.a7a7c22df9"))
	else:
		notify(TextDB.text("ui.5bf03238ca"))


# 封装 notify 的处理，供相关流程复用。
func notify(message: String) -> void:
	_toast_message.text = message
	_toast_message.visible = true
	_toast.visible = true
	_toast.move_to_front()
	_toast_timer.start()


# 封装 new_modal 的处理，供相关流程复用。
func _new_modal(_title: String, popup_name: String) -> HBoxContainer:
	_task_icon_click_timer.stop()
	_task_icon_click_count = 0
	_remember_crop_scroll()
	if _shop_timer != null:
		_shop_timer.stop()
	for popup in _popups.values():
		(popup as PanelContainer).visible = false
	if not CODEX_WINDOW_POPUPS.has(popup_name):
		codex_window.hide()
	if popup_name != "ShopPopup":
		shop_window.hide()
	if popup_name != "SettingsPopup":
		settings_window.hide()
	if popup_name != "GMPopup":
		gm_window.hide()
	if popup_name != "PlotPopup":
		plant_window.hide()
	if popup_name != "CottagePopup":
		cottage_window.hide()
	if popup_name != "WorkbenchPopup":
		workbench_window.hide()
	if popup_name != "PondPopup":
		pond_window.hide()
	pasture_window.hide()
	pasture_feed_window.hide()
	task_window.hide()
	_modal = _popups.get(popup_name) as PanelContainer
	if _modal == null:
		push_error(TextDB.text("ui.a9262343cb") % popup_name)
		return null
	_modal_body = null if popup_name in ["PlotPopup", "CodexPopup", "SettingsPopup", "GMPopup", "CottagePopup", "WorkbenchPopup", "PondPopup"] else _modal.get_node("ContentSurface/ContentScroll/Content/Body") as HBoxContainer
	return _modal_body


# 准备 info_actions，供调用方继续处理。
func _prepare_info_actions(body: HBoxContainer) -> HBoxContainer:
	var content := body.get_node("InfoActionsContent") as HBoxContainer
	_reset_info_actions(content)
	return content


# 重置 info_actions，供调用方继续处理。
func _reset_info_actions(content: HBoxContainer) -> void:
	var option := content.get_node("Actions/Option") as CheckBox
	for connection in option.toggled.get_connections():
		option.toggled.disconnect(connection["callable"])
	option.visible = false
	for index in range(1, 5):
		var button := content.get_node("Actions/Action%d" % index) as Button
		for connection in button.pressed.get_connections():
			button.pressed.disconnect(connection["callable"])
		button.visible = false
		button.disabled = false


# 显示 modal，供调用方继续处理。
func _show_modal() -> void:
	_hide_plot_progress()
	_modal.visible = true
	_modal.move_to_front()
	if CODEX_WINDOW_POPUPS.has(_modal.name):
		_position_codex_window()
		codex_window.show()
		# macOS/Godot 4.7.1 的原生子窗口在 show() 时会清掉透明标志。
		# 必须在显示之后重新设置，否则木框周围的透明像素会显示为黑色。
		codex_window.transparent_bg = true
		codex_window.transparent = true
	elif _modal.name == "ShopPopup":
		_position_shop_window()
		shop_window.show()
		shop_window.transparent_bg = true
		shop_window.transparent = true
	elif _modal.name == "SettingsPopup":
		_position_pond_relative_window(settings_window)
		settings_window.show()
		settings_window.transparent_bg = true
		settings_window.transparent = true
	elif _modal.name == "GMPopup":
		_position_floating_window(gm_window)
		gm_window.show()
		gm_window.transparent_bg = true
		gm_window.transparent = true
	elif _modal.name == "PlotPopup":
		_position_floating_window(plant_window)
		plant_window.show()
		plant_window.transparent_bg = true
		plant_window.transparent = true
		call_deferred("_restore_crop_scroll")
	elif _modal.name == "CottagePopup":
		_position_building_window(cottage_window, "House")
		cottage_window.show()
		cottage_window.transparent_bg = true
		cottage_window.transparent = true
	elif _modal.name == "WorkbenchPopup":
		_position_building_window(workbench_window, "Workbench")
		workbench_window.show()
		workbench_window.transparent_bg = true
		workbench_window.transparent = true
	elif _modal.name == "PondPopup":
		_position_pond_window()
		pond_window.show()
		pond_window.transparent_bg = true
		pond_window.transparent = true
	call_deferred("_focus_first_in_modal")


# 定位 floating_window，供调用方继续处理。
func _position_floating_window(popup_window: Window) -> void:
	if not bool(popup_window.get("follow_main")) or DisplayServer.get_name() == "headless":
		return
	var main_window := get_window()
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var offset: Vector2i = popup_window.get("desktop_offset")
	var desired_x: int = main_window.position.x + roundi(float(main_window.size.x - popup_window.size.x) / 2.0) + offset.x
	var desired_y: int = main_window.position.y - popup_window.size.y + offset.y
	popup_window.position = Vector2i(
		clampi(desired_x, usable.position.x, maxi(usable.position.x, usable.end.x - popup_window.size.x)),
		clampi(desired_y, usable.position.y, maxi(usable.position.y, usable.end.y - popup_window.size.y))
	)


# 将当前档位的主画布 X 坐标换算为桌面像素。
func _desktop_x_for_view_x(view_x: float) -> int:
	var main_window := get_window()
	return main_window.position.x + roundi(view_x * float(main_window.size.x) / float(_display_width))


# 定位 building_window，供调用方继续处理。
func _position_building_window(popup_window: Window, building_name: String) -> void:
	if not bool(popup_window.get("follow_main")) or DisplayServer.get_name() == "headless":
		return
	var main_window := get_window()
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var building := static_world.get_node_or_null("ResourceNodes/%s" % building_name) as Node2D
	var building_x: float = building.global_position.x if building != null else float(_display_width) * 0.5
	var offset: Vector2i = popup_window.get("desktop_offset")
	var desired_x: int = _desktop_x_for_view_x(building_x) - popup_window.size.x / 2 + offset.x
	var desired_y: int = main_window.position.y - popup_window.size.y + offset.y
	popup_window.position = Vector2i(
		clampi(desired_x, usable.position.x, maxi(usable.position.x, usable.end.x - popup_window.size.x)),
		clampi(desired_y, usable.position.y, maxi(usable.position.y, usable.end.y - popup_window.size.y))
	)


# 定位 codex_window，供调用方继续处理。
func _position_codex_window() -> void:
	_position_pond_relative_window(codex_window)


# 定位 pond_window，供调用方继续处理。
func _position_pond_window() -> void:
	_position_pond_relative_window(pond_window)


# 定位 pond_relative_window，供调用方继续处理。
func _position_pond_relative_window(popup_window: Window) -> void:
	if not bool(popup_window.get("follow_pond")):
		return
	if DisplayServer.get_name() == "headless":
		return
	var main_window := get_window()
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var pond := static_world.get_node_or_null("ResourceNodes/Pond") as Node2D
	var pond_offset: Vector2i = popup_window.get("pond_offset")
	var gap_to_main: int = popup_window.get("gap_to_main")
	var pond_x: float = pond.global_position.x if pond != null else float(_display_width) * 0.85
	var pond_screen_x := _desktop_x_for_view_x(pond_x)
	var desired_x: int = pond_screen_x - popup_window.size.x / 2 + pond_offset.x
	var desired_y: int = main_window.position.y - popup_window.size.y - gap_to_main + pond_offset.y
	popup_window.position = Vector2i(
		clampi(desired_x, usable.position.x, maxi(usable.position.x, usable.end.x - popup_window.size.x)),
		clampi(desired_y, usable.position.y, maxi(usable.position.y, usable.end.y - popup_window.size.y))
	)


# 定位 shop_window，供调用方继续处理。
func _position_shop_window() -> void:
	if not bool(shop_window.get("follow_shop")):
		return
	if DisplayServer.get_name() == "headless":
		return
	# 与图鉴共享纵坐标，包括图鉴在 Inspector 中设置的手动定位。
	_position_codex_window()
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var shop := static_world.get_node_or_null("ResourceNodes/ShopBuilding") as Node2D
	var shop_x: float = shop.global_position.x if shop != null else float(_display_width) * 0.75
	var shop_screen_x := _desktop_x_for_view_x(shop_x)
	var offset: Vector2i = shop_window.get("shop_offset")
	var desired_x: int = shop_screen_x - shop_window.size.x / 2 + offset.x
	var desired_y: int = codex_window.position.y + offset.y
	shop_window.position = Vector2i(
		clampi(desired_x, usable.position.x, maxi(usable.position.x, usable.end.x - shop_window.size.x)),
		clampi(desired_y, usable.position.y, maxi(usable.position.y, usable.end.y - shop_window.size.y))
	)


# 封装 focus_first_in_modal 的处理，供相关流程复用。
func _focus_first_in_modal() -> void:
	var close := _modal.find_child("CloseButton", true, false) as Button
	if close != null:
		close.grab_focus()


# 关闭 modal，供调用方继续处理。
func _close_modal() -> void:
	_task_icon_click_timer.stop()
	_task_icon_click_count = 0
	_remember_crop_scroll()
	if _shop_timer != null:
		_shop_timer.stop()
	for popup in _popups.values():
		(popup as PanelContainer).visible = false
	codex_window.hide()
	shop_window.hide()
	settings_window.hide()
	gm_window.hide()
	plant_window.hide()
	cottage_window.hide()
	workbench_window.hide()
	pond_window.hide()
	pasture_window.hide()
	pasture_feed_window.hide()
	task_window.hide()


# 封装 plant_crop 的处理，供相关流程复用。
func _plant_crop(index: int, crop_id: String, repeat_crop: bool = false, grouped: bool = true) -> void:
	var plot: Dictionary = _state.get_plot(str(index))
	var cells: Array = plot.get("cells", [])
	var jobs: Node = _services.get("JobManager")
	if jobs == null:
		return
	var single_cell := _selected_cell_index
	if not grouped and (single_cell < 0 or single_cell >= cells.size()):
		for cell_index in range(cells.size()):
			if str((cells[cell_index] as Dictionary).get("crop", "")).is_empty():
				single_cell = cell_index
				break
	var target_cells: Array[int] = []
	var plot_id := str(plot.get("id", index))
	var queued_targets := _queued_plot_targets(jobs, plot_id, "plant")
	for cell_index in range(cells.size()):
		if not grouped and cell_index != single_cell:
			continue
		var target_id := "%s:%d" % [plot_id, cell_index]
		if str((cells[cell_index] as Dictionary).get("crop", "")).is_empty() and not queued_targets.has(target_id) and not queued_targets.has(plot_id + ":*"):
			target_cells.append(cell_index)
	if target_cells.is_empty():
		_close_modal()
		notify(TextDB.text("ui.59085ce031"))
		_selected_cell_index = -1
		return
	if int(jobs.call("get_available_command_slots")) <= 0:
		_close_modal()
		notify(TextDB.text("ui.1e399ca0d0"))
		_selected_cell_index = -1
		return
	var registry := get_node_or_null("/root/DataRegistry")
	var crop: Dictionary = registry.get_crop(crop_id) if registry != null else {}
	var total_cost := maxi(0, int(crop.get("plant_cost", 0))) * target_cells.size()
	if int(_state.coins) < total_cost:
		_close_modal()
		notify(TextDB.text("ui.6eed603650") % [target_cells.size(), total_cost, int(_state.coins)])
		_selected_cell_index = -1
		return
	var target_ids: Array[String] = []
	for cell_index in target_cells:
		target_ids.append("%s:%d" % [plot_id, cell_index])
	jobs.call("enqueue_task_batch", "plant_cell", target_ids, [crop_id, repeat_crop, grouped], TextDB.text("ui.9a44212b6a") % _display_id(crop_id), TextDB.text("ui.2f6af7f04b"))
	_close_modal()
	# notify("已安排依次播种 %d 个小格" % queued if queued > 0 else "播种指令未能加入队列")
	_selected_cell_index = -1


# 统一检查建筑操作能否入队；target_id 为地块索引，开垦复用系统中的等级、前置条件与同组去重规则。
func _can_queue_building_action(action: String, target_id: String = "") -> bool:
	if _state == null:
		return false
	var jobs: Node = _services.get("JobManager")
	if jobs == null or int(jobs.call("get_available_command_slots")) <= 0:
		return false
	var pending_commands: Array = jobs.call("get_pending_commands")
	var cost := -1
	if action == "unlock_plot":
		var farming: Node = _services.get("FarmingSystem")
		if farming == null or not bool(farming.call("can_unlock_plot", target_id)):
			return false
		var group_id := str(farming.call("get_plot_unlock_group_id", target_id))
		for pending in pending_commands:
			if pending is Dictionary and str(pending.get("action", "")) == action and str(farming.call("get_plot_unlock_group_id", str(pending.get("target_id", "")))) == group_id:
				return false
		cost = int(farming.call("get_plot_unlock_cost", target_id))
	elif action == "upgrade_cottage":
		if not (_state.call("get_cottage_construction") as Dictionary).is_empty():
			return false
		for pending in pending_commands:
			if pending is Dictionary and str(pending.get("action", "")) == action:
				return false
		cost = int(_state.call("get_next_cottage_upgrade_cost"))
	return cost >= 0 and int(_prop(_state, "coins", 0)) >= cost


# 资源或队列变化时刷新现有按钮和费用颜色，保留当前弹窗与信号，条件满足后可直接恢复操作。
func _refresh_building_action_buttons() -> void:
	if plant_window.visible:
		var locked_content := plant_window.get_node("PlotPopup/ContentSurface/PlotContent/LockedContent") as Control
		if locked_content.visible:
			var unlock := locked_content.get_node("Unlock") as Button
			unlock.disabled = not _can_queue_building_action("unlock_plot", str(unlock.get_meta("plot_index", -1)))
			_set_coin_requirement(locked_content.get_node("UnlockCostRow/Amount") as Label, _unlock_cost(int(unlock.get_meta("plot_index", -1))))
	if cottage_window.visible:
		var upgrade := cottage_window.get_node("CottagePopup/ContentSurface/Upgrade") as Button
		upgrade.disabled = not _can_queue_building_action("upgrade_cottage")
		_set_coin_requirement(cottage_window.get_node("CottagePopup/ContentSurface/UpgradeCostRow/Amount") as Label, int(_state.call("get_next_cottage_upgrade_cost")))


# 封装 unlock_plot 的处理，供相关流程复用。
func _unlock_plot(index: int) -> void:
	if not _can_unlock_plot_at_cottage_level(index):
		return
	var jobs: Node = _services.get("JobManager")
	if jobs != null:
		for pending in jobs.call("get_pending_commands"):
			if pending is Dictionary and str(pending.get("action", "")) == "unlock_plot" and str(pending.get("target_id", "")) == str(index):
				_close_modal()
				return
	var cost := _unlock_cost(index)
	var current_coins := int(_state.coins)
	if current_coins < cost:
		_close_modal()
		notify(TextDB.text("plot.unlock.insufficient_coins") % [_plot_display_number(index), cost, current_coins])
		return
	_queue_action("unlock_plot", str(index), [], TextDB.text("ui.b491b31b74") % _plot_display_number(index), TextDB.text("ui.0258dac50b"))


# 封装 plot_display_number 的处理，供相关流程复用。
func _plot_display_number(index: int) -> int:
	return PLOT_COUNT - index


# 检查是否允许 unlock_plot_at_cottage_level 对应的条件。
func _can_unlock_plot_at_cottage_level(index: int) -> bool:
	var farming: Node = _services.get("FarmingSystem")
	var required_level := int(farming.call("get_plot_required_cottage_level", str(index))) if farming != null else 1
	if int(_state.cottage_level) >= required_level:
		return true
	notify(TextDB.text("ui.4faaa0fa9f") % required_level)
	return false


# 封装 craft_bait 的处理，供相关流程复用。
func _craft_bait(bait_id: String, batches: int = 1) -> void:
	_queue_action("craft_bait", "", [bait_id, batches], TextDB.text("ui.c7b01b6bff") % [_display_id(bait_id), batches], TextDB.text("ui.3d67880fdf"))


# 选择 rod，供调用方继续处理。
func _select_rod(rod_id: String) -> void:
	_queue_action("select_rod", "", [rod_id], TextDB.text("ui.ee1088e725"), TextDB.text("ui.8e8200a596"))


# 出售 all_fish，供调用方继续处理。
func _sell_all_fish() -> void:
	_queue_action("sell_all", "", [], TextDB.text("ui.46a8394c9b"), TextDB.text("ui.6c95c1ab53"))


# 封装 upgrade_rod 的处理，供相关流程复用。
func _upgrade_rod() -> void:
	_queue_action("upgrade_rod", "", [], TextDB.text("ui.357d968e9f"), TextDB.text("ui.29e2bb4218"))


# 封装 upgrade_cottage 的处理，供相关流程复用。
func _upgrade_cottage() -> void:
	var next_cost := int(_state.call("get_next_cottage_upgrade_cost"))
	if next_cost < 0:
		_close_modal()
		notify(TextDB.text("ui.aa3e67bb64"))
		return
	var current_coins := int(_state.coins)
	if current_coins < next_cost:
		_close_modal()
		notify(TextDB.text("ui.a52df49692") % [next_cost, current_coins])
		return
	_queue_action("upgrade_cottage", "", [], TextDB.text("ui.08f07afeb3"), TextDB.text("ui.b207eef1bc") % next_cost)


# 小屋到期后提交验收任务，角色到达小屋后才完成升级。
func _finish_cottage_construction() -> void:
	if _state == null:
		return
	var construction: Dictionary = _state.call("get_cottage_construction")
	if construction.is_empty():
		return
	var remaining := maxi(0, int(construction.get("ready_at", 0)) - int(Time.get_unix_time_from_system()))
	if remaining > 0:
		notify(TextDB.text("ui.fb22d04ac0") % _format_duration(remaining))
		return
	_queue_action("complete_cottage", "", [], TextDB.text("ui.eed8bbe00b"), TextDB.text("ui.c001eb228c"))


# 启动 fishing，供调用方继续处理。
func _start_fishing() -> void:
	_queue_action("start_fishing", "", [], TextDB.text("ui.f69f19fafa"), TextDB.text("ui.6bc6443c0b"))


# 停止 fishing，供调用方继续处理。
func _stop_fishing() -> void:
	_queue_action("stop_fishing", "", [], TextDB.text("ui.5399ac7cfd"), TextDB.text("ui.99a5f184f4"))


# 封装 queue_action 的处理，供相关流程复用。
func _queue_action(action: String, target_id: String, args: Array, success_text: String, failure_text: String) -> void:
	var jobs: Node = _services.get("JobManager")
	var command_id := -1
	if jobs != null and jobs.has_method("enqueue_command"):
		command_id = int(jobs.call("enqueue_command", action, target_id, args, success_text, failure_text))
	_close_modal()
	if command_id < 0:
		if jobs != null and int(jobs.call("get_available_command_slots")) == 0:
			notify(TextDB.text("ui.65c44e737b"))
		else:
			notify(failure_text)
	# notify("指令已下达，角色正在前往" if command_id > 0 else "指令未能加入队列")


# 响应 command_finished 对应的事件或条件。
func _on_command_finished(command: Dictionary, success: bool) -> void:
	# 逐格播种和收获完成时不弹通知；失败和其他操作仍正常播报。
	if bool(command.get("repeat_plant_failed", false)) or not (success and str(command.get("action", "")) in ["plant", "plant_cell", "harvest", "harvest_cell"]):
		notify(str(command.get("success_text", TextDB.text("ui.66c6340147"))) if success else str(command.get("failure_text", TextDB.text("ui.09e424b5e8"))))
	_refresh()


# 封装 toggle_dock 的处理，供相关流程复用。
func _toggle_dock() -> void:
	_stick_to_bottom = not _stick_to_bottom
	if _stick_to_bottom:
		var screen := DisplayServer.window_get_current_screen()
		var usable := DisplayServer.screen_get_usable_rect(screen)
		var window_size := DisplayServer.window_get_size()
		var current := DisplayServer.window_get_position()
		var x := clampi(current.x, usable.position.x, usable.end.x - window_size.x)
		DisplayServer.window_set_position(Vector2i(x, clampi(usable.end.y - window_size.y - int(_state.settings.get("display_raise", 0)), usable.position.y, maxi(usable.position.y, usable.end.y - window_size.y))))
	notify(TextDB.text("ui.8418ee69de") % (TextDB.text("ui.256783b7d4") if _stick_to_bottom else TextDB.text("ui.6c14bd7f6f")))
	_open_settings()


# 封装 toggle_always_on_top 的处理，供相关流程复用。
func _toggle_always_on_top() -> void:
	_always_on_top = not _always_on_top
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, _always_on_top)
	if _state != null:
		_state.settings["always_on_top"] = _always_on_top
		_state.settings["always_on_top_user_set"] = true
		var saver := get_node_or_null("/root/SaveManager")
		if saver != null:
			saver.request_save()
	notify(TextDB.text("ui.1ea0e6e698") % (TextDB.text("ui.256783b7d4") if _always_on_top else TextDB.text("ui.6c14bd7f6f")))
	_open_settings()


# 封装 toggle_mute 的处理，供相关流程复用。
func _toggle_mute() -> void:
	var music := get_node("/root/MusicManager")
	music.set_enabled(not music.is_enabled())
	_open_settings()


# 封装 prop 的处理，供相关流程复用。
func _prop(object: Object, property: String, fallback):
	if not object or not _has_property(object, property):
		return fallback
	var value = object.get(property)
	return fallback if value == null else value


# 封装 dict_prop 的处理，供相关流程复用。
func _dict_prop(object: Object, property: String) -> Dictionary:
	var value = _prop(object, property, {})
	return value if value is Dictionary else {}


# 判断是否具有 property 对应的条件。
func _has_property(object: Object, property: String) -> bool:
	if not object:
		return false
	for item in object.get_property_list():
		if String(item.name) == property:
			return true
	return false


# 封装 sum_values 的处理，供相关流程复用。
func _sum_values(data: Dictionary) -> int:
	var total := 0
	for value in data.values():
		total += int(value)
	return total


# 封装 sum_dictionary 的处理，供相关流程复用。
func _sum_dictionary(data: Dictionary, keys: Array) -> int:
	var total := 0
	for key in keys:
		total += int(data.get(key, 0))
	return total


# 封装 catalog_crop_ids 的处理，供相关流程复用。
func _catalog_crop_ids() -> Array:
	var registry := get_node_or_null("/root/DataRegistry")
	if registry == null:
		return CROP_IDS
	var ids: Array = []
	for crop in registry.get_all("crops"):
		if crop is Dictionary:
			ids.append(str(crop.get("id", "")))
	return ids


# 封装 fish_icon_texture 的处理，供相关流程复用。
func _fish_icon_texture(fish: Dictionary) -> Texture2D:
	var path := str(fish.get("icon_resource", ""))
	var source: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else FISH_PLACEHOLDER_ICON
	var width := float(fish.get("icon_region_width", 0))
	var height := float(fish.get("icon_region_height", 0))
	if width <= 0.0 or height <= 0.0:
		return source
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	atlas.region = Rect2(float(fish.get("icon_region_x", 0)), float(fish.get("icon_region_y", 0)), width, height)
	return atlas


# 封装 unlock_cost 的处理，供相关流程复用。
func _unlock_cost(index: int) -> int:
	var farming: Node = _services.get("FarmingSystem")
	return int(farming.call("get_plot_unlock_cost", str(index))) if farming != null else 0


# 封装 display_id 的处理，供相关流程复用。
func _display_id(id: String) -> String:
	var registry := get_node_or_null("/root/DataRegistry")
	if registry and registry.has_method("get_entry"):
		for category in ["crops", "baits", "fish", "rods", "shop_items"]:
			var entry = registry.call("get_entry", category, id)
			if entry is Dictionary and not entry.is_empty():
				return String(entry.get("display_name", entry.get("name", id)))
	return id.replace("_", " ")


# 格式化 duration，供调用方继续处理。
func _format_duration(seconds: int) -> String:
	var capped := mini(seconds, GameConfig.get_int("time_save", "offline_cap_seconds"))
	return TextDB.text("ui.82dfeb88a2") % [floori(float(capped) / 3600.0), floori(float(capped % 3600) / 60.0)]


# 封装 button 的处理，供相关流程复用。
func _button(text: String, _tooltip: String, secondary: bool = false) -> Button:
	var button := (SECONDARY_BUTTON if secondary else PRIMARY_BUTTON).instantiate() as Button
	button.text = text
	return button


# 构建 theme，供调用方继续处理。
func _build_theme() -> Theme:
	var ui_theme := Theme.new()
	# 字体与默认字号由「项目设置 → GUI → 主题」统一提供。
	# 不在运行时指定字体，否则会覆盖编辑器中设置的全局 UI 字体。
	ui_theme.set_color("font_color", "Label", COLOR_INK)
	ui_theme.set_color("font_color", "Button", COLOR_INK)
	ui_theme.set_constant("separation", "HBoxContainer", 8)
	ui_theme.set_constant("separation", "VBoxContainer", 8)
	return ui_theme


# 封装 change_display 的处理，供相关流程复用。
func _change_display(screen: int, raise_pixels: int) -> void:
	_state.settings["display_screen"] = screen
	_state.settings["display_raise"] = raise_pixels
	var previous := get_window().position
	_apply_desktop_window()
	_update_display_offset_label()
	var delta := get_window().position - previous
	var usable := DisplayServer.screen_get_usable_rect(screen)
	for child in get_children():
		if child is Window:
			var popup := child as Window
			var desired := popup.position + delta
			popup.position = Vector2i(clampi(desired.x, usable.position.x, maxi(usable.position.x, usable.end.x - popup.size.x)), clampi(desired.y, usable.position.y, maxi(usable.position.y, usable.end.y - popup.size.y)))
	get_node("/root/SaveManager").call("save_game")


# 移动 display_vertical，供调用方继续处理。
func _move_display_vertical(step: int) -> void:
	var screen := DisplayServer.window_get_current_screen()
	var limit := maxi(0, DisplayServer.screen_get_usable_rect(screen).size.y - get_window().size.y)
	_change_display(screen, clampi(int(_state.settings.get("display_raise", 0)) + step, 0, limit))


# 封装 display_device_name 的处理，供相关流程复用。
func _display_device_name(index: int) -> String:
	if _display_names.is_empty() and OS.get_name() == "Windows":
		var output: Array = []
		var helper := ProjectSettings.globalize_path("res://tools/display_names.ps1")
		if OS.execute("powershell.exe", PackedStringArray(["-NoProfile", "-NonInteractive", "-Command", FileAccess.get_file_as_string(helper)]), output) == OK:
			var parsed: Variant = JSON.parse_string("".join(output))
			if parsed is Array:
				_display_names = parsed
	var fallback := TextDB.text("settings.screen_number") % (index + 1)
	var origin := DisplayServer.screen_get_position(index)
	for entry in _display_names:
		if entry is Dictionary and int(entry.get("x", 0)) == origin.x and int(entry.get("y", 0)) == origin.y:
			return "%s · %s" % [fallback, str(entry.get("name", ""))]
	return fallback


# 更新 display_offset_label，供调用方继续处理。
func _update_display_offset_label() -> void:
	var label := settings_window.get_node("SettingsPopup/ContentSurface/SettingsContent/OffsetPixels") as Label
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	label.text = "%d px" % maxi(0, usable.end.y - get_window().size.y - get_window().position.y)


# 封装 toggle_effects 的处理，供相关流程复用。
func _toggle_effects() -> void:
	_state.settings["sfx_enabled"] = not bool(_state.settings.get("sfx_enabled", true))
	get_node("/root/MusicManager").call("sync_effects")
	get_node("/root/SaveManager").request_save()
	var button := settings_window.get_node("SettingsPopup/ContentSurface/SettingsContent/EffectsToggle") as Button
	button.text = TextDB.text("ui.256783b7d4") if bool(_state.settings["sfx_enabled"]) else TextDB.text("ui.6c14bd7f6f")


# 封装 unlock_dot_entries 的处理，供相关流程复用。
func _unlock_dot_entries() -> Dictionary:
	var entries := {
		"crop": _state.discovered_crops.duplicate(),
		"bait": _state.crafted_baits.duplicate(),
		"achievement": [],
	}
	for tab in FISH_RARITY_TABS:
		entries["fish_" + str(tab.id)] = []
	for fish_id in _state.discovered_fish:
		var fish: Dictionary = DataRegistry.get_fish(str(fish_id))
		var group := "fish_" + str(fish.get("rarity", "common"))
		if entries.has(group):
			entries[group].append(fish_id)
	for achievement_id in _state.achievement_unlocks:
		var unlock: Dictionary = _state.achievement_unlocks[achievement_id]
		if not bool(unlock.get("migrated", false)):
			entries["achievement"].append(achievement_id)
	return entries


# 同步 unlock_dots，供调用方继续处理。
func _sync_unlock_dots() -> void:
	if _state == null:
		return
	var current := _unlock_dot_entries()
	var previous: Dictionary = _state.settings.get("unlock_dot_entries", {})
	var unread: Dictionary = _state.settings.get("unlock_dot_unread", {})
	var updated := {}
	for group in current:
		var pending: Array = unread.get(group, [])
		var old_entries: Array = previous.get(group, current[group])
		var new_pending: Array = []
		for id in current[group]:
			if pending.has(id) or not old_entries.has(id):
				new_pending.append(id)
		if not new_pending.is_empty():
			updated[group] = new_pending
	_state.settings["unlock_dot_entries"] = current
	_state.settings["unlock_dot_unread"] = updated
	(overlay.get_node("RightIcons/CodexIcon/NewUnlockDot") as Control).visible = not updated.is_empty()
	if updated != unread:
		SaveManager.request_save()
