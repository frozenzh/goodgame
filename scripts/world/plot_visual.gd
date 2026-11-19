# 定义 PlotVisual 的状态和可用操作。
@tool
class_name PlotVisual
extends Node2D

## All visual states live under one editable StateVisuals node.
signal became_mature

const MATURE_SPRITES := {
	"wheat": "MatureWheatCells",
	"carrot": "MatureCarrotCells",
	"white_radish": "MatureWhiteRadishCells",
	"cabbage": "MatureCabbageCells",
	"lettuce": "MatureLettuceCells",
	"tomato": "MatureTomatoCells",
	"corn": "MatureCornCells",
	"strawberry": "MatureStrawberryCells",
	"barley": "Mature_barley_Cells",
	"oat": "Mature_oat_Cells",
	"rice": "Mature_rice_Cells",
	"sorghum": "Mature_sorghum_Cells",
	"rye": "Mature_rye_Cells",
	"potato": "Mature_potato_Cells",
	"sweet_potato": "Mature_sweet_potato_Cells",
	"beet": "Mature_beet_Cells",
	"turnip": "Mature_turnip_Cells",
	"burdock": "Mature_burdock_Cells",
	"pumpkin": "Mature_pumpkin_Cells",
	"eggplant": "Mature_eggplant_Cells",
	"cucumber": "Mature_cucumber_Cells",
	"watermelon": "Mature_watermelon_Cells",
	"blueberry": "Mature_blueberry_Cells",
	"spinach": "Mature_spinach_Cells",
	"bok_choy": "Mature_bok_choy_Cells",
	"kale": "Mature_kale_Cells",
	"celery": "Mature_celery_Cells",
	"water_spinach": "Mature_water_spinach_Cells"
}

@export var interaction_offset_x := 0.0:
	set(value):
		interaction_offset_x = value
		_refresh_layout()
@export var unlocked := false:
	set(value):
		unlocked = value
		_refresh_visual()
@export_enum("none", "seed", "leaf", "mature") var preview_stage := "none":
	set(value):
		preview_stage = value
		_refresh_visual()
@export var preview_crop := "carrot":
	set(value):
		preview_crop = value
		_refresh_visual()
@export_group("变异预览")
@export var preview_mutation := false:
	set(value):
		preview_mutation = value
		_refresh_visual()
@export_range(0, 2) var preview_mutation_column := 1:
	set(value):
		preview_mutation_column = value
		_refresh_visual()
@export_range(0, 1) var preview_mutation_start_row := 0:
	set(value):
		preview_mutation_start_row = value
		_refresh_visual()
@export var preview_alignment_overlay := false:
	set(value):
		preview_alignment_overlay = value
		_refresh_visual()
@export var preview_watered := false:
	set(value):
		preview_watered = value
		_refresh_visual()

var _runtime_stage := "none"
var _runtime_crop := ""
var _planted_at := 0
var _mature_at := 0
var _runtime_mutation: Dictionary = {}
var _runtime_cells: Array = []
var _last_cell_refresh_second := -1
var _last_cell_growth: Dictionary = {}
var _maturity_tweens: Dictionary = {}
var _harvest_tweens: Dictionary = {}
var _mutation_hidden_cells: Dictionary = {}
var _work_status: Dictionary = {}


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	_refresh_layout()
	_refresh_visual()
	_refresh_work_badge()
	set_process(not Engine.is_editor_hint())


# 设置 work_status，供调用方继续处理。
func set_work_status(status: Dictionary) -> void:
	_work_status = status.duplicate(true)
	_refresh_work_badge()


# 同步静态队列标签；开垦标签只在等待或前往阶段显示，实际劳动开始后隐藏。
func _refresh_work_badge() -> void:
	if Engine.is_editor_hint():
		return
	var badge := get_node_or_null("PendingBadge") as Control
	if badge == null:
		return
	var plant: Dictionary = _work_status.get("plant", {}) if _work_status.get("plant", {}) is Dictionary else {}
	var harvest: Dictionary = _work_status.get("harvest", {}) if _work_status.get("harvest", {}) is Dictionary else {}
	var unlock_status: Dictionary = _work_status.get("unlock", {}) if _work_status.get("unlock", {}) is Dictionary else {}
	var plant_row := badge.get_node_or_null("Rows/PlantRow") as Control
	var harvest_row := badge.get_node_or_null("Rows/HarvestRow") as Control
	var unlock_row := badge.get_node_or_null("Rows/UnlockRow") as Control
	if unlock_row != null:
		unlock_row.visible = not unlocked and int(unlock_status.get("waiting_count", 0)) > 0
	if plant_row != null:
		plant_row.visible = int(plant.get("total_count", 0)) > 0
		var label := plant_row.get_node_or_null("State") as Label
		if label != null:
			label.text = TextDB.text("plot.work.plant_running") if int(plant.get("running_count", 0)) > 0 else TextDB.text("plot.work.plant_waiting")
	if harvest_row != null:
		harvest_row.visible = int(harvest.get("total_count", 0)) > 0
		var label := harvest_row.get_node_or_null("State") as Label
		if label != null:
			label.text = TextDB.text("plot.work.harvest_running") if int(harvest.get("running_count", 0)) > 0 else TextDB.text("plot.work.harvest_waiting")
	badge.visible = plant_row != null and plant_row.visible or harvest_row != null and harvest_row.visible or unlock_row != null and unlock_row.visible


