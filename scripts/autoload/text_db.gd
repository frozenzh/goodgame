extends Node

## Player-facing text comes from excel/文本.xlsx via data/text/texts.json.
## Scene metadata keeps the Chinese preview editable in the Godot editor.

signal language_changed(language: String)

const TEXT_PATH := "res://data/text/texts.json"
const LANGUAGE_PATH := "user://language.txt"
const LOCALIZED_PROPERTIES := ["text", "placeholder_text", "tooltip_text", "title"]

var language := "zh"
var _entries: Dictionary = {}
var _missing: Dictionary = {}


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	var file := FileAccess.open(TEXT_PATH, FileAccess.READ)
	if file == null:
		push_error("Missing text export: " + TEXT_PATH)
	else:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			_entries = parsed
		else:
			push_error("Invalid text export: " + TEXT_PATH)
	var saved := FileAccess.open(LANGUAGE_PATH, FileAccess.READ)
	if saved != null and saved.get_as_text().strip_edges() == "en":
		language = "en"
	get_tree().node_added.connect(_on_node_added)


# 封装 text 的处理，供相关流程复用。
func text(id: String, fallback: String = "") -> String:
	var entry: Variant = _entries.get(id)
	if entry is Dictionary:
		return str(entry.get(language, entry.get("zh", fallback)))
	if not _missing.has(id):
		_missing[id] = true
		push_warning("Missing text ID: " + id)
	return fallback if not fallback.is_empty() else id


# 判断是否具有 id 对应的条件。
func has_id(id: String) -> bool:
	return _entries.has(id)


# 设置 language，供调用方继续处理。
func set_language(value: String) -> void:
	if value not in ["zh", "en"] or value == language:
		return
	language = value
	var file := FileAccess.open(LANGUAGE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(language)
	_apply_tree(get_tree().root)
	language_changed.emit(language)


# 响应 node_added 对应的事件或条件。
func _on_node_added(node: Node) -> void:
	_apply_node(node)


# 应用 tree，供调用方继续处理。
func _apply_tree(node: Node) -> void:
	_apply_node(node)
	for child in node.get_children():
		_apply_tree(child)


# 应用 node，供调用方继续处理。
func _apply_node(node: Node) -> void:
	for property_name in LOCALIZED_PROPERTIES:
		var meta_key: String = "l10n_" + str(property_name)
		if node.has_meta(meta_key):
			node.set(property_name, text(str(node.get_meta(meta_key))))
