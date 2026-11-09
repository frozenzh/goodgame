# 定义 FishingSystem 的状态和可用操作。
class_name FishingSystem
extends Node

## Automatic, bait-gated fishing. One bait is consumed when a cast starts.

const RARITY_ORDER := ["common", "good", "rare", "epic"]

@onready var GameConfig: Node = get_node("/root/GameConfig")
var _rng := RandomNumberGenerator.new()


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	_rng.randomize()
	_connect_bus("tick", Callable(self, "_on_tick"))
	_connect_bus("game_loaded", Callable(self, "_on_game_loaded"))
	_connect_bus("game_reset", Callable(self, "_on_game_reset"))
	_connect_bus("weather_changed", Callable(self, "_on_weather_changed"))
	call_deferred("_on_game_loaded")


# 响应 game_loaded 对应的事件或条件。
func _on_game_loaded() -> void:
	var state: Variant = _state()
	if state != null and (str(state.selected_bait).is_empty() or state.get_item_count(str(state.selected_bait)) <= 0):
		_select_first_owned_bait(state)


# 响应 game_reset 对应的事件或条件。
func _on_game_reset() -> void:
	pass


# 响应 weather_changed 对应的事件或条件。
func _on_weather_changed(previous_id: String, current_id: String) -> void:
	if previous_id == current_id or previous_id not in ["sunny", "rain", "snow", "wind"]:
		return
	var state: Variant = _state()
	if state == null or state.fishing_cast.is_empty():
		return
	var now := int(state.weather_state.get("started_at", _now()))
	var ready_at := int(state.fishing_cast.get("ready_at", now))
	if ready_at <= now:
		return
	var weather := _weather_system()
	var old_speed := float(weather.get_fishing_speed_for(previous_id)) if weather != null else 1.0
	var new_speed := float(weather.get_fishing_speed_for(current_id)) if weather != null else 1.0
	state.fishing_cast["ready_at"] = now + maxi(1, ceili(float(ready_at - now) * old_speed / new_speed))
	_request_save()


# 检查是否允许 fish 对应的条件。
func can_fish() -> bool:
	var state: Variant = _state()
	if state == null:
		return false
	if str(state.selected_bait).is_empty() or state.get_item_count(str(state.selected_bait)) <= 0:
		_select_first_owned_bait(state)
	return not str(state.selected_bait).is_empty() and state.get_item_count(str(state.selected_bait)) > 0 and not _build_fish_pool(str(state.selected_bait)).is_empty()


# 选择 first_owned_bait，供调用方继续处理。
func _select_first_owned_bait(state: Variant) -> void:
	var registry: Variant = _registry()
	if registry == null:
		return
	for bait_value in registry.get_all("baits"):
		var bait: Dictionary = bait_value
		var bait_id := str(bait.get("id", ""))
		if not bait_id.is_empty() and state.get_item_count(bait_id) > 0:
			state.selected_bait = bait_id
			_emit("bait_changed", [bait_id])
			_request_save()
			return


# 每轮开始时读取所选鱼饵并消耗一个，写入本轮快照；途中切换选择不会改变本轮的鱼饵或结束时间。
func start_cast(now_unix: int = 0) -> bool:
	var state: Variant = _state()
	if state == null or not state.fishing_cast.is_empty() or not can_fish():
		return false
	var bait_id := str(state.selected_bait)
	var weather := _weather_system()
	var weather_id := str(weather.get_weather_id()) if weather != null else "sunny"
	var weather_multiplier := 1.0
	var bait_multiplier: float = GameConfig.get_float("fishing", "matching_bait_weight")
	var candidate_weights := _build_fish_pool(bait_id, bait_multiplier, weather_multiplier)
	if candidate_weights.is_empty():
		return false
	if not state.consume_item(bait_id, 1):
		return false
	var current := _now() if now_unix <= 0 else now_unix
	var speed := float(weather.get_fishing_speed_multiplier()) if weather != null else 1.0
	var ready_at := current + maxi(1, ceili(float(get_cast_interval_seconds()) / speed))
	state.fishing_cast = {
		"bait_id": bait_id, "started_at": current, "ready_at": ready_at,
		"rod_id": str(state.selected_rod),
		"weather_id": weather_id, "weather_matching_multiplier": weather_multiplier,
		"matching_bait_weight": bait_multiplier,
	}
	_emit("fish_cast_started", [bait_id, ready_at])
	_request_save()
	return true


