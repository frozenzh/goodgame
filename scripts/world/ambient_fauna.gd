extends Node2D

## 纯环境生物：静态槽位复用，不写存档；全部时钟使用 delta，暂停与读档不补刷离线数量。
const COLOR_LIST := "res://assets/hd/world/ambient_fauna/butterfly_colors.json"

var _rng := RandomNumberGenerator.new()
var _colors: Array[SpriteFrames] = []
var _butterflies: Array[Dictionary] = []
var _birds: Array[Dictionary] = []
var _plots: Dictionary = {}
var _bird_wait := 0.0
var _flock_active := false
var _weather_allowed := false
var _started := false


# 仅加载实际交付的五组帧资源；每次生成只选择一次，不使用整图调色。
func _ready() -> void:
	_rng.randomize()
	var entries: Variant = JSON.parse_string(FileAccess.get_file_as_string(COLOR_LIST))
	if entries is Array:
		for entry in entries:
			var frames := load(str(entry.get("sprite_frames", ""))) as SpriteFrames
			if frames != null:
				_colors.append(frames)
	for sprite in $Butterflies.get_children():
		_butterflies.append({"sprite": sprite, "phase": "idle"})
	for sprite in $Birds.get_children():
		_birds.append({"sprite": sprite, "phase": "idle"})
	EventBus.game_loaded.connect(_reset_activity)
	EventBus.game_reset.connect(_reset_activity)
	_reset_activity()


# 所有数值来自环境生物源表，时间统一以秒计。
func _value(key: String) -> float:
	return GameConfig.get_float("ambient_fauna", key)


# GM 跳过成熟地块的生成等待和小鸟刷新等待；仍需成熟作物、非雨天及安全落点，不清除已有个体。
func trigger_activity() -> Dictionary:
	if str(GameState.weather_state.get("id", "sunny")) == "rain":
		return {"weather_allowed": false, "butterflies": 0, "birds": 0}
	_started = true
	_weather_allowed = true
	var before_butterflies := _count(_butterflies)
	var before_birds := _count(_birds)
	_schedule_butterflies(0.0)
	for index in _plots:
		var schedule: Dictionary = _plots[index]
		if bool(schedule["mature"]) and not bool(schedule["spawned"]):
			schedule["wait"] = 0.0
		if bool(schedule["mature"]):
			var pending: Array = schedule["respawns"]
			for index_pending in range(pending.size()):
				pending[index_pending] = 0.0
	if before_birds == 0:
		_flock_active = false
		_bird_wait = 0.0
	_schedule_butterflies(0.0)
	_schedule_birds(0.0)
	return {"weather_allowed": true, "butterflies": _count(_butterflies) - before_butterflies, "birds": _count(_birds) - before_birds}


# 读取一对最小/最大时间参数，随机数只在状态切换时生成，避免逐帧抖动。
func _between(prefix: String) -> float:
	return _rng.randf_range(_value(prefix + "_min"), _value(prefix + "_max"))


# 存档切换属于重建环境，不保留上个存档的生物；普通天气切换则必须走自然飞离。
func _reset_activity() -> void:
	for slot in _butterflies + _birds:
		_recycle(slot)
	_plots.clear()
	for anchor in $PlotRanges.get_children():
		_plots[int(anchor.get_meta("plot_index"))] = {"wait": 0.0, "mature": false, "spawned": false,
			"respawns": [],
			"target": _rng.randi_range(int(_value("butterfly_plot_min")), int(_value("butterfly_plot_max")))}
	_bird_wait = _between("initial_wait")
	_flock_active = false
	_started = false
	_weather_allowed = false


# 仅进入雨天时停止生成并飞离；其他天气互切不重置活动或等待。暂停不积累墙钟时间，离场仍占额度。
func _process(delta: float) -> void:
	if not SaveManager.startup_choice_done:
		return
	var weather_allowed := str(GameState.weather_state.get("id", "sunny")) != "rain"
	if not _started or weather_allowed != _weather_allowed:
		_started = true
		_weather_allowed = weather_allowed
		if not weather_allowed:
			for slot in _butterflies + _birds:
				slot["respawn_after_exit"] = false
				_depart(slot, _between("weather_exit"))
			for schedule in _plots.values():
				schedule["mature"] = false
				schedule["spawned"] = false
				(schedule["respawns"] as Array).clear()
		else:
			_bird_wait = _between("initial_wait")
	for slot in _butterflies:
		_animate(slot, delta, false)
	for slot in _birds:
		_animate(slot, delta, true)
	if _weather_allowed:
		_schedule_butterflies(delta)
		_schedule_birds(delta)


