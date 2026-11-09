# 定义 StaticWorldStrip 的状态和可用操作。
class_name StaticWorldStrip
extends Node2D

const PLOT_COUNT := 7
const BUILDING_HOVER_SPRITES := {
	"cottage": [
		"ResourceNodes/House/LevelVisuals/Level1", "ResourceNodes/House/LevelVisuals/Level2",
		"ResourceNodes/House/LevelVisuals/Level3", "ResourceNodes/House/LevelVisuals/Level4",
		"ResourceNodes/House/ConstructionVisual/Scaffold", "ResourceNodes/House/ConstructionVisual/SignGroup/Board",
	],
	"workbench": [
		"ResourceNodes/Workbench/Sprite", "ResourceNodes/Workbench/ConstructionVisual/Scaffold",
		"ResourceNodes/Workbench/ConstructionVisual/SignGroup/Board",
	],
	"shop": [
		"ResourceNodes/ShopBuilding/LevelVisuals/Level1", "ResourceNodes/ShopBuilding/LevelVisuals/Level2",
		"ResourceNodes/ShopBuilding/LevelVisuals/Level3", "ResourceNodes/ShopBuilding/ConstructionVisual/Scaffold",
		"ResourceNodes/ShopBuilding/ConstructionVisual/SignGroup/Board",
	],
	"pasture": ["PastureAreas/PastureBarn/BarnSprite", "PastureAreas/PastureBarn/ConstructionOverlay"],
}
const DEFAULT_UNLOCKED_START_INDEX := 5
const SPARKLE_BURST := preload("res://scenes/world/SparkleBurst.tscn")
const DISCOVERY_CELEBRATION := preload("res://scenes/world/NewDiscoveryCelebration.tscn")
const DROP_TOAST := preload("res://scenes/world/DropToast.tscn")
const CLICK_RIPPLE := preload("res://scenes/world/ClickRipple.tscn")
const COIN_ART := preload("res://assets/hd/ui/icon_coin_simple.png")
const BAIT_ART := preload("res://assets/hd/ui/icon_bait_simple.png")
const CROP_ART := preload("res://assets/hd/ui/icon_crop_simple.png")

@onready var plot_nodes: Node2D = $PlotLayer/PlotNodes
@onready var plot_path_segments: Node2D = $PathLayer/PlotSegments
@onready var house_level_visuals: Node2D = $ResourceNodes/House/LevelVisuals
@onready var shop_level_visuals: Node2D = $ResourceNodes/ShopBuilding/LevelVisuals
@onready var construction_visual: Node2D = $ResourceNodes/House/ConstructionVisual
@onready var workbench_smoke: AnimatedSprite2D = $ResourceNodes/Workbench/Sprite/ChimneySmoke
@onready var workbench_smoke_timer: Timer = $ResourceNodes/Workbench/Sprite/ChimneyIdleTimer
@onready var effect_layer: Node2D = $EffectLayer
@onready var cloud_fog: CloudFog = $CloudFog
var _hovered_building := ""
var _pending_fish_sizes: Dictionary = {}
var _harvest_motion_delay: Tween
var _workbench_crafting := false


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	workbench_smoke_timer.timeout.connect(_on_workbench_smoke_timeout)
	workbench_smoke.animation_looped.connect(_on_workbench_smoke_looped)
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.connect("tick", Callable(self, "_on_tick"))
		bus.connect("plot_unlocked", Callable(self, "_on_plot_unlocked"))
		bus.connect("fish_caught_live", Callable(self, "_on_fish_caught_live"))
		bus.connect("fish_size_caught", Callable(self, "_on_fish_size_caught"))
		bus.connect("job_completed", Callable(self, "_on_job_completed"))
		bus.connect("job_labor_started", Callable(self, "_on_harvest_labor_started"))
		bus.connect("job_queue_changed", Callable(self, "_refresh_plot_work_statuses"))
		bus.connect("cottage_construction_started", Callable(self, "_on_cottage_construction_started"))
		bus.connect("cottage_upgrade_completed", Callable(self, "_on_cottage_upgrade_completed"))
		bus.connect("workbench_unlocked", Callable(self, "_on_workbench_unlocked"))
		bus.connect("shop_unlocked", Callable(self, "_on_shop_unlocked"))
		bus.connect("game_loaded", Callable(self, "_on_game_loaded"))
		bus.connect("game_reset", Callable(self, "_on_game_reset"))
		bus.connect("codex_entry_unlocked", Callable(self, "_on_codex_entry_unlocked"))
		bus.connect("item_dropped", Callable(self, "_on_item_dropped"))
	for child in plot_nodes.get_children():
		var plot := child as PlotVisual
		if plot != null:
			plot.became_mature.connect(_on_plot_became_mature.bind(plot))
	var state = get_node_or_null("/root/GameState")
	if state != null:
		set_plot_states(state.plots)
		_refresh_plot_work_statuses()
		set_cottage_level(int(state.cottage_level), false)
		set_shop_level(int(state.shop_level))
		set_construction_state(state.get_cottage_construction())
		set_building_unlock_states()


