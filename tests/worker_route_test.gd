extends SceneTree

const RoutePlanner = preload("res://scripts/world/worker_route_planner.gd")


# 封装 initialize 的处理，供相关流程复用。
func _initialize() -> void:
	call_deferred("_run")


# 封装 run 的处理，供相关流程复用。
func _run() -> void:
	var scene := load("res://scenes/main/Main.tscn") as PackedScene
	var main := scene.instantiate()
	root.add_child(main)
	await physics_frame
	var state := root.get_node("GameState")
	state.reset_to_defaults(false)
	var world := main.get_node("StaticWorldStrip") as StaticWorldStrip
	world.set_plot_states(state.plots)
	var worker := main.get_node("StaticWorldStrip/DynamicAnchors/Worker") as WorkerActor
	worker.set_physics_process(false)
	var road: Dictionary = RoutePlanner.road_at(world, worker.global_position, 20.0)
	if road.is_empty():
		_fail("The worker must start beside the visible house road")
		return
	var target := world.get_plot_centers()[5] as Vector2
	target.y = worker._marker("FarmPoint").y
	worker._set_route(target)
	var route: Array[Vector2] = worker._route
	if route.is_empty():
		_fail("The route to an unlocked plot is empty")
		return
	var uses_road := false
	for point in route:
		if absf(point.y - float(road["y"])) < 0.5:
			uses_road = true
	if not uses_road:
		_fail("The route to an unlocked plot does not follow the visible road")
		return
	if not _route_is_clear(worker, route):
		_fail("The plot route crosses a collision body")
		return
	worker._set_route(worker._marker("FishingPoint"))
	if worker._route.is_empty() or not _route_is_clear(worker, worker._route):
		_fail("The fishing-pier route must stay out of pond water")
		return
	worker._set_route(worker._marker("ShopPoint"))
	if worker._route.is_empty() or not _route_is_clear(worker, worker._route):
		_fail("The route beyond the pond must avoid its water collider")
		return
	worker.global_position = worker._marker("ShopPoint")
	worker._set_route(worker._marker("FishingPoint"))
	if worker._route.is_empty() or not _route_is_clear(worker, worker._route):
		_fail("The return route around pond water must be collision-free")
		return
	worker.global_position = Vector2(100.0, float(road["y"]))
	var off_road_target := Vector2(190.0, float(road["y"]))
	worker._set_route(off_road_target)
	if worker._route.size() != 1 or worker._route[0].distance_to(off_road_target) > 0.1:
		_fail("A roadless, clear section must use the direct shortest route")
		return
	if not RoutePlanner.road_at(world, worker.global_position, 20.0).is_empty():
		_fail("A locked plot must not contribute a road segment")
		return
	var second_plot: Dictionary = state.plots[1]
	second_plot["unlocked"] = true
	world.set_plot_states(state.plots)
	if RoutePlanner.road_at(world, Vector2(190.0, worker.global_position.y), 20.0).is_empty():
		_fail("Unlocking a visible plot must make its road available to routing")
		return
	print("WORKER_ROUTE_TEST_OK")
	quit(0)


# 封装 route_is_clear 的处理，供相关流程复用。
func _route_is_clear(worker: WorkerActor, route: Array[Vector2]) -> bool:
	var previous := worker.global_position
	for point in route:
		if not RoutePlanner._segment_clear(worker, previous, point):
			return false
		previous = point
	return true


# 封装 fail 的处理，供相关流程复用。
func _fail(message: String) -> void:
	push_error(message)
	quit(1)