# 仅解锁且存在成熟未收获作物的地块可触发蝴蝶，初始定制成熟地块走同一入口。
func _eligible_plots() -> Array[int]:
	var eligible: Array[int] = []
	var now := int(Time.get_unix_time_from_system())
	for index in range(GameState.plots.size()):
		var plot: Dictionary = GameState.plots[index]
		if not bool(plot.get("unlocked", false)) or not _plots.has(index):
			continue
		for cell in plot.get("cells", []):
			if not str(cell.get("crop", "")).is_empty() and now >= int(cell.get("mature_at", 0)):
				eligible.append(index)
				break
	return eligible


# 返回当前地块使用的静态范围，Plot07 对应索引 0，Plot01 对应索引 6。
func _anchor(index: int) -> Node2D:
	return $PlotRanges.get_child(index) as Node2D


# Area 的四个静态偏移定义蝴蝶绕行范围；转换到管理器空间，显示缩放和世界横移不会导致漂移。
func _area(index: int) -> Rect2:
	var area := _anchor(index).get_node("Area") as Control
	return Rect2(to_local(area.global_position), area.size)


# 未显示的延迟入场和飞离中的槽位也占额度；空闲槽仅在完整离场后回收。
func _count(slots: Array[Dictionary], plot_index: int = -1) -> int:
	var total := 0
	for slot in slots:
		if str(slot["phase"]) != "idle" and (plot_index < 0 or int(slot.get("plot", -1)) == plot_index):
			total += 1
	return total


# 成熟后首次等待5–10秒；随后每只蝴蝶各自活动10–20秒、消失后各自等待5–10秒重现，不等待整批。
# 最后一株成熟作物收走后取消全部待重现记录，已有个体在1–5秒内离场；各地块互相独立。
func _schedule_butterflies(delta: float) -> void:
	var eligible := _eligible_plots()
	var due: Array[int] = []
	for index in _plots:
		var schedule: Dictionary = _plots[index]
		if not eligible.has(int(index)):
			if bool(schedule["mature"]):
				for slot in _butterflies:
					if int(slot.get("plot", -1)) == int(index):
						slot["respawn_after_exit"] = false
						_depart(slot, _between("butterfly_harvest_exit"))
				schedule["mature"] = false
				schedule["spawned"] = false
				(schedule["respawns"] as Array).clear()
			continue
		if not bool(schedule["mature"]):
			schedule["mature"] = true
			schedule["spawned"] = false
			schedule["wait"] = _between("butterfly_mature_delay")
			schedule["target"] = _rng.randi_range(int(_value("butterfly_plot_min")), int(_value("butterfly_plot_max")))
		if bool(schedule["spawned"]):
			continue
		schedule["wait"] = maxf(0.0, float(schedule["wait"]) - delta)
		if float(schedule["wait"]) <= 0.0 and _count(_butterflies, int(index)) == 0:
			due.append(int(index))
	if due.is_empty():
		_advance_butterfly_respawns(eligible, delta)
		return
	var targets: Dictionary = {}
	var wishes: Dictionary = {}
	var cap := mini(_butterflies.size(), int(_value("butterfly_cap")))
	var remaining := cap
	for index in eligible:
		targets[index] = mini(1, remaining)
		remaining -= int(targets[index])
		wishes[index] = int(_plots[index]["target"])
	while remaining > 0:
		var candidates: Array[int] = []
		for index in eligible:
			if int(targets[index]) < int(wishes[index]):
				candidates.append(index)
		if candidates.is_empty():
			break
		var chosen := candidates[_rng.randi_range(0, candidates.size() - 1)]
		targets[chosen] = int(targets[chosen]) + 1
		remaining -= 1
	# 每轮先给尚无蝴蝶的地块一个槽位，再处理额外数量，避免前面的地块抢光额度。
	for pass_index in range(3):
		for index in due:
			if _count(_butterflies) >= cap:
				_advance_butterfly_respawns(eligible, delta)
				return
			if pass_index >= int(targets.get(index, 0)):
				continue
			_spawn_butterfly(index, 0.0)
			_plots[index]["spawned"] = true
	_advance_butterfly_respawns(eligible, delta)


