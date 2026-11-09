extends SceneTree

## Exercises the real Main UI without saving to the player's file.


# 封装 initialize 的处理，供相关流程复用。
func _initialize() -> void:
	call_deferred("_run")


# 封装 run 的处理，供相关流程复用。
func _run() -> void:
	var saver := root.get_node("SaveManager")
	(saver.get_node("AutosaveTimer") as Timer).stop()
	(saver.get_node("SaveDebounceTimer") as Timer).stop()
	var packed := load("res://scenes/main/Main.tscn") as PackedScene
	var main := packed.instantiate() as Control
	root.add_child(main)
	(saver.get_node("AutosaveTimer") as Timer).stop()
	(saver.get_node("SaveDebounceTimer") as Timer).stop()
	var toast := main.get_node("AchievementToast") as PanelContainer
	var names := toast.get_node("Content/Text/Names") as Label
	var title := toast.get_node("Content/Text/Title") as Label
	var failures: Array[String] = []
	var first: Array[String] = ["ACH_FIRST_HARVEST"]
	root.get_node("EventBus").emit_signal("achievements_unlocked", first, false)
	if not toast.visible or names.text != "第一捧麦香" or title.text != "成就达成":
		failures.append("unlock signal did not show the pond achievement bar")
	if toast.position.x < 900.0 or toast.z_index <= 20:
		failures.append("achievement bar is not above the pond UI layer")
	var second: Array[String] = ["ACH_FIRST_BAIT"]
	root.get_node("EventBus").emit_signal("achievements_unlocked", second, false)
	if (main.get("_achievement_toast_queue") as Array).size() != 1:
		failures.append("a second unlock should wait instead of replacing the first")
	(toast.get_node("Timer") as Timer).stop()
	main.call("_show_next_achievement_toast")
	if names.text != "自己做的才香":
		failures.append("queued achievement was not displayed")
	(saver.get_node("SaveDebounceTimer") as Timer).stop()
	if failures.is_empty():
		print("ACHIEVEMENT_TOAST_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
