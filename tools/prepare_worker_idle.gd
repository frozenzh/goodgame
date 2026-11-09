extends SceneTree

## Rebuild the character's 1024 px animation frames with a shared foot baseline.
## New idle poses are cut from the supplied sheet without redrawing any pixels.
const SOURCE_SHEET := "res://assets/source/worker_idle_yawn_scratch_sheet.png"
const EXISTING_DIR := "res://assets/hd/worker"
const OUTPUT_DIR := "res://assets/hd/worker/frames"
const FRAME_SIZE := Vector2i(1024, 1024)
const FOOT_Y := 940
const STANDING_HEIGHT := 840.0
const SOURCE_IDLE_SCALE := 6.0
const TOP_COLUMNS := [Vector2i(82, 161), Vector2i(224, 301), Vector2i(370, 448), Vector2i(512, 603), Vector2i(677, 771), Vector2i(839, 932), Vector2i(990, 1110), Vector2i(1173, 1256), Vector2i(1316, 1393), Vector2i(1470, 1546), Vector2i(1621, 1698), Vector2i(1775, 1852)]
const BOTTOM_COLUMNS := [Vector2i(83, 163), Vector2i(224, 302), Vector2i(369, 447), Vector2i(515, 593), Vector2i(679, 762), Vector2i(843, 929), Vector2i(1009, 1092), Vector2i(1173, 1250), Vector2i(1315, 1392), Vector2i(1471, 1548), Vector2i(1624, 1701), Vector2i(1776, 1854)]


# 封装 initialize 的处理，供相关流程复用。
func _initialize() -> void:
	call_deferred("_run")


# 封装 run 的处理，供相关流程复用。
func _run() -> void:
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	if err != OK:
		push_error("Cannot create worker frame directory: %s" % err)
		quit(1)
		return
	var sheet := Image.load_from_file(ProjectSettings.globalize_path(SOURCE_SHEET))
	if sheet.is_empty() or sheet.get_size() != Vector2i(2048, 1144):
		push_error("The new idle sheet must be 2048 x 1144 pixels")
		quit(1)
		return
	for index in range(12):
		var top_bounds: Vector2i = TOP_COLUMNS[index]
		var bottom_bounds: Vector2i = BOTTOM_COLUMNS[index]
		var yawn := _extract_cell(sheet, Rect2i(top_bounds.x - 4, 237, top_bounds.y - top_bounds.x + 9, 148))
		var scratch := _extract_cell(sheet, Rect2i(bottom_bounds.x - 4, 715, bottom_bounds.y - bottom_bounds.x + 9, 151))
		if not _save_frame(_align_frame(yawn, SOURCE_IDLE_SCALE), "actor_idle_yawn_%02d.png" % [index + 1]):
			quit(1)
			return
		if not _save_frame(_align_frame(scratch, SOURCE_IDLE_SCALE), "actor_idle_scratch_%02d.png" % [index + 1]):
			quit(1)
			return
	for group in ["down", "left", "right", "up", "idle", "fishing"]:
		var count := 8 if group == "idle" or group == "fishing" else 4
		var first := Image.load_from_file(ProjectSettings.globalize_path("%s/actor_%s_01.png" % [EXISTING_DIR, group]))
		var reference_height := first.get_used_rect().size.y
		var scale_factor := STANDING_HEIGHT / float(reference_height) if group != "fishing" else 1.0
		for index in range(1, count + 1):
			var name := "actor_%s_%02d.png" % [group, index]
			var image := Image.load_from_file(ProjectSettings.globalize_path("%s/%s" % [EXISTING_DIR, name]))
			var output := _align_frame(image, scale_factor, group != "fishing")
			if not _save_frame(output, name):
				quit(1)
				return
	print("WORKER_IDLE_FRAMES_OK: 24 new idle frames; 32 existing frames aligned")
	quit(0)


# 封装 extract_cell 的处理，供相关流程复用。
func _extract_cell(sheet: Image, cell: Rect2i) -> Image:
	var result := Image.create_empty(cell.size.x, cell.size.y, false, Image.FORMAT_RGBA8)
	result.fill(Color.TRANSPARENT)
	for y in range(cell.size.y):
		for x in range(cell.size.x):
			var pixel := sheet.get_pixel(cell.position.x + x, cell.position.y + y)
			var brightest := maxf(pixel.r, maxf(pixel.g, pixel.b))
			var darkest := minf(pixel.r, minf(pixel.g, pixel.b))
			var average := (pixel.r + pixel.g + pixel.b) / 3.0
			# Checkerboard is neutral gray (roughly 213–240); the outline and
			# clothing are dark or chromatic. A hard alpha edge prevents gray halos.
			if brightest - darkest > 20.0 / 255.0 or average < 100.0 / 255.0:
				result.set_pixel(x, y, Color(pixel.r, pixel.g, pixel.b, 1.0))
	return result


# 封装 align_frame 的处理，供相关流程复用。
func _align_frame(image: Image, scale_factor: float, center_on_feet: bool = true) -> Image:
	var used := image.get_used_rect()
	var output := Image.create_empty(FRAME_SIZE.x, FRAME_SIZE.y, false, Image.FORMAT_RGBA8)
	output.fill(Color.TRANSPARENT)
	if used.size.x <= 0 or used.size.y <= 0:
		return output
	var cropped := image.get_region(used)
	var scaled_size := Vector2i(roundi(float(used.size.x) * scale_factor), roundi(float(used.size.y) * scale_factor))
	cropped.resize(maxi(1, scaled_size.x), maxi(1, scaled_size.y), Image.INTERPOLATE_NEAREST)
	var foot_center := float(used.position.x) + float(used.size.x) * 0.5
	if center_on_feet:
		foot_center = _find_foot_center(image, used)
	var left := roundi(float(FRAME_SIZE.x) * 0.5 - (foot_center - float(used.position.x)) * scale_factor)
	if not center_on_feet:
		left = used.position.x
	var top := FOOT_Y - cropped.get_height()
	output.blit_rect(cropped, Rect2i(Vector2i.ZERO, cropped.get_size()), Vector2i(left, top))
	return output


# 查找 foot_center，供调用方继续处理。
func _find_foot_center(image: Image, used: Rect2i) -> float:
	var first_x := used.end.x
	var last_x := used.position.x
	var band_top := maxi(used.position.y, used.end.y - maxi(8, roundi(float(used.size.y) * 0.12)))
	for y in range(band_top, used.end.y):
		for x in range(used.position.x, used.end.x):
			if image.get_pixel(x, y).a > 0.5:
				first_x = mini(first_x, x)
				last_x = maxi(last_x, x)
	return float(first_x + last_x) * 0.5 if first_x <= last_x else float(used.position.x + used.end.x) * 0.5


# 保存 frame，供调用方继续处理。
func _save_frame(image: Image, name: String) -> bool:
	var destination := ProjectSettings.globalize_path("%s/%s" % [OUTPUT_DIR, name])
	var err := image.save_png(destination)
	if err != OK:
		push_error("Cannot save worker frame %s: %s" % [name, err])
		return false
	return true
