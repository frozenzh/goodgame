extends SceneTree

## 将内置生图原稿裁成与当前地景相同的尺寸，并拼成可横向拖动的背景。
const GENERATED_SOURCE := "res://assets/source/background_left_generated_raw.png"
const ORIGINAL_BACKGROUND := "res://assets/hd/world/background.png"
const LEFT_OUTPUT := "res://assets/hd/world/background_left_extension.png"
const COMBINED_OUTPUT := "res://assets/hd/world/background_extended.png"
const SOURCE_RECT := Rect2i(123, 225, 2048, 272)
const PANEL_SIZE := Vector2i(2048, 256)
const SEAM_BLEND_WIDTH := 160


# 封装 initialize 的处理，供相关流程复用。
func _initialize() -> void:
	var generated := Image.new()
	var original := Image.new()
	if generated.load(GENERATED_SOURCE) != OK or original.load(ORIGINAL_BACKGROUND) != OK:
		push_error("无法读取背景原稿")
		quit(1)
		return
	if original.get_size() != PANEL_SIZE:
		push_error("原背景尺寸与预期不符：%s" % original.get_size())
		quit(1)
		return
	var left := generated.get_region(SOURCE_RECT)
	left.resize(PANEL_SIZE.x, PANEL_SIZE.y, Image.INTERPOLATE_NEAREST)
	left.convert(Image.FORMAT_RGBA8)
	original.convert(Image.FORMAT_RGBA8)
	# 在接缝末端引用原背景的左缘纹理，让新旧两幅图自然衔接。
	for x in range(PANEL_SIZE.x - SEAM_BLEND_WIDTH, PANEL_SIZE.x):
		var t := float(x - (PANEL_SIZE.x - SEAM_BLEND_WIDTH)) / float(SEAM_BLEND_WIDTH - 1)
		var weight := t * t * (3.0 - 2.0 * t)
		for y in range(PANEL_SIZE.y):
			var reflected_x := PANEL_SIZE.x - 1 - x
			left.set_pixel(x, y, left.get_pixel(x, y).lerp(original.get_pixel(reflected_x, y), weight))
	if left.save_png(LEFT_OUTPUT) != OK:
		push_error("无法保存左侧背景")
		quit(1)
		return
	var combined := Image.create_empty(PANEL_SIZE.x * 2, PANEL_SIZE.y, false, Image.FORMAT_RGBA8)
	combined.blit_rect(left, Rect2i(Vector2i.ZERO, PANEL_SIZE), Vector2i.ZERO)
	combined.blit_rect(original, Rect2i(Vector2i.ZERO, PANEL_SIZE), Vector2i(PANEL_SIZE.x, 0))
	if combined.save_png(COMBINED_OUTPUT) != OK:
		push_error("无法保存拼接后的背景")
		quit(1)
		return
	print("已生成左侧背景与拼接背景：", combined.get_size())
	quit()
