# 定义 PastureManager 的状态和可用操作。
class_name PastureManager
extends Node2D

const ANIMAL_ARTS := {
	"chicken": preload("res://assets/hd/world/pasture_chicken_4dir_8.png"),
	"pig": preload("res://assets/hd/world/pasture_pig_4dir_8.png"),
	"sheep": preload("res://assets/hd/world/pasture_sheep_4dir_8.png"),
	"cow": preload("res://assets/hd/world/pasture_cow_4dir_8.png"),
	"dog": preload("res://assets/hd/world/pasture_dog_walk_8.png"),
}
const SLEEP_ART := preload("res://assets/hd/world/pasture_dog_sleep.png")
const FOOT_SHADOW := preload("res://scenes/world/AnimalFootShadow.tscn")
const TYPES := ["chicken", "pig", "sheep", "cow"]
const NAMES := {"chicken": "ui.88b9eae481", "pig": "ui.c3095b7c23", "sheep": "ui.3b3f2d6a40", "cow": "ui.06c95e6b4b"}
const FRAME_COUNT := 8
const FEED_SLOT_COUNT := 1

var _animals: Array[Dictionary] = []
var _sprites: Dictionary = {}
var _walk_targets: Dictionary = {}
var _walk_speeds: Dictionary = {}
var _eat_pauses: Dictionary = {}
var _frame_cache: Dictionary = {}
var _feed_slots: Dictionary = {}
var _dragged_id := -1
var _drag_origin: Dictionary = {}
var _frame_time := 0.0
var _frame_index := 0
var _hunger_time := 0.0
var _dog_time := 0.0
var _dog_sleeping := true
var _dog_target := Vector2(39, 194)


# 封装 cfg_int 的处理，供相关流程复用。
func _cfg_int(key: String) -> int:
	return int(get_node("/root/GameConfig").call("get_int", "pasture", key))


# 封装 cfg_float 的处理，供相关流程复用。
func _cfg_float(key: String) -> float:
	return float(get_node("/root/GameConfig").call("get_float", "pasture", key))


# 读取 price，供调用方继续处理。
func get_price(kind: String) -> int:
	return _cfg_int("%s_price" % kind)


# 读取 pen_capacity，供调用方继续处理。
func get_pen_capacity() -> int:
	return _cfg_int("max_animals_per_pen")


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	_load_animals()
	_load_feed_slots()
	$AutoFeedCheck.timeout.connect(_try_auto_feed)
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.connect("cottage_upgrade_completed", Callable(self, "_on_cottage_upgrade_completed"))
		bus.connect("game_reset", Callable(self, "_on_game_reset"))
		bus.connect("game_loaded", Callable(self, "_on_game_loaded"))
	_refresh_building()
	_rebuild_sprites()
	_refresh_all_feed_slots()


# 响应 cottage_upgrade_completed 对应的事件或条件。
func _on_cottage_upgrade_completed(_level: int) -> void:
	_refresh_building()
	_save()


# 响应 game_reset 对应的事件或条件。
func _on_game_reset() -> void:
	_animals.clear()
	_feed_slots.clear()
	_load_feed_slots()
	_rebuild_sprites()
	_refresh_building()
	_refresh_all_feed_slots()


# 响应 game_loaded 对应的事件或条件。
func _on_game_loaded() -> void:
	_load_animals()
	_load_feed_slots()
	_rebuild_sprites()
	_refresh_building()
	_refresh_all_feed_slots()


# 判断是否满足 unlocked 对应的条件。
func is_unlocked() -> bool:
	var state := get_node_or_null("/root/GameState")
	return state != null and int(state.cottage_level) >= 4


# 小屋达到四级时用牧场房替换工地，同时启用牧场设施。
func _refresh_building() -> void:
	var built := is_unlocked()
	$PastureBarn/BarnSprite.visible = built
	$PastureBarn/ConstructionOverlay.visible = not built
	$Dog.visible = built
	var road := get_node_or_null("../PathLayer/PastureSegments") as Node2D
	if road != null:
		road.visible = built
	for area_id in [3, 4]:
		_refresh_alert(area_id)
		var area := _area(area_id)
		if area == null:
			continue
		var animals := area.get_node_or_null("Animals") as Node2D
		if animals != null:
			animals.visible = built
		var slots := area.get_node_or_null("FeedSlots") as Node2D
		if slots != null:
			slots.visible = built