# 响应 plot_unlocked 对应的事件或条件。
func _on_plot_unlocked(plot_id: String) -> void:
	var state = get_node_or_null("/root/GameState")
	if state == null:
		return
	for index in range(mini(state.plots.size(), plot_nodes.get_child_count())):
		var data: Dictionary = state.plots[index]
		if str(data.get("id", index)) == plot_id:
			var plot := plot_nodes.get_child(index) as PlotVisual
			if plot != null:
				_spawn_sparkles(plot.get_node_or_null("StateVisuals/SparkleAnchor"), 34.0, 11, Color("#ffe5a0"))
			return


# 响应 plot_became_mature 对应的事件或条件。
func _on_plot_became_mature(plot: PlotVisual) -> void:
	_spawn_sparkles(plot.get_node_or_null("StateVisuals/SparkleAnchor"), 30.0, 10, Color("#fff0a5"))


# 响应 fish_caught_live 对应的事件或条件。
func _on_fish_caught_live(_fish_id: String, _first_time: bool) -> void:
	_spawn_sparkles(get_node_or_null("DynamicAnchors/FishVisuals/FishSpawnPoint"), 37.0, 12, Color("#bff6ff"))


# 响应 fish_size_caught 对应的事件或条件。
func _on_fish_size_caught(fish_id: String, size_cm: int, _is_minimum: bool, is_maximum: bool) -> void:
	if not _pending_fish_sizes.has(fish_id):
		_pending_fish_sizes[fish_id] = []
	(_pending_fish_sizes[fish_id] as Array).append({"size_cm": size_cm, "is_maximum": is_maximum})


