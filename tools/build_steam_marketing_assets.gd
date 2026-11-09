extends SceneTree

const OUT_DIR := "res://assets/branding/steam"
const LOGO_PATH := "res://assets/branding/logo-concept-02-window-farm-pond-v2.png"
const ACTOR_SHEET_PATH := "res://assets/previews/worker_walk_8_preview.png"
const HOUSE_PATH := "res://assets/world/world_house.png"
const POND_PATH := "res://assets/world/world_pond.png"


# 在实例创建时初始化数据。
func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var full_logo := Image.load_from_file(LOGO_PATH)
	var actor_sheet := Image.load_from_file(ACTOR_SHEET_PATH)
	var actor := _trim_alpha(actor_sheet.get_region(Rect2i(0, 0, 128, 128)))
	var house := _trim_alpha(Image.load_from_file(HOUSE_PATH))
	var pond := _trim_alpha(Image.load_from_file(POND_PATH))

	if full_logo.is_empty() or actor.is_empty() or house.is_empty() or pond.is_empty():
		push_error("Unable to load one or more Steam marketing source assets.")
		quit(1)
		return

	var chinese_half := full_logo.get_region(Rect2i(
		0,
		full_logo.get_height() / 2,
		full_logo.get_width(),
		full_logo.get_height() - full_logo.get_height() / 2
	))
	var chinese_logo := _trim_alpha(chinese_half)

	_build_library_logo(chinese_logo)
	_build_store_header(chinese_logo, actor)
	_build_library_hero(chinese_logo, actor, house, pond)

	print("Steam marketing assets written to: ", OUT_DIR)
	quit()


# 构建 library_logo，供调用方继续处理。
func _build_library_logo(source: Image) -> void:
	var logo := source.duplicate()
	_scale_to_fit(logo, 1280, 720)
	logo.save_png(OUT_DIR + "/library-logo-zh-1280.png")


# 构建 store_header，供调用方继续处理。
func _build_store_header(chinese_logo: Image, actor_source: Image) -> void:
	var canvas := Image.create(920, 430, false, Image.FORMAT_RGBA8)
	_paint_simple_background(canvas, Color("#f7ddbd"), Color("#f4edcf"), 286)

	# A restrained desktop-window cue without recreating operating-system chrome.
	canvas.fill_rect(Rect2i(0, 0, 920, 8), Color("#254f37"))
	canvas.fill_rect(Rect2i(0, 8, 920, 3), Color("#8eb46f"))

	var actor := actor_source.duplicate()
	_scale_to_fit(actor, 205, 286)
	_draw_ellipse(canvas, Vector2i(785, 365), Vector2i(92, 18), Color("#31543b"))
	_blit_centered(canvas, actor, Vector2i(790, 240))

	var logo := chinese_logo.duplicate()
	_scale_to_fit(logo, 675, 350)
	_blit_centered(canvas, logo, Vector2i(350, 218))

	canvas.save_png(OUT_DIR + "/store-header-zh-920x430.png")


# 构建 library_hero，供调用方继续处理。
func _build_library_hero(
	chinese_logo: Image,
	actor_source: Image,
	house_source: Image,
	pond_source: Image
) -> void:
	var hero := Image.create(3840, 1240, false, Image.FORMAT_RGBA8)
	_paint_simple_background(hero, Color("#f5d7b8"), Color("#eef0cf"), 795)

	# Keep the left side calm for Steam's independently positioned logo layer.
	var house := house_source.duplicate()
	_scale_to_fit(house, 680, 700)
	_blit_centered(hero, house, Vector2i(2525, 695))

	var pond := pond_source.duplicate()
	_scale_to_fit(pond, 1050, 440)
	_blit_centered(hero, pond, Vector2i(3150, 965))

	var actor := actor_source.duplicate()
	_scale_to_fit(actor, 500, 700)
	_draw_ellipse(hero, Vector2i(2010, 1040), Vector2i(220, 38), Color("#31543b"))
	_blit_centered(hero, actor, Vector2i(2010, 735))

	# Official upload: artwork only, no embedded title.
	hero.save_png(OUT_DIR + "/library-hero-3840x1240.png")

	# Review-only composite showing the separate Steam logo layer placement.
	var preview := hero.duplicate()
	var logo := chinese_logo.duplicate()
	_scale_to_fit(logo, 1280, 720)
	_blit_centered(preview, logo, Vector2i(780, 820))
	preview.save_png(OUT_DIR + "/library-hero-logo-preview-3840x1240.png")


# 封装 paint_simple_background 的处理，供相关流程复用。
func _paint_simple_background(
	image: Image,
	top_color: Color,
	bottom_color: Color,
	grass_y: int
) -> void:
	var width := image.get_width()
	var height := image.get_height()
	for y in range(height):
		var t := float(y) / float(maxi(height - 1, 1))
		image.fill_rect(Rect2i(0, y, width, 1), top_color.lerp(bottom_color, t))

	var hill_back := Color("#b8cf91")
	var hill_front := Color("#91b56f")
	_draw_hill(image, int(width * 0.20), grass_y + 35, int(width * 0.33), int(height * 0.28), hill_back)
	_draw_hill(image, int(width * 0.72), grass_y + 30, int(width * 0.39), int(height * 0.33), hill_back)
	_draw_hill(image, int(width * 0.42), grass_y + 55, int(width * 0.28), int(height * 0.23), hill_front)
	_draw_hill(image, int(width * 0.90), grass_y + 55, int(width * 0.25), int(height * 0.22), hill_front)

	image.fill_rect(Rect2i(0, grass_y, width, height - grass_y), Color("#6f9c58"))
	image.fill_rect(Rect2i(0, grass_y, width, maxi(5, height / 90)), Color("#a8cc72"))
	image.fill_rect(Rect2i(0, height - maxi(15, height / 28), width, maxi(15, height / 28)), Color("#4e7445"))

	# Sparse blocky flowers keep the background recognizably pastoral but quiet.
	var flower_step := maxi(92, width / 18)
	for x in range(flower_step / 2, width, flower_step):
		var y := grass_y + 28 + (x * 17) % maxi(36, height - grass_y - 70)
		_draw_pixel_flower(image, Vector2i(x, y), maxi(2, height / 260))


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


# 绘制 pixel_flower，供调用方继续处理。
func _draw_pixel_flower(image: Image, center: Vector2i, scale: int) -> void:
	var white := Color("#f7f0d5")
	var gold := Color("#e7ae45")
	for offset in [Vector2i(-scale, 0), Vector2i(scale, 0), Vector2i(0, -scale), Vector2i(0, scale)]:
		image.fill_rect(Rect2i(center + offset, Vector2i(scale, scale)), white)
	image.fill_rect(Rect2i(center, Vector2i(scale, scale)), gold)


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
