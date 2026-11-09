extends SceneTree

## Splits generated atlases and re-registers every image to the original frame
## footprint. This keeps existing animation timing, origin and plot alignment.

const GENERATED := "res://assets/hd/atlases/"
const WORKER_OUTPUT := "res://assets/hd/worker/"
const PLOT_OUTPUT := "res://assets/hd/world/"
const FRAME_SIZE := 1024
const FRAME_SCALE := 8.0
const PLOT_WIDTH := 1024
const PLOT_HEIGHT := 963
const PLOT_SCALE := 1024.0 / 168.0

const ACTOR_ATLASES := {
	"down": "exec-b1a820d8-e688-410c-949c-b75d3da8c349.png",
	"left": "exec-e3aea33f-4bd5-430d-b4f5-8882dbcafd77.png",
	"right": "exec-065d472e-f4f6-4458-a7cc-694923949259.png",
	"up": "exec-163ce12b-32a3-4c9f-9a44-7aac2c642668.png",
	"fishing_1": "exec-1529b10c-537f-49e9-a096-dbc08a47ccce.png",
	"fishing_2": "exec-2063a863-f8f4-4f89-9f6d-32bb5d9e6289.png",
	"idle_1": "exec-244d2f9a-7aff-462b-96df-f8ce38d565df.png",
	"idle_2": "exec-e8857dd7-b9fc-4ad6-b417-bbe2c3f45010.png"
}
const PLOT_ATLAS := "exec-1b5158f8-73db-462b-ae93-bdfea3cda292.png"
const PLOT_NAMES := ["plot_locked", "plot_cleared", "carrot_seed", "carrot_leaf", "carrot_mature"]
const PLOT_SOURCES := ["new_plot_locked", "new_plot_cleared", "new_carrot_seed", "new_carrot_leaf", "new_carrot_mature"]


# 封装 initialize 的处理，供相关流程复用。
func _initialize() -> void:
	for key in ACTOR_ATLASES:
		_process_actor_atlas(str(key), GENERATED + str(ACTOR_ATLASES[key]))
	_process_plots()
	quit()


# 封装 process_actor_atlas 的处理，供相关流程复用。
func _process_actor_atlas(key: String, path: String) -> void:
	var atlas := Image.load_from_file(ProjectSettings.globalize_path(path))
	if atlas.is_empty():
		push_error("Cannot load " + path)
		return
	atlas.resize(FRAME_SIZE * 2, FRAME_SIZE * 2, Image.INTERPOLATE_NEAREST)
	var action := key.trim_suffix("_1").trim_suffix("_2")
	var start := 5 if key.ends_with("_2") else 1
	for index in range(4):
		var frame_number := start + index
		var original_path := "res://assets/source/actor_%s_%02d.png" % [action, frame_number]
		var original := Image.load_from_file(ProjectSettings.globalize_path(original_path))
		var cell := atlas.get_region(Rect2i(index % 2 * FRAME_SIZE, index / 2 * FRAME_SIZE, FRAME_SIZE, FRAME_SIZE))
		var source_rect := _alpha_bounds(original)
		var generated_rect := _alpha_bounds(cell)
		if source_rect.size.x <= 0 or generated_rect.size.x <= 0:
			push_error("Empty frame: " + original_path)
			continue
		var output := Image.create(FRAME_SIZE, FRAME_SIZE, false, Image.FORMAT_RGBA8)
		output.fill(Color.TRANSPARENT)
		var content := cell.get_region(generated_rect)
		var source_x := source_rect.position.x + (128 - original.get_width()) / 2
		var target_rect := Rect2i(
			roundi(float(source_x) * FRAME_SCALE),
			roundi(float(source_rect.position.y) * FRAME_SCALE),
			roundi(float(source_rect.size.x) * FRAME_SCALE),
			roundi(float(source_rect.size.y) * FRAME_SCALE)
		)
		content.resize(target_rect.size.x, target_rect.size.y, Image.INTERPOLATE_NEAREST)
		output.blend_rect(content, Rect2i(Vector2i.ZERO, content.get_size()), target_rect.position)
		_clean_alpha(output)
		var output_path := WORKER_OUTPUT + "actor_%s_%02d.png" % [action, frame_number]
		_save(output, output_path)


# 封装 process_plots 的处理，供相关流程复用。
func _process_plots() -> void:
	var atlas := Image.load_from_file(ProjectSettings.globalize_path(GENERATED + PLOT_ATLAS))
	var reference := Image.load_from_file(ProjectSettings.globalize_path(GENERATED + "plot_states_reference.png"))
	if atlas.is_empty() or reference.is_empty():
		push_error("Missing plot atlas or reference mask")
		return
	reference.resize(atlas.get_width(), atlas.get_height(), Image.INTERPOLATE_NEAREST)
	for y in range(atlas.get_height()):
		for x in range(atlas.get_width()):
			var color := atlas.get_pixel(x, y)
			var mask_alpha := reference.get_pixel(x, y).a
			color.a = minf(color.a, mask_alpha)
			atlas.set_pixel(x, y, color if color.a > 0.03 else Color.TRANSPARENT)
	var cell_width := atlas.get_width() / 3
	var cell_height := atlas.get_height() / 2
	for index in range(PLOT_NAMES.size()):
		var cell := atlas.get_region(Rect2i(index % 3 * cell_width, index / 3 * cell_height, cell_width, cell_height))
		var original_path := "res://assets/source/" + str(PLOT_SOURCES[index]) + ".png"
		var original := Image.load_from_file(ProjectSettings.globalize_path(original_path))
		var source_rect := _alpha_bounds(original)
		var generated_rect := _alpha_bounds(cell)
		if source_rect.size.x <= 0 or generated_rect.size.x <= 0:
			push_error("Empty plot state: " + original_path)
			continue
		var output := Image.create(PLOT_WIDTH, PLOT_HEIGHT, false, Image.FORMAT_RGBA8)
		output.fill(Color.TRANSPARENT)
		var content := cell.get_region(generated_rect)
		var target_rect := Rect2i(
			roundi(float(source_rect.position.x) * PLOT_SCALE),
			roundi(float(source_rect.position.y) * PLOT_SCALE),
			roundi(float(source_rect.size.x) * PLOT_SCALE),
			roundi(float(source_rect.size.y) * PLOT_SCALE)
		)
		content.resize(target_rect.size.x, target_rect.size.y, Image.INTERPOLATE_NEAREST)
		output.blend_rect(content, Rect2i(Vector2i.ZERO, content.get_size()), target_rect.position)
		_clean_alpha(output)
		_save(output, PLOT_OUTPUT + str(PLOT_NAMES[index]) + ".png")


# 封装 alpha_bounds 的处理，供相关流程复用。
func _alpha_bounds(image: Image) -> Rect2i:
	var minimum := Vector2i(image.get_width(), image.get_height())
	var maximum := Vector2i(-1, -1)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.12:
				continue
			minimum.x = mini(minimum.x, x)
			minimum.y = mini(minimum.y, y)
			maximum.x = maxi(maximum.x, x)
			maximum.y = maxi(maximum.y, y)
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE) if maximum.x >= 0 else Rect2i()


# 封装 clean_alpha 的处理，供相关流程复用。
func _clean_alpha(image: Image) -> void:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.a < 0.08:
				image.set_pixel(x, y, Color.TRANSPARENT)


# 封装 save 的处理，供相关流程复用。
func _save(image: Image, path: String) -> void:
	var error := image.save_png(ProjectSettings.globalize_path(path))
	if error != OK:
		push_error("Could not save " + path)
	else:
		print(path)