# 响应 item_dropped 对应的事件或条件。
func _on_item_dropped(item_type: String, item_id: String, amount: int, source_key: String) -> void:
	var shop_window := get_parent().get_node_or_null("ShopWindow") as Window
	if item_type == "coins" and source_key == "shop" and shop_window != null and shop_window.visible:
		return
	var anchor := _drop_anchor(source_key)
	if anchor == null:
		return
	var registry := get_node_or_null("/root/DataRegistry")
	var data: Dictionary = {}
	if registry != null:
		match item_type:
			"crop":
				data = registry.get_crop(item_id)
			"fish":
				data = registry.get_fish(item_id)
			"bait":
				data = registry.get_bait(item_id)
			"pasture_product":
				data = registry.get_entry("pasture_products", item_id)
			"item":
				for category in ["crops", "baits", "fish", "shop_items"]:
					data = registry.get_entry(category, item_id)
					if not data.is_empty():
						break
	var display_name := str(data.get("display_name", item_id))
	var icon: Texture2D
	if item_type == "coins":
		display_name = TextDB.text("ui.61f608b0d9")
		var coin_cutout := AtlasTexture.new()
		coin_cutout.atlas = COIN_ART
		coin_cutout.region = Rect2(700, 698, 1110, 1108)
		icon = coin_cutout
	elif item_type == "fertilizer":
		display_name = TextDB.text("ui.867cb2fd1f")
		icon = CROP_ART
	else:
		var icon_path := str(data.get("icon_resource", ""))
		if ResourceLoader.exists(icon_path):
			icon = load(icon_path) as Texture2D
		elif item_type == "bait":
			icon = BAIT_ART
		else:
			icon = CROP_ART
	var toast := DROP_TOAST.instantiate() as DropToast
	var size_cm := 0
	var is_maximum := false
	if item_type == "fish" and _pending_fish_sizes.has(item_id):
		var sizes: Array = _pending_fish_sizes[item_id]
		if not sizes.is_empty() and sizes[0] is Dictionary:
			var size_data: Dictionary = sizes.pop_front()
			size_cm = int(size_data.get("size_cm", 0))
			is_maximum = bool(size_data.get("is_maximum", false))
		if sizes.is_empty():
			_pending_fish_sizes.erase(item_id)
	toast.configure(icon, display_name, amount, size_cm, is_maximum)
	var canvas_position := anchor.get_global_transform_with_canvas().origin
	var viewport_height := get_viewport_rect().size.y
	canvas_position.y = clampf(canvas_position.y, 42.0, viewport_height - 7.0)
	toast.position = effect_layer.get_global_transform_with_canvas().affine_inverse() * canvas_position
	effect_layer.add_child(toast)


# 封装 drop_anchor 的处理，供相关流程复用。
func _drop_anchor(source_key: String) -> Node2D:
	if source_key.begins_with("pasture:"):
		var area_id := source_key.trim_prefix("pasture:")
		return get_node_or_null("PastureAreas/PastureArea%02d" % int(area_id)) as Node2D
	if source_key.begins_with("plot:"):
		var plot_id := source_key.trim_prefix("plot:")
		var state := get_node_or_null("/root/GameState")
		if state != null:
			for index in range(mini(state.plots.size(), plot_nodes.get_child_count())):
				var plot: Dictionary = state.plots[index]
				if str(plot.get("id", "")) == plot_id:
					return plot_nodes.get_child(index).get_node_or_null("StateVisuals/SparkleAnchor") as Node2D
	match source_key:
		"pond":
			return get_node_or_null("DynamicAnchors/FishVisuals/FishSpawnPoint") as Node2D
		"workbench":
			return get_node_or_null("ResourceNodes/Workbench") as Node2D
		"shop":
			return get_node_or_null("ResourceNodes/ShopBuilding") as Node2D
		"house":
			return get_node_or_null("ResourceNodes/House/SparkleAnchor") as Node2D
	return get_node_or_null("DynamicAnchors/Worker") as Node2D


# 响应 codex_entry_unlocked 对应的事件或条件。
func _on_codex_entry_unlocked(entry_type: String, entry_id: String) -> void:
	set_building_unlock_states()
	if entry_type != "fish" and entry_type != "crop":
		return
	var registry := get_node_or_null("/root/DataRegistry")
	if registry == null:
		return
	var data: Dictionary = registry.get_fish(entry_id) if entry_type == "fish" else registry.get_crop(entry_id)
	var icon_path := str(data.get("icon_resource", ""))
	if not ResourceLoader.exists(icon_path):
		return
	var anchor: Node2D = get_node_or_null("DynamicAnchors/FishVisuals/FishSpawnPoint") if entry_type == "fish" else _nearest_plot_to_worker()
	if anchor == null:
		return
	var effect := DISCOVERY_CELEBRATION.instantiate() as NewDiscoveryCelebration
	effect.configure(entry_type, load(icon_path) as Texture2D, anchor.global_position + Vector2(0, -24))
	effect_layer.add_child(effect)


# 封装 nearest_plot_to_worker 的处理，供相关流程复用。
func _nearest_plot_to_worker() -> Node2D:
	var worker := get_node_or_null("DynamicAnchors/Worker") as Node2D
	if worker == null:
		return null
	var nearest: Node2D
	var distance := INF
	for child in plot_nodes.get_children():
		var plot := child as Node2D
		if plot != null and plot.global_position.distance_to(worker.global_position) < distance:
			distance = plot.global_position.distance_to(worker.global_position)
			nearest = plot
	return nearest


