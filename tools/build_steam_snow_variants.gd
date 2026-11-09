extends SceneTree

const OUT_ROOT := "res://assets/branding/steam"
const LOGO_PATH := "res://assets/branding/logo-concept-02-window-farm-pond-v2.png"
const ACTOR_FISHING_PATH := "res://assets/source/actor_fishing_01.png"
const HOUSE_PATH := "res://assets/world/world_house.png"
const POND_PATH := "res://assets/world/world_pond.png"


# 在实例创建时初始化数据。
func _init() -> void:
	var full_logo := Image.load_from_file(LOGO_PATH)
	var actor := _trim_alpha(Image.load_from_file(ACTOR_FISHING_PATH))
	var house := _trim_alpha(Image.load_from_file(HOUSE_PATH))
	var pond := _trim_alpha(Image.load_from_file(POND_PATH))

	if full_logo.is_empty() or actor.is_empty() or house.is_empty() or pond.is_empty():
		push_error("Unable to load one or more source assets for the snow variants.")
		quit(1)
		return

	var lower_half := full_logo.get_region(Rect2i(
		0,
		full_logo.get_height() / 2,
		full_logo.get_width(),
		full_logo.get_height() - full_logo.get_height() / 2
	))
	var chinese_logo := _trim_alpha(lower_half)

	_build_variant("snow-variant-a", false, chinese_logo, actor, house, pond)
	_build_variant("snow-variant-b", true, chinese_logo, actor, house, pond)
	print("Snow Steam variants written to: ", OUT_ROOT)
	quit()


# 构建 variant，供调用方继续处理。
func _build_variant(
	folder_name: String,
	is_night: bool,
	logo_source: Image,
	actor_source: Image,
	house_source: Image,
	pond_source: Image
) -> void:
	var output_dir := OUT_ROOT + "/" + folder_name
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))

	var store := _build_store_header(is_night, logo_source, actor_source, pond_source)
	store.save_png(output_dir + "/store-header-zh-920x430.png")

	var hero := _build_library_hero(is_night, actor_source, house_source, pond_source)
	hero.save_png(output_dir + "/library-hero-3840x1240.png")

	var preview := hero.duplicate()
	var logo := logo_source.duplicate()
	_scale_to_fit(logo, 1280, 650)
	var logo_center := Vector2i(760, 810 if not is_night else 720)
	_blit_centered(preview, logo, logo_center)
	preview.save_png(output_dir + "/library-hero-logo-preview-3840x1240.png")


# 构建 store_header，供调用方继续处理。
func _build_store_header(
	is_night: bool,
	logo_source: Image,
	actor_source: Image,
	pond_source: Image
) -> Image:
	var image := Image.create(920, 430, false, Image.FORMAT_RGBA8)
	_paint_snow_background(image, is_night, 278)

	var pond := pond_source.duplicate()
	_scale_to_fit(pond, 380, 165)
	var pond_center := Vector2i(750, 346)
	_draw_ellipse(image, pond_center + Vector2i(0, 8), Vector2i(205, 68), _snow_color(is_night))
	_blit_centered(image, pond, pond_center)

	var actor := actor_source.duplicate()
	_scale_to_fit(actor, 285, 235)
	_blit_centered(image, actor, Vector2i(650, 252))

	var logo := logo_source.duplicate()
	_scale_to_fit(logo, 545, 300)
	_blit_centered(image, logo, Vector2i(278, 207))

	# Thin frame ties the composition back to the desktop-window premise.
	var frame_color := Color("#234b3a") if not is_night else Color("#172a46")
	image.fill_rect(Rect2i(0, 0, 920, 7), frame_color)
	image.fill_rect(Rect2i(0, 423, 920, 7), frame_color)
	return image