# 停止 fishing，供调用方继续处理。
func stop_fishing(reason: String = "manual") -> void:
	var state: Variant = _state()
	if state == null:
		return
	if reason == "shutdown":
		_refund_unfinished_cast(state)
	state.flags["fishing_active"] = false
	state.flags["fishing_started_by_idle"] = false
	state.fishing_cast.clear()
	_emit("fishing_stopped", [reason])
	_request_save()


# 封装 pause_for_work 的处理，供相关流程复用。
func pause_for_work() -> void:
	var state: Variant = _state()
	if state == null or not bool(state.flags.get("fishing_active", false)):
		return
	_refund_unfinished_cast(state)
	state.fishing_cast.clear()
	state.flags["fishing_active"] = false
	state.flags["fishing_started_by_idle"] = false
	_emit("fishing_stopped", ["work"])
	_request_save()


# 读取 seconds_until_catch，供调用方继续处理。
func get_seconds_until_catch(now_unix: int = 0) -> int:
	var state: Variant = _state()
	if state == null or state.fishing_cast.is_empty():
		return 0
	var current := _now() if now_unix <= 0 else now_unix
	return maxi(0, int(state.fishing_cast.get("ready_at", current)) - current)


# 读取 cast_interval_seconds，供调用方继续处理。
func get_cast_interval_seconds() -> int:
	return _rng.randi_range(GameConfig.get_int("fishing", "cast_min_seconds"), GameConfig.get_int("fishing", "cast_max_seconds"))


# 构建 fish_weights，供调用方继续处理。
func build_fish_weights(bait_id: String = "") -> Array:
	var state: Variant = _state()
	var selected := bait_id
	if selected.is_empty() and state != null:
		selected = str(state.selected_bait)
	return _build_fish_pool(selected).duplicate(true)


# 封装 settle_offline 的处理，供相关流程复用。
func settle_offline(_seconds: int, _from_unix: int, _to_unix: int) -> Dictionary:
	var state: Variant = _state()
	var summary := {"fish": {}, "casts": 0, "bait_used": {}, "new_codex": []}
	if state == null:
		return summary
	# Fishing is an online-only worker action; never complete casts while away.
	var had_session: bool = not state.fishing_cast.is_empty() or bool(state.flags.get("fishing_active", false))
	_refund_unfinished_cast(state)
	state.fishing_cast.clear()
	state.flags["fishing_active"] = false
	state.flags["fishing_started_by_idle"] = false
	if had_session:
		_request_save()
	return summary


# 封装 refund_unfinished_cast 的处理，供相关流程复用。
func _refund_unfinished_cast(state: Variant) -> void:
	if state.fishing_cast.is_empty():
		return
	var bait_id := str(state.fishing_cast.get("bait_id", ""))
	if not bait_id.is_empty():
		state.add_item(bait_id, 1)


# 响应 tick 对应的事件或条件。
func _on_tick(now_unix: int, _delta_seconds: int) -> void:
	var state: Variant = _state()
	if state == null:
		return
	if not state.fishing_cast.is_empty():
		if now_unix >= int(state.fishing_cast.get("ready_at", now_unix + 1)):
			var caught := _complete_cast(str(state.fishing_cast.get("bait_id", state.selected_bait)))
			if not caught.is_empty():
				var first_time := bool(caught.get("first_time", false))
				_emit("fish_caught_live", [str(caught.get("fish_id", "")), first_time])
			if bool(state.flags.get("fishing_active", false)) and can_fish():
				start_cast(now_unix)
		return
	if not bool(state.flags.get("fishing_active", false)):
		return
	if can_fish():
		start_cast(now_unix)
	else:
		state.flags["fishing_active"] = false
		state.flags["fishing_started_by_idle"] = false
		_emit("fishing_stopped", ["no_bait" if state.get_item_count(str(state.selected_bait)) <= 0 else "unavailable"])
		_request_save()


# 封装 complete_cast 的处理，供相关流程复用。
func _complete_cast(bait_id: String) -> Dictionary:
	var state: Variant = _state()
	if state == null:
		return {}
	var cast: Dictionary = state.fishing_cast.duplicate(true)
	state.fishing_cast.clear()
	# Rebuild the pool so an old cast cannot use cached non-matching fish.
	var pool := _build_fish_pool(bait_id, float(cast.get("matching_bait_weight", GameConfig.get_float("fishing", "matching_bait_weight"))), float(cast.get("weather_matching_multiplier", 1.0)), str(cast.get("rod_id", "")))
	if pool.is_empty():
		state.add_item(bait_id, 1)
	var caught := _catch_from_pool(pool, str(cast.get("rod_id", "")), bait_id)
	_request_save()
	return caught