# 响应 job_completed 对应的事件或条件。
func _on_job_completed(job: Dictionary) -> void:
	if not bool(job.get("success", false)):
		return
	match str(job.get("action", "")):
		"upgrade_pond":
			_spawn_sparkles(get_node_or_null("ResourceNodes/Pond/SparkleAnchor"), 57.0, 16, Color("#cff7ff"))


# 响应 cottage_construction_started 对应的事件或条件。
func _on_cottage_construction_started(_target_level: int, _ready_at: int) -> void:
	var state = get_node_or_null("/root/GameState")
	if state != null:
		set_construction_state(state.get_cottage_construction())


# 响应 cottage_upgrade_completed 对应的事件或条件。
func _on_cottage_upgrade_completed(level: int) -> void:
	set_cottage_level(level)
	set_construction_state({})
	_spawn_sparkles(get_node_or_null("ResourceNodes/House/SparkleAnchor"), 65.0, 18, Color("#ffe4a1"))


# 响应 workbench_unlocked 对应的事件或条件。
func _on_workbench_unlocked() -> void:
	set_building_unlock_states()
	_spawn_sparkles(get_node_or_null("ResourceNodes/Workbench/SparkleAnchor"), 42.0, 15, Color("#d7f4b3"))


# 响应 shop_unlocked 对应的事件或条件。
func _on_shop_unlocked() -> void:
	set_building_unlock_states()
	_spawn_sparkles(get_node_or_null("ResourceNodes/ShopBuilding/SparkleAnchor"), 50.0, 16, Color("#ffe4a1"))


# 响应 game_loaded 对应的事件或条件。
func _on_game_loaded() -> void:
	_reset_plot_motion()
	var state = get_node_or_null("/root/GameState")
	if state != null:
		set_cottage_level(int(state.cottage_level), false)
		set_shop_level(int(state.shop_level))
		set_construction_state(state.get_cottage_construction())
	set_building_unlock_states()
	call_deferred("_refresh_plot_work_statuses")


# 响应 game_reset 对应的事件或条件。
func _on_game_reset() -> void:
	_reset_plot_motion()
	_pending_fish_sizes.clear()
	set_cottage_level(1, false)
	set_construction_state({})
	set_shop_level(1)
	set_building_unlock_states()
	call_deferred("_refresh_plot_work_statuses")
	for child in effect_layer.get_children():
		child.queue_free()


# 生成 sparkles，供调用方继续处理。
func _spawn_sparkles(anchor: Node2D, spread: float, count: int, color: Color) -> void:
	if anchor == null:
		return
	var burst := SPARKLE_BURST.instantiate() as Node2D
	burst.call("configure", spread, count, color)
	effect_layer.add_child(burst)
	burst.global_position = anchor.global_position


# 响应 tick 对应的事件或条件。
func _on_tick(_now_unix: int, _delta_seconds: int) -> void:
	var state = get_node_or_null("/root/GameState")
	if state != null:
		set_plot_states(state.plots)
		set_cottage_level(int(state.cottage_level))
		set_shop_level(int(state.shop_level))
		set_construction_state(state.get_cottage_construction())
		set_building_unlock_states()


# 设置 cottage_level，供调用方继续处理。
func set_cottage_level(level: int, animate: bool = true) -> void:
	var active := clampi(level, 1, 4)
	for index in range(1, 5):
		var sprite := house_level_visuals.get_node_or_null("Level%d" % index) as Sprite2D
		if sprite != null:
			sprite.visible = index == active
	cloud_fog.set_cottage_level(active, animate)


# 判断是否满足 world_point_covered_by_cloud 对应的条件。
func is_world_point_covered_by_cloud(world_point: Vector2) -> bool:
	return cloud_fog.covers_world_point(world_point)


