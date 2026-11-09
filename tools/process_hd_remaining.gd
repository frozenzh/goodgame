extends SceneTree

## Faithful enlargement for compact HUD icons. The generated 2K grass background
## is rebuilt separately by process_seamless_background.gd.

const ICON_NAMES := [
	"icon_coin", "icon_crop", "icon_fish", "icon_bait", "icon_codex", "icon_settings",
	"icon_coin_simple", "icon_crop_simple", "icon_fish_simple", "icon_bait_simple",
	"icon_codex_simple", "icon_settings_simple"
]


# 封装 initialize 的处理，供相关流程复用。
func _initialize() -> void:
	for icon_name in ICON_NAMES:
		_process_image("res://assets/ui/%s.png" % icon_name, "res://assets/hd/ui/%s.png" % icon_name, 2)
	_process_image("res://assets/ui/wood_sign.png", "res://assets/hd/ui/wood_sign.png", 1)
	quit()


# 封装 process_image 的处理，供相关流程复用。
func _process_image(source_path: String, output_path: String, factor: int) -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(source_path))
	if image.is_empty():
		push_error("Cannot load " + source_path)
		return
	# Undo white-matte contamination only at translucent edge pixels.
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.a < 0.06:
				image.set_pixel(x, y, Color.TRANSPARENT)
			elif color.a < 0.95:
				color.r = clampf((color.r - (1.0 - color.a)) / color.a, 0.0, 1.0)
				color.g = clampf((color.g - (1.0 - color.a)) / color.a, 0.0, 1.0)
				color.b = clampf((color.b - (1.0 - color.a)) / color.a, 0.0, 1.0)
				image.set_pixel(x, y, color)
	if factor > 1:
		image.resize(image.get_width() * factor, image.get_height() * factor, Image.INTERPOLATE_NEAREST)
	var error := image.save_png(ProjectSettings.globalize_path(output_path))
	if error != OK:
		push_error("Cannot save " + output_path)
	else:
		print(output_path)