# 每个计时对应一只已经完整消失的蝴蝶；槽位不足时保留到期记录，取得空槽后再重现。
func _advance_butterfly_respawns(eligible: Array[int], delta: float) -> void:
	var cap := mini(_butterflies.size(), int(_value("butterfly_cap")))
	for index in eligible:
		var schedule: Dictionary = _plots[index]
		var pending: Array = schedule["respawns"]
		for pending_index in range(pending.size() - 1, -1, -1):
			pending[pending_index] = maxf(0.0, float(pending[pending_index]) - delta)
			if float(pending[pending_index]) > 0.0 or _count(_butterflies) >= cap or _count(_butterflies, index) >= int(schedule["target"]):
				continue
			var before := _count(_butterflies)
			_spawn_butterfly(index, 0.0)
			if _count(_butterflies) > before:
				pending.remove_at(pending_index)


# 从固定池取一个空槽；返回空字典表示本帧没有容量，不会临时增加节点。
func _free_slot(slots: Array[Dictionary]) -> Dictionary:
	for slot in slots:
		if str(slot["phase"]) == "idle":
			return slot
	return {}


# 蝴蝶颜色在入场时等概率选一次；fly/perch 和离场共享该 SpriteFrames，整体 alpha 只用于淡入淡出。
func _spawn_butterfly(index: int, delay: float) -> void:
	if _colors.is_empty():
		return
	var slot := _free_slot(_butterflies)
	if slot.is_empty():
		return
	var rect := _area(index)
	var center := rect.get_center()
	_initialize(slot, index, center, delay, _between("butterfly_life"), false)
	slot["radius"] = rect.size * _rng.randf_range(0.28, 0.44)
	slot["angle"] = _rng.randf_range(0.0, TAU)
	slot["turn"] = _rng.randf_range(0.65, 1.15) * (-1.0 if _rng.randf() < 0.5 else 1.0)
	slot["rest_at"] = float(slot["life"]) * _rng.randf_range(0.35, 0.55)
	slot["rest_for"] = _between("butterfly_rest")
	var radius: Vector2 = slot["radius"]
	slot["rest_point"] = center + Vector2(cos(float(slot["angle"])) * radius.x, sin(float(slot["angle"])) * radius.y)
	slot["rest_point"] = _plant_perch(index, slot["rest_point"])
	slot["rest_checked"] = false
	var sprite: AnimatedSprite2D = slot["sprite"]
	sprite.sprite_frames = _colors[_rng.randi_range(0, _colors.size() - 1)]
	sprite.offset = Vector2.ZERO
	sprite.play("fly")


# 使用当前可见植物的实际位置；没有可见植物时才回退到活动区域内的备用停留点。
func _plant_perch(index: int, fallback: Vector2) -> Vector2:
	var anchor := _anchor(index)
	var plot_path: NodePath = anchor.get("plot_path")
	var plot := anchor.get_node_or_null(plot_path)
	if plot != null and plot.has_method("get_ambient_perch_points"):
		var points: Array = plot.call("get_ambient_perch_points")
		if not points.is_empty():
			return to_local(points[_rng.randi_range(0, points.size() - 1)])
	return fallback


# 蝴蝶在所属地块 Area 的周界随机出现和消失，不再飞往场景边缘；Area 仍可在编辑器独立调整。
func _butterfly_edge(index: int) -> Vector2:
	var rect := _area(index)
	var perimeter := 2.0 * (rect.size.x + rect.size.y)
	var distance := _rng.randf() * perimeter
	if distance < rect.size.x:
		return rect.position + Vector2(distance, 0.0)
	distance -= rect.size.x
	if distance < rect.size.y:
		return Vector2(rect.end.x, rect.position.y + distance)
	distance -= rect.size.y
	if distance < rect.size.x:
		return Vector2(rect.end.x - distance, rect.end.y)
	return Vector2(rect.position.x, rect.end.y - (distance - rect.size.x))


