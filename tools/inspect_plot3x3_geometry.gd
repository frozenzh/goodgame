extends SceneTree

const SOURCE := "res://assets/hd/world/plot3x3/soil_cell.png"

# 封装 initialize 的处理，供相关流程复用。
func _initialize() -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(SOURCE))
	print("SOIL_CELL: image=", image.get_size(), " used=", image.get_used_rect())
	var row_counts := PackedInt32Array()
	var col_counts := PackedInt32Array()
	row_counts.resize(image.get_height())
	col_counts.resize(image.get_width())
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				row_counts[y] += 1
				col_counts[x] += 1
	var left := 0
	var right := image.get_width() - 1
	var top := 0
	var bottom := image.get_height() - 1
	while col_counts[left] < 50:
		left += 1
	while col_counts[right] < 50:
		right -= 1
	while row_counts[top] < 50:
		top += 1
	while row_counts[bottom] < 50:
		bottom -= 1
	print("SOIL_CELL_ROBUST_BOUNDS: ", Rect2i(left, top, right - left + 1, bottom - top + 1))
	quit()
