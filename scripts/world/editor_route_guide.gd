@tool
extends Node2D

## Editor-only guide. The road sprites and WorkerTargets markers are the actual
## controls used by the runtime route planner; this node never changes movement.
@export var show_road_line := true:
	set(value):
		show_road_line = value
		queue_redraw()

@export var show_target_links := true:
	set(value):
		show_target_links = value
		queue_redraw()

@export var route_color := Color(0.96, 0.13, 0.12, 0.95):
	set(value):
		route_color = value
		queue_redraw()

@export_range(1.0, 8.0, 0.5) var line_width := 3.0:
	set(value):
		line_width = value
		queue_redraw()


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	set_process(Engine.is_editor_hint())
	queue_redraw()


# 随渲染帧更新状态，时间增量以秒计。
func _process(_delta: float) -> void:
	# Scene overrides and dragged markers move without a signal in the editor.
	queue_redraw()


# 提交本节点的自定义绘制命令。
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var world := get_parent()
	if world == null:
		return
	var road_segments := _road_segments(world)
	if show_road_line:
		_draw_road(road_segments)
	if show_target_links:
		_draw_targets(world, road_segments)


# 封装 road_segments 的处理，供相关流程复用。
func _road_segments(world: Node) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	for layer_name in ["PlotSegments", "SharedSegments"]:
		var layer := world.get_node_or_null("PathLayer/" + layer_name)
		if layer == null:
			continue
		for child in layer.get_children():
			var sprite := child as Sprite2D
			if sprite == null or sprite.texture == null:
				continue
			var half_width := float(sprite.texture.get_width()) * 0.5
			var left_point := to_local(sprite.to_global(Vector2(-half_width, 0.0)))
			var right_point := to_local(sprite.to_global(Vector2(half_width, 0.0)))
			segments.append({
				"left": minf(left_point.x, right_point.x),
				"right": maxf(left_point.x, right_point.x),
				"y": (left_point.y + right_point.y) * 0.5,
				"active": sprite.is_visible_in_tree(),
			})
	segments.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["left"]) < float(b["left"]))
	return segments


# 绘制 road，供调用方继续处理。
func _draw_road(segments: Array[Dictionary]) -> void:
	for segment in segments:
		var start := Vector2(float(segment["left"]), float(segment["y"]))
		var finish := Vector2(float(segment["right"]), float(segment["y"]))
		var color := route_color if bool(segment["active"]) else Color(route_color.r, route_color.g, route_color.b, 0.35)
		_draw_contrast_line(start, finish, color, line_width)
		_draw_handle((start + finish) * 0.5, color, 3.5)


# 绘制 targets，供调用方继续处理。
func _draw_targets(world: Node, segments: Array[Dictionary]) -> void:
	var targets := world.get_node_or_null("DynamicAnchors/WorkerTargets")
	if targets == null:
		return
	for child in targets.get_children():
		var marker := child as Marker2D
		if marker == null:
			continue
		var position_local := to_local(marker.global_position)
		_draw_target_link(position_local, segments)
		_draw_handle(position_local, route_color, 5.0)

	# Plot commands use each plot's x coordinate and FarmPoint's y coordinate.
	var farm_marker := targets.get_node_or_null("FarmPoint") as Marker2D
	var plot_nodes := world.get_node_or_null("PlotLayer/PlotNodes")
	if farm_marker == null or plot_nodes == null:
		return
	var farm_y := to_local(farm_marker.global_position).y
	for plot in plot_nodes.get_children():
		var hit_area := plot.get_node_or_null("StateVisuals/HitArea") as Node2D
		if hit_area == null:
			continue
		var target := Vector2(to_local(hit_area.global_position).x, farm_y)
		_draw_target_link(target, segments)
		_draw_handle(target, route_color, 3.5)


# 绘制 target_link，供调用方继续处理。
func _draw_target_link(target: Vector2, segments: Array[Dictionary]) -> void:
	var nearest := target
	var best_distance := INF
	for segment in segments:
		if not bool(segment["active"]):
			continue
		var point := Vector2(clampf(target.x, float(segment["left"]), float(segment["right"])), float(segment["y"]))
		var distance := target.distance_squared_to(point)
		if distance < best_distance:
			best_distance = distance
			nearest = point
	if best_distance == INF or target.distance_to(nearest) < 2.0:
		return
	_draw_dashed_line(nearest, target, Color(route_color.r, route_color.g, route_color.b, 0.8))


# 绘制 dashed_line，供调用方继续处理。
func _draw_dashed_line(start: Vector2, finish: Vector2, color: Color) -> void:
	var length := start.distance_to(finish)
	var direction := (finish - start) / length
	var cursor := 0.0
	while cursor < length:
		var next := minf(cursor + 6.0, length)
		_draw_contrast_line(start + direction * cursor, start + direction * next, color, 2.0)
		cursor += 10.0


# 绘制 contrast_line，供调用方继续处理。
func _draw_contrast_line(start: Vector2, finish: Vector2, color: Color, width: float) -> void:
	draw_line(start, finish, Color(1.0, 1.0, 1.0, color.a * 0.8), width + 2.0, true)
	draw_line(start, finish, color, width, true)


# 绘制 handle，供调用方继续处理。
func _draw_handle(point: Vector2, color: Color, radius: float) -> void:
	draw_circle(point, radius + 1.5, Color(1.0, 1.0, 1.0, color.a))
	draw_circle(point, radius, color)