# 小鸟从距离当前落点最近的两个静态出入口中随机选择，避免横跨整个场景；直接使用 Marker 位置便于编辑器微调。
# leaving 决定使用飞出组还是飞入组；蝴蝶仍独立使用所属地块边缘。
func _flight_marker(center: Vector2, leaving: bool) -> Vector2:
	var group: Node2D = $ExitPoints if leaving else $EntryPoints
	var points: Array[Vector2] = []
	for child in group.get_children():
		var marker := child as Marker2D
		if marker != null and marker.is_visible_in_tree():
			points.append(to_local(marker.global_position))
	if points.is_empty():
		return center
	points.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.distance_squared_to(center) < b.distance_squared_to(center)
	)
	return points[_rng.randi_range(0, mini(2, points.size()) - 1)]


# 两类共用无存档的生命周期数据；延迟入场也预占一个静态槽位。
func _initialize(slot: Dictionary, index: int, center: Vector2, delay: float, life: float, bird: bool) -> void:
	slot.merge({"phase": "delay", "plot": index, "age": 0.0, "delay": delay, "life": life,
		"respawn_after_exit": false,
		"center": center, "from": _flight_marker(center, false) if bird else _butterfly_edge(index), "enter": _rng.randf_range(2.5, 4.0),
		"fade": _between("fade_in"), "bird": bird}, true)
	var sprite: AnimatedSprite2D = slot["sprite"]
	sprite.position = slot["from"]
	sprite.modulate.a = 0.0
	sprite.hide()


# 地面落点检查解锁与水面；栅栏/屋顶检查实际精灵是否显示。各类均避云、工作点与当前角色。
func _safe_landing(point: Vector2, index: int, surface: String = "ground", marker: Marker2D = null) -> bool:
	if surface == "ground" and (index < 0 or index >= GameState.plots.size() or not bool(GameState.plots[index].get("unlocked", false))):
		return false
	var world := get_parent()
	var global_point := to_global(point)
	var water := $WaterExclusion as Control
	if surface == "ground" and water.get_global_rect().has_point(global_point):
		return false
	if surface != "ground":
		if not is_instance_valid(marker):
			return false
		var target := marker.get_parent().call("get_surface_target") as Sprite2D
		if target == null or not target.is_visible_in_tree() or target.texture == null:
			return false
		if surface == "fence":
			for roof in $BirdLandings/Roofs.get_children():
				var building := roof.call("get_surface_target") as Sprite2D
				if building != null and building.is_visible_in_tree() and building.is_pixel_opaque(building.to_local(global_point)):
					return false
	if world.has_method("is_world_point_covered_by_cloud") and world.call("is_world_point_covered_by_cloud", global_point):
		return false
	var targets := world.get_node("DynamicAnchors/WorkerTargets")
	for work_marker in targets.get_children():
		if work_marker is Node2D and point.distance_to(to_local(work_marker.global_position)) < _value("workpoint_clearance"):
			return false
	var worker := world.get_node("DynamicAnchors/Worker") as Node2D
	return point.distance_to(to_local(worker.global_position)) >= _value("worker_clearance")


