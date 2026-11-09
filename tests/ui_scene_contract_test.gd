extends SceneTree

var failures := 0


# 封装 initialize 的处理，供相关流程复用。
func _initialize() -> void:
	call_deferred("_run")


# 封装 run 的处理，供相关流程复用。
func _run() -> void:
	var scene := load("res://scenes/main/Main.tscn") as PackedScene
	_check(scene != null, "主场景可加载")
	if scene == null:
		quit(1)
		return
	var main := scene.instantiate() as Control
	var popup_bodies := {
		"PlantWindow/PlotPopup": "PlotContent",
		"CottageWindow/CottagePopup": "InfoActionsContent",
		"WorkbenchWindow/WorkbenchPopup": "WorkbenchContent",
		"PondPopup": "InfoActionsContent",
		"ShopWindow/ShopPopup": "ShopContent",
		"CodexWindow/CodexPopup": "",
		"SettingsWindow/SettingsPopup": "SettingsContent",
		"ResetPopup": "InfoActionsContent",
		"OfflinePopup": "InfoActionsContent",
	}
	for popup_name in popup_bodies:
		var popup := main.get_node_or_null(popup_name) as PanelContainer
		_check(popup != null, "%s 为静态弹窗" % popup_name)
		if popup == null:
			continue
		var body := popup.get_node_or_null("ContentSurface/ContentScroll/Content/Body")
		if popup_name == "CodexWindow/CodexPopup":
			_check(popup.get_node_or_null("ContentSurface/CodexContent") != null, "%s 有独立静态内容" % popup_name)
		elif popup_name == "PlantWindow/PlotPopup" or popup_name == "SettingsWindow/SettingsPopup" or popup_name == "WorkbenchWindow/WorkbenchPopup":
			_check(popup.get_node_or_null("ContentSurface/%s" % popup_bodies[popup_name]) != null, "%s 有独立静态内容" % popup_name)
			_check(popup.get_node_or_null("ContentSurface/ContentScroll") == null, "%s 已删除无用外层滚动区" % popup_name)
		else:
			_check(body != null and body.get_node_or_null(popup_bodies[popup_name]) != null, "%s 有静态内容" % popup_name)
		if popup_name.contains("Window/"):
			var native_window := main.get_node(popup_name.get_slice("/", 0)) as Window
			_check(popup.anchor_right == 1.0 and popup.anchor_bottom == 1.0 and native_window.force_native, "%s 填满独立原生子窗口" % popup_name)
		else:
			_check(popup.offset_left >= 0.0 and popup.offset_top >= 62.0 and popup.offset_right <= 1280.0 and popup.offset_bottom <= 230.0, "%s 在裁切后的可见画布内" % popup_name)
	_check(main.get_node_or_null("Overlay/RightIcons/SettingsIcon/SettingsHitArea") is Button, "设置图标保留独立点击区")
	_check(main.get_node_or_null("Overlay/ResetHitArea") == null, "不再有覆盖设置图标的透明 GM 按钮")
	var progress_panel := main.get_node("PlotProgressAnchor/Panel") as PanelContainer
	_check(progress_panel.offset_left > 0.0 and progress_panel.offset_top > -62.0, "地块进度和收获面板静态偏移位于触发地块右侧")
	var crop_container := main.get_node_or_null("PlantWindow/PlotPopup/ContentSurface/PlotContent/SelectionBoard/CropContainer") as Control
	_check(crop_container != null and crop_container.get_node_or_null("CropViewport/CropRow") is HBoxContainer, "种植列表有可单独调整位置和尺寸的静态容器")
	var crop_row := crop_container.get_node("CropViewport/CropRow") as HBoxContainer
	_check(crop_row.get_child_count() == 8 and crop_row.get_node_or_null("CropSlot01/MatureCropIcon") is TextureRect, "种植窗口预置八张可编辑作物卡")
	_check((crop_row.get_node("CropSlot01/CropName") as Label).text == "小麦" and (crop_row.get_node("CropSlot08/CropName") as Label).text == "生菜", "静态作物槽在编辑器中显示真实预览内容")
	var first_crop_slot := crop_row.get_child(0)
	var crop_slots: Array = main.call("_data_slots", crop_row, load("res://scenes/ui/CropChoiceCard.tscn"), 8)
	_check(crop_slots.size() == 8 and crop_slots[0] == first_crop_slot, "运行时复用静态作物卡而非清空重建")
	var expanded_slots: Array = main.call("_data_slots", crop_row, load("res://scenes/ui/CropChoiceCard.tscn"), 9)
	_check(expanded_slots.size() == 9 and bool((expanded_slots[8] as Node).get_meta("runtime_extra", false)), "新增配置条目才补充卡片实例")
	var shop_window := main.get_node("ShopWindow") as Window
	var codex_window := main.get_node("CodexWindow") as Window
	for window_name in ["CottageWindow", "WorkbenchWindow"]:
		var building_window := main.get_node(window_name) as Window
		_check(building_window.force_native and building_window.transparent and building_window.transparent_bg and building_window.borderless, "%s 为透明原生子窗口" % window_name)
	var bench_content := main.get_node("WorkbenchWindow/WorkbenchPopup/ContentSurface/WorkbenchContent") as Control
	var bench_grid := bench_content.get_node("ItemsViewport/ItemGrid") as GridContainer
	_check(bench_grid.columns == 4 and bench_grid.get_child_count() == 8, "工作台有四列、八张静态可调鱼饵卡")
	_check(bench_content.get_node("DetailPanel/MaterialRow").get_child_count() == 3, "工作台有三个静态材料槽")
	_check(shop_window.transparent and shop_window.transparent_bg and shop_window.borderless and shop_window.unresizable and shop_window.transient, "鱼铺窗口与图鉴使用同类透明无边框属性")
	_check(shop_window.size.y == codex_window.size.y and bool(shop_window.get("follow_shop")), "鱼铺窗口与图鉴等高且默认跟随建筑")
	var shop_content := main.get_node_or_null("ShopWindow/ShopPopup/ContentSurface/ContentScroll/Content/Body/ShopContent")
	_check(shop_content != null and shop_content.get_node_or_null("HighPriceSection/Content/OffersScroll/OffersRow") != null, "高价收购有独立静态底板和卡片区")
	_check(shop_content.get_node("OwnedSection/Content/OwnedScroll/OwnedGrid").get_child_count() == 8 and shop_content.get_node("HighPriceSection/Content/OffersScroll/OffersRow").get_child_count() == 3, "鱼铺背包和高价收购卡可在场景中预览")
	_check(shop_content.get_node_or_null("OwnedSection/Content/OwnedScroll/OwnedGrid") != null and shop_content.get_node_or_null("HighPriceSection/Content/ActionRow/SellAll") != null, "鱼铺背包和出售按钮为静态可调节点")
	var shop_popup := main.get_node("ShopWindow/ShopPopup") as PanelContainer
	var shop_panel_art := shop_popup.get_theme_stylebox("panel") as StyleBoxTexture
	_check(shop_panel_art != null and shop_panel_art.texture.resource_path.ends_with("shop_panel_blank.png"), "鱼铺整张木框使用图片而非代码画底色")
	var shop_panel_image := shop_panel_art.texture.get_image() if shop_panel_art != null else null
	_check(shop_panel_image != null and shop_panel_image.get_pixel(0, 0).a == 0.0, "鱼铺木框外角真实透明")
	_check(not bool(ProjectSettings.get_setting("display/window/size/always_on_top", true)), "游戏窗口默认不置顶")
	var offer_scene := load("res://scenes/ui/ShopOfferCard.tscn") as PackedScene
	var offer_card := offer_scene.instantiate() as PanelContainer
	_check(offer_card.get_node_or_null("Content/MultiplierBoard/Multiplier") != null, "高倍鱼卡片有独立绿色倍率牌")
	_check(offer_card.get_theme_stylebox("panel") is StyleBoxTexture, "高倍鱼卡片使用独立图片资源")
	offer_card.free()
	var owned_scene := load("res://scenes/ui/ShopOwnedCard.tscn") as PackedScene
	var owned_card := owned_scene.instantiate() as PanelContainer
	_check(owned_card.get_theme_stylebox("panel") is StyleBoxTexture, "背包鱼卡片使用独立图片资源")
	owned_card.free()
	var fish_card_scene := load("res://scenes/ui/FishCodexCard.tscn") as PackedScene
	var fish_card := fish_card_scene.instantiate() as PanelContainer
	var fish_card_content := fish_card.get_node_or_null("Content") as VBoxContainer
	_check(fish_card_content != null and fish_card_content.get_child(0).name == "FishIcon" and fish_card_content.get_child(1).name == "FishName", "鱼图鉴卡片为上图标、下鱼名")
	_check(absf(fish_card.custom_minimum_size.x - fish_card.custom_minimum_size.y) <= 1.0, "鱼图鉴卡片接近正方形")
	_check(fish_card.get_node_or_null("SelectedFrame") is Panel, "鱼图鉴卡片有静态选中边框")
	fish_card.free()
	var codex_popup := main.get_node("CodexWindow/CodexPopup") as PanelContainer
	_check(codex_popup.get_node_or_null("ContentSurface/ContentScroll") == null, "图鉴已删除包含菜单的外层滚动区")
	var codex_content := codex_popup.get_node("ContentSurface/CodexContent") as Control
	_check(codex_content.get_node("EntriesViewport/Pages/FishPage").get_child_count() == 12 and codex_content.get_node("EntriesViewport/Pages/CropPage").get_child_count() == 8 and codex_content.get_node("EntriesViewport/Pages/BaitPage").get_child_count() == 8, "图鉴三类卡片有静态可调槽位")
	var primary_menu := codex_content.get_node("PrimaryMenu") as HBoxContainer
	var secondary_menu := codex_content.get_node("SecondaryMenu") as HBoxContainer
	var entries_scroll := codex_content.get_node("EntriesViewport") as ScrollContainer
	_check(primary_menu.get_parent() == codex_content and secondary_menu.get_parent() == codex_content and entries_scroll.get_parent() == codex_content, "一级菜单、二级菜单和内容滚动区为三个平级组件")
	_check(primary_menu.get_child_count() == 4 and primary_menu.get_node_or_null("AchievementTab") is Button and (primary_menu.get_node("FishTab") as Button).custom_minimum_size.x >= 80.0 and (primary_menu.get_node("FishTab") as Button).custom_minimum_size.y >= 40.0, "四个一级菜单为顶部独立页签")
	_check((secondary_menu.get_node("CommonTab") as Button).custom_minimum_size.x >= 83.0 and (secondary_menu.get_node("CommonTab") as Button).custom_minimum_size.y >= 36.0, "二级菜单为独立筛选组件")
	_check(entries_scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED and entries_scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "只有内容区允许纵向滚动")
	var achievement_page := codex_content.get_node_or_null("AchievementPage") as ScrollContainer
	_check(achievement_page != null and achievement_page.get_node_or_null("List/Slot01/Content/Icon") is TextureRect and achievement_page.get_node_or_null("List/Slot12/Content/Details/ProgressRow/Progress") is ProgressBar, "成就页预置十二张含图标和进度的静态卡")
	var fish_grid := codex_content.get_node_or_null("EntriesViewport/Pages/FishPage") as GridContainer
	_check(fish_grid != null and fish_grid.columns == 4, "鱼图鉴以四列方形卡片排列")
	var codex_pages := codex_content.get_node("EntriesViewport/Pages") as Control
	_check(codex_pages.custom_minimum_size.y >= 356.0, "鱼图鉴三行卡片不会被 170 高度压到框外")
	_check(primary_menu.position.y + primary_menu.size.y <= secondary_menu.position.y and codex_content.get_node_or_null("PreviewPanel/PreviewIcon") != null, "顶部筛选与右侧资料区互不重叠")
	for kind in ["Crop", "Bait"]:
		var card_scene := load("res://scenes/ui/%sCodexCard.tscn" % kind) as PackedScene
		var card := card_scene.instantiate() as PanelContainer
		var card_content := card.get_node_or_null("Content") as VBoxContainer
		_check(card_content != null and card_content.get_child(0).name == "%sIcon" % kind and card_content.get_child(1).name == "%sName" % kind, "%s 图鉴为上图标、下名称" % kind)
		_check(absf(card.custom_minimum_size.x - card.custom_minimum_size.y) <= 1.0, "%s 图鉴卡片接近正方形" % kind)
		card.free()
		var page := codex_content.get_node_or_null("EntriesViewport/Pages/%sPage" % kind) as GridContainer
		_check(page != null and page.columns == 4, "%s 图鉴为四列" % kind)
	var panel_texture := load("res://assets/hd/ui/shop_v04/panel_transparent.png") as Texture2D
	var panel_image := panel_texture.get_image() if panel_texture != null else null
	_check(panel_image != null and panel_image.get_pixel(0, 0).a == 0.0 and panel_image.get_pixel(panel_image.get_width() / 2, panel_image.get_height() / 2).a > 0.9, "木框外角真正透明，中心保持可见")
	var reference_style := codex_popup.get_theme_stylebox("panel") as StyleBoxTexture
	_check(reference_style != null and reference_style.texture is AtlasTexture and (reference_style.texture as AtlasTexture).atlas.resource_path.ends_with("popup_frame_light.png"), "图鉴、设置和种植使用参考图浅木框资源")
	_check(main.get_node_or_null("CodexWindow/FishDetailPopup") == null and codex_content.get_node_or_null("PreviewPanel/PreviewInfo") is Label, "鱼详情直接显示在图鉴右侧，无二级弹窗")
	_check(main.get_node_or_null("FarmStrip") == null, "已移除与图片脱离的点击层")
	var world_hit := main.get_node_or_null("StaticWorldStrip") as StaticWorldStrip
	_check(world_hit != null and world_hit.has_method("hit_test_building") and world_hit.has_method("hit_test_plot"), "建筑和地块按可见贴图像素判定点击")
	_check(main.get_node_or_null("StaticWorldStrip/ResourceNodes/ShopBuilding/Sprite") is Sprite2D, "鱼铺建筑为静态资源节点")
	var shop_shadow := main.get_node_or_null("StaticWorldStrip/ResourceNodes/ShopBuilding/GroundShadow") as Node2D
	_check(shop_shadow != null and shop_shadow.get_node_or_null("SoftShadow") is Polygon2D and shop_shadow.get_node_or_null("ContactShadow") is Polygon2D, "鱼铺阴影从世界源场景加载为独立静态节点")
	var world_source := load("res://scenes/world/StaticWorldStrip.tscn") as PackedScene
	var world_instance := world_source.instantiate() as Node2D
	_check(world_instance.get_node_or_null("ResourceNodes/ShopBuilding/GroundShadow") is Node2D, "单独打开世界场景时也能编辑和预览鱼铺阴影")
	_check(world_instance.get_node_or_null("FunctionalZones") == null, "未被逻辑读取的旧功能区节点已清理")
	world_instance.free()
	main.free()
	print("UI_SCENE_CONTRACT_OK" if failures == 0 else "UI_SCENE_CONTRACT_FAILED: %d" % failures)
	quit(0 if failures == 0 else 1)


# 封装 check 的处理，供相关流程复用。
func _check(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] ", message)
	else:
		failures += 1
		push_error("[FAIL] %s" % message)