# 设置 shop_level，供调用方继续处理。
func set_shop_level(level: int) -> void:
	var active := clampi(level, 1, 3)
	for index in range(1, 4):
		var sprite := shop_level_visuals.get_node_or_null("Level%d" % index) as Sprite2D
		if sprite != null:
			sprite.visible = index == active


# 非空施工记录显示工地，ready_at 为 Unix 秒数；到期后保留工地直到玩家验收。
func set_construction_state(construction: Dictionary) -> void:
	construction_visual.visible = not construction.is_empty()
	house_level_visuals.visible = construction.is_empty()
	if construction_visual.visible:
		var ready := int(Time.get_unix_time_from_system()) >= int(construction.get("ready_at", 0))
		_set_construction_sign($ResourceNodes/House/ConstructionVisual/SignGroup, ready)


# 工作台和鱼铺满足解锁条件时更新木牌，玩家验收后用建筑替换工地。
func set_building_unlock_states() -> void:
	var state = get_node_or_null("/root/GameState")
	if state == null:
		return
	var workbench_ready := bool(state.workbench_unlocked)
	var shop_ready := bool(state.shop_unlocked)
	$ResourceNodes/Workbench/Sprite.visible = workbench_ready
	_sync_workbench_smoke(_workbench_crafting)
	$ResourceNodes/Workbench/ConstructionVisual.visible = not workbench_ready
	_set_construction_sign($ResourceNodes/Workbench/ConstructionVisual/SignGroup, state.is_workbench_construction_ready())
	shop_level_visuals.visible = shop_ready
	$ResourceNodes/ShopBuilding/ConstructionVisual.visible = not shop_ready
	_set_construction_sign($ResourceNodes/ShopBuilding/ConstructionVisual/SignGroup, state.is_shop_construction_ready())


# ready 表示已完工且等待验收，同步更新木牌文字与感叹号。
func _set_construction_sign(sign_group: Node2D, ready: bool) -> void:
	var label := sign_group.get_node("Text") as Label
	var badge := sign_group.get_node("CompletionBadge") as Sprite2D
	label.text = TextDB.text("ui.f08fd28247" if ready else "ui.310cd4240e")
	badge.visible = ready


# 封装 hit_test_building 的处理，供相关流程复用。
func hit_test_building(global_point: Vector2) -> String:
	# 按实际绘制层级从前往后判断，透明像素不触发交互。
	var pasture := get_node_or_null("PastureAreas") as PastureManager
	if pasture != null and pasture.hit_test_barn(global_point):
		return "pasture"
	if _sprite_hit($ResourceNodes/House/ConstructionVisual/SignGroup/Board, global_point) or _sprite_hit($ResourceNodes/House/ConstructionVisual/Scaffold, global_point):
		return "finish_cottage"
	if _sprite_hit($ResourceNodes/ShopBuilding/ConstructionVisual/SignGroup/Board, global_point) or _sprite_hit($ResourceNodes/ShopBuilding/ConstructionVisual/Scaffold, global_point):
		return "finish_shop"
	for level in ["Level3", "Level2", "Level1"]:
		if _sprite_hit(shop_level_visuals.get_node_or_null(level) as Sprite2D, global_point):
			return "shop"
	if _sprite_hit($ResourceNodes/Pond/Sprite, global_point):
		return "pond"
	if _sprite_hit($ResourceNodes/Workbench/ConstructionVisual/SignGroup/Board, global_point) or _sprite_hit($ResourceNodes/Workbench/ConstructionVisual/Scaffold, global_point):
		return "finish_workbench"
	if _sprite_hit($ResourceNodes/Workbench/Sprite, global_point):
		return "workbench"
	for level in ["Level4", "Level3", "Level2", "Level1"]:
		if _sprite_hit(house_level_visuals.get_node_or_null(level) as Sprite2D, global_point):
			return "cottage"
	return ""


