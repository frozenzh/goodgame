# 定义 ShopSystem 的状态和可用操作。
class_name ShopSystem
extends Node

var _rng := RandomNumberGenerator.new()

## Explicit, low-frequency transactions. Fish never sell or become fertilizer
## without a UI call into this system.


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	_rng.randomize()
	_connect_bus("tick", Callable(self, "_on_tick"))


# 读取指定商店等级的栏位数和倍率范围，未指定时使用当前等级。
func get_level_data(level: int = 0) -> Dictionary:
	var state = _state()
	var actual: int = level if level > 0 else int(state.shop_level)
	var prefix := "level_%d_" % actual
	return {
		"offer_slots": GameConfig.get_int("shop", prefix + "offer_slots"),
		"multiplier_min": GameConfig.get_float("shop", prefix + "multiplier_min"),
		"multiplier_max": GameConfig.get_float("shop", prefix + "multiplier_max"),
	}


# 首次开启或报价到期时，从鱼类目录无放回抽取，栏位受商店等级和目录数量限制。
# now_unix 使用 Unix 秒数，传 0 时读取系统时间。新报价和到期时间一起存档。
func refresh_offers_if_due(now_unix: int = 0) -> void:
	var state = _state()
	var registry = _registry()
	if state == null or registry == null:
		return
	var now: int = now_unix if now_unix > 0 else int(Time.get_unix_time_from_system())
	if not state.shop_offers.is_empty() and now < int(state.shop_refresh_at):
		return
	var fish_ids: Array[String] = []
	for value in registry.get_all("fish"):
		if value is Dictionary:
			fish_ids.append(str(value.get("id", "")))
	fish_ids.shuffle()
	var level_data := get_level_data()
	var count := mini(fish_ids.size(), int(level_data.get("offer_slots", 3)))
	state.shop_offers = []
	for index in range(count):
		state.shop_offers.append({"fish_id": fish_ids[index], "multiplier": snappedf(_rng.randf_range(float(level_data.get("multiplier_min", 1.0)), float(level_data.get("multiplier_max", 1.0))), 0.1)})
	state.shop_refresh_at = now + maxi(1, int(GameConfig.get_float("shop", "refresh_hours") * 3600.0))
	_request_save()


# 计算单条鱼的出售价格，命中本轮高价收购时应用报价倍率。
func get_unit_price(fish_id: String) -> int:
	var registry = _registry()
	if registry == null:
		return 0
	var fish: Dictionary = registry.get_fish(fish_id)
	var base := maxi(0, int(fish.get("sell_price", 0)))
	var state = _state()
	if state != null:
		for value in state.shop_offers:
			if value is Dictionary and str(value.get("fish_id", "")) == fish_id:
				return int(ceil(float(base) * float(value.get("multiplier", 1.0))))
	return base


# 响应 tick 对应的事件或条件。
func _on_tick(now_unix: int, _delta_seconds: int) -> void:
	if is_unlocked():
		refresh_offers_if_due(now_unix)


# 判断是否满足 unlocked 对应的条件。
func is_unlocked() -> bool:
	var state: Variant = _state()
	return state != null and bool(state.shop_unlocked)


# 出售 fish，供调用方继续处理。
func sell_fish(fish_id: String, amount: int) -> int:
	var state: Variant = _state()
	var registry: Variant = _registry()
	if not is_unlocked() or registry == null or amount <= 0:
		return 0
	var owned: int = state.get_fish_count(fish_id)
	var sell_amount := mini(amount, owned)
	var fish: Dictionary = registry.get_fish(fish_id)
	if sell_amount <= 0 or fish.is_empty():
		return 0
	refresh_offers_if_due()
	var gained := sell_amount * get_unit_price(fish_id)
	if not state.remove_fish(fish_id, sell_amount):
		return 0
	DropService.grant_coins(gained, "shop")
	# 首次真实卖鱼后只自动开启一次；后续卖鱼不覆盖玩家手动关闭的偏好。
	if gained > 0 and not bool(state.flags.get("idle_auto_fish_first_sale_done", false)):
		state.flags["idle_auto_fish_first_sale_done"] = true
		state.settings["idle_auto_fish"] = true
		state.flags["fishing_manual_pause"] = false
	_emit("fish_sold", [fish_id, sell_amount, gained])
	_emit("achievement_action", [state.next_achievement_event_id(), "fish_sold", {"fish_id": fish_id, "amount": sell_amount, "coins": gained}])
	_request_save()
	return gained


