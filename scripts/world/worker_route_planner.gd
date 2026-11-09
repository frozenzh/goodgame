extends RefCounted

## The visible road has a lower travel cost. Everywhere else the visibility
## graph uses straight, swept-collision-checked edges around static blockers.
static func plan(actor: CharacterBody2D, world: StaticWorldStrip, target: Vector2, road_travel_cost: float, corner_clearance: float) -> Array[Vector2]:
	var start := actor.global_position
	if start.distance_to(target) <= 0.1:
		return [target]
	var points: Array[Vector2] = [start, target]
	var road_ids: Array[int] = [-1, -1]
	if world != null:
		var runs := world.get_visible_road_runs()
		for run_index in range(runs.size()):
			var run: Dictionary = runs[run_index]
			var left := float(run["left"])
			var right := float(run["right"])
			var road_y := float(run["y"])
			# An unrelated, distant road must not pull a short off-road trip away.
			if right < minf(start.x, target.x) or left > maxf(start.x, target.x):
				continue
			for x in [left, clampf(start.x, left, right), clampf(target.x, left, right), right]:
				var road_point := Vector2(x, road_y)
				var existing := points.find(road_point)
				if existing >= 0:
					road_ids[existing] = run_index
				else:
					points.append(road_point)
					road_ids.append(run_index)
	_append_obstacle_corners(world, actor.collision_mask, corner_clearance, points, road_ids)
	return _shortest_visible_route(actor, points, road_ids, road_travel_cost)


# 封装 nearest_road_point 的处理，供相关流程复用。
static func nearest_road_point(world: StaticWorldStrip, position: Vector2, max_distance: float) -> Vector2:
	if world == null:
		return position
	var nearest := position
	var nearest_distance := max_distance
	for run in world.get_visible_road_runs():
		var point := Vector2(clampf(position.x, float(run["left"]), float(run["right"])), float(run["y"]))
		var distance := position.distance_to(point)
		if distance < nearest_distance:
			nearest = point
			nearest_distance = distance
	return nearest


# 封装 road_at 的处理，供相关流程复用。
static func road_at(world: StaticWorldStrip, position: Vector2, vertical_tolerance: float) -> Dictionary:
	if world == null:
		return {}
	for run in world.get_visible_road_runs():
		if position.x >= float(run["left"]) and position.x <= float(run["right"]) and absf(position.y - float(run["y"])) <= vertical_tolerance:
			return run
	return {}


# 封装 append_obstacle_corners 的处理，供相关流程复用。
static func _append_obstacle_corners(world: StaticWorldStrip, collision_mask: int, corner_clearance: float, points: Array[Vector2], road_ids: Array[int]) -> void:
	if world == null:
		return
	for node in world.find_children("*", "StaticBody2D", true, false):
		var body := node as StaticBody2D
		if body == null or body.collision_layer & collision_mask == 0:
			continue
		for child in body.get_children():
			var collision_shape := child as CollisionShape2D
			if collision_shape != null and not collision_shape.disabled:
				var rectangle := collision_shape.shape as RectangleShape2D
				if rectangle != null:
					var half := rectangle.size * 0.5
					for sx in [-1.0, 1.0]:
						for sy in [-1.0, 1.0]:
							points.append(collision_shape.to_global(Vector2(sx * half.x, sy * half.y)) + Vector2(sx, sy) * corner_clearance)
							road_ids.append(-1)
			var collision_polygon := child as CollisionPolygon2D
			if collision_polygon != null and not collision_polygon.disabled and not collision_polygon.polygon.is_empty():
				var center := Vector2.ZERO
				for vertex in collision_polygon.polygon:
					center += collision_polygon.to_global(vertex)
				center /= float(collision_polygon.polygon.size())
				for vertex in collision_polygon.polygon:
					var global_vertex := collision_polygon.to_global(vertex)
					points.append(global_vertex + (global_vertex - center).normalized() * corner_clearance)
					road_ids.append(-1)


# 封装 shortest_visible_route 的处理，供相关流程复用。
static func _shortest_visible_route(actor: CharacterBody2D, points: Array[Vector2], road_ids: Array[int], road_travel_cost: float) -> Array[Vector2]:
	var count := points.size()
	var distances := PackedFloat32Array()
	var previous := PackedInt32Array()
	var visited := PackedByteArray()
	distances.resize(count)
	previous.resize(count)
	visited.resize(count)
	for index in range(count):
		distances[index] = INF
		previous[index] = -1
		visited[index] = 0
	distances[0] = 0.0
	for _iteration in range(count):
		var current := -1
		for index in range(count):
			if visited[index] == 0 and (current < 0 or distances[index] < distances[current]):
				current = index
		if current < 0 or is_inf(distances[current]):
			break
		if current == 1:
			break
		visited[current] = 1
		for other in range(count):
			if other == current or visited[other] != 0:
				continue
			if not _segment_clear(actor, points[current], points[other]):
				continue
			var cost := points[current].distance_to(points[other])
			if road_ids[current] >= 0 and road_ids[current] == road_ids[other]:
				cost *= road_travel_cost
			var candidate := distances[current] + cost
			if candidate < distances[other]:
				distances[other] = candidate
				previous[other] = current
	if previous[1] < 0:
		return []
	var reversed_route: Array[Vector2] = []
	var cursor := 1
	while cursor != 0 and cursor >= 0:
		reversed_route.append(points[cursor])
		cursor = previous[cursor]
	reversed_route.reverse()
	return reversed_route


# 封装 segment_clear 的处理，供相关流程复用。
static func _segment_clear(actor: CharacterBody2D, from: Vector2, to: Vector2) -> bool:
	if from.distance_squared_to(to) < 0.01:
		return true
	var foot := actor.get_node_or_null("FootCollision") as CollisionShape2D
	if foot == null or foot.shape == null:
		return false
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = foot.shape
	query.transform = Transform2D(0.0, from)
	query.motion = to - from
	query.collision_mask = actor.collision_mask
	query.exclude = [actor.get_rid()]
	var safe_fractions := actor.get_world_2d().direct_space_state.cast_motion(query)
	return safe_fractions.size() > 0 and safe_fractions[0] >= 0.999