# zone 来自建筑像素命中检测；施工入口与成品共用分组，所有等级同步切换，隐藏外观不会残留悬停状态。
func set_building_hover(zone: String) -> void:
	var target := zone.trim_prefix("finish_")
	if not BUILDING_HOVER_SPRITES.has(target):
		target = ""
	if target == _hovered_building:
		return
	_hovered_building = target
	for building_id in BUILDING_HOVER_SPRITES:
		for sprite_path in BUILDING_HOVER_SPRITES[building_id]:
			var sprite := get_node_or_null(NodePath(sprite_path)) as Sprite2D
			if sprite == null:
				continue
			var outline := sprite.material as ShaderMaterial
			if outline != null:
				outline.set_shader_parameter("hovered", 1.0 if building_id == target else 0.0)


# 封装 hit_test_plot 的处理，供相关流程复用。
func hit_test_plot(global_point: Vector2) -> int:
	for index in range(plot_nodes.get_child_count() - 1, -1, -1):
		var plot := plot_nodes.get_child(index) as PlotVisual
		if plot == null or not plot.is_visible_in_tree():
			continue
		var visuals := plot.get_node_or_null("StateVisuals") as Node2D
		if visuals == null:
			continue
		for group in visuals.get_children():
			var cell_group := group as Node2D
			if cell_group == null or not cell_group.visible or cell_group.name.ends_with("ShadowSprite"):
				continue
			if _sprite_hit(cell_group as Sprite2D, global_point):
				return index
			for cell in cell_group.get_children():
				if _sprite_hit(cell as Sprite2D, global_point):
					return index
	return -1


# 封装 hit_test_ground 的处理，供相关流程复用。
func hit_test_ground(global_point: Vector2) -> bool:
	if _sprite_hit($StaticBackground/Landscape, global_point):
		return true
	for layer_name in ["PlotSegments", "SharedSegments"]:
		var layer := get_node_or_null("PathLayer/" + layer_name)
		if layer == null:
			continue
		for child in layer.get_children():
			if _sprite_hit(child as Sprite2D, global_point):
				return true
	return false


# 显示 ground_click_ripple，供调用方继续处理。
func show_ground_click_ripple(global_point: Vector2) -> void:
	var ripple := CLICK_RIPPLE.instantiate() as Node2D
	effect_layer.add_child(ripple)
	ripple.global_position = global_point


# 封装 sprite_hit 的处理，供相关流程复用。
func _sprite_hit(sprite: Sprite2D, global_point: Vector2) -> bool:
	return sprite != null and sprite.texture != null and sprite.is_visible_in_tree() and sprite.is_pixel_opaque(sprite.to_local(global_point))


# 设置 plot_states，供调用方继续处理。
func set_plot_states(plots: Array) -> void:
	var nodes := plot_nodes.get_children()
	var paths := plot_path_segments.get_children()
	for index in range(nodes.size()):
		var plot := nodes[index] as PlotVisual
		if not plot:
			continue
		var data: Dictionary = plots[index] if index < plots.size() and plots[index] is Dictionary else {}
		var default_unlocked := index >= DEFAULT_UNLOCKED_START_INDEX and index < PLOT_COUNT
		plot.set_plot_data(data, default_unlocked)
		if index < paths.size():
			var path := paths[index] as Sprite2D
			if path != null:
				path.visible = bool(data.get("unlocked", default_unlocked)) and plot.visible


# 刷新 plot_work_statuses，供调用方继续处理。
func _refresh_plot_work_statuses() -> void:
	var jobs := get_node_or_null("../Systems/JobManager")
	if jobs == null or not jobs.has_method("get_plot_work_status"):
		return
	var state := get_node_or_null("/root/GameState")
	var nodes := plot_nodes.get_children()
	for index in range(nodes.size()):
		var plot := nodes[index] as PlotVisual
		if plot == null:
			continue
		var plot_id := str(index)
		if state != null and index < state.plots.size() and state.plots[index] is Dictionary:
			plot_id = str((state.plots[index] as Dictionary).get("id", index))
		plot.set_work_status(jobs.call("get_plot_work_status", plot_id))
	_refresh_facility_work_statuses(jobs)