# 构建 library_hero，供调用方继续处理。
func _build_library_hero(
	is_night: bool,
	actor_source: Image,
	house_source: Image,
	pond_source: Image
) -> Image:
	var image := Image.create(3840, 1240, false, Image.FORMAT_RGBA8)
	_paint_snow_background(image, is_night, 780)

	var house := house_source.duplicate()
	_scale_to_fit(house, 690, 700)
	var house_center := Vector2i(3190, 765)
	_draw_ellipse(image, house_center + Vector2i(0, 285), Vector2i(390, 95), _snow_color(is_night))
	_blit_centered(image, house, house_center)

	var pond := pond_source.duplicate()
	_scale_to_fit(pond, 1420, 520)
	var pond_center := Vector2i(2580 if not is_night else 2440, 970)
	_draw_ellipse(image, pond_center + Vector2i(0, 25), Vector2i(760, 210), _snow_color(is_night))
	_blit_centered(image, pond, pond_center)

	var actor := actor_source.duplicate()
	_scale_to_fit(actor, 900, 690)
	var actor_center := Vector2i(1960 if not is_night else 1810, 735)
	_blit_centered(image, actor, actor_center)

	return image


# 封装 paint_snow_background 的处理，供相关流程复用。
func _paint_snow_background(image: Image, is_night: bool, snowline_y: int) -> void:
	var width := image.get_width()
	var height := image.get_height()
	var top := Color("#172642") if is_night else Color("#bcd7e6")
	var horizon := Color("#4f6685") if is_night else Color("#eef4ef")
	for y in range(height):
		var t := float(y) / float(maxi(height - 1, 1))
		image.fill_rect(Rect2i(0, y, width, 1), top.lerp(horizon, t))

	if is_night:
		var moon_center := Vector2i(int(width * 0.82), int(height * 0.18))
		var moon_radius := maxi(28, int(height * 0.075))
		_draw_ellipse(image, moon_center, Vector2i(moon_radius + 14, moon_radius + 14), Color("#405172"))
		_draw_ellipse(image, moon_center, Vector2i(moon_radius, moon_radius), Color("#f4ddb0"))

	var far_hill := Color("#617594") if is_night else Color("#d2e1e5")
	var near_hill := Color("#3d5871") if is_night else Color("#b6cfd6")
	_draw_hill(image, int(width * 0.18), snowline_y + 65, int(width * 0.34), int(height * 0.26), far_hill)
	_draw_hill(image, int(width * 0.72), snowline_y + 45, int(width * 0.42), int(height * 0.34), far_hill)
	_draw_hill(image, int(width * 0.45), snowline_y + 85, int(width * 0.32), int(height * 0.22), near_hill)
	_draw_hill(image, int(width * 0.95), snowline_y + 80, int(width * 0.30), int(height * 0.24), near_hill)

	var tree_color := Color("#263e4c") if is_night else Color("#6f8f8a")
	var tree_step := maxi(100, width / 22)
	for x in range(tree_step / 2, width, tree_step):
		var tree_height := maxi(42, height / 9 + (x * 13) % maxi(24, height / 14))
		_draw_pine(image, Vector2i(x, snowline_y + 12), tree_height, tree_color)

	var snow := _snow_color(is_night)
	image.fill_rect(Rect2i(0, snowline_y, width, height - snowline_y), snow)
	var shadow_color := Color("#a9c2d2") if not is_night else Color("#334d69")
	image.fill_rect(Rect2i(0, snowline_y, width, maxi(8, height / 100)), shadow_color)
	image.fill_rect(Rect2i(0, height - maxi(18, height / 30), width, maxi(18, height / 30)), shadow_color)

	_draw_snowflakes(image, 54 if width < 1000 else 210, 37 if not is_night else 83, is_night)


