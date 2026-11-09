extends SceneTree

## Registers every planted state to the exact same visible rectangle as empty soil.
## Existing seed/leaf art is reused for all crops; five generated masters stay in atlases/.

const WORLD := "res://assets/hd/world/"
const MASTERS := "res://assets/hd/atlases/"
const CROPS := ["wheat", "cabbage", "tomato", "corn", "strawberry"]


# 封装 initialize 的处理，供相关流程复用。
func _initialize() -> void:
	var reference := Image.load_from_file(ProjectSettings.globalize_path(WORLD + "plot_cleared.png"))
	var footprint := _alpha_bounds(reference)
	if reference.is_empty() or footprint.size.x <= 0:
		push_error("Missing empty-plot footprint")
		quit(1)
		return
	_register(WORLD + "plot_locked.png", WORLD + "plot_locked_aligned.png", reference.get_size(), footprint)
	_register(WORLD + "carrot_seed.png", WORLD + "plot_seed.png", reference.get_size(), footprint)
	_register(WORLD + "carrot_leaf.png", WORLD + "plot_leaf.png", reference.get_size(), footprint)
	_register(WORLD + "carrot_mature.png", WORLD + "mature_carrot.png", reference.get_size(), footprint)
	for crop_id in CROPS:
		var source_path := MASTERS + "mature_%s_master.png" % crop_id
		_register(source_path, WORLD + "mature_%s.png" % crop_id, reference.get_size(), footprint)
	quit()


# 封装 register 的处理，供相关流程复用。
func _register(source_path: String, target_path: String, canvas_size: Vector2i, footprint: Rect2i) -> void:
	var source := Image.load_from_file(ProjectSettings.globalize_path(source_path))
	var used := _alpha_bounds(source)
	if source.is_empty() or used.size.x <= 0:
		push_error("Missing source: " + source_path)
		return
	var content := source.get_region(used)
	content.resize(footprint.size.x, footprint.size.y, Image.INTERPOLATE_NEAREST)
	var output := Image.create(canvas_size.x, canvas_size.y, false, Image.FORMAT_RGBA8)
	output.fill(Color.TRANSPARENT)
	output.blend_rect(content, Rect2i(Vector2i.ZERO, content.get_size()), footprint.position)
	# Pixel-art opacity should be binary, preventing tinted matte pixels on transparent edges.
	for y in range(output.get_height()):
		for x in range(output.get_width()):
			var color := output.get_pixel(x, y)
			if color.a < 0.85:
				output.set_pixel(x, y, Color.TRANSPARENT)
			else:
				color.a = 1.0
				output.set_pixel(x, y, color)
	var error := output.save_png(ProjectSettings.globalize_path(target_path))
	if error == OK:
		print(target_path)
	else:
		push_error("Failed to save " + target_path)


# 封装 alpha_bounds 的处理，供相关流程复用。
func _alpha_bounds(image: Image) -> Rect2i:
	if image.is_empty():
		return Rect2i()
	var minimum := Vector2i(image.get_width(), image.get_height())
	var maximum := Vector2i(-1, -1)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a < 0.85:
				continue
			minimum.x = mini(minimum.x, x)
			minimum.y = mini(minimum.y, y)
			maximum.x = maxi(maximum.x, x)
			maximum.y = maxi(maximum.y, y)
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE) if maximum.x >= 0 else Rect2i()