# 随渲染帧更新状态，时间增量以秒计。
func _process(_delta: float) -> void:
	if not _runtime_cells.is_empty():
		var now := int(Time.get_unix_time_from_system())
		if now != _last_cell_refresh_second:
			_last_cell_refresh_second = now
			_refresh_visual()
			_sync_cell_maturity(now)
		return
	if unlocked and not _runtime_crop.is_empty():
		var next_stage := _growth_stage(int(Time.get_unix_time_from_system()))
		if next_stage != _runtime_stage:
			var was_growing := _runtime_stage == "seed" or _runtime_stage == "leaf"
			_runtime_stage = next_stage
			_refresh_visual()
			if was_growing and next_stage == "mature":
				became_mature.emit()


# 设置 plot_data，供调用方继续处理。
func set_plot_data(data: Dictionary, default_unlocked: bool) -> void:
	var previous_stage := _runtime_stage
	var previous_crop := _runtime_crop
	var crop := str(data.get("crop", ""))
	_runtime_crop = crop
	_planted_at = int(data.get("planted_at", 0))
	_mature_at = int(data.get("mature_at", 0))
	_runtime_mutation = data.get("mutation", {}) if data.get("mutation", {}) is Dictionary else {}
	_runtime_cells = data.get("cells", []) if data.get("cells", []) is Array else []
	var next_unlocked := bool(data.get("unlocked", default_unlocked))
	_runtime_stage = "none"
	if next_unlocked and not crop.is_empty():
		_runtime_stage = _growth_stage(int(Time.get_unix_time_from_system()))
	unlocked = next_unlocked
	_sync_cell_maturity(int(Time.get_unix_time_from_system()))
	if _runtime_cells.is_empty() and previous_crop == crop and not crop.is_empty() and previous_stage in ["seed", "leaf"] and _runtime_stage == "mature":
		became_mature.emit()


# 封装 growth_stage 的处理，供相关流程复用。
func _growth_stage(now_unix: int) -> String:
	if _runtime_crop.is_empty():
		return "none"
	if _mature_at > 0 and now_unix >= _mature_at:
		return "mature"
	if _mature_at > _planted_at and now_unix >= _planted_at + (_mature_at - _planted_at) / 2:
		return "leaf"
	return "seed"


# 编辑器预览与游戏共用场景里的作物精灵布局；游戏根据各格生长状态切换显示。
func _refresh_visual() -> void:
	var group := get_node_or_null("StateVisuals") as Node2D
	if group == null:
		return
	for cell_node in _mutation_hidden_cells:
		if is_instance_valid(cell_node):
			(cell_node as Sprite2D).visible = bool(_mutation_hidden_cells[cell_node])
	_mutation_hidden_cells.clear()
	var blocker := group.get_node_or_null("WalkBlocker") as StaticBody2D
	if blocker != null:
		blocker.collision_layer = 0 if unlocked else 2
	if not Engine.is_editor_hint() and _runtime_cells.size() == 9:
		_refresh_cell_visuals(group)
		return
	var water_preview := group.get_node_or_null("WaterOverlays") as Node2D
	if water_preview != null:
		water_preview.visible = Engine.is_editor_hint() and preview_watered and unlocked
	var stage: String = preview_stage if Engine.is_editor_hint() else _runtime_stage
	var crop_id: String = preview_crop if Engine.is_editor_hint() else _runtime_crop
	var shadows := group.get_node_or_null("ContactShadows") as Node2D
	if shadows != null:
		shadows.visible = unlocked and stage in ["seed", "leaf", "mature"]
	var visible_name := "LockedSprite"
	if unlocked:
		match stage:
			"seed": visible_name = "SeedCells"
			"leaf": visible_name = "LeafCells"
			"mature": visible_name = String(MATURE_SPRITES.get(crop_id, "MatureOtherCells"))
			_: visible_name = "ClearedSprite"
	if unlocked and stage in ["seed", "leaf", "mature"] and not (stage == "mature" and MATURE_SPRITES.has(crop_id)):
		_apply_crop_resource_to_group(group, visible_name, crop_id, stage)
	var align_preview := Engine.is_editor_hint() and preview_alignment_overlay and unlocked and visible_name != "ClearedSprite"
	var locked_decor := group.get_node_or_null("LockedDecor") as Node2D
	if locked_decor != null:
		locked_decor.visible = not unlocked
	for child in group.get_children():
		if not (child is Sprite2D or child.name.ends_with("Cells")):
			continue
		# 所有种植阶段共用一张已开垦 3×3 底图，内部格子尺寸固定。
		child.visible = child.name == visible_name or (unlocked and child.name == "ClearedSprite")
		child.modulate = Color(1.0, 1.0, 1.0, 0.5) if align_preview and child.visible else Color.WHITE
	_refresh_mutation_visual(group, visible_name, crop_id, stage)