# 根据当前显示的牧场贴图检测点击；point 为世界坐标。
func hit_test_barn(point: Vector2) -> bool:
	var sprite: Sprite2D = $PastureBarn/BarnSprite if is_unlocked() else $PastureBarn/ConstructionOverlay
	return sprite.is_visible_in_tree() and sprite.is_pixel_opaque(sprite.to_local(point))


# 封装 buy_animal 的处理，供相关流程复用。
func buy_animal(kind: String, area_id: int) -> bool:
	if not is_unlocked() or kind not in TYPES or _animal_count(area_id) >= get_pen_capacity():
		return false
	var state := get_node_or_null("/root/GameState")
	if state == null or not state.spend_coins(get_price(kind)):
		return false
	var id := int(state.flags.get("pasture_serial", 0)) + 1
	state.flags["pasture_serial"] = id
	var record: Dictionary = {"id": id, "type": kind, "area": area_id, "x": randf_range(-70, 70), "y": randf_range(125, 175), "hunger": 0, "productive_seconds": 0.0}
	_animals.append(record)
	_rebuild_sprites()
	_save()
	return true


# 封装 hit_test_feed_slot 的处理，供相关流程复用。
func hit_test_feed_slot(point: Vector2) -> Dictionary:
	if not is_unlocked():
		return {}
	for area_id in [3, 4]:
		var area := _area(area_id)
		var trough := area.get_node_or_null("FeedSlots/Trough") as Sprite2D if area != null else null
		if trough != null and trough.is_visible_in_tree() and trough.is_pixel_opaque(trough.to_local(point)):
			return {"area": area_id, "slot": 0}
	return {}


# 读取 food_slot_summary，供调用方继续处理。
func get_food_slot_summary(area_id: int, slot_index: int) -> Dictionary:
	var slot := _feed_slot_data(area_id, slot_index)
	var queue: Array = slot.get("queue", [])
	var count := 0
	for lot in queue:
		if lot is Dictionary:
			count += maxi(0, int(lot.get("count", 0)))
	var first_crop := str((queue[0] as Dictionary).get("crop", "")) if not queue.is_empty() else ""
	return {"crop": first_crop, "count": count}


# 读取 max_feed_quantity，供调用方继续处理。
func get_max_feed_quantity(crop_id: String) -> int:
	var state := get_node_or_null("/root/GameState")
	var registry := get_node_or_null("/root/DataRegistry")
	if state == null or registry == null or registry.get_crop(crop_id).is_empty():
		return 0
	return maxi(0, int(state.inventory.get(crop_id, 0)) / maxi(1, _cfg_int("feed_crop_count")))


# 请求 feed_crop，供调用方继续处理。
func request_feed_crop(area_id: int, slot_index: int, crop_id: String, quantity: int = 1) -> bool:
	if not is_unlocked() or area_id not in [3, 4] or slot_index < 0 or slot_index >= FEED_SLOT_COUNT:
		return false
	if quantity < 1 or quantity > get_max_feed_quantity(crop_id):
		return false
	var jobs := get_tree().root.find_child("JobManager", true, false) as JobManager
	return jobs != null and jobs.enqueue_command("feed_pasture", "%d:%d" % [area_id, slot_index], [crop_id, quantity], TextDB.text("ui.6c0980870c"), TextDB.text("ui.b0a4ebbb3e")) > 0


# 尝试执行 auto_feed，供调用方继续处理。
func _try_auto_feed() -> void:
	if not is_unlocked():
		return
	var jobs := get_tree().root.find_child("JobManager", true, false) as JobManager
	if jobs == null or not jobs.get_pending_commands().is_empty():
		return
	var state := get_node_or_null("/root/GameState")
	var registry := get_node_or_null("/root/DataRegistry")
	if state == null or registry == null:
		return
	var crop_id := ""
	var most_stock := 0
	var required := maxi(1, _cfg_int("feed_crop_count"))
	for crop_value in registry.get_all("crops"):
		var crop: Dictionary = crop_value
		var candidate := str(crop.get("id", ""))
		var stocked := int(state.inventory.get(candidate, 0))
		if stocked >= required and stocked > most_stock:
			crop_id = candidate
			most_stock = stocked
	if crop_id.is_empty():
		return
	for area_id in [3, 4]:
		if _animal_count(area_id) > 0 and int(get_food_slot_summary(area_id, 0).get("count", 0)) <= 0:
			request_feed_crop(area_id, 0, crop_id)
			return