# 出售 all_common，供调用方继续处理。
func sell_all_common() -> Dictionary:
	var state: Variant = _state()
	var registry: Variant = _registry()
	var result := {"coins": 0, "fish": {}}
	if not is_unlocked() or registry == null:
		return result
	for fish_id in state.fish_basket.keys().duplicate():
		var fish: Dictionary = registry.get_fish(str(fish_id))
		if str(fish.get("rarity", "common")).to_lower() != "common":
			continue
		var amount: int = state.get_fish_count(str(fish_id))
		var gained := sell_fish(str(fish_id), amount)
		if amount > 0:
			result["fish"][str(fish_id)] = amount
			result["coins"] = int(result["coins"]) + gained
	return result


# 出售 all_fish，供调用方继续处理。
func sell_all_fish() -> Dictionary:
	var state: Variant = _state()
	var result := {"coins": 0, "fish": {}}
	if not is_unlocked():
		return result
	for fish_id in state.fish_basket.keys().duplicate():
		var amount: int = state.get_fish_count(str(fish_id))
		var gained := sell_fish(str(fish_id), amount)
		if gained > 0:
			result["fish"][str(fish_id)] = amount
			result["coins"] = int(result["coins"]) + gained
	return result


# 出售 all_of_type，供调用方继续处理。
func sell_all_of_type(fish_id: String) -> int:
	var state: Variant = _state()
	return sell_fish(fish_id, state.get_fish_count(fish_id)) if state != null else 0


# 出售 pasture_product，供调用方继续处理。
func sell_pasture_product(product_id: String, amount: int) -> int:
	return _sell_inventory_item("pasture_products", product_id, amount)


# 出售 crop，供调用方继续处理。
func sell_crop(crop_id: String, amount: int) -> int:
	return _sell_inventory_item("crops", crop_id, amount)


# 出售 inventory_item，供调用方继续处理。
func _sell_inventory_item(category: String, item_id: String, amount: int) -> int:
	var state: Variant = _state()
	var registry: Variant = _registry()
	if not is_unlocked() or state == null or registry == null or amount <= 0:
		return 0
	var item: Dictionary = registry.get_entry(category, item_id)
	var price := int(item.get("sell_price", 0))
	if price <= 0:
		return 0
	var owned := int(state.inventory.get(item_id, 0))
	var sold := mini(amount, owned)
	if sold <= 0 or not state.consume_item(item_id, sold):
		return 0
	var gained := sold * price
	DropService.grant_coins(gained, "shop")
	_request_save()
	return gained


# 出售 all_pasture_products，供调用方继续处理。
func sell_all_pasture_products() -> int:
	return _sell_all_inventory_items("pasture_products")


# 出售 all_crops，供调用方继续处理。
func sell_all_crops() -> int:
	return _sell_all_inventory_items("crops")


# 出售 all_inventory_items，供调用方继续处理。
func _sell_all_inventory_items(category: String) -> int:
	var state: Variant = _state()
	var registry: Variant = _registry()
	if not is_unlocked() or state == null or registry == null:
		return 0
	var gained := 0
	for value in registry.get_all(category):
		var item: Dictionary = value
		var id := str(item.get("id", ""))
		gained += _sell_inventory_item(category, id, int(state.inventory.get(id, 0)))
	return gained