# 刷新 facility_work_statuses，供调用方继续处理。
func _refresh_facility_work_statuses(jobs: Node) -> void:
	if not jobs.has_method("get_facility_work_status"):
		return
	var status: Dictionary = jobs.call("get_facility_work_status")
	var cottage: Dictionary = status.get("cottage", {}) if status.get("cottage", {}) is Dictionary else {}
	_set_facility_work_badge(
		get_node_or_null("ResourceNodes/House/WorkPendingBadge") as Control,
		cottage,
		"world.work.cottage_waiting",
		"world.work.cottage_waiting"
	)
	var craft: Dictionary = status.get("craft", {}) if status.get("craft", {}) is Dictionary else {}
	_sync_workbench_smoke(int(craft.get("running_count", 0)) > 0)
	_set_facility_work_badge(
		get_node_or_null("ResourceNodes/Workbench/WorkPendingBadge") as Control,
		craft,
		"world.work.craft_waiting",
		"world.work.craft_running"
	)
	var pasture_status: Dictionary = status.get("pasture", {}) if status.get("pasture", {}) is Dictionary else {}
	for area_id in [3, 4]:
		var entry: Dictionary = pasture_status.get(str(area_id), {}) if pasture_status.get(str(area_id), {}) is Dictionary else {}
		_set_facility_work_badge(
			get_node_or_null("PastureAreas/PastureArea%02d/FeedPendingBadge" % area_id) as Control,
			entry,
			"world.work.feed_waiting",
			"world.work.feed_running"
		)


# 制作优先于空闲冒烟。重复刷新保留现有帧进度和空闲倒计时。
func _sync_workbench_smoke(crafting: bool) -> void:
	var was_crafting := _workbench_crafting
	_workbench_crafting = crafting
	if not $ResourceNodes/Workbench/Sprite.is_visible_in_tree():
		workbench_smoke_timer.stop()
		workbench_smoke.stop()
		workbench_smoke.hide()
		return
	if crafting:
		workbench_smoke_timer.stop()
		if not workbench_smoke.is_playing():
			workbench_smoke.show()
			workbench_smoke.play()
		return
	if was_crafting:
		workbench_smoke.stop()
		workbench_smoke.hide()
	if not workbench_smoke.is_playing() and workbench_smoke_timer.is_stopped():
		workbench_smoke_timer.start(randf_range(2.0, 5.0))


# 随机等待结束后，播放一轮空闲灰烟。
func _on_workbench_smoke_timeout() -> void:
	if not _workbench_crafting and $ResourceNodes/Workbench/Sprite.is_visible_in_tree():
		workbench_smoke.show()
		workbench_smoke.play()


# 空闲播放满一轮后隐藏烟雾，再重新抽取等待时长。
func _on_workbench_smoke_looped() -> void:
	if not _workbench_crafting:
		workbench_smoke.stop()
		workbench_smoke.hide()
		_sync_workbench_smoke(false)


# 设置 facility_work_badge，供调用方继续处理。
func _set_facility_work_badge(badge: Control, entry: Dictionary, waiting_text_id: String, running_text_id: String) -> void:
	if badge == null:
		return
	badge.visible = int(entry.get("total_count", 0)) > 0
	var label := badge.get_node_or_null("Content/State") as Label
	if label != null:
		label.text = TextDB.text(running_text_id) if int(entry.get("running_count", 0)) > 0 else TextDB.text(waiting_text_id)


# 读取 plot_centers，供调用方继续处理。
func get_plot_centers() -> Array:
	var centers: Array = []
	for node in plot_nodes.get_children():
		var plot := node as PlotVisual
		if plot:
			centers.append(plot.get_interaction_global_position())
	return centers