# 添加 food_from_command，供调用方继续处理。
func add_food_from_command(area_id: int, slot_index: int, crop_id: String, quantity: int = 1) -> bool:
	if not is_unlocked() or area_id not in [3, 4]:
		return false
	# Older saves may still contain queued orders for the former second or third slot.
	slot_index = 0
	var state := get_node_or_null("/root/GameState")
	if quantity < 1 or state == null or not state.consume_item(crop_id, maxi(1, _cfg_int("feed_crop_count")) * quantity):
		return false
	var slot := _feed_slot_data(area_id, slot_index)
	var queue: Array = slot.get("queue", [])
	queue.append({"crop": crop_id, "count": maxi(1, _cfg_int("food_per_crop")) * quantity})
	slot["queue"] = queue
	_refresh_feed_slot_visual(area_id, slot_index)
	_refresh_alert(area_id)
	_save()
	return true


# 加载 feed_slots，供调用方继续处理。
func _load_feed_slots() -> void:
	var state := get_node_or_null("/root/GameState")
	var saved: Dictionary = state.flags.get("pasture_feed_slots", {}) if state != null else {}
	var old_food: Dictionary = state.flags.get("pasture_food", {}) if state != null else {}
	for area_id in [3, 4]:
		var saved_slots: Array = saved.get(str(area_id), [])
		var queue: Array = []
		for raw_value in saved_slots:
			var raw: Dictionary = raw_value if raw_value is Dictionary else {}
			var raw_queue: Array = raw.get("queue", [])
			for lot in raw_queue:
				if lot is Dictionary and int(lot.get("count", 0)) > 0:
					queue.append({"crop": str(lot.get("crop", "")), "count": int(lot.get("count", 0))})
		if queue.is_empty() and saved_slots.is_empty() and int(old_food.get(str(area_id), 0)) > 0:
			queue.append({"crop": "", "count": int(old_food[str(area_id)])})
		_feed_slots[str(area_id)] = [{"queue": queue}]


# 封装 feed_slot_data 的处理，供相关流程复用。
func _feed_slot_data(area_id: int, slot_index: int) -> Dictionary:
	var slots: Array = _feed_slots.get(str(area_id), [])
	if slot_index < 0 or slot_index >= slots.size():
		return {}
	return slots[slot_index] as Dictionary


# 封装 feed_slot 的处理，供相关流程复用。
func _feed_slot(area_id: int, slot_index: int) -> Node2D:
	var area := _area(area_id)
	return area.get_node_or_null("FeedSlots/Slot%d" % (slot_index + 1)) as Node2D if area != null else null


# 刷新 all_feed_slots，供调用方继续处理。
func _refresh_all_feed_slots() -> void:
	for area_id in [3, 4]:
		for slot_index in range(FEED_SLOT_COUNT):
			_refresh_feed_slot_visual(area_id, slot_index)


# 刷新 feed_slot_visual，供调用方继续处理。
func _refresh_feed_slot_visual(area_id: int, slot_index: int) -> void:
	var slot_node := _feed_slot(area_id, slot_index)
	if slot_node == null:
		return
	var summary := get_food_slot_summary(area_id, slot_index)
	var count := int(summary.get("count", 0))
	var count_label := slot_node.get_node("Count") as Label
	count_label.visible = count > 0
	count_label.text = str(count)
	var icon := slot_node.get_node("FoodIcon") as Sprite2D
	var registry := get_node_or_null("/root/DataRegistry")
	var crop: Dictionary = registry.get_crop(str(summary.get("crop", ""))) if registry != null else {}
	var icon_path := str(crop.get("icon_resource", ""))
	icon.visible = count > 0 and ResourceLoader.exists(icon_path)
	if icon.visible:
		icon.texture = load(icon_path) as Texture2D
		var size := icon.texture.get_size()
		icon.scale = Vector2(14.0 / maxf(size.x, 1.0), 14.0 / maxf(size.y, 1.0))


