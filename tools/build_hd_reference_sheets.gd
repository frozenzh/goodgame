extends SceneTree

## Layout references for high-resolution edits. Originals remain untouched.
const OUTPUT_DIR := "/private/tmp/myfavorite_hd_refs"


# 封装 initialize 的处理，供相关流程复用。
func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	for direction in ["down", "left", "right", "up"]:
		var paths: Array[String] = []
		for frame in range(1, 5):
			paths.append("res://assets/source/actor_%s_%02d.png" % [direction, frame])
		_build_sheet("actor_" + direction, paths, 2, 2, 160)
	for action in ["fishing", "idle"]:
		for part in range(2):
			var paths: Array[String] = []
			for frame in range(part * 4 + 1, part * 4 + 5):
				paths.append("res://assets/source/actor_%s_%02d.png" % [action, frame])
			_build_sheet("actor_%s_%d" % [action, part + 1], paths, 2, 2, 160)
	_build_sheet("plot_states", [
		"res://assets/source/new_plot_locked.png",
		"res://assets/source/new_plot_cleared.png",
		"res://assets/source/new_carrot_seed.png",
		"res://assets/source/new_carrot_leaf.png",
		"res://assets/source/new_carrot_mature.png"
	], 3, 2, 200)
	quit()


# 构建 sheet，供调用方继续处理。
func _build_sheet(name: String, paths: Array[String], columns: int, rows: int, cell: int) -> void:
	var sheet := Image.create(columns * cell, rows * cell, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.TRANSPARENT)
	for index in paths.size():
		var sprite := Image.load_from_file(ProjectSettings.globalize_path(paths[index]))
		if sprite.is_empty():
			push_error("Missing sprite: " + paths[index])
			continue
		var col := index % columns
		var row := index / columns
		var x := col * cell + (cell - sprite.get_width()) / 2
		var y := row * cell + (cell - sprite.get_height()) / 2
		sheet.blend_rect(sprite, Rect2i(0, 0, sprite.get_width(), sprite.get_height()), Vector2i(x, y))
	var path := OUTPUT_DIR + "/" + name + ".png"
	var err := sheet.save_png(path)
	if err != OK:
		push_error("Failed to save " + path)
	else:
		print(path)
