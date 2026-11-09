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
	var state := root.get_node("GameState")
	state.reset_to_defaults(false)
	var farming := main.get_node("Systems/FarmingSystem") as FarmingSystem
	var jobs := main.get_node("Systems/JobManager") as JobManager
	var worker := main.get_node("StaticWorldStrip/DynamicAnchors/Worker") as WorkerActor
	worker.set_process(false)
	var now := int(Time.get_unix_time_from_system())
	if jobs.enqueue_command("plant", "5", ["wheat"]) < 0:
		_fail("Could not queue planting")
		return
	worker._sync_command()
	worker.global_position = worker.get("_destination")
	worker._move_to_command(0.0)
	worker._update_action_progress()
	if worker.animated_sprite.animation != &"up" or not worker.action_progress.visible:
		_fail("Worker must face up and show action progress while planting")
		return
	worker._execute_command(3.1)
	var plot: Dictionary = state.get_plot("5")
	if str(plot.get("crop", "")) != "wheat":
		_fail("Planting must complete after the work phase")
		return
	plot["planted_at"] = now - 1000
	plot["mature_at"] = now - 1
	var maturity: Dictionary = farming.refresh(now)
	if not maturity.get("mature_plots", []).has("5"):
		_fail("Mature plot must wait for a player harvest order")
		return
	jobs.enqueue_command("harvest", "5")
	var commands := jobs.get_pending_commands()
	if commands.size() != 1 or str(commands[0].get("action", "")) != "harvest":
		_fail("Player harvest order must enqueue one worker command")
		return
	worker._sync_command()
	worker.global_position = worker.get("_destination")
	worker._move_to_command(0.0)
	worker._update_action_progress()
	if worker.animated_sprite.animation != &"up" or not worker.action_progress.visible:
		_fail("Worker must face up and show action progress at the plot")
		return
	worker._execute_command(1.5)
	worker._update_action_progress()
	if absf(worker.action_progress.value - 50.0) > 1.0:
		_fail("Action progress must track the three-second work phase")
		return
	worker._execute_command(1.6)
	worker._update_action_progress()
	plot = state.get_plot("5")
	if not str(plot.get("crop", "")).is_empty() or int(state.get_item_count("wheat")) < 2 or worker.action_progress.visible:
		_fail("Harvest must finish after work and hide action progress")
		return
	print("WORKER_ACTION_TEST_OK")
	quit(0)


# 封装 fail 的处理，供相关流程复用。
func _fail(message: String) -> void:
	push_error(message)
	quit(1)
