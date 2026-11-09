extends SceneTree

## Rebuild the two generated cottage variants on the level-2 sprite's 2K canvas.
const TARGET_SIZE := Vector2i(2048, 1318)
const VARIANTS := [
	{"source": "res://assets/source/house_level_1_generated.png", "target": "res://assets/hd/world/house_level_1.png"},
	{"source": "res://assets/source/house_level_3_generated.png", "target": "res://assets/hd/world/house_level_3.png"}
]


# 封装 initialize 的处理，供相关流程复用。
func _initialize() -> void:
	var failed := false
	for variant in VARIANTS:
		var source_path := str(variant["source"])
		var target_path := str(variant["target"])
		var image := Image.load_from_file(ProjectSettings.globalize_path(source_path))
		if image.is_empty():
			push_error("Missing cottage source: " + source_path)
			failed = true
			continue
		image.resize(TARGET_SIZE.x, TARGET_SIZE.y, Image.INTERPOLATE_NEAREST)
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				var color := image.get_pixel(x, y)
				if color.a < 0.85:
					image.set_pixel(x, y, Color.TRANSPARENT)
				else:
					color.a = 1.0
					image.set_pixel(x, y, color)
		var error := image.save_png(ProjectSettings.globalize_path(target_path))
		if error != OK:
			push_error("Could not save cottage variant: " + target_path)
			failed = true
		else:
			print("Saved ", target_path)
	quit(1 if failed else 0)
