extends SceneTree

## Prepare the generated wide grass strip for the 1280x230 desktop scene.
## This keeps the editable source while producing an exact 2048px runtime texture.
const SOURCE := "res://assets/source/background_2k_generated.png"
const OUTPUT := "res://assets/hd/world/background.png"
const OUTPUT_SIZE := Vector2i(2048, 256)
const SEAM_FADE := 32


# 封装 initialize 的处理，供相关流程复用。
func _initialize() -> void:
	var source := Image.load_from_file(ProjectSettings.globalize_path(SOURCE))
	if source.is_empty():
		push_error("Cannot load generated background: " + SOURCE)
		quit(1)
		return
	var top := source.get_height()
	var bottom := -1
	for y in range(source.get_height()):
		for x in range(source.get_width()):
			if source.get_pixel(x, y).a >= 0.15:
				top = mini(top, y)
				bottom = maxi(bottom, y)
	if bottom < top:
		push_error("Generated background has no opaque grass")
		quit(1)
		return
	var strip := source.get_region(Rect2i(0, top, source.get_width(), bottom - top + 1))
	strip.resize(OUTPUT_SIZE.x, OUTPUT_SIZE.y, Image.INTERPOLATE_NEAREST)
	for y in range(strip.get_height()):
		var left := strip.get_pixel(0, y)
		var right := strip.get_pixel(strip.get_width() - 1, y)
		var seam := left if left.a >= right.a else right
		for i in range(SEAM_FADE):
			var fade := float(i) / float(SEAM_FADE - 1)
			strip.set_pixel(i, y, seam.lerp(strip.get_pixel(i, y), fade))
			strip.set_pixel(strip.get_width() - 1 - i, y, seam.lerp(strip.get_pixel(strip.get_width() - 1 - i, y), fade))
	for y in range(strip.get_height()):
		for x in range(strip.get_width()):
			var color := strip.get_pixel(x, y)
			if color.a < 0.15:
				strip.set_pixel(x, y, Color.TRANSPARENT)
			elif color.a < 0.95 and color.r > 0.85 and color.g > 0.85 and color.b > 0.85:
				color.r = clampf((color.r - (1.0 - color.a)) / color.a, 0.0, 1.0)
				color.g = clampf((color.g - (1.0 - color.a)) / color.a, 0.0, 1.0)
				color.b = clampf((color.b - (1.0 - color.a)) / color.a, 0.0, 1.0)
				strip.set_pixel(x, y, color)
	var error := strip.save_png(ProjectSettings.globalize_path(OUTPUT))
	if error != OK:
		push_error("Cannot save background: " + OUTPUT)
		quit(1)
		return
	print("Saved seamless background ", OUTPUT, " at ", OUTPUT_SIZE)
	quit()