# 绘制 snowflakes，供调用方继续处理。
func _draw_snowflakes(image: Image, count: int, seed: int, is_night: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var color := Color("#ffffff") if not is_night else Color("#d9e8f5")
	var max_y := int(image.get_height() * 0.86)
	for index in range(count):
		var x := rng.randi_range(8, image.get_width() - 9)
		var y := rng.randi_range(12, max_y)
		var size := rng.randi_range(1, 3) * maxi(1, image.get_height() / 620)
		image.fill_rect(Rect2i(x - size, y, size * 2 + 1, maxi(1, size)), color)
		image.fill_rect(Rect2i(x, y - size, maxi(1, size), size * 2 + 1), color)


# 绘制 pine，供调用方继续处理。
func _draw_pine(image: Image, base: Vector2i, height: int, color: Color) -> void:
	var levels := 3
	for level in range(levels):
		var level_top := base.y - height + int(level * height * 0.22)
		var level_height := int(height * 0.48)
		var max_half_width := int(height * (0.24 + level * 0.05))
		for row in range(level_height):
			var t := float(row) / float(maxi(level_height - 1, 1))
			var half_width := int(max_half_width * t)
			var y := level_top + row
			if y >= 0 and y < image.get_height():
				image.fill_rect(Rect2i(base.x - half_width, y, half_width * 2 + 1, 1), color)


# 绘制 hill，供调用方继续处理。
func _draw_hill(image: Image, center_x: int, baseline_y: int, radius_x: int, radius_y: int, color: Color) -> void:
	var start_x := maxi(0, center_x - radius_x)
	var end_x := mini(image.get_width() - 1, center_x + radius_x)
	for x in range(start_x, end_x + 1):
		var nx := float(x - center_x) / float(radius_x)
		var curve := sqrt(maxf(0.0, 1.0 - nx * nx))
		var top_y := maxi(0, baseline_y - int(curve * radius_y))
		var bottom_y := mini(image.get_height(), baseline_y)
		if bottom_y > top_y:
			image.fill_rect(Rect2i(x, top_y, 1, bottom_y - top_y), color)


# 绘制 ellipse，供调用方继续处理。
func _draw_ellipse(image: Image, center: Vector2i, radius: Vector2i, color: Color) -> void:
	for y in range(center.y - radius.y, center.y + radius.y + 1):
		if y < 0 or y >= image.get_height():
			continue
		for x in range(center.x - radius.x, center.x + radius.x + 1):
			if x < 0 or x >= image.get_width():
				continue
			var nx := float(x - center.x) / float(maxi(radius.x, 1))
			var ny := float(y - center.y) / float(maxi(radius.y, 1))
			if nx * nx + ny * ny <= 1.0:
				image.set_pixel(x, y, color)


# 封装 snow_color 的处理，供相关流程复用。
func _snow_color(is_night: bool) -> Color:
	return Color("#d8e4ee") if is_night else Color("#f6f5ed")


# 封装 scale_to_fit 的处理，供相关流程复用。
func _scale_to_fit(image: Image, max_width: int, max_height: int) -> void:
	var scale := minf(
		float(max_width) / float(image.get_width()),
		float(max_height) / float(image.get_height())
	)
	var width := maxi(1, int(round(image.get_width() * scale)))
	var height := maxi(1, int(round(image.get_height() * scale)))
	image.resize(width, height, Image.INTERPOLATE_NEAREST)


# 封装 blit_centered 的处理，供相关流程复用。
func _blit_centered(target: Image, source: Image, center: Vector2i) -> void:
	var destination := center - Vector2i(source.get_width() / 2, source.get_height() / 2)
	target.blend_rect(source, source.get_used_rect(), destination)


# 封装 trim_alpha 的处理，供相关流程复用。
func _trim_alpha(source: Image) -> Image:
	var min_x := source.get_width()
	var min_y := source.get_height()
	var max_x := -1
	var max_y := -1
	for y in range(source.get_height()):
		for x in range(source.get_width()):
			if source.get_pixel(x, y).a > 0.01:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return Image.create(1, 1, false, Image.FORMAT_RGBA8)
	return source.get_region(Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1))
