extends SceneTree

const LOGO_PATH := "res://assets/branding/logo-concept-02-window-farm-pond-v2.png"
const ACTOR_PATH := "res://assets/source/actor_fishing_01.png"


# 在实例创建时初始化数据。
func _init() -> void:
	var full_logo := Image.load_from_file(LOGO_PATH)
	var actor := _trim_alpha(Image.load_from_file(ACTOR_PATH))
	var lower_half := full_logo.get_region(Rect2i(
		0,
		full_logo.get_height() / 2,
		full_logo.get_width(),
		full_logo.get_height() - full_logo.get_height() / 2
	))
	var logo := _trim_alpha(lower_half)

	_compose("res://assets/branding/steam/layout-variant-a", logo, actor, Vector2i(785, 288), Vector2i(2450, 790))
	_compose("res://assets/branding/steam/layout-variant-b", logo, actor, Vector2i(780, 288), Vector2i(2470, 790))
	print("Reference-layout Steam variants composed.")
	quit()


# 封装 compose 的处理，供相关流程复用。
func _compose(
	base_dir: String,
	logo_source: Image,
	actor_source: Image,
	store_actor_center: Vector2i,
	hero_actor_center: Vector2i
) -> void:
	var store := Image.load_from_file(base_dir + "/background-store-920x430.png")
	store.convert(Image.FORMAT_RGBA8)

	var actor := actor_source.duplicate()
	_scale_to_fit(actor, 315, 245)
	_blit_centered(store, actor, store_actor_center)

	var logo := logo_source.duplicate()
	_scale_to_fit(logo, 640, 345)
	_blit_centered(store, logo, Vector2i(320, 215))
	store.save_png(base_dir + "/store-header-zh-920x430.png")

	var hero := Image.load_from_file(base_dir + "/background-hero-3840x1240.png")
	hero.convert(Image.FORMAT_RGBA8)

	var hero_actor := actor_source.duplicate()
	_scale_to_fit(hero_actor, 980, 740)
	_blit_centered(hero, hero_actor, hero_actor_center)
	hero.save_png(base_dir + "/library-hero-3840x1240.png")

	var preview := hero.duplicate()
	var preview_logo := logo_source.duplicate()
	_scale_to_fit(preview_logo, 1450, 720)
	_blit_centered(preview, preview_logo, Vector2i(790, 770))
	preview.save_png(base_dir + "/library-hero-logo-preview-3840x1240.png")


# 封装 scale_to_fit 的处理，供相关流程复用。
func _scale_to_fit(image: Image, max_width: int, max_height: int) -> void:
	var scale := minf(float(max_width) / image.get_width(), float(max_height) / image.get_height())
	image.resize(
		maxi(1, int(round(image.get_width() * scale))),
		maxi(1, int(round(image.get_height() * scale))),
		Image.INTERPOLATE_NEAREST
	)


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