# 刷新 cell_visuals，供调用方继续处理。
func _refresh_cell_visuals(group: Node2D) -> void:
	var locked := group.get_node_or_null("LockedSprite") as Sprite2D
	var cleared := group.get_node_or_null("ClearedSprite") as Sprite2D
	if locked != null:
		locked.visible = not unlocked
	if cleared != null:
		cleared.visible = unlocked
	var decor := group.get_node_or_null("LockedDecor") as Node2D
	if decor != null:
		decor.visible = not unlocked
	var now := int(Time.get_unix_time_from_system())
	var registry := get_node_or_null("/root/DataRegistry")
	var shadows := group.get_node_or_null("ContactShadows") as Node2D
	if shadows != null:
		shadows.visible = unlocked
		for index in range(9):
			var shadow := shadows.get_node_or_null("Shadow_%d" % index) as CanvasItem
			if shadow != null:
				shadow.visible = not str((_runtime_cells[index] as Dictionary).get("crop", "")).is_empty()
	for group_name in ["SeedCells", "LeafCells"] + MATURE_SPRITES.values() + ["MatureOtherCells"]:
		var sprites := group.get_node_or_null(group_name) as Node2D
		if sprites == null:
			continue
		sprites.visible = unlocked
		for index in range(9):
			var sprite := sprites.get_node_or_null("Cell_%d_%d" % [floori(float(index) / 3.0) + 1, index % 3 + 1]) as Sprite2D
			if sprite == null:
				continue
			var cell: Dictionary = _runtime_cells[index]
			var crop_id := str(cell.get("crop", ""))
			var stage := "empty"
			if not crop_id.is_empty():
				stage = "mature" if now >= int(cell.get("mature_at", 0)) else "leaf" if now >= int(cell.get("leaf_at", 0)) else "seed"
			var wanted := "SeedCells" if stage == "seed" else "LeafCells" if stage == "leaf" else str(MATURE_SPRITES.get(crop_id, "MatureOtherCells")) if stage == "mature" else ""
			sprite.visible = group_name == wanted
			if sprite.visible and registry != null and not (stage == "mature" and MATURE_SPRITES.has(crop_id)):
				var crop: Dictionary = registry.get_crop(crop_id)
				var path := str(crop.get(stage + "_resource", ""))
				if not path.is_empty() and ResourceLoader.exists(path):
					var texture := load(path) as Texture2D
					if texture != null:
						sprite.texture = texture
	var water_group := group.get_node_or_null("WaterOverlays") as Node2D
	if water_group != null:
		water_group.visible = unlocked
		for index in range(9):
			var cell: Dictionary = _runtime_cells[index]
			var overlay := water_group.get_node_or_null("Water_%d" % index) as Polygon2D
			if overlay == null:
				continue
			var stage := "empty"
			if not str(cell.get("crop", "")).is_empty():
				stage = "mature" if now >= int(cell.get("mature_at", 0)) else "leaf" if now >= int(cell.get("leaf_at", 0)) else "seed"
			overlay.visible = stage in ["seed", "leaf"] and bool(cell.get("watered_" + stage, false))
	var same_mature_crop := ""
	for value in _runtime_cells:
		var cell: Dictionary = value
		var crop_id := str(cell.get("crop", ""))
		if crop_id.is_empty() or now < int(cell.get("mature_at", 0)) or not same_mature_crop.is_empty() and crop_id != same_mature_crop:
			same_mature_crop = ""
			break
		same_mature_crop = crop_id
	_refresh_mutation_visual(group, str(MATURE_SPRITES.get(same_mature_crop, "MatureOtherCells")), same_mature_crop, "mature" if not same_mature_crop.is_empty() else "none")