# 封装 begin_drag 的处理，供相关流程复用。
func begin_drag(point: Vector2) -> bool:
	if not is_unlocked():
		return false
	for animal in _animals:
		var id := int(animal["id"])
		var sprite := _sprites.get(id) as Sprite2D
		if sprite != null and sprite.is_pixel_opaque(sprite.to_local(point)):
			_dragged_id = id
			_drag_origin = animal.duplicate(true)
			return true
	return false


# 判断是否满足 dragging 对应的条件。
func is_dragging() -> bool:
	return _dragged_id >= 0


# 封装 drag_to 的处理，供相关流程复用。
func drag_to(point: Vector2) -> void:
	if _dragged_id < 0:
		return
	var sprite := _sprites.get(_dragged_id) as Sprite2D
	if sprite != null:
		sprite.global_position = point


# 封装 end_drag 的处理，供相关流程复用。
func end_drag(point: Vector2) -> void:
	if _dragged_id < 0:
		return
	var target_area := _area_at(point)
	for animal in _animals:
		if int(animal["id"]) != _dragged_id:
			continue
		if target_area in [3, 4] and (target_area == int(animal["area"]) or _animal_count(target_area) < get_pen_capacity()):
			var area := _area(target_area)
			var local := area.to_local(point)
			animal["area"] = target_area
			animal["x"] = clampf(local.x, -94.0, 94.0)
			animal["y"] = clampf(local.y, 119.0, 185.0)
		else:
			animal.merge(_drag_origin, true)
		break
	_dragged_id = -1
	_drag_origin.clear()
	_rebuild_sprites()
	_save()


# 封装 area_at 的处理，供相关流程复用。
func _area_at(point: Vector2) -> int:
	for id in [3, 4]:
		var area := _area(id)
		if area != null:
			var local := area.to_local(point)
			if absf(local.x) <= 104.0 and local.y >= 111.0 and local.y <= 192.0:
				return id
	return -1


# 封装 area 的处理，供相关流程复用。
func _area(id: int) -> Node2D:
	return get_node_or_null("PastureArea%02d" % id) as Node2D


# 封装 animal_count 的处理，供相关流程复用。
func _animal_count(id: int) -> int:
	var count := 0
	for animal in _animals:
		if int(animal.get("area", 0)) == id:
			count += 1
	return count


# 读取 animal_count，供调用方继续处理。
func get_animal_count(id: int) -> int:
	return _animal_count(id)


# 加载 animals，供调用方继续处理。
func _load_animals() -> void:
	_animals.clear()
	var state := get_node_or_null("/root/GameState")
	if state == null:
		return
	var saved: Variant = state.flags.get("pasture_animals", [])
	if saved is Array:
		for record in saved:
			if record is Dictionary and str(record.get("type", "")) in TYPES and int(record.get("area", 0)) in [3, 4]:
				_animals.append(record.duplicate(true))


# 封装 save 的处理，供相关流程复用。
func _save() -> void:
	var state := get_node_or_null("/root/GameState")
	if state != null:
		state.flags["pasture_animals"] = _animals.duplicate(true)
		state.flags["pasture_feed_slots"] = _feed_slots.duplicate(true)
	var saver := get_node_or_null("/root/SaveManager")
	if saver != null:
		saver.call("request_save")


# 封装 frame 的处理，供相关流程复用。
func _frame(kind: String, index: int, direction: int = 0) -> Texture2D:
	var key := "%s_%d_%d" % [kind, direction, index]
	if _frame_cache.has(key):
		return _frame_cache[key] as Texture2D
	var source := ANIMAL_ARTS.get(kind) as Texture2D
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	var frame_width := float(source.get_width()) / float(FRAME_COUNT)
	var frame_height := float(source.get_height()) if kind == "dog" else float(source.get_height()) / 4.0
	atlas.region = Rect2(float(index) * frame_width, float(direction) * frame_height, frame_width, frame_height)
	_frame_cache[key] = atlas
	return atlas


