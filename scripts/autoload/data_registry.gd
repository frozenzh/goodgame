extends Node

## Loads loose JSON catalogs from res://data/catalog. The loader accepts either
## arrays, id-keyed dictionaries, or {"items": [...]} wrappers.

const CATALOG_DIR := "res://data/catalog"
const CATEGORIES := [
	"crops", "fish", "baits", "recipes", "upgrades", "rods",
	"shop_items", "pasture_products", "events", "plots", "codex_milestones", "fertility_levels", "cottage_levels", "achievements"
]

var catalogs: Dictionary = {}
var documents: Dictionary = {}
var load_errors: Array = []
var is_loaded := false


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	reload_catalogs()


# 封装 reload_catalogs 的处理，供相关流程复用。
func reload_catalogs() -> bool:
	catalogs.clear()
	documents.clear()
	load_errors.clear()
	for category in CATEGORIES:
		catalogs[category] = {}

	var directory := DirAccess.open(CATALOG_DIR)
	if directory == null:
		load_errors.append("Catalog directory not found: %s" % CATALOG_DIR)
		is_loaded = true
		return false

	directory.list_dir_begin()
	var file_name := directory.get_next()
	while file_name != "":
		if not directory.current_is_dir() and file_name.get_extension().to_lower() == "json":
			_load_catalog_file(CATALOG_DIR.path_join(file_name), file_name.get_basename())
		file_name = directory.get_next()
	directory.list_dir_end()
	is_loaded = true
	return load_errors.is_empty()


# 读取 entry，供调用方继续处理。
func get_entry(category: String, entry_id: String) -> Dictionary:
	var normalized := _normalize_category(category)
	var bucket: Dictionary = catalogs.get(normalized, {})
	var value = bucket.get(entry_id, {})
	return _localized_entry(normalized, value) if value is Dictionary else {}


# 读取 all，供调用方继续处理。
func get_all(category: String) -> Array:
	var normalized := _normalize_category(category)
	var bucket: Dictionary = catalogs.get(normalized, {})
	var result: Array = []
	for value in bucket.values():
		if value is Dictionary:
			result.append(_localized_entry(normalized, value))
	return result


# 封装 localized_entry 的处理，供相关流程复用。
func _localized_entry(category: String, value: Dictionary) -> Dictionary:
	var entry := value.duplicate(true)
	var entry_id := str(entry.get("id", ""))
	for field in ["display_name", "name", "description"]:
		if entry.has(field):
			var key := "catalog.%s.%s.%s" % [category, entry_id, field]
			if TextDB.has_id(key):
				entry[field] = TextDB.text(key)
	return entry


# 判断是否具有 entry 对应的条件。
func has_entry(category: String, entry_id: String) -> bool:
	return not get_entry(category, entry_id).is_empty()


# 读取 document，供调用方继续处理。
func get_document(document_id: String) -> Dictionary:
	var value = documents.get(_normalize_category(document_id), {})
	return value if value is Dictionary else {}


# 读取 crop，供调用方继续处理。
func get_crop(crop_id: String) -> Dictionary:
	return get_entry("crops", crop_id)


# 读取 fish，供调用方继续处理。
func get_fish(fish_id: String) -> Dictionary:
	return get_entry("fish", fish_id)


# 读取 bait，供调用方继续处理。
func get_bait(bait_id: String) -> Dictionary:
	return get_entry("baits", bait_id)


# 读取 recipe，供调用方继续处理。
func get_recipe(recipe_id: String) -> Dictionary:
	var recipe := get_entry("recipes", recipe_id)
	if recipe.is_empty():
		recipe = get_bait(recipe_id)
	return recipe


# 读取 rod，供调用方继续处理。
func get_rod(rod_id: String) -> Dictionary:
	return get_entry("rods", rod_id)


# 读取 shop_item，供调用方继续处理。
func get_shop_item(item_id: String) -> Dictionary:
	return get_entry("shop_items", item_id)


# 加载 catalog_file，供调用方继续处理。
func _load_catalog_file(path: String, fallback_category: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		load_errors.append("Cannot read catalog: %s" % path)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed == null:
		load_errors.append("Invalid JSON: %s" % path)
		return

	var category := _normalize_category(fallback_category)
	var entries: Array = []
	if parsed is Array:
		entries = parsed
	elif parsed is Dictionary:
		var wrapper: Dictionary = parsed
		category = _normalize_category(str(wrapper.get("catalog_type", wrapper.get("category", wrapper.get("type", category)))))
		documents[category] = wrapper.duplicate(true)
		_index_embedded_catalogs(wrapper)
		if wrapper.get("items") is Array:
			entries = wrapper["items"]
		elif wrapper.get("entries") is Array:
			entries = wrapper["entries"]
		else:
			for key in wrapper:
				var value = wrapper[key]
				if value is Dictionary:
					var entry: Dictionary = value.duplicate(true)
					if not entry.has("id"):
						entry["id"] = str(key)
					entries.append(entry)

	if not catalogs.has(category):
		catalogs[category] = {}
	var bucket: Dictionary = catalogs[category]
	for value in entries:
		if not value is Dictionary:
			continue
		var entry: Dictionary = value
		var entry_id := str(entry.get("id", ""))
		if entry_id.is_empty():
			load_errors.append("Entry without id in %s" % path)
			continue
		bucket[entry_id] = entry


# 封装 index_embedded_catalogs 的处理，供相关流程复用。
func _index_embedded_catalogs(wrapper: Dictionary) -> void:
	for category in ["rods", "codex_milestones", "fertility_levels"]:
		var values = wrapper.get(category, [])
		if not values is Array:
			continue
		if not catalogs.has(category):
			catalogs[category] = {}
		var bucket: Dictionary = catalogs[category]
		for index in range(values.size()):
			if not values[index] is Dictionary:
				continue
			var entry: Dictionary = values[index]
			var fallback_id = entry.get("fish_count", entry.get("level", index))
			var entry_id := str(entry.get("id", fallback_id))
			bucket[entry_id] = entry


# 规范化 category，供调用方继续处理。
func _normalize_category(value: String) -> String:
	var category := value.to_lower().replace("-", "_")
	var aliases := {
		"crop": "crops", "fish_data": "fish", "fishes": "fish",
		"bait": "baits", "recipe": "recipes", "upgrade": "upgrades",
		"rod": "rods", "shop": "shop_items", "shop_item": "shop_items",
		"random_events": "events", "event": "events", "plot": "plots"
	}
	return str(aliases.get(category, category))