# 共享作物节点仅换贴图；位置、缩放和偏移沿用场景设置。
func _apply_crop_resource_to_group(group: Node2D, group_name: String, crop_id: String, stage: String) -> void:
	if not is_inside_tree():
		return
	var registry := get_node_or_null("/root/DataRegistry")
	if registry == null:
		return
	var crop: Dictionary = registry.get_crop(crop_id)
	var resource_path := str(crop.get(stage + "_resource", ""))
	if resource_path.is_empty() or not ResourceLoader.exists(resource_path):
		return
	var texture := load(resource_path) as Texture2D
	var cells := group.get_node_or_null(group_name) as Node2D
	if texture == null or cells == null:
		return
	for cell in cells.get_children():
		if cell is Sprite2D:
			var sprite := cell as Sprite2D
			sprite.texture = texture


# 刷新 mutation_visual，供调用方继续处理。
func _refresh_mutation_visual(group: Node2D, visible_name: String, crop_id: String, stage: String) -> void:
	var mutation_visual := group.get_node_or_null("MutationVisual") as Node2D
	if mutation_visual == null:
		return
	var mutation: Dictionary = {"active": preview_mutation, "column": preview_mutation_column, "start_row": preview_mutation_start_row} if Engine.is_editor_hint() else _runtime_mutation
	mutation_visual.visible = unlocked and stage == "mature" and bool(mutation.get("active", false))
	if not mutation_visual.visible:
		return
	if not is_inside_tree():
		mutation_visual.visible = false
		return
	var crop_group := group.get_node_or_null(visible_name) as Node2D
	var registry := get_node_or_null("/root/DataRegistry")
	if crop_group == null or registry == null:
		mutation_visual.visible = false
		return
	var crop: Dictionary = registry.get_crop(crop_id)
	var resource_path := str(crop.get("mature_resource", ""))
	if not ResourceLoader.exists(resource_path):
		mutation_visual.visible = false
		return
	var column := clampi(int(mutation.get("column", 0)), 0, 2)
	var start_row := clampi(int(mutation.get("start_row", 0)), 0, 1)
	for row in range(start_row, start_row + 2):
		var cell := crop_group.get_node_or_null("Cell_%d_%d" % [row + 1, column + 1]) as Sprite2D
		if cell != null:
			_mutation_hidden_cells[cell] = cell.visible
			cell.visible = false
	var marker := mutation_visual.get_node_or_null("Pair_%d_%d" % [start_row + 1, column + 1]) as Marker2D
	var sprite := mutation_visual.get_node_or_null("Plant") as Sprite2D
	var texture := load(resource_path) as Texture2D
	if marker == null or sprite == null or texture == null:
		return
	var width := maxf(1.0, float(crop.get("mature_visual_width", 40.0)) * 1.55)
	var height := maxf(1.0, float(crop.get("mature_visual_height", 50.0)) * 1.8)
	sprite.texture = texture
	if not _maturity_tweens.has(sprite):
		sprite.scale = Vector2(width / maxf(texture.get_width(), 1.0), height / maxf(texture.get_height(), 1.0))
	sprite.position = marker.position + crop_group.position + Vector2(0.0, 18.0 - height * 0.5)


# 刷新 layout，供调用方继续处理。
func _refresh_layout() -> void:
	var hit_area := get_node_or_null("StateVisuals/HitArea") as Area2D
	var interaction_point := get_node_or_null("StateVisuals/InteractionPoint") as Marker2D
	if hit_area:
		hit_area.position.x = interaction_offset_x
	if interaction_point:
		interaction_point.position.x = interaction_offset_x


# 读取 interaction_global_position，供调用方继续处理。
func get_interaction_global_position() -> Vector2:
	var hit_area := get_node_or_null("StateVisuals/HitArea") as Area2D
	return hit_area.global_position if hit_area else global_position


# 重置 crop_motion，供调用方继续处理。
func reset_crop_motion() -> void:
	_last_cell_growth.clear()
	for sprite in _maturity_tweens:
		var motion: Array = _maturity_tweens[sprite]
		(motion[0] as Tween).kill()
		sprite.scale = motion[1]
	_maturity_tweens.clear()
	for sprite in _harvest_tweens:
		var motion: Array = _harvest_tweens[sprite]
		(motion[0] as Tween).kill()
		sprite.rotation = motion[1]
	_harvest_tweens.clear()


