extends Node

# 用无视觉和无磁盘写入的牧场验证生产、领取与寿命边界。
class TestPasture extends PastureManager:
	func _ready() -> void:
		pass
	func _save() -> void:
		pass
	func _rebuild_sprites() -> void:
		pass
	func _update_dog(_delta: float) -> void:
		pass


# 延后到自动加载完成后执行，测试进程不写玩家存档。
func _ready() -> void:
	call_deferred("_run")


# 覆盖待收获不入库、重复领取、售卖、寿命到期及旧数据兼容。
func _run() -> void:
	var root := get_tree().root
	var state = root.get_node("GameState")
	root.get_node("SaveManager").set_process(false)
	state.cottage_level = 4
	state.inventory = {}
	state.flags = {}
	var pasture := TestPasture.new()
	root.add_child(pasture)
	pasture._animals.append({"id": 1, "type": "chicken", "area": 3, "hunger": 0, "productive_seconds": 599.9})
	pasture._process(0.2)
	assert(pasture.get_pending_products().get("egg", 0) == 1)
	assert(state.get_item_count("egg") == 0)
	assert(pasture.harvest_products() == 1)
	assert(state.get_item_count("egg") == 1)
	assert(pasture.harvest_products() == 0)
	var shop := ShopSystem.new()
	root.add_child(shop)
	assert(shop.sell_pasture_product("egg", 1) == 12)
	assert(state.get_item_count("egg") == 0)
	state.flags["pasture_pending_products"] = {"milk": 2}
	pasture._animals[0]["age_seconds"] = pasture.get_lifetime_hours("chicken") * 3600.0 - 0.1
	pasture._process(0.2)
	assert(pasture._animals.is_empty())
	assert(pasture.get_pending_products().get("milk") == 2)
	var window := load("res://scenes/ui/PastureWindow.tscn").instantiate() as Window
	root.add_child(window)
	assert(window.get_node("PasturePopup/ContentSurface/HarvestRow").get_child_count() == 5)
	print("PASTURE_HARVEST_OK")
	get_tree().quit()