# 读取 plot_cell_position，供调用方继续处理。
func get_plot_cell_position(plot_index: int, cell_index: int) -> Vector2:
	if plot_index < 0 or plot_index >= plot_nodes.get_child_count() or cell_index < 0 or cell_index >= 9:
		return Vector2.ZERO
	var plot := plot_nodes.get_child(plot_index) as PlotVisual
	var row := floori(float(cell_index) / 3.0) + 1
	var column := cell_index % 3 + 1
	var marker := plot.get_node_or_null("StateVisuals/SeedCells/Cell_%d_%d" % [row, column]) as Node2D
	return marker.global_position + Vector2(0, 12) if marker != null else plot.global_position


# 封装 hit_test_plot_cell 的处理，供相关流程复用。
func hit_test_plot_cell(plot_index: int, global_point: Vector2) -> int:
	var closest := -1
	var distance := 22.0
	for index in range(9):
		var cell_center := get_plot_cell_position(plot_index, index) - Vector2(0, 12)
		var current := cell_center.distance_to(global_point)
		if current < distance:
			closest = index
			distance = current
	return closest


## Read the visible, editor-positioned road sprites instead of assuming a fixed lane.
func get_visible_road_runs() -> Array[Dictionary]:
	var pieces: Array[Dictionary] = []
	for layer_name in ["PlotSegments", "SharedSegments", "PastureSegments"]:
		var layer := get_node_or_null("PathLayer/" + layer_name)
		if layer == null:
			continue
		for child in layer.get_children():
			var sprite := child as Sprite2D
			# Doorway stepping stones are visual connectors, not horizontal lanes.
			if sprite == null or sprite.texture == null or not sprite.is_visible_in_tree() or bool(sprite.get_meta("road_connector", false)):
				continue
			var half_width := float(sprite.texture.get_width()) * absf(sprite.global_scale.x) * 0.5
			pieces.append({"left": sprite.global_position.x - half_width, "right": sprite.global_position.x + half_width, "y": sprite.global_position.y})
	pieces.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["left"]) < float(b["left"]))
	var runs: Array[Dictionary] = []
	for piece in pieces:
		if not runs.is_empty():
			var last: Dictionary = runs[runs.size() - 1]
			if float(piece["left"]) <= float(last["right"]) + 2.0 and absf(float(piece["y"]) - float(last["y"])) <= 8.0:
				last["right"] = maxf(float(last["right"]), float(piece["right"]))
				runs[runs.size() - 1] = last
				continue
		runs.append(piece.duplicate())
	return runs


# 重置 plot_motion，供调用方继续处理。
func _reset_plot_motion() -> void:
	if _harvest_motion_delay != null:
		_harvest_motion_delay.kill()
	for child in plot_nodes.get_children():
		if child is PlotVisual:
			child.reset_crop_motion()


# 响应 harvest_labor_started 对应的事件或条件。
func _on_harvest_labor_started(job: Dictionary) -> void:
	var action := str(job.get("action", ""))
	if action not in ["harvest", "harvest_cell"]:
		return
	var parts := str(job.get("target_id", "")).split(":")
	if action == "harvest_cell" and (parts.size() != 2 or not parts[1].is_valid_int()):
		return
	var cell_index := int(parts[1]) if action == "harvest_cell" else -1
	if action == "harvest_cell" and (cell_index < 0 or cell_index >= 9):
		return
	var state := get_node_or_null("/root/GameState")
	var jobs := get_node_or_null("../Systems/JobManager")
	if state == null or jobs == null:
		return
	for index in range(state.plots.size()):
		if str(state.plots[index].get("id", index)) != parts[0]:
			continue
		var plot := plot_nodes.get_child(index) as PlotVisual
		if plot == null:
			return
		var labor_time := maxf(0.1, GameConfig.get_float("farming", "harvest_action_seconds"))
		var motion_time := minf(0.24, labor_time)
		var command_id := int(job.get("id", -1))
		_harvest_motion_delay = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		_harvest_motion_delay.tween_interval(labor_time - motion_time)
		_harvest_motion_delay.tween_callback(func():
			if is_instance_valid(plot) and is_instance_valid(jobs) and int(jobs.get_labor_command_id()) == command_id:
				plot.play_harvest_motion(cell_index, motion_time)
		)
		return