# 封装 catch_from_pool 的处理，供相关流程复用。
func _catch_from_pool(pool: Array, rod_id: String, bait_id: String) -> Dictionary:
	if pool.is_empty():
		return {}
	var total_weight := 0.0
	for entry in pool:
		total_weight += maxf(0.0, float(entry.get("weight", 0.0)))
	if total_weight <= 0.0:
		return {}
	var roll := _rng.randf_range(0.0, total_weight)
	var cursor := 0.0
	for entry in pool:
		cursor += maxf(0.0, float(entry.get("weight", 0.0)))
		if roll <= cursor:
			return _record_catch(str(entry.get("fish_id", "")), rod_id, bait_id)
	return _record_catch(str(pool.back().get("fish_id", "")), rod_id, bait_id)


# 封装 record_catch 的处理，供相关流程复用。
func _record_catch(fish_id: String, rod_id: String, bait_id: String) -> Dictionary:
	var state: Variant = _state()
	if state == null or fish_id.is_empty():
		return {}
	var registry: Variant = _registry()
	if registry == null:
		return {}
	var fish: Dictionary = registry.get_fish(fish_id)
	var bait: Dictionary = registry.get_bait(bait_id)
	var rod: Dictionary = registry.get_rod(rod_id if not rod_id.is_empty() else str(state.selected_rod))
	if fish.is_empty() or not bait_matches_fish(bait, fish):
		return {}
	var fish_rank := RARITY_ORDER.find(str(fish.get("rarity", "")))
	var rod_rank := RARITY_ORDER.find(str(rod.get("max_fish_rarity", "")))
	if fish_rank < 0 or rod_rank < 0 or fish_rank > rod_rank:
		return {}
	var rarity := str(fish.get("rarity", "common"))
	var limits := get_size_limits(rarity)
	var size_cm := roll_size_cm(limits.x, limits.y, _rng)
	var record: Dictionary = state.fish_size_records.get(fish_id, {}).duplicate(true)
	record["smallest_cm"] = mini(int(record.get("smallest_cm", size_cm)), size_cm)
	record["largest_cm"] = maxi(int(record.get("largest_cm", size_cm)), size_cm)
	record["caught_minimum"] = bool(record.get("caught_minimum", false)) or size_cm == limits.x
	record["caught_maximum"] = bool(record.get("caught_maximum", false)) or size_cm == limits.y
	record["last_cm"] = size_cm
	state.fish_size_records[fish_id] = record
	var first_time: bool = not state.discovered_fish.has(fish_id)
	DropService.grant_fish(fish_id, 1, "pond")
	_emit("fish_caught", [fish_id, first_time])
	EventBus.fish_size_caught.emit(fish_id, size_cm, size_cm == limits.x, size_cm == limits.y)
	# Keep the core loop safe if CodexSystem or ShopSystem is mounted later.
	if first_time and not state.discovered_fish.has(fish_id):
		state.discover("fish", fish_id)
		_emit("codex_entry_unlocked", ["fish", fish_id])
	_emit("achievement_action", [state.next_achievement_event_id(), "fish_caught", {"fish_id": fish_id, "rod_id": rod_id}])
	return {"fish_id": fish_id, "first_time": first_time, "size_cm": size_cm}


# 读取 size_limits，供调用方继续处理。
func get_size_limits(rarity: String) -> Vector2i:
	var key := rarity if RARITY_ORDER.has(rarity) else "common"
	return Vector2i(GameConfig.get_int("fishing", key + "_size_min_cm"), GameConfig.get_int("fishing", key + "_size_max_cm"))


# 封装 roll_size_cm 的处理，供相关流程复用。
static func roll_size_cm(minimum: int, maximum: int, rng: RandomNumberGenerator) -> int:
	# Discrete triangular weights keep both exact endpoints possible, but uncommon.
	if maximum <= minimum:
		return minimum
	var span := maximum - minimum
	var total := 0
	for offset in range(span + 1):
		total += 1 + mini(offset, span - offset)
	var roll := rng.randi_range(1, total)
	for offset in range(span + 1):
		roll -= 1 + mini(offset, span - offset)
		if roll <= 0:
			return minimum + offset
	return maximum