# 重建 sprites，供调用方继续处理。
func _rebuild_sprites() -> void:
	for sprite in _sprites.values():
		if is_instance_valid(sprite):
			sprite.queue_free()
	_sprites.clear()
	_walk_targets.clear()
	_walk_speeds.clear()
	_eat_pauses.clear()
	for animal in _animals:
		var area := _area(int(animal["area"]))
		if area == null:
			continue
		var layer := area.get_node_or_null("Animals") as Node2D
		if layer == null:
			continue
		var sprite := Sprite2D.new()
		sprite.name = "Animal_%d" % int(animal["id"])
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.texture = _frame(str(animal["type"]), 0)
		sprite.scale = Vector2(0.12, 0.12)
		sprite.position = Vector2(float(animal["x"]), float(animal["y"]))
		layer.add_child(sprite)
		sprite.add_child(FOOT_SHADOW.instantiate())
		_sprites[int(animal["id"])] = sprite
		_walk_targets[int(animal["id"])] = Vector2(randf_range(-85.0, 85.0), randf_range(120.0, 180.0))
		_walk_speeds[int(animal["id"])] = randf_range(_cfg_float("animal_walk_min_speed"), _cfg_float("animal_walk_max_speed"))
		_eat_pauses[int(animal["id"])] = 0.0
	for id in [3, 4]:
		_refresh_alert(id)


# 刷新 alert，供调用方继续处理。
func _refresh_alert(id: int) -> void:
	var area := _area(id)
	if area == null:
		return
	var label := area.get_node_or_null("Alert") as Label
	if label == null:
		return
	label.visible = is_unlocked() and _animal_count(id) > 0
	if not label.visible:
		return
	var hungry := false
	for animal in _animals:
		if int(animal["area"]) == id and int(animal.get("hunger", 0)) >= _cfg_int("hungry_alert_ticks"):
			hungry = true
			break
	var food_count := 0
	for slot_index in range(FEED_SLOT_COUNT):
		food_count += int(get_food_slot_summary(id, slot_index).get("count", 0))
	label.text = "×" if hungry and food_count <= 0 else "!" if food_count <= 0 else ""
	label.visible = not label.text.is_empty()
	label.add_theme_color_override("font_color", Color("#e84638") if hungry else Color("#ffdf5e"))


# 随渲染帧更新状态，时间增量以秒计。
func _process(delta: float) -> void:
	if not is_unlocked():
		return
	_frame_time += delta
	_hunger_time += delta
	var frame_period := _cfg_float("animal_animation_frame_seconds")
	var frame_changed := false
	while _frame_time >= frame_period:
		_frame_time -= frame_period
		_frame_index = (_frame_index + 1) % FRAME_COUNT
		frame_changed = true
	for animal in _animals:
		var id := int(animal["id"])
		var kind := str(animal.get("type", ""))
		if int(animal.get("hunger", 0)) < _cfg_int("hungry_alert_ticks"):
			var productive := float(animal.get("productive_seconds", 0.0)) + delta
			var interval := maxf(60.0, _cfg_float("%s_product_minutes" % kind) * 60.0)
			if productive >= interval:
				productive -= interval
				animal["productive_seconds"] = productive
				var product_id := _product_for_animal(kind)
				if not product_id.is_empty():
					DropService.grant_item(product_id, 1, "pasture:%d" % int(animal.get("area", 3)), "pasture_product")
				_save()
			else:
				animal["productive_seconds"] = productive
		else:
			animal["productive_seconds"] = 0.0
		var sprite := _sprites.get(id) as Sprite2D
		if sprite == null or id == _dragged_id:
			continue
		var eat_pause := float(_eat_pauses.get(id, 0.0))
		if eat_pause > 0.0:
			_eat_pauses[id] = maxf(0.0, eat_pause - delta)
			continue
		var target: Vector2 = _walk_targets.get(id, sprite.position)
		var area_id := int(animal.get("area", 0))
		var food_slot_index := _nearest_stocked_slot(area_id, sprite.position) if int(animal.get("hunger", 0)) > 0 else -1
		if food_slot_index >= 0:
			var area := _area(area_id)
			var slot := _feed_slot(area_id, food_slot_index)
			if area != null and slot != null:
				target = area.to_local(slot.global_position) + Vector2(-19.0, 0.0)
				if sprite.position.distance_to(target) <= 5.0 and _consume_feed_portion(area_id, food_slot_index):
					animal["hunger"] = 0
					_eat_pauses[id] = 0.8
					_walk_targets[id] = Vector2(randf_range(-85.0, 85.0), randf_range(120.0, 180.0))
					_refresh_alert(area_id)
					_save()
					continue
		elif sprite.position.distance_to(target) < 2.0:
			target = Vector2(randf_range(-85.0, 85.0), randf_range(120.0, 180.0))
			_walk_targets[id] = target
		if frame_changed:
			var travel := target - sprite.position
			var direction := 0
			if absf(travel.x) >= absf(travel.y):
				direction = 2 if travel.x >= 0.0 else 1
			else:
				direction = 0 if travel.y >= 0.0 else 3
			sprite.texture = _frame(str(animal["type"]), _frame_index, direction)
		sprite.flip_h = false
		sprite.position = sprite.position.move_toward(target, float(_walk_speeds.get(id, 10.0)) * delta)
		animal["x"] = sprite.position.x
		animal["y"] = sprite.position.y
	_update_dog(delta)
	if _hunger_time >= _cfg_float("hunger_tick_seconds"):
		_hunger_time -= _cfg_float("hunger_tick_seconds")
		for animal in _animals:
			animal["hunger"] = int(animal.get("hunger", 0)) + 1
		for area_id in [3, 4]:
			_refresh_alert(area_id)
		_save()


