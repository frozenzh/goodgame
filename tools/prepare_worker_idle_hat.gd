extends SceneTree

## 从生图原稿切出脱帽动作，并以行走帧的脚底位置和人物比例对齐。
const SOURCE_PATH := "res://assets/hd/worker/idle_hat_regenerated_sheet.png"
const OUTPUT_DIR := "res://assets/hd/worker/frames"
const FRAME_BOUNDS := [
	Vector2i(20, 302), Vector2i(302, 570), Vector2i(570, 840),
	Vector2i(840, 1089), Vector2i(1089, 1340), Vector2i(1340, 1612),
	Vector2i(1612, 1881), Vector2i(1881, 2160)
]
const SCALE := 840.0 / 357.0
const CANVAS_SIZE := Vector2i(1024, 1280)
const FEET_POSITION := Vector2i(512, 1068)
const ALPHA_THRESHOLD := 0.5


# 封装 initialize 的处理，供相关流程复用。
func _initialize() -> void:
	var source := Image.new()
	if source.load(SOURCE_PATH) != OK:
		push_error("无法读取脱帽动作原稿：%s" % SOURCE_PATH)
		quit(1)
		return
	for index in range(FRAME_BOUNDS.size()):
		if not _write_frame(source, index):
			quit(1)
			return
	quit()


# 写入 frame，供调用方继续处理。
func _write_frame(source: Image, index: int) -> bool:
	var bounds: Vector2i = FRAME_BOUNDS[index]
	var min_x := bounds.y
	var max_x := bounds.x - 1
	var min_y := source.get_height()
	var max_y := -1
	var foot_min_x := bounds.y
	var foot_max_x := bounds.x - 1
	for y in range(source.get_height()):
		for x in range(bounds.x, bounds.y):
			if source.get_pixel(x, y).a < ALPHA_THRESHOLD:
				continue
			min_x = mini(min_x, x)
			max_x = maxi(max_x, x)
			min_y = mini(min_y, y)
			max_y = maxi(max_y, y)
			if y >= 550 and y <= 606:
				foot_min_x = mini(foot_min_x, x)
				foot_max_x = maxi(foot_max_x, x)
	if max_x < min_x or max_y < min_y or foot_max_x < foot_min_x:
		push_error("脱帽动作第 %d 帧无法识别人物或鞋子" % (index + 1))
		return false
	var frame := source.get_region(Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1))
	for y in range(frame.get_height()):
		for x in range(frame.get_width()):
			var pixel := frame.get_pixel(x, y)
			frame.set_pixel(x, y, Color(pixel.r, pixel.g, pixel.b, 1.0) if pixel.a >= ALPHA_THRESHOLD else Color.TRANSPARENT)
	frame.resize(roundi(float(frame.get_width()) * SCALE), roundi(float(frame.get_height()) * SCALE), Image.INTERPOLATE_NEAREST)
	var foot_center := (foot_min_x + foot_max_x) / 2.0
	var offset := Vector2i(
		FEET_POSITION.x - roundi((foot_center - float(min_x)) * SCALE),
		FEET_POSITION.y - frame.get_height()
	)
	var canvas := Image.create_empty(CANVAS_SIZE.x, CANVAS_SIZE.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color.TRANSPARENT)
	canvas.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), offset)
	var output_path := OUTPUT_DIR.path_join("actor_idle_%02d.png" % (index + 1))
	if canvas.save_png(output_path) != OK:
		push_error("无法保存脱帽动作：%s" % output_path)
		return false
	print("脱帽帧 %d：人物 %s，落点 %s" % [index + 1, frame.get_size(), offset])
	return true
