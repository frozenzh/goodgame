extends SceneTree

## Keep the generated source intact; arrange three larger stones with an even repeat gap.
const SOURCE := "res://assets/source/dirt_path_tile_v2_generated.png"
const OUTPUT := "res://assets/hd/world/dirt_path_tile.png"
const OUTPUT_SIZE := Vector2i(2048, 400)
const STONE_SIZE := Vector2i(455, 380)


# 封装 initialize 的处理，供相关流程复用。
func _initialize() -> void:
	var source := Image.load_from_file(ProjectSettings.globalize_path(SOURCE))
	if source.is_empty():
		push_error("Cannot load dirt path source: " + SOURCE)
		quit(1)
		return
	var strip := Image.create(OUTPUT_SIZE.x, OUTPUT_SIZE.y, false, Image.FORMAT_RGBA8)
	strip.fill(Color.TRANSPARENT)
	var pitch := float(OUTPUT_SIZE.x) / 3.0
	for index in range(3):
		var start_x := floori(float(index * source.get_width()) / 3.0)
		var end_x := ceili(float((index + 1) * source.get_width()) / 3.0)
		var left := end_x
		var right := -1
		var top := source.get_height()
		var bottom := -1
		for y in range(source.get_height()):
			for x in range(start_x, end_x):
				if source.get_pixel(x, y).a >= 0.8:
					left = mini(left, x)
					right = maxi(right, x)
					top = mini(top, y)
					bottom = maxi(bottom, y)
		if right < left or bottom < top:
			push_error("Cannot find dirt path stone %d" % (index + 1))
			quit(1)
			return
		var stone := source.get_region(Rect2i(left, top, right - left + 1, bottom - top + 1))
		stone.resize(STONE_SIZE.x, STONE_SIZE.y, Image.INTERPOLATE_NEAREST)
		for y in range(stone.get_height()):
			for x in range(stone.get_width()):
				var color := stone.get_pixel(x, y)
				var red_fringe := color.r > 0.78 and color.g < 0.40 and color.b < 0.30
				var yellow_fringe := color.r > 0.95 and color.g > 0.90 and color.b < 0.25
				if color.a < 0.82 or red_fringe or yellow_fringe:
					stone.set_pixel(x, y, Color.TRANSPARENT)
				else:
					# Blend only the dark recessed rim into the grass under the path.
					color.a = 0.55 if color.r < 0.55 and color.g < 0.45 else 1.0
					stone.set_pixel(x, y, color)
		var target_x := roundi(pitch * float(index) + (pitch - float(STONE_SIZE.x)) * 0.5)
		var target_y := (OUTPUT_SIZE.y - STONE_SIZE.y) / 2
		strip.blit_rect(stone, Rect2i(Vector2i.ZERO, STONE_SIZE), Vector2i(target_x, target_y))
	var error := strip.save_png(ProjectSettings.globalize_path(OUTPUT))
	if error != OK:
		push_error("Cannot save dirt path: " + OUTPUT)
		quit(1)
		return
	print("Saved dirt path tile ", OUTPUT, " at ", OUTPUT_SIZE)
	quit()
