extends SceneTree

## Read-only smoke check: verifies the exported config autoload and actor scene.
func _initialize() -> void:
	call_deferred("_check")


# 封装 check 的处理，供相关流程复用。
func _check() -> void:
	var config := root.get_node_or_null("GameConfig")
	if config == null:
		push_error("GameConfig autoload is missing")
		quit(1)
		return
	var expected := {"worker": "move_speed", "fishing": "cast_min_seconds", "farming": "max_fertility", "random_events": "delay_min_seconds", "time_save": "offline_cap_seconds", "ui": "toast_seconds"}
	for module_name in expected:
		var value: Variant = config.get_value(module_name, expected[module_name])
		if value == null:
			push_error("Missing exported value: %s.%s" % [module_name, expected[module_name]])
			quit(1)
			return
	print("Config loaded: worker.move_speed=", config.get_float("worker", "move_speed"), ", fishing.cast_min_seconds=", config.get_int("fishing", "cast_min_seconds"))
	quit(0)
