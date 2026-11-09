extends SceneTree


# 封装 initialize 的处理，供相关流程复用。
func _initialize() -> void:
	call_deferred("_capture")


# 封装 capture 的处理，供相关流程复用。
func _capture() -> void:
	var packed: PackedScene = load("res://scenes/main/Main.tscn")
	if packed == null:
		push_error("Unable to load main scene")
		quit(1)
		return
	var main: Node = packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await process_frame
	var state: Node = root.get_node("GameState")
	state.reset_to_defaults(false)
	main.call("_close_modal")
	main.call("_refresh")
	root.size = Vector2i(1280, 168)
	await process_frame
	main.call("_layout_overlays")
	await process_frame
	RenderingServer.force_draw(true)
	await process_frame
	var image := root.get_texture().get_image()
	var error := image.save_png("res://tests/ui_preview.png")
	if error != OK:
		push_error("Unable to save UI preview: %s" % error)
		quit(1)
		return
	print("UI_PREVIEW_OK")
	quit(0)
