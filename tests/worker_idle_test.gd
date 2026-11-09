extends SceneTree


# 封装 initialize 的处理，供相关流程复用。
func _initialize() -> void:
	call_deferred("_run")


# 封装 run 的处理，供相关流程复用。
func _run() -> void:
	var scene := load("res://scenes/main/Main.tscn") as PackedScene
	var main := scene.instantiate()
	root.add_child(main)
	await process_frame
	var worker := main.get_node("StaticWorldStrip/DynamicAnchors/Worker") as WorkerActor
	worker.set_physics_process(false)
	var frames := worker.animated_sprite.sprite_frames
	var names: Array[StringName] = [&"idle_hat", &"idle_yawn", &"idle_scratch"]
	var expected_counts := [8, 12, 12]
	for index in range(names.size()):
		var animation: StringName = names[index]
		if not frames.has_animation(animation) or frames.get_frame_count(animation) != expected_counts[index] or frames.get_animation_loop(animation):
			_fail("Idle animation is missing frames or must not loop: %s" % animation)
			return
		for frame_index in range(frames.get_frame_count(animation)):
			var texture := frames.get_frame_texture(animation, frame_index)
			if texture == null or texture.get_size() != Vector2(1024, 1024):
				_fail("Idle frame must use the shared 1024 px canvas")
				return
			var used := texture.get_image().get_used_rect()
			if used.end.y != 940:
				_fail("Idle frame feet are not on the common baseline")
				return
	worker._random.seed = 42
	var seen := {&"idle_hat": 0, &"idle_yawn": 0, &"idle_scratch": 0}
	for _index in range(100):
		worker._begin_rest()
		if worker.animated_sprite.is_playing():
			var selected: StringName = worker.animated_sprite.animation
			if seen.has(selected):
				seen[selected] = int(seen[selected]) + 1
	for animation in names:
		if int(seen[animation]) <= 0:
			_fail("The idle randomizer never selected %s" % animation)
			return
	print("WORKER_IDLE_TEST_OK")
	quit(0)


# 封装 fail 的处理，供相关流程复用。
func _fail(message: String) -> void:
	push_error(message)
	quit(1)
