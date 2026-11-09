extends SceneTree

## Read-only regression check for the shared nine-square cleared base and all eight crop IDs.
const CROPS := ["wheat", "corn", "carrot", "white_radish", "strawberry", "tomato", "cabbage", "lettuce"]
const MATURE_NODES := {
	"wheat": "MatureWheatCells", "carrot": "MatureCarrotCells",
	"white_radish": "MatureWhiteRadishCells", "cabbage": "MatureCabbageCells",
	"lettuce": "MatureLettuceCells", "tomato": "MatureTomatoCells",
	"corn": "MatureCornCells", "strawberry": "MatureStrawberryCells"
}
const PLANTED_NODES := [
	"SeedCells", "LeafCells", "MatureCarrotCells", "MatureWheatCells",
	"MatureCabbageCells", "MatureTomatoCells", "MatureCornCells", "MatureStrawberryCells",
	"MatureWhiteRadishCells", "MatureLettuceCells"
]


# 封装 initialize 的处理，供相关流程复用。
func _initialize() -> void:
	call_deferred("_run")


# 封装 run 的处理，供相关流程复用。
func _run() -> void:
	var scene := load("res://scenes/world/PlotTile.tscn") as PackedScene
	if scene == null:
		quit(1)
		return
	var failures := 0
	var now := int(Time.get_unix_time_from_system())
	var zone: Dictionary = Time.get_time_zone_from_system()
	if not zone.has("bias"):
		push_error("System time zone does not provide a bias for maturity-clock display")
		failures += 1
	for crop_id in CROPS:
		failures += _check(scene, crop_id, now, now + 100, "SeedCells")
		failures += _check(scene, crop_id, now - 60, now + 40, "LeafCells")
		failures += _check(scene, crop_id, now - 100, now - 1, str(MATURE_NODES[crop_id]))
	failures += _check_group_alignment(scene)
	failures += _check_stage_fit(scene)
	print("Crop visual checks: ", CROPS.size() * 3 + 3 - failures, " passed, ", failures, " failed")
	quit(1 if failures > 0 else 0)


# 封装 check 的处理，供相关流程复用。
func _check(scene: PackedScene, crop_id: String, planted_at: int, mature_at: int, expected: String) -> int:
	var plot := scene.instantiate() as PlotVisual
	root.add_child(plot)
	plot.set_plot_data({"unlocked": true, "crop": crop_id, "planted_at": planted_at, "mature_at": mature_at}, true)
	var visuals := plot.get_node("StateVisuals")
	var actual := ""
	var base_visible := false
	for child in visuals.get_children():
		if child is CanvasItem and child.visible:
			if child.name == "ClearedSprite":
				base_visible = true
			else:
				if child.name.ends_with("Cells"):
					actual = str(child.name)
	plot.free()
	if actual != expected or not base_visible:
		push_error("%s expected %s over ClearedSprite, got %s (base=%s)" % [crop_id, expected, actual, base_visible])
		return 1
	return 0


# 检查 stage_fit，供调用方继续处理。
func _check_stage_fit(scene: PackedScene) -> int:
	var plot := scene.instantiate() as PlotVisual
	root.add_child(plot)
	var visuals := plot.get_node("StateVisuals") as Node2D
	var cleared := visuals.get_node("ClearedSprite") as Sprite2D
	var locked := visuals.get_node("LockedSprite") as Sprite2D
	var base_size := cleared.texture.get_size() * cleared.scale
	var seed_origin := (visuals.get_node("SeedCells") as Node2D).position
	var failure := false
	if cleared.texture.get_size() != Vector2(1254, 1254) or base_size.x != base_size.y:
		push_error("Cleared 3×3 base no longer covers the plot: %s" % base_size)
		failure = true
	if locked.texture.get_size() != cleared.texture.get_size() or locked.scale != cleared.scale:
		push_error("Locked and cleared plot sprites no longer share one square footprint")
		failure = true
	for node_name in PLANTED_NODES:
		var cells := visuals.get_node(node_name) as Node2D
		if cells.get_child_count() != 9:
			push_error("%s must contain exactly nine static sprites" % node_name)
			failure = true
		# Mature crop groups have deliberate hand-adjusted visual offsets.
		if node_name in ["SeedCells", "LeafCells"] and cells.position != seed_origin:
			push_error("%s no longer shares the common seed origin" % node_name)
			failure = true
		for row in range(1, 4):
			for col in range(1, 4):
				var cell := cells.get_node_or_null("Cell_%d_%d" % [row, col]) as Sprite2D
				if cell == null or cell.texture == null:
					push_error("%s missing Cell_%d_%d" % [node_name, row, col])
					failure = true
	plot.free()
	return 1 if failure else 0


# 检查 group_alignment，供调用方继续处理。
func _check_group_alignment(scene: PackedScene) -> int:
	var plot := scene.instantiate() as PlotVisual
	root.add_child(plot)
	var visuals := plot.get_node("StateVisuals") as Node2D
	var before := plot.get_interaction_global_position()
	visuals.position += Vector2(13, 9)
	visuals.force_update_transform()
	(plot.get_node("StateVisuals/HitArea") as CanvasItem).force_update_transform()
	var movement := plot.get_interaction_global_position() - before
	plot.free()
	if movement != Vector2(13, 9):
		push_error("StateVisuals movement did not carry interaction point: " + str(movement))
		return 1
	return 0
