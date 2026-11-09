extends SceneTree

## Read-only scene/load check; does not start gameplay or touch save data.
const SCENES := [
	"res://scenes/main/Main.tscn",
	"res://scenes/world/StaticWorldStrip.tscn",
	"res://scenes/world/PlotTile.tscn",
	"res://scenes/world/Worker.tscn",
	"res://scenes/ui/ResourceBar.tscn",
	"res://scenes/ui/UtilityButtons.tscn",
	"res://scenes/ui/CropChoiceCard.tscn",
	"res://scenes/ui/FishCodexCard.tscn"
]


# 封装 initialize 的处理，供相关流程复用。
func _initialize() -> void:
	var failures := 0
	for scene_path in SCENES:
		var scene := load(scene_path) as PackedScene
		if scene == null:
			push_error("Scene failed: " + scene_path)
			failures += 1
		else:
			print("Scene loaded: " + scene_path)
	quit(1 if failures > 0 else 0)