# 构建 fish_pool，供调用方继续处理。
func _build_fish_pool(bait_id: String, bait_multiplier: float = -1.0, weather_multiplier: float = -1.0, rod_id: String = "") -> Array:
	var state: Variant = _state()
	var registry: Variant = _registry()
	if state == null or registry == null or bait_id.is_empty():
		return []
	var bait: Dictionary = registry.get_bait(bait_id)
	if bait.is_empty():
		return []
	var rod: Dictionary = registry.get_rod(rod_id if not rod_id.is_empty() else str(state.selected_rod))
	if bait_multiplier < 0.0:
		bait_multiplier = GameConfig.get_float("fishing", "matching_bait_weight")
	if weather_multiplier < 0.0:
		var weather := _weather_system()
		weather_multiplier = 1.0
	return build_candidate_pool(registry.get_all("fish"), rod, bait, bait_multiplier, weather_multiplier)


# 构建 candidate_pool，供调用方继续处理。
static func build_candidate_pool(fish_entries: Array, rod: Dictionary, bait: Dictionary, matching_bait_weight: float = -1.0, weather_matching_multiplier: float = 1.0) -> Array:
	if matching_bait_weight < 0.0:
		var tree := Engine.get_main_loop() as SceneTree
		var config: Node = tree.root.get_node_or_null("GameConfig") if tree != null else null
		if config == null:
			push_error("GameConfig is required to build fish weights")
			return []
		matching_bait_weight = float(config.get_float("fishing", "matching_bait_weight"))
	var max_rarity := str(rod.get("max_fish_rarity", "common"))
	var max_rank := RARITY_ORDER.find(max_rarity)
	if max_rank < 0:
		max_rank = 0
	var bait_id := str(bait.get("id", ""))
	var high_rarity_bait := str(bait.get("rarity", "common")) in ["good", "rare", "epic"]
	var high_rarity_multiplier := 1.0
	if high_rarity_bait:
		var tree := Engine.get_main_loop() as SceneTree
		var config: Node = tree.root.get_node_or_null("GameConfig") if tree != null else null
		high_rarity_multiplier = maxf(1.0, float(config.get_float("fishing", "high_rarity_bait_rare_epic_weight_multiplier"))) if config != null else 5.0
	var pool: Array = []
	for fish_value in fish_entries:
		var fish: Dictionary = fish_value
		var rarity_rank := RARITY_ORDER.find(str(fish.get("rarity", "common")))
		if rarity_rank < 0 or rarity_rank > max_rank:
			continue
		if not bait_matches_fish(bait, fish):
			continue
		var fish_id := str(fish.get("id", ""))
		var weight := maxf(0.0, float(fish.get("base_weight", 1.0)))
		if high_rarity_bait and str(fish.get("rarity", "")) in ["rare", "epic"]:
			weight *= high_rarity_multiplier
		if not bait_id.is_empty() and str(fish.get("favorite_bait_id", "")) == bait_id:
			weight *= matching_bait_weight * maxf(1.0, weather_matching_multiplier)
		if weight > 0.0:
			pool.append({"fish_id": fish_id, "weight": weight})
	return pool


# 封装 bait_matches_fish 的处理，供相关流程复用。
static func bait_matches_fish(bait: Dictionary, fish: Dictionary) -> bool:
	var preferred_type := str(fish.get("preferred_bait_type", "")).strip_edges()
	if preferred_type.is_empty():
		return false
	for bait_type in str(bait.get("bait_type", "")).split(";"):
		if bait_type.strip_edges() == preferred_type:
			return true
	return false


# 封装 weather_system 的处理，供相关流程复用。
func _weather_system() -> Node:
	return get_node_or_null("../WeatherSystem")


# 封装 state 的处理，供相关流程复用。
func _state():
	return get_node_or_null("/root/GameState")


# 封装 registry 的处理，供相关流程复用。
func _registry():
	return get_node_or_null("/root/DataRegistry")


# 封装 now 的处理，供相关流程复用。
func _now() -> int:
	var time_manager = get_node_or_null("/root/TimeManager")
	return time_manager.now_unix() if time_manager != null else int(Time.get_unix_time_from_system())


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