# 封装 product_for_animal 的处理，供相关流程复用。
func _product_for_animal(kind: String) -> String:
	var registry := get_node_or_null("/root/DataRegistry")
	if registry == null:
		return ""
	for value in registry.get_all("pasture_products"):
		var product: Dictionary = value
		if str(product.get("source_animal", "")) == kind:
			return str(product.get("id", ""))
	return ""


# 封装 nearest_stocked_slot 的处理，供相关流程复用。
func _nearest_stocked_slot(area_id: int, from_position: Vector2) -> int:
	var area := _area(area_id)
	if area == null:
		return -1
	var selected := -1
	var best_distance := INF
	for index in range(FEED_SLOT_COUNT):
		if int(get_food_slot_summary(area_id, index).get("count", 0)) <= 0:
			continue
		var slot := _feed_slot(area_id, index)
		if slot == null:
			continue
		var distance := from_position.distance_squared_to(area.to_local(slot.global_position))
		if distance < best_distance:
			best_distance = distance
			selected = index
	return selected


# 封装 consume_feed_portion 的处理，供相关流程复用。
func _consume_feed_portion(area_id: int, slot_index: int) -> bool:
	var slot := _feed_slot_data(area_id, slot_index)
	var queue: Array = slot.get("queue", [])
	if queue.is_empty():
		return false
	var first := queue[0] as Dictionary
	first["count"] = int(first.get("count", 0)) - 1
	if int(first["count"]) <= 0:
		queue.pop_front()
	_refresh_feed_slot_visual(area_id, slot_index)
	return true


# 更新 dog，供调用方继续处理。
func _update_dog(delta: float) -> void:
	var dog := $Dog as Sprite2D
	_dog_time += delta
	if _dog_sleeping:
		dog.texture = SLEEP_ART
		dog.scale = Vector2(0.042, 0.042)
		if _dog_time > _cfg_float("dog_sleep_seconds"):
			_dog_sleeping = false
			_dog_time = 0.0
			_dog_target = Vector2(randf_range(-350, 1100), randf_range(202, 210))
	else:
		dog.texture = _frame("dog", _frame_index)
		dog.scale = Vector2(0.12, 0.12)
		dog.flip_h = _dog_target.x < dog.position.x
		dog.position = dog.position.move_toward(_dog_target, _cfg_float("dog_walk_speed") * delta)
		if dog.position.distance_to(_dog_target) < 4.0:
			if _dog_time > _cfg_float("dog_wander_seconds"):
				_dog_target = Vector2(39, 194)
				if dog.position.distance_to(_dog_target) < 5.0:
					_dog_sleeping = true
					_dog_time = 0.0
			else:
				_dog_target = Vector2(randf_range(-350, 1100), randf_range(202, 210))
