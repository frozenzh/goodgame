extends SceneTree

## Re-run with: Godot --headless --path . --script res://tools/export_worker_actions.gd
## The supplied sheet has an opaque checkerboard, so the exterior checker is
## flood-filled to transparency without changing the character pixels.

const SOURCE := "res://assets/source/worker_action_sheet.png"
const SIZE := 128
const X_ORIGINS := [58, 206, 355, 503, 652, 800, 949, 1098]


# 封装 initialize 的处理，供相关流程复用。
func _initialize() -> void:
	var source := Image.load_from_file(ProjectSettings.globalize_path(SOURCE))
	if source.is_empty():
		push_error("Could not load worker action sheet")
		quit(1)
		return
	for index in X_ORIGINS.size():
		_export_frame(source, index, 80, "fishing")
		_export_frame(source, index, 532, "idle")
	quit()


# 导出 frame，供调用方继续处理。
func _export_frame(source: Image, index: int, y_origin: int, action: String) -> void:
	var frame := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	frame.blit_rect(source, Rect2i(X_ORIGINS[index], y_origin, SIZE, SIZE), Vector2i.ZERO)
	var visited := PackedByteArray()
	visited.resize(SIZE * SIZE)
	var queue: Array[Vector2i] = []
	for x in SIZE:
		queue.append(Vector2i(x, 0))
		queue.append(Vector2i(x, SIZE - 1))
	for y in SIZE:
		queue.append(Vector2i(0, y))
		queue.append(Vector2i(SIZE - 1, y))
	var cursor := 0
	while cursor < queue.size():
		var point := queue[cursor]
		cursor += 1
		if point.x < 0 or point.x >= SIZE or point.y < 0 or point.y >= SIZE:
			continue
		var offset := point.y * SIZE + point.x
		if visited[offset] != 0:
			continue
		visited[offset] = 1
		var color := frame.get_pixelv(point)
		if not _is_checker(color):
			continue
		frame.set_pixelv(point, Color(color.r, color.g, color.b, 0.0))
		queue.append(point + Vector2i.LEFT)
		queue.append(point + Vector2i.RIGHT)
		queue.append(point + Vector2i.UP)
		queue.append(point + Vector2i.DOWN)
	var path := "res://assets/source/actor_%s_%02d.png" % [action, index + 1]
	var error := frame.save_png(ProjectSettings.globalize_path(path))
	if error != OK:
		push_error("Could not save %s: %s" % [path, error])
	else:
		print(path)


# 判断是否满足 checker 对应的条件。
func _is_checker(color: Color) -> bool:
	var high := maxf(color.r, maxf(color.g, color.b)) * 255.0
	var low := minf(color.r, minf(color.g, color.b)) * 255.0
	var mean := (color.r + color.g + color.b) * 85.0
	return high - low <= 12.0 and mean >= 208.0 and mean <= 249.0
