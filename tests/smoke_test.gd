extends SceneTree

var failures: Array[String] = []


# 封装 initialize 的处理，供相关流程复用。
func _initialize() -> void:
	call_deferred("_run")


# 封装 run 的处理，供相关流程复用。
func _run() -> void:
	await process_frame
	var packed: PackedScene = load("res://scenes/main/Main.tscn")
	_check(packed != null, "主场景可加载")
	if packed == null:
		_finish()
		return
	var main: Node = packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var state: Node = root.get_node("GameState")
	var registry: Node = root.get_node("DataRegistry")
	state.reset_to_defaults(false)
	_check(not bool(state.settings.get("always_on_top", true)), "开局默认关闭窗口置顶")
	var legacy_save: Dictionary = state.to_save_data()
	legacy_save["settings"] = {"idle_auto_fish": false, "always_on_top": true}
	state.load_save_data(legacy_save)
	_check(not bool(state.settings.get("always_on_top", true)), "旧存档未手动设置置顶时迁移为关闭")
	state.reset_to_defaults(false)
	_check(registry.get_all("crops").size() >= 8, "加载作物表（含原有8种）")
	_check(registry.get_all("baits").size() == 8, "加载8种具体鱼饵")
	_check(registry.get_all("fish").size() >= 30, "加载鱼表（含原有30种）")
	_check(int(state.coins) == 50, "开局金币为50")
	var unlocked_plots := 0
	for value in state.plots:
		if value is Dictionary and bool(value.get("unlocked", false)):
			unlocked_plots += 1
	_check(state.plots.size() == 7, "开局共有7块田")
	_check(unlocked_plots == 2, "开局仅解锁最右侧2块田")

	var farming: Node = main.get_node("Systems/FarmingSystem")
	var crafting: Node = main.get_node("Systems/CraftingSystem")
	var fishing: Node = main.get_node("Systems/FishingSystem")
	var shop: Node = main.get_node("Systems/ShopSystem")
	var now := int(Time.get_unix_time_from_system())
	var planted: bool = farming.plant("5", "wheat", now - 240)
	_check(planted, "可以播种小麦")
	var harvest_status: Dictionary = farming.refresh(now)
	_check(harvest_status.get("mature_plots", []).has("5"), "成熟作物保留在地里等待点击收获")
	_check(farming.harvest_plot("5", now), "玩家下达收获后作物入仓")
	_check(int(state.get_item_count("wheat")) == 2, "收获小麦数量正确")
	var craft_job: Dictionary = crafting.craft_bait("wheat_bait", 1, now - 20)
	_check(not craft_job.is_empty(), "可以用小麦制作谷物型鱼饵")
	crafting.settle_offline(20, now - 20, now)
	_check(state.get_item_count("wheat_bait") == 10, "一批鱼饵产出10次")
	_check(crafting.select_bait("wheat_bait"), "可以选择当前鱼饵")
	_check(fishing.can_fish(), "有已选鱼饵时允许钓鱼")
	var basic_pool: Array = fishing.build_fish_weights()
	_check(basic_pool.size() == _fish_count_at_or_below(registry, "common"), "普通鱼竿仅有普通鱼候选")
	var grain_weight := 0.0
	var root_weight := 0.0
	for entry in basic_pool:
		if str(entry.get("fish_id", "")) == "fish_001":
			grain_weight = float(entry.get("weight", 0.0))
		if str(entry.get("fish_id", "")) == "fish_002":
			root_weight = float(entry.get("weight", 0.0))
	_check(is_equal_approx(grain_weight, root_weight * 1.5), "匹配鱼饵只将偏好鱼权重乘1.5")
	state.add_coins(3000)
	_check(crafting.upgrade_rod(), "金币升级优秀鱼竿")
	_check(fishing.build_fish_weights().size() == _fish_count_at_or_below(registry, "good"), "优秀竿保留普通鱼并加入优秀鱼")
	_check(crafting.upgrade_rod(), "金币升级稀有鱼竿")
	_check(fishing.build_fish_weights().size() == _fish_count_at_or_below(registry, "rare"), "稀有竿保留旧品质鱼")
	_check(crafting.upgrade_rod(), "金币升级史诗鱼竿")
	_check(fishing.build_fish_weights().size() == registry.get_all("fish").size(), "史诗竿可钓表中全部鱼")
	fishing._catch_one("wheat_bait")
	_check(bool(state.shop_unlocked), "鱼铺开局可用")
	state.add_fish("fish_001", 2)
	var coins_before := int(state.coins)
	shop.refresh_offers_if_due()
	var expected_price := int(shop.get_unit_price("fish_001")) * 2
	_check(shop.sell_fish("fish_001", 2) == expected_price, "鱼铺按当前收购价卖鱼")
	_check(int(state.coins) == coins_before + expected_price, "卖鱼金币正确入账")
	crafting.select_bait("")
	_check(not fishing.can_fish(), "无当前鱼饵时绝不钓鱼")
	var world := main.get_node("StaticWorldStrip") as Node2D
	var workbench := world.get_node("ResourceNodes/Workbench") as Node2D
	var shop_building := world.get_node("ResourceNodes/ShopBuilding") as Node2D
	var pond := world.get_node("ResourceNodes/Pond") as Node2D
	_check(workbench.position.x < shop_building.position.x and shop_building.position.x < pond.position.x, "鱼铺位于工具台与鱼塘之间")
	var ui := main as Control
	var modals_inside := true
	var modal: Control
	for method in ["_open_plot", "_open_cottage", "_open_workbench", "_open_pond", "_open_shop", "_open_codex", "_open_settings"]:
		if method == "_open_plot":
			main.call(method, 5)
		else:
			main.call(method)
		await process_frame
		modal = main.get("_modal") as Control
		if method in ["_open_codex", "_open_shop", "_open_plot", "_open_settings", "_open_cottage", "_open_workbench"]:
			var window_name: String = str({"_open_codex": "CodexWindow", "_open_shop": "ShopWindow", "_open_plot": "PlantWindow", "_open_settings": "SettingsWindow", "_open_cottage": "CottageWindow", "_open_workbench": "WorkbenchWindow"}[method])
			var native_window := main.get_node(window_name) as Window
			modals_inside = modals_inside and modal.get_parent() == native_window and native_window.force_native
		else:
			modals_inside = modals_inside and modal.position.x >= 0.0 and modal.position.y >= 0.0 and modal.position.x + modal.size.x <= ui.size.x + 1.0 and modal.position.y + modal.size.y <= ui.size.y + 1.0
	_check(modals_inside, "窄条弹窗留在主画面；图鉴、鱼铺、种植和设置位于独立子窗口")
	_check(main.get_node_or_null("ShopWindow/ShopPopup") != null and main.get_node_or_null("CodexWindow/CodexPopup") != null, "每类弹窗都有可编辑的静态节点")
	main.call("_open_codex", "bait")
	var codex_layout := main.get_node("CodexWindow/CodexPopup/ContentSurface/CodexContent") as Control
	var primary_menu := codex_layout.get_node("PrimaryMenu") as Control
	var secondary_menu := codex_layout.get_node("SecondaryMenu") as Control
	var entries_viewport := codex_layout.get_node("EntriesViewport") as ScrollContainer
	_check(primary_menu.position.y + primary_menu.size.y <= secondary_menu.position.y and secondary_menu.position.y + secondary_menu.size.y <= entries_viewport.position.y, "顶部两级菜单不压住卡片内容区")
	_check(not secondary_menu.visible and main.get_node_or_null("CodexWindow/CodexPopup/ContentSurface/ContentScroll") == null, "植物和鱼饵页只滚动卡片，不保留无用外层滚动区")
	var bait_page := main.get_node("CodexWindow/CodexPopup/ContentSurface/CodexContent/EntriesViewport/Pages/BaitPage") as GridContainer
	_check(bait_page.get_child_count() == registry.get_all("baits").size() and bait_page.get_child(0).get_node_or_null("Content/BaitIcon") is TextureRect, "鱼饵图鉴按数据生成方形图标卡片")
	main.call("_open_codex", "crop")
	var crop_page := main.get_node("CodexWindow/CodexPopup/ContentSurface/CodexContent/EntriesViewport/Pages/CropPage") as GridContainer
	_check(crop_page.get_child_count() == registry.get_all("crops").size() and crop_page.get_child(0).get_node_or_null("Content/CropIcon") is TextureRect, "植物图鉴按数据生成方形图标卡片")
	main.call("_open_codex", "fish")
	var fish_page := main.get_node("CodexWindow/CodexPopup/ContentSurface/CodexContent/EntriesViewport/Pages/FishPage") as GridContainer
	var second_fish_card := fish_page.get_child(1) as PanelContainer
	(second_fish_card.get_node("ClickArea") as Button).pressed.emit()
	var preview_name := codex_layout.get_node("PreviewPanel/PreviewName") as Label
	var preview_info := codex_layout.get_node("PreviewPanel/PreviewInfo") as Label
	_check(preview_name.text == (second_fish_card.get_node("Content/FishName") as Label).text and preview_info.text.contains("喜爱鱼饵"), "点击鱼卡更新右侧名称和偏好鱼饵")
	_check((second_fish_card.get_node("SelectedFrame") as Panel).visible and main.get("_modal") == main.get_node("CodexWindow/CodexPopup"), "鱼卡选中留在图鉴窗口，不打开二级弹窗")
	main.call("_open_plot", 5)
	var selection_board := main.get_node("PlantWindow/PlotPopup/ContentSurface/PlotContent/SelectionBoard") as Control
	var crop_row := selection_board.get_node("CropContainer/CropViewport/CropRow") as HBoxContainer
	_check(crop_row.get_child_count() == registry.get_all("crops").size() and not (selection_board.get_node("ConfirmPlant") as Button).disabled, "种植横向卡片可选择并确认")
	main.call("_open_settings")
	var settings_content := main.get_node("SettingsWindow/SettingsPopup/ContentSurface/SettingsContent") as Control
	_check(settings_content.get_node_or_null("OptionsBoard") is TextureRect and settings_content.get_node_or_null("LanguageValue") is Button, "设置弹窗有浅色内板和三行设置")
	var popup_style := main.get_node("CodexWindow/CodexPopup").get_theme_stylebox("panel") as StyleBoxTexture
	_check(popup_style != null and popup_style.texture is AtlasTexture and (popup_style.texture as AtlasTexture).atlas == load("res://assets/hd/ui/popup_frame_light.png"), "参考弹窗使用浅木框图片资源")
	var sample_button := main.call("_button", "检查", "", false) as Button
	var button_style := sample_button.get_theme_stylebox("normal") as StyleBoxTexture
	_check(button_style != null, "弹窗按钮使用新版贴图而非程序绘制底板")
	sample_button.free()

	main.queue_free()
	_finish()


# 封装 fish_count_at_or_below 的处理，供相关流程复用。
func _fish_count_at_or_below(registry: Node, max_rarity: String) -> int:
	var rarity_order := ["common", "good", "rare", "epic"]
	var maximum := rarity_order.find(max_rarity)
	var count := 0
	for fish in registry.get_all("fish"):
		if fish is Dictionary and rarity_order.find(str(fish.get("rarity", ""))) <= maximum:
			count += 1
	return count


# 封装 check 的处理，供相关流程复用。
func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] ", description)
	else:
		failures.append(description)
		push_error("[FAIL] %s" % description)


# 封装 finish 的处理，供相关流程复用。
func _finish() -> void:
	if failures.is_empty():
		print("SMOKE_TEST_OK")
		quit(0)
	else:
		print("SMOKE_TEST_FAILED: ", failures)
		quit(1)
