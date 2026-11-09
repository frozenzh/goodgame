extends Node

## Runtime tuning exported from excel/*.xlsx. Export before starting the game.
const CONFIG_DIR := "res://data/config"
const MODULES := ["worker", "fishing", "farming", "random_events", "time_save", "ui", "shop", "weather", "pasture"]

var _modules: Dictionary = {}


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	reload()


# 封装 reload 的处理，供相关流程复用。
func reload() -> bool:
	_modules.clear()
	var valid := true
	for module_name in MODULES:
		var path := CONFIG_DIR.path_join(module_name + ".json")
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			push_error(TextDB.text("ui.1569aae4fa") % path)
			valid = false
			continue
		var document: Variant = JSON.parse_string(file.get_as_text())
		if not document is Dictionary or not document.get("values") is Dictionary:
			push_error(TextDB.text("ui.d9d75f3400") % path)
			valid = false
			continue
		_modules[module_name] = document["values"]
	return valid


# 读取 value，供调用方继续处理。
func get_value(module_name: String, key: String) -> Variant:
	var entries: Dictionary = _modules.get(module_name, {})
	if not entries.has(key):
		push_error(TextDB.text("ui.1ea612df81") % [module_name, key])
		return null
	return entries[key]


# 读取 float，供调用方继续处理。
func get_float(module_name: String, key: String) -> float:
	return float(get_value(module_name, key))


# 读取 int，供调用方继续处理。
func get_int(module_name: String, key: String) -> int:
	return int(get_value(module_name, key))
