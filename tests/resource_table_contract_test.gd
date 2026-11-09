extends SceneTree

## Confirms that the Excel-exported catalog paths resolve in Godot.


# 封装 initialize 的处理，供相关流程复用。
func _initialize() -> void:
	call_deferred("_run")


# 封装 run 的处理，供相关流程复用。
func _run() -> void:
	var registry := root.get_node("DataRegistry")
	var errors: Array[String] = []
	var fields := {
		"crops": ["seed_resource", "leaf_resource", "mature_resource", "icon_resource"],
		"fish": ["icon_resource"],
		"baits": ["icon_resource"],
		"rods": ["icon_resource"],
		"achievements": ["icon_locked", "icon_unlocked"],
	}
	for category in fields:
		for entry_value in registry.get_all(category):
			var entry: Dictionary = entry_value
			for field in fields[category]:
				var path := str(entry.get(field, ""))
				if not ResourceLoader.exists(path) or not load(path) is Texture2D:
					errors.append("%s/%s: %s" % [category, str(entry.get("id", "")), field])
	for bait_value in registry.get_all("baits"):
		if str(bait_value.get("icon_resource", "")) != "res://assets/hd/ui/icon_bait_simple.png":
			errors.append("bait still references a crop image: " + str(bait_value.get("id", "")))
	if errors.is_empty():
		print("RESOURCE_TABLE_CONTRACT_OK")
		quit(0)
	else:
		for error in errors:
			push_error(error)
		quit(1)