# 收集同一级静态落点，飞入后保留 Marker 引用，建筑隐藏或升级后原落点失效便自然飞离。
func _surface_landings(group: Node2D, surface: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for anchor in group.get_children():
		for child in anchor.get_children():
			var marker := child as Marker2D
			if marker == null:
				continue
			var point := to_local(marker.global_position)
			if _safe_landing(point, -1, surface, marker):
				var overlaps := false
				for existing in result:
					if point.distance_to(existing["point"]) < 24.0:
						overlaps = true
						break
				if not overlaps:
					result.append({"point": point, "plot": -1, "surface": surface, "marker": marker})
	return result


# 每群结束后才开始 60–120 秒冷却；先确定不同落点，再错峰入场，不因帧耗时产生补刷。
func _schedule_birds(delta: float) -> void:
	if _flock_active:
		if _count(_birds) == 0:
			_flock_active = false
			_bird_wait = _between("bird_cooldown")
		return
	_bird_wait = maxf(0.0, _bird_wait - delta)
	if _bird_wait > 0.0:
		return
	var points := _all_bird_landings()
	if points.size() < int(_value("bird_flock_min")):
		_bird_wait = _rng.randf_range(3.0, 6.0)
		return
	var amount := mini(mini(_birds.size(), int(_value("bird_cap"))), mini(points.size(), _rng.randi_range(int(_value("bird_flock_min")), int(_value("bird_flock_max")))))
	for number in range(amount):
		var choice := _weighted_bird_landing(points)
		var landing: Dictionary = points[choice]
		points.remove_at(choice)
		var slot := _free_slot(_birds)
		if slot.is_empty():
			break
		_initialize(slot, int(landing["plot"]), landing["point"], float(number) * _rng.randf_range(0.4, 0.9), _between("bird_life"), true)
		slot["landing_marker"] = landing["marker"]
		slot["surface"] = landing["surface"]
		slot["action_at"] = 0.0
		slot["actions_left"] = _rng.randi_range(2, 3)
		slot["action_interval"] = maxf(0.7, (float(slot["life"]) - float(slot["enter"]) - _value("natural_exit_seconds") - 0.8) / float(slot["actions_left"]))
		slot["action"] = "stand"
		slot["moves_left"] = _rng.randi_range(int(_value("bird_relocation_min")), int(_value("bird_relocation_max")))
		slot["moving"] = false
		slot["move_at"] = float(slot["enter"]) + _between("bird_relocation_wait")
		# 转点属于额外活动，必要时延长停留，为抽中的飞行和原有地面动作留出时间。
		var move_budget := float(slot["moves_left"]) * (_value("bird_relocation_flight_max") + _value("bird_relocation_wait_max"))
		slot["life"] = maxf(float(slot["life"]), float(slot["enter"]) + move_budget + 2.0 + _value("natural_exit_seconds"))
		(slot["sprite"] as AnimatedSprite2D).play("fly")
	_flock_active = true


# 首次落地和转点共用同一组静态 Marker，不创建运行时落点。
func _all_bird_landings() -> Array[Dictionary]:
	var points := _surface_landings($BirdLandings/Fences, "fence")
	points.append_array(_surface_landings($BirdLandings/Roofs, "roof"))
	for index in range($PlotRanges.get_child_count()):
		for node_name in ["BirdLandingLeft", "BirdLandingRight"]:
			var marker := _anchor(index).get_node(node_name) as Marker2D
			var point := to_local(marker.global_position)
			if _safe_landing(point, index):
				points.append({"point": point, "plot": index, "surface": "ground", "marker": marker})
	return points


# 每只鸟每批随机转点0–2次；只选相近、安全且未被其他鸟占用的静态点，并沿用类别权重。
# 返回true表示本帧由飞行动画处理；没有安全邻点时取消剩余转点，不强行远飞。
func _bird_relocation(slot: Dictionary, age: float) -> bool:
	var sprite: AnimatedSprite2D = slot["sprite"]
	if not bool(slot.get("moving", false)):
		if int(slot.get("moves_left", 0)) <= 0 or age < float(slot.get("move_at", 0.0)):
			return false
		var ground_age := age - float(slot["enter"])
		if sprite.animation == &"peck" and sprite.is_playing():
			return false
		if str(slot.get("action", "")) == "hop" and ground_age - float(slot.get("action_start", 0.0)) < 0.6:
			return false
		var nearby: Array[Dictionary] = []
		for landing in _all_bird_landings():
			var point: Vector2 = landing["point"]
			var distance := point.distance_to(slot["center"])
			if landing["marker"] == slot["landing_marker"] or distance < 14.0 or distance > _value("bird_relocation_radius"):
				continue
			var reserved := false
			for other in _birds:
				if other["sprite"] == sprite or str(other["phase"]) in ["idle", "exit"]:
					continue
				if point.distance_to(other["center"]) < 24.0:
					reserved = true
					break
			if not reserved:
				nearby.append(landing)
		if nearby.is_empty():
			slot["moves_left"] = 0
			return false
		var destination: Dictionary = nearby[_weighted_bird_landing(nearby)]
		slot.merge({"moving": true, "move_start": age, "move_from": sprite.position,
			"move_duration": _between("bird_relocation_flight"), "landing_marker": destination["marker"],
			"surface": destination["surface"], "plot": destination["plot"], "center": destination["point"]}, true)
		slot["moves_left"] = int(slot["moves_left"]) - 1
		sprite.play("fly")
	var target: Vector2 = slot["center"]
	var progress := clampf((age - float(slot["move_start"])) / float(slot["move_duration"]), 0.0, 1.0)
	sprite.position = (slot["move_from"] as Vector2).lerp(target, smoothstep(0.0, 1.0, progress)) + Vector2(0.0, -sin(progress * PI) * _value("bird_relocation_arc_height"))
	sprite.flip_h = target.x < float(slot["move_from"].x)
	if progress >= 1.0:
		slot["moving"] = false
		slot["move_at"] = age + _between("bird_relocation_wait")
		slot["action"] = "stand"
		sprite.play("stand")
	return true


# 权重针对类别而非每个 Marker；某类没有可用落点时才移除其权重，其余按比例重新分配。
func _weighted_bird_landing(points: Array[Dictionary]) -> int:
	var groups: Dictionary = {"fence": [], "roof": [], "ground": []}
	for index in range(points.size()):
		(groups[str(points[index]["surface"])] as Array).append(index)
	var total := 0.0
	for surface in groups:
		if not (groups[surface] as Array).is_empty():
			total += maxf(0.0, _value("bird_" + str(surface) + "_weight"))
	if total <= 0.0:
		return _rng.randi_range(0, points.size() - 1)
	var roll := _rng.randf() * total
	var last_index := 0
	for surface in groups:
		var candidates: Array = groups[surface]
		if candidates.is_empty():
			continue
		last_index = int(candidates[_rng.randi_range(0, candidates.size() - 1)])
		roll -= maxf(0.0, _value("bird_" + str(surface) + "_weight"))
		if roll < 0.0:
			return last_index
	return last_index


# 生命周期包含入场、活动、离场；离场结束才隐藏回收。恶劣天气不重置已经离场的计时。
func _animate(slot: Dictionary, delta: float, bird: bool) -> void:
	var phase := str(slot["phase"])
	if phase == "idle":
		return
	var sprite: AnimatedSprite2D = slot["sprite"]
	if phase == "delay":
		slot["delay"] = float(slot["delay"]) - delta
		if float(slot["delay"]) <= 0.0:
			slot["phase"] = "active"
			sprite.show()
		return
	slot["age"] = float(slot["age"]) + delta
	var age := float(slot["age"])
	var previous := sprite.position
	if phase == "exit":
		var progress := clampf(age / float(slot["exit_duration"]), 0.0, 1.0)
		sprite.position = (slot["exit_from"] as Vector2).lerp(slot["exit_to"], smoothstep(0.0, 1.0, progress)) + Vector2(0.0, -sin(progress * PI) * 12.0)
		sprite.modulate.a = float(slot["exit_alpha"]) * (1.0 - smoothstep(0.55, 1.0, progress))
		if progress >= 1.0:
			var plot_index := int(slot.get("plot", -1))
			var respawn := not bird and bool(slot.get("respawn_after_exit", false)) and _weather_allowed and _plots.has(plot_index) and bool(_plots[plot_index]["mature"])
			_recycle(slot)
			if respawn:
				(_plots[plot_index]["respawns"] as Array).append(_between("butterfly_respawn_delay"))
		return
	var enter := float(slot["enter"])
	var life := float(slot["life"])
	if bird and age >= life - _value("natural_exit_seconds"):
		_depart(slot, _value("natural_exit_seconds"))
		return
	if not bird and age >= life - _value("butterfly_exit_seconds"):
		slot["respawn_after_exit"] = true
		_depart(slot, _value("butterfly_exit_seconds"))
		return
	sprite.modulate.a = clampf(age / float(slot["fade"]), 0.0, 1.0)
	var center: Vector2 = slot["center"]
	if bird:
		var marker := slot.get("landing_marker") as Marker2D
		if is_instance_valid(marker):
			center = to_local(marker.global_position)
			slot["center"] = center
		if not _safe_landing(center, int(slot["plot"]), str(slot.get("surface", "ground")), marker):
			_depart(slot, _between("weather_exit"))
			return
		if age < enter:
			sprite.position = (slot["from"] as Vector2).lerp(center, smoothstep(0.0, 1.0, age / enter)) + Vector2(0.0, -sin(age / enter * PI) * 14.0)
		else:
			if _bird_relocation(slot, age):
				return
			_bird_ground_action(slot, age - enter)
	else:
		# 个体寿命内独立绕飞和停留，寿命到期后从地块边缘消失，再单独等待重现。
		var angle := float(slot["angle"]) + (float(slot["age"]) - enter) * float(slot["turn"])
		var radius: Vector2 = slot["radius"]
		var flying_point := center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y * 0.7 + sin(angle * 2.1) * 3.0)
		var rest_at := float(slot["rest_at"])
		var rest_for := minf(float(slot["rest_for"]), maxf(0.5, life - rest_at - 2.0))
		if not bool(slot.get("rest_checked", false)) and age >= rest_at - 2.0:
			slot["rest_point"] = _plant_perch(int(slot["plot"]), slot["rest_point"])
			slot["rest_checked"] = true
		var rest_point: Vector2 = slot["rest_point"]
		if age < enter:
			sprite.position = (slot["from"] as Vector2).lerp(flying_point, smoothstep(0.0, 1.0, age / enter))
		elif age < rest_at:
			sprite.play("fly")
			sprite.position = flying_point.lerp(rest_point, smoothstep(rest_at - 2.0, rest_at, age))
		elif age < rest_at + rest_for:
			sprite.position = rest_point
			sprite.play("perch")
		else:
			sprite.play("fly")
			sprite.position = rest_point.lerp(flying_point, smoothstep(rest_at + rest_for, rest_at + rest_for + 2.0, age))
	if absf(sprite.position.x - previous.x) > 0.01:
		sprite.flip_h = sprite.position.x < previous.x


