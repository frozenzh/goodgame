extends SceneTree


# 封装 initialize 的处理，供相关流程复用。
func _initialize() -> void:
	call_deferred("_run")


# 封装 run 的处理，供相关流程复用。
func _run() -> void:
	var errors: Array[String] = []
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/catalog/achievements.json"))
	var entries: Array = catalog.get("items", [])
	if entries.size() != 12:
		errors.append("achievement catalog must have 12 entries")
	for entry_value in entries:
		var entry: Dictionary = entry_value
		for key in ["icon_locked", "icon_unlocked"]:
			var path := str(entry.get(key, ""))
			if not ResourceLoader.exists(path):
				errors.append("missing icon: " + path)
			continue
			var texture := load(path) as Texture2D
			if texture == null or texture.get_size() != Vector2(256, 256):
				errors.append("invalid icon size: " + path)
	var content_scene := load("res://scenes/ui/CodexContent.tscn") as PackedScene
	if content_scene == null:
		errors.append("CodexContent does not load")
	else:
		var content := content_scene.instantiate() as Control
		root.add_child(content)
		var page := content.get_node_or_null("AchievementPage") as ScrollContainer
		var menu := content.get_node_or_null("PrimaryMenu/AchievementTab") as Button
		if page == null or menu == null:
			errors.append("achievement page or menu is missing")
		else:
			var list := page.get_node("List") as VBoxContainer
			for index in range(1, 13):
				var card := list.get_node_or_null("Slot%02d" % index) as PanelContainer
				if card == null or not card.has_node("Content/Icon") or not card.has_node("Content/Details/ProgressRow/Progress") or not card.has_node("ClickArea"):
					errors.append("static achievement card %d is incomplete" % index)
		content.queue_free()
	if errors.is_empty():
		print("ACHIEVEMENT_SCENE_OK")
		quit(0)
	else:
		for error in errors:
			push_error(error)
		quit(1)
