extends SceneTree

## Remove the reference sheet's checkerboard and cut its exact poses into the
## same 1024 px, foot-aligned canvases used by every other Worker animation.
const SOURCE_SHEET := "res://assets/source/worker_fish_discovery_reference.png"
const OUTPUT_DIR := "res://assets/hd/worker/frames"
const FRAME_COUNT := 12
const CELL_BOUNDARIES := [0, 190, 360, 535, 700, 865, 1030, 1195, 1355, 1520, 1685, 1855, 2048]
const FRAME_SIZE := Vector2i(1024, 1024)
const FOOT_Y := 940
const STANDING_HEIGHT := 840.0
const ROW_TOP := 490
const ROW_BOTTOM := 690


# 封装 initialize 的处理，供相关流程复用。
func _initialize() -> void:
	call_deferred("_run")


# 封装 run 的处理，供相关流程复用。
func _run() -> void:
	var sheet := Image.load_from_file(ProjectSettings.globalize_path(SOURCE_SHEET))
	if sheet.is_empty():
		push_error("Cannot load discovery sprite sheet")
		quit(1)
		return
	var first_cell := Rect2i(CELL_BOUNDARIES[0], ROW_TOP, CELL_BOUNDARIES[1] - CELL_BOUNDARIES[0], ROW_BOTTOM - ROW_TOP)
	var first_bounds := _visible_bounds(sheet, first_cell)
	if first_bounds.size.y <= 0:
		push_error("Discovery sheet has no visible character in frame 1")
		quit(1)
		return
	var scale_factor := STANDING_HEIGHT / float(first_bounds.size.y)
	for index in range(FRAME_COUNT):
		var left: int = CELL_BOUNDARIES[index]
		var right: int = CELL_BOUNDARIES[index + 1]
		var cell := Rect2i(left, ROW_TOP, right - left, ROW_BOTTOM - ROW_TOP)
		var bounds := _visible_bounds(sheet, cell)
		if bounds.size.x <= 0 or bounds.size.y <= 0:
			push_error("Discovery frame %d is empty" % (index + 1))
			quit(1)
			return
		var source := _extract_character(sheet, bounds)
		var scaled_size := Vector2i(maxi(1, roundi(float(bounds.size.x) * scale_factor)), maxi(1, roundi(float(bounds.size.y) * scale_factor)))
		source.resize(scaled_size.x, scaled_size.y, Image.INTERPOLATE_LANCZOS)
		var output := Image.create_empty(FRAME_SIZE.x, FRAME_SIZE.y, false, Image.FORMAT_RGBA8)
		output.fill(Color.TRANSPARENT)
		var foot_center := _foot_center(sheet, bounds)
		var output_left := roundi(float(FRAME_SIZE.x) * 0.5 - (foot_center - float(bounds.position.x)) * scale_factor)
		output.blit_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), Vector2i(output_left, FOOT_Y - source.get_height()))
		var path := ProjectSettings.globalize_path("%s/actor_fish_discovery_%02d.png" % [OUTPUT_DIR, index + 1])
		if output.save_png(path) != OK:
			push_error("Cannot save discovery frame %d" % (index + 1))
			quit(1)
			return
		print("DISCOVERY_FRAME_%02d: %s" % [index + 1, bounds])
	print("WORKER_DISCOVERY_FRAMES_OK")
	quit(0)


# 封装 visible_bounds 的处理，供相关流程复用。
func _visible_bounds(sheet: Image, cell: Rect2i) -> Rect2i:
	var min_x := cell.end.x
	var min_y := cell.end.y
	var max_x := cell.position.x - 1
	var max_y := cell.position.y - 1
	for y in range(cell.position.y, cell.end.y):
		for x in range(cell.position.x, cell.end.x):
			if not _is_character_pixel(sheet.get_pixel(x, y)):
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < min_x:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


# 封装 extract_character 的处理，供相关流程复用。
func _extract_character(sheet: Image, bounds: Rect2i) -> Image:
	var output := Image.create_empty(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
	output.fill(Color.TRANSPARENT)
	for y in range(bounds.size.y):
		for x in range(bounds.size.x):
			var pixel := sheet.get_pixel(bounds.position.x + x, bounds.position.y + y)
			if _is_character_pixel(pixel):
				output.set_pixel(x, y, Color(pixel.r, pixel.g, pixel.b, 1.0))
	return output


# 判断是否满足 character_pixel 对应的条件。
func _is_character_pixel(pixel: Color) -> bool:
	var brightest := maxf(pixel.r, maxf(pixel.g, pixel.b))
	var darkest := minf(pixel.r, minf(pixel.g, pixel.b))
	var average := (pixel.r + pixel.g + pixel.b) / 3.0
	return brightest - darkest > 20.0 / 255.0 or average < 100.0 / 255.0


# 封装 foot_center 的处理，供相关流程复用。
func _foot_center(sheet: Image, bounds: Rect2i) -> float:
	var first_x := bounds.end.x
	var last_x := bounds.position.x
	var band_top := maxi(bounds.position.y, bounds.end.y - maxi(8, roundi(float(bounds.size.y) * 0.1)))
	for y in range(band_top, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			if _is_character_pixel(sheet.get_pixel(x, y)):
				first_x = mini(first_x, x)
				last_x = maxi(last_x, x)
	return float(first_x + last_x) * 0.5 if first_x <= last_x else float(bounds.position.x + bounds.end.x) * 0.5