# 落地后随机执行 2–3 次啄地、转向或小跳；小跳只移动精灵，不改变落点或帧锚点。
func _bird_ground_action(slot: Dictionary, elapsed: float) -> void:
	var sprite: AnimatedSprite2D = slot["sprite"]
	var center: Vector2 = slot["center"]
	var action := str(slot.get("action", "stand"))
	var start := float(slot.get("action_start", 0.0))
	if action == "hop" and elapsed - start < 0.6:
		var progress := clampf((elapsed - start) / 0.6, 0.0, 1.0)
		sprite.position = center + Vector2(0.0, -sin(progress * PI) * 6.0)
		return
	sprite.position = center
	if action == "peck":
		if sprite.animation == &"peck" and sprite.is_playing():
			return
		slot["action"] = "stand"
	sprite.play("stand")
	if elapsed < float(slot["action_at"]) or int(slot["actions_left"]) <= 0:
		return
	slot["actions_left"] = int(slot["actions_left"]) - 1
	slot["action_start"] = elapsed
	slot["action_at"] = elapsed + float(slot["action_interval"]) * _rng.randf_range(0.85, 1.0)
	match _rng.randi_range(0, 2):
		0:
			slot["action"] = "peck"
			sprite.play("peck")
		1:
			slot["action"] = "hop"
		2:
			slot["action"] = "stand"
			sprite.flip_h = not sprite.flip_h


# duration 以秒计；尚未显示的预留槽可直接归还，已显示的生物沿弧线淡出，不突然消失。
func _depart(slot: Dictionary, duration: float) -> void:
	if str(slot["phase"]) in ["idle", "exit"]:
		return
	if str(slot["phase"]) == "delay":
		_recycle(slot)
		return
	var sprite: AnimatedSprite2D = slot["sprite"]
	var destination := _flight_marker(sprite.position, true) if bool(slot.get("bird", false)) else _butterfly_edge(int(slot["plot"]))
	slot.merge({"phase": "exit", "age": 0.0, "exit_duration": maxf(0.1, duration),
		"exit_from": sprite.position, "exit_to": destination, "exit_alpha": sprite.modulate.a}, true)
	sprite.play("fly")
	sprite.flip_h = float(slot["exit_to"].x) < sprite.position.x


# 只在完整离场或存档重建时归还静态槽，不删除编辑器节点。
func _recycle(slot: Dictionary) -> void:
	var sprite: AnimatedSprite2D = slot["sprite"]
	sprite.hide()
	sprite.stop()
	sprite.modulate.a = 1.0
	slot["phase"] = "idle"
	slot["respawn_after_exit"] = false