# 同步 cell_maturity，供调用方继续处理。
func _sync_cell_maturity(now: int) -> void:
	if Engine.is_editor_hint() or not unlocked or _runtime_cells.size() != 9:
		_last_cell_growth.clear()
		return
	for index in range(_runtime_cells.size()):
		var cell: Dictionary = _runtime_cells[index]
		var crop := str(cell.get("crop", ""))
		if crop.is_empty():
			_last_cell_growth.erase(index)
			continue
		var planted_at := int(cell.get("planted_at", 0))
		var mature := now >= int(cell.get("mature_at", 0))
		var previous: Array = _last_cell_growth.get(index, [])
		_last_cell_growth[index] = [crop, planted_at, mature]
		if not mature or previous.is_empty() or previous[0] != crop or previous[1] != planted_at or previous[2]:
			continue
		var sprite := _mature_cell_sprite(index, crop)
		if sprite != null and not _maturity_tweens.has(sprite):
			var base := sprite.scale
			var tween := create_tween()
			_maturity_tweens[sprite] = [tween, base]
			tween.tween_property(sprite, "scale", base * Vector2(1.08, 1.12), 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(sprite, "scale", base, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.finished.connect(func(): _maturity_tweens.erase(sprite))
		became_mature.emit()


# 封装 mature_cell_sprite 的处理，供相关流程复用。
func _mature_cell_sprite(index: int, crop: String) -> Sprite2D:
	var group := str(MATURE_SPRITES.get(crop, "MatureOtherCells"))
	var row := floori(float(index) / 3.0)
	var column := index % 3
	var sprite := get_node_or_null("StateVisuals/%s/Cell_%d_%d" % [group, row + 1, column + 1]) as Sprite2D
	if sprite != null and sprite.is_visible_in_tree():
		return sprite
	if _mutation_hidden_cells.has(sprite):
		var mutation := get_node_or_null("StateVisuals/MutationVisual/Plant") as Sprite2D
		if mutation != null and mutation.is_visible_in_tree():
			return mutation
	return null


# 返回实际可见植物上部的世界坐标，供蝴蝶停留；优先叶片/成熟植物，只有种子时才使用种子位置。
# 直接读取静态精灵变换，保留编辑器布置、每种植物尺寸以及变异大作物的位置。
func get_ambient_perch_points() -> Array[Vector2]:
	var plants: Array[Vector2] = []
	var seeds: Array[Vector2] = []
	var visuals := get_node_or_null("StateVisuals")
	if visuals == null or not unlocked:
		return plants
	var groups: Array = ["LeafCells"] + MATURE_SPRITES.values() + ["MatureOtherCells", "MutationVisual", "SeedCells"]
	for group_name in groups:
		var group := visuals.get_node_or_null(NodePath(str(group_name)))
		if group == null:
			continue
		for child in group.get_children():
			var plant := child as Sprite2D
			if plant == null or plant.texture == null or not plant.is_visible_in_tree():
				continue
			var point := _ambient_plant_perch(plant)
			if str(group_name) == "SeedCells":
				seeds.append(point)
			else:
				plants.append(point)
	return seeds if plants.is_empty() else plants


# 从植物上部向下找实际不透明像素，避免带透明留白的贴图让蝴蝶停在植物上方的空气中。
func _ambient_plant_perch(plant: Sprite2D) -> Vector2:
	var rect := plant.get_rect()
	for row in range(2, 15):
		for fraction in [0.5, 0.4, 0.6, 0.3, 0.7]:
			var point := rect.position + rect.size * Vector2(float(fraction), float(row) / 20.0)
			if plant.is_pixel_opaque(point):
				return plant.to_global(point)
	return plant.to_global(rect.get_center())


# 封装 play_harvest_motion 的处理，供相关流程复用。
func play_harvest_motion(cell_index: int, duration: float) -> void:
	if not unlocked or _runtime_cells.size() != 9:
		return
	var now := int(Time.get_unix_time_from_system())
	for index in range(_runtime_cells.size()):
		if cell_index >= 0 and cell_index != index:
			continue
		var cell: Dictionary = _runtime_cells[index]
		var crop := str(cell.get("crop", ""))
		if crop.is_empty() or now < int(cell.get("mature_at", 0)):
			continue
		var sprite := _mature_cell_sprite(index, crop)
		if sprite == null or _harvest_tweens.has(sprite):
			continue
		var base := sprite.rotation
		var tween := create_tween().set_trans(Tween.TRANS_SINE)
		_harvest_tweens[sprite] = [tween, base]
		tween.tween_property(sprite, "rotation", base + deg_to_rad(5.0), duration * 0.3)
		tween.tween_property(sprite, "rotation", base - deg_to_rad(4.0), duration * 0.4)
		tween.tween_property(sprite, "rotation", base, duration * 0.3)
		tween.finished.connect(func(): _harvest_tweens.erase(sprite))