# 封装 buy_bait 的处理，供相关流程复用。
func buy_bait(shop_item_id: String, packs: int = 1) -> bool:
	var state: Variant = _state()
	var item := _resolve_shop_item(shop_item_id)
	if not is_unlocked() or state == null or item.is_empty() or packs <= 0:
		return false
	var item_type := str(item.get("item_type", "bait")).to_lower()
	if item_type != "bait" and item_type != "baits":
		return false
	var bait_id := str(item.get("item_id", item.get("bait_id", "")))
	var pack_amount := maxi(1, int(item.get("pack_amount", 1)))
	var total_price := maxi(0, int(item.get("buy_price", 0))) * packs
	if bait_id.is_empty() or not state.spend_coins(total_price):
		return false
	var amount := pack_amount * packs
	DropService.grant_item(bait_id, amount, "shop", "bait")
	_emit("bait_purchased", [bait_id, amount, total_price])
	_request_save()
	return true


# 封装 convert_fish_to_fertilizer 的处理，供相关流程复用。
func convert_fish_to_fertilizer(fish_id: String, amount: int) -> int:
	var state: Variant = _state()
	var registry: Variant = _registry()
	if state == null or registry == null or amount <= 0:
		return 0
	var fish: Dictionary = registry.get_fish(fish_id)
	var convert_amount := mini(amount, state.get_fish_count(fish_id))
	if fish.is_empty() or convert_amount <= 0:
		return 0
	var gained := convert_amount * maxi(0, int(fish.get("fertilizer_value", 1)))
	if not state.remove_fish(fish_id, convert_amount):
		return 0
	DropService.grant_fertilizer(gained, "shop")
	_emit("fish_converted_to_fertilizer", [fish_id, convert_amount, gained])
	_request_save()
	return gained


# 封装 convert_all_duplicates 的处理，供相关流程复用。
func convert_all_duplicates(keep_each: int = 1) -> Dictionary:
	var state: Variant = _state()
	var result := {"fertilizer": 0, "fish": {}}
	if state == null:
		return result
	for fish_id in state.fish_basket.keys().duplicate():
		var amount := maxi(0, state.get_fish_count(str(fish_id)) - maxi(0, keep_each))
		var gained := convert_fish_to_fertilizer(str(fish_id), amount)
		if gained > 0:
			result["fish"][str(fish_id)] = amount
			result["fertilizer"] = int(result["fertilizer"]) + gained
	return result


# 读取 shop_baits，供调用方继续处理。
func get_shop_baits() -> Array:
	var registry: Variant = _registry()
	if registry == null:
		return []
	var result: Array = []
	for value in registry.get_all("shop_items"):
		var item: Dictionary = value
		if str(item.get("item_type", "bait")).to_lower() in ["bait", "baits"]:
			result.append(item)
	return result


# 解析 shop_item，供调用方继续处理。
func _resolve_shop_item(item_id: String) -> Dictionary:
	var registry: Variant = _registry()
	if registry == null:
		return {}
	var item: Dictionary = registry.get_shop_item(item_id)
	if not item.is_empty():
		return item
	for value in registry.get_all("shop_items"):
		var candidate: Dictionary = value
		if str(candidate.get("item_id", candidate.get("bait_id", ""))) == item_id:
			return candidate
	return {}


# 封装 state 的处理，供相关流程复用。
func _state():
	return get_node_or_null("/root/GameState")


# 封装 registry 的处理，供相关流程复用。
func _registry():
	return get_node_or_null("/root/DataRegistry")


# 请求 save，供调用方继续处理。
func _request_save() -> void:
	var saver = get_node_or_null("/root/SaveManager")
	if saver != null:
		saver.request_save()


# 绑定 bus，供调用方继续处理。
func _connect_bus(signal_name: String, callable: Callable) -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus != null and bus.has_signal(signal_name) and not bus.is_connected(signal_name, callable):
		bus.connect(signal_name, callable)


# 封装 emit 的处理，供相关流程复用。
func _emit(signal_name: String, arguments: Array = []) -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus == null or not bus.has_signal(signal_name):
		return
	match arguments.size():
		0: bus.emit_signal(signal_name)
		1: bus.emit_signal(signal_name, arguments[0])
		2: bus.emit_signal(signal_name, arguments[0], arguments[1])
		3: bus.emit_signal(signal_name, arguments[0], arguments[1], arguments[2])
