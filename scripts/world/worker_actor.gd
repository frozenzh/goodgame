# 定义 WorkerActor 的状态和可用操作。
class_name WorkerActor
extends CharacterBody2D

const RoutePlanner = preload("res://scripts/world/worker_route_planner.gd")

@export_group("钓鱼帧对齐")
@export var fishing_frame_x_offsets: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 4.0, 52.0, 40.0, -33.0, 25.0, 22.0])
@export_group("浇水帧对齐")
@export var watering_frame_x_offsets: PackedFloat32Array = PackedFloat32Array([0.0, 16.0, 14.0, 7.0, 5.0, 2.0, 0.0, 7.0])

## Work commands and ground clicks interrupt wandering. Work begins after arrival.
var move_speed: float
var action_seconds: float
var wander_horizontal_radius: float
var wander_vertical_radius: float
var world_x_limits: Vector2
var world_y_limits: Vector2
var wander_walk_seconds: Vector2
var wander_rest_seconds: Vector2
var arrival_distance: float
var fish_break_count: Vector2i
var fish_break_seconds: Vector2
var fish_retry_seconds: Vector2
var reset_rest_seconds: float
var wander_edge_margin: float
var wander_vertical_bias: float
var road_travel_cost: float
var route_corner_clearance: float

# 原始 1024 像素帧中，鱼线离开竿尖的位置。顺序与 WorkerFrames 一致。
const FISHING_ROD_TIPS := [
	Vector2(967, 520), Vector2(985, 520), Vector2(968, 526), Vector2(984, 343),
	Vector2(939, 362), Vector2(969, 357), Vector2(819, 463), Vector2(885, 462),
]

enum Phase { WALK, REST, COMMAND, EXECUTING, FISHING, RETURNING, CELEBRATING, MANUAL_MOVE }

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var GameConfig: Node = get_node("/root/GameConfig")
@onready var fishing_line: Line2D = $FishingLine
@onready var fishing_water_effect = $FishingWaterEffect
@onready var fishing_bobber: Node2D = $FishingBobber
@onready var fishing_progress: ProgressBar = $FishingProgress
@onready var action_progress: ProgressBar = $ActionProgress
@onready var fishing_rest_badge: Control = $"../WorkerTargets/FishingPoint/RestBadge"

var _world: StaticWorldStrip
var _job_manager: JobManager
var _fishing_system: FishingSystem
var _random := RandomNumberGenerator.new()
var _phase := Phase.WALK
var _phase_seconds := 0.0
var _action_total_seconds := 0.0
var _wander_direction := Vector2.RIGHT
var _wander_origin := Vector2.ZERO
var _destination := Vector2.ZERO
var _command_id := -1
var _command_action := ""
var _facing := "down"
var _route: Array[Vector2] = []
var _route_index := 0
var _route_replan_attempted := false
var _route_blocked_reported := false
var _auto_fishing_requested := false
var _fish_since_break := 0
var _fish_break_target := 0
var _fish_break_seconds := 0.0
var _taking_fishing_break := false
var _discovery_plays_remaining := 0
var _pending_discoveries := 0
var _phase_before_discovery := Phase.REST
var _house_celebration_plays_remaining := 0
var _house_celebration_pending := false
var _phase_before_house := Phase.REST
var _animation_before_house: StringName = &"down"
var _animation_before_house_playing := false
var _normal_sprite_scale := Vector2.ONE


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	_load_tuning()
	_normal_sprite_scale = animated_sprite.scale
	_random.randomize()
	_world = get_parent().get_parent() as StaticWorldStrip
	_job_manager = get_tree().root.find_child("JobManager", true, false) as JobManager
	_fishing_system = get_tree().root.find_child("FishingSystem", true, false) as FishingSystem
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.connect("game_reset", Callable(self, "_on_game_reset"))
		bus.connect("fish_caught", Callable(self, "_on_fish_caught"))
		bus.connect("cottage_upgrade_completed", Callable(self, "_on_cottage_upgrade_completed"))
		bus.connect("codex_entry_unlocked", Callable(self, "_on_codex_entry_unlocked"))
	animated_sprite.animation_finished.connect(_on_animation_finished)
	animated_sprite.frame_changed.connect(_align_action_frame)
	animated_sprite.animation_changed.connect(_align_action_frame)
	_align_action_frame()
	_fish_break_target = _random.randi_range(fish_break_count.x, fish_break_count.y)
	_wander_origin = global_position
	fishing_progress.hide()
	action_progress.hide()
	fishing_rest_badge.hide()
	# Resolve the route on the first physics tick, after collision space is ready.
	_phase = Phase.REST
	_phase_seconds = 0.0


# 响应 game_reset 对应的事件或条件。
func _on_game_reset() -> void:
	_command_id = -1
	_command_action = ""
	_route.clear()
	_auto_fishing_requested = false
	_fish_since_break = 0
	_fish_break_seconds = 0.0
	_taking_fishing_break = false
	fishing_rest_badge.hide()
	_discovery_plays_remaining = 0
	_pending_discoveries = 0
	_house_celebration_plays_remaining = 0
	_house_celebration_pending = false
	_fish_break_target = _random.randi_range(fish_break_count.x, fish_break_count.y)
	_phase = Phase.REST
	_phase_seconds = reset_rest_seconds
	_wander_origin = global_position
	_stand()
	fishing_progress.hide()
	action_progress.hide()


## 主场景横向拖动会改变世界节点的全局坐标；同步尚未走完的路线。
func shift_world_coordinates(offset: Vector2) -> void:
	if offset.is_zero_approx():
		return
	_wander_origin += offset
	_destination += offset
	world_x_limits += Vector2(offset.x, offset.x)
	world_y_limits += Vector2(offset.y, offset.y)
	for index in range(_route.size()):
		_route[index] += offset


# 按物理帧推进模拟，时间增量以秒计。
func _physics_process(delta: float) -> void:
	if _phase == Phase.WALK or _phase == Phase.REST:
		_fish_break_seconds = maxf(0.0, _fish_break_seconds - delta)
	_sync_command()
	match _phase:
		Phase.COMMAND:
			_move_to_command(delta)
		Phase.EXECUTING:
			_execute_command(delta)
		Phase.WALK:
			_wander(delta)
		Phase.REST:
			_phase_seconds -= delta
			if _phase_seconds <= 0.0:
				_begin_wander()
		Phase.FISHING:
			_move_to_fishing_point(delta)
		Phase.RETURNING:
			_move_to_rest_lane(delta)
		Phase.MANUAL_MOVE:
			_move_to_manual_target(delta)
	_update_fishing_progress()
	_update_fishing_line(delta)
	_update_action_progress()
	if _pending_discoveries > 0 and _phase in [Phase.WALK, Phase.REST, Phase.FISHING]:
		_begin_next_discovery_celebration()
	_update_fishing_rest_badge()


# 仅显示连续钓鱼触发的休息；标签固定在钓鱼点，接任务、手动移动或恢复钓鱼时清除。
func _update_fishing_rest_badge() -> void:
	var state = get_node_or_null("/root/GameState")
	if _taking_fishing_break:
		if (
			_fish_break_seconds <= 0.0 or _is_fishing_active() or not _idle_fishing_enabled()
			or state == null or bool(state.flags.get("fishing_manual_pause", false))
			or _phase in [Phase.COMMAND, Phase.EXECUTING, Phase.FISHING, Phase.MANUAL_MOVE]
		):
			_taking_fishing_break = false
	fishing_rest_badge.visible = _taking_fishing_break and _phase in [Phase.WALK, Phase.REST, Phase.RETURNING]


# 队首变化时中断当前动作并重新寻路，建筑验收也可打断庆祝。
func _sync_command() -> void:
	if _job_manager == null:
		return
	var command := _job_manager.get_next_command()
	var urgent := str(command.get("action", "")) in JobManager.BUILDING_COMPLETION_ACTIONS
	if _phase == Phase.EXECUTING:
		if int(command.get("id", -1)) == _command_id:
			return
		_phase = Phase.COMMAND
		_command_id = -1
		_command_action = ""
		_phase_seconds = 0.0
		animated_sprite.scale = _normal_sprite_scale
		action_progress.hide()
	if _phase == Phase.CELEBRATING:
		if not urgent:
			return
		_discovery_plays_remaining = 0
		_house_celebration_plays_remaining = 0
		_house_celebration_pending = false
	# 手动移动保持目标，除非玩家随后又下达了新的交互指令。
	if _phase == Phase.MANUAL_MOVE and command.is_empty():
		return
	if command.is_empty():
		if _is_fishing_active():
			if _idle_fishing_is_active() and not _idle_fishing_enabled():
				_fishing_system.pause_for_work()
				_auto_fishing_requested = false
				_start_idle_from_here()
				return
			_auto_fishing_requested = false
			var fishing_point := _marker("FishingPoint")
			if _phase != Phase.FISHING or _destination.distance_to(fishing_point) > 0.1:
				_set_route(fishing_point)
			_phase = Phase.FISHING
			_command_id = -1
			_command_action = ""
			return
		if _phase == Phase.FISHING and _auto_fishing_requested:
			if _idle_fishing_enabled():
				return
			_auto_fishing_requested = false
			_start_idle_from_here()
			return
		if _phase == Phase.RETURNING:
			return
		if _phase == Phase.FISHING:
			_start_idle_from_here()
		if _phase == Phase.COMMAND:
			_command_id = -1
			_command_action = ""
			_start_idle_from_here()
		if _fish_break_seconds <= 0.0 and _can_auto_fish():
			_auto_fishing_requested = true
			_set_route(_marker("FishingPoint"))
			_phase = Phase.FISHING
		return
	var next_id := int(command.get("id", -1))
	if _phase == Phase.COMMAND and next_id == _command_id:
		return
	if (urgent or _phase == Phase.FISHING) and _fishing_system != null and _is_fishing_active():
		_fishing_system.pause_for_work()
	_auto_fishing_requested = false
	_command_id = next_id
	_command_action = str(command.get("action", ""))
	_set_route(_target_for_command(command))
	_phase = Phase.COMMAND
	_phase_seconds = 0.0


# 移动 to_command，供调用方继续处理。
func _move_to_command(delta: float) -> void:
	if _advance_route(delta):
		if _job_manager != null:
			_job_manager.begin_next_command(_command_id)
		# 钓鱼到点就进入抛竿进度；开始/停止都不播放通用的三秒操作条。
		if _command_action in ["start_fishing", "stop_fishing"]:
			var completed_id := _command_id
			_command_id = -1
			_command_action = ""
			if _job_manager != null:
				_job_manager.execute_next_command(completed_id)
			if _is_fishing_active():
				_phase = Phase.FISHING
				animated_sprite.play(&"fishing")
			else:
				_start_idle_from_here()
			return
		_phase = Phase.EXECUTING
		if _job_manager != null:
			_job_manager.begin_command_labor(_command_id)
		_action_total_seconds = _command_duration()
		_phase_seconds = _action_total_seconds
		_facing = "up"
		_play_work_animation()
		return


# 封装 execute_command 的处理，供相关流程复用。
func _execute_command(delta: float) -> void:
	_play_work_animation()
	_phase_seconds -= delta
	if _phase_seconds > 0.0:
		return
	var completed_id := _command_id
	_command_id = -1
	_command_action = ""
	animated_sprite.scale = _normal_sprite_scale
	_phase = Phase.COMMAND
	if _job_manager != null:
		_job_manager.execute_next_command(completed_id)
	if _phase == Phase.CELEBRATING:
		return
	# 收获可能同步解锁植物图鉴。先播完庆祝，再从队列取下一块地的收获/播种。
	if _pending_discoveries > 0:
		_begin_next_discovery_celebration()
		return
	_sync_command()


# 封装 play_work_animation 的处理，供相关流程复用。
func _play_work_animation() -> void:
	var desired: StringName = &"up"
	if _command_action == "water_cell":
		desired = &"watering"
	elif _command_action in ["plant", "plant_cell", "harvest", "harvest_cell", "craft_bait"]:
		desired = &"working"
	animated_sprite.scale = Vector2(0.18, 0.18) if desired == &"watering" else _normal_sprite_scale
	if animated_sprite.animation != desired or not animated_sprite.is_playing():
		animated_sprite.play(desired)


# 移动 to_fishing_point，供调用方继续处理。
func _move_to_fishing_point(delta: float) -> void:
	if _advance_route(delta):
		if _auto_fishing_requested:
			_start_auto_fishing()
		if not _is_fishing_active():
			return
		if animated_sprite.animation != &"fishing" or not animated_sprite.is_playing():
			animated_sprite.play(&"fishing")


# 移动 to_rest_lane，供调用方继续处理。
func _move_to_rest_lane(delta: float) -> void:
	if _advance_route(delta):
		_start_idle_from_here()


# 请求 manual_move，供调用方继续处理。
func request_manual_move(target: Vector2) -> bool:
	# 整组播种已经预留了全部种子金币，必须完成全部小格后才能接受地面移动。
	if _job_manager != null:
		var next_command := _job_manager.get_next_command()
		if str(next_command.get("action", "")) in JobManager.BUILDING_COMPLETION_ACTIONS or _job_manager.has_uninterruptible_plant_task():
			return false
	if target.x < _worker_min_x():
		return false
	# 无法到达时保留当前工作，不让误点吞掉既有指令。
	var planned_route: Array[Vector2] = RoutePlanner.plan(self, _world, target, road_travel_cost, route_corner_clearance)
	if planned_route.is_empty() and global_position.distance_to(target) > arrival_distance:
		return false
	if _job_manager != null:
		_job_manager.cancel_pending_commands()
	if _fishing_system != null and _is_fishing_active():
		_fishing_system.pause_for_work()
	_auto_fishing_requested = false
	_fish_since_break = 0
	_fish_break_seconds = maxf(_fish_break_seconds, _random.randf_range(fish_break_seconds.x, fish_break_seconds.y))
	_command_id = -1
	_command_action = ""
	_discovery_plays_remaining = 0
	_pending_discoveries = 0
	_house_celebration_plays_remaining = 0
	_house_celebration_pending = false
	_phase_seconds = 0.0
	fishing_progress.hide()
	action_progress.hide()
	_destination = target
	_route = planned_route
	_route_index = 0
	_route_replan_attempted = false
	_route_blocked_reported = false
	_phase = Phase.MANUAL_MOVE
	if global_position.distance_to(target) <= arrival_distance:
		_finish_manual_move()
	return true


# 移动 to_manual_target，供调用方继续处理。
func _move_to_manual_target(delta: float) -> void:
	if _advance_route(delta) or _route_blocked_reported or (_route.is_empty() and global_position.distance_to(_destination) > arrival_distance):
		_finish_manual_move()


# 结束 manual_move，供调用方继续处理。
func _finish_manual_move() -> void:
	_route.clear()
	_wander_origin = global_position
	_begin_rest()


# 检查是否允许 auto_fish 对应的条件。
func _can_auto_fish() -> bool:
	var state = get_node_or_null("/root/GameState")
	if state == null or _fishing_system == null or not _idle_fishing_enabled() or bool(state.flags.get("fishing_manual_pause", false)):
		return false
	# Never switch bait behind the player's back: bait type is their fish target.
	return _fishing_system.can_fish()


# 启动 auto_fishing，供调用方继续处理。
func _start_auto_fishing() -> void:
	_auto_fishing_requested = false
	var state = get_node_or_null("/root/GameState")
	if state == null or _fishing_system == null or not _fishing_system.can_fish():
		_fish_break_seconds = _random.randf_range(fish_retry_seconds.x, fish_retry_seconds.y)
		_start_idle_from_here()
		return
	state.flags["fishing_active"] = true
	state.flags["fishing_started_by_idle"] = true
	if not _fishing_system.start_cast():
		state.flags["fishing_active"] = false
		state.flags["fishing_started_by_idle"] = false
		_fish_break_seconds = _random.randf_range(fish_retry_seconds.x, fish_retry_seconds.y)
		_start_idle_from_here()


# 响应 fish_caught 对应的事件或条件。
func _on_fish_caught(_fish_id: String, _first_time: bool) -> void:
	if _phase != Phase.FISHING or not _is_fishing_active() or not _idle_fishing_is_active():
		return
	# A discovery gets its full celebration before any idle-fishing rest break.
	if _first_time:
		return
	_fish_since_break += 1
	if _fish_since_break < _fish_break_target:
		return
	_fish_since_break = 0
	_fish_break_target = _random.randi_range(fish_break_count.x, fish_break_count.y)
	_fish_break_seconds = _random.randf_range(fish_break_seconds.x, fish_break_seconds.y)
	_taking_fishing_break = true
	if _fishing_system != null:
		_fishing_system.stop_fishing("rest_break")
	_start_idle_from_here()


# 响应 codex_entry_unlocked 对应的事件或条件。
func _on_codex_entry_unlocked(entry_type: String, _entry_id: String) -> void:
	if entry_type in ["fish", "crop"]:
		_pending_discoveries += 1


# 封装 begin_next_discovery_celebration 的处理，供相关流程复用。
func _begin_next_discovery_celebration() -> void:
	_pending_discoveries -= 1
	_phase_before_discovery = _phase
	_discovery_plays_remaining = 2
	_phase = Phase.CELEBRATING
	fishing_progress.hide()
	animated_sprite.play(&"fish_discovery")
	animated_sprite.set_frame_and_progress(0, 0.0)


# 响应 cottage_upgrade_completed 对应的事件或条件。
func _on_cottage_upgrade_completed(_level: int) -> void:
	if _house_celebration_plays_remaining > 0:
		_house_celebration_plays_remaining = 2
		animated_sprite.set_frame_and_progress(0, 0.0)
		return
	if _phase == Phase.CELEBRATING and _discovery_plays_remaining > 0:
		_house_celebration_pending = true
		return
	_begin_house_celebration()


# 封装 begin_house_celebration 的处理，供相关流程复用。
func _begin_house_celebration() -> void:
	_phase_before_house = _phase
	_animation_before_house = animated_sprite.animation
	_animation_before_house_playing = animated_sprite.is_playing()
	_house_celebration_plays_remaining = 2
	_phase = Phase.CELEBRATING
	fishing_progress.hide()
	action_progress.hide()
	animated_sprite.play(&"fish_discovery")
	animated_sprite.set_frame_and_progress(0, 0.0)


# 响应 animation_finished 对应的事件或条件。
func _on_animation_finished() -> void:
	if _phase != Phase.CELEBRATING or animated_sprite.animation != &"fish_discovery":
		return
	if _house_celebration_plays_remaining > 0:
		_house_celebration_plays_remaining -= 1
		if _house_celebration_plays_remaining > 0:
			animated_sprite.play(&"fish_discovery")
			animated_sprite.set_frame_and_progress(0, 0.0)
			return
		_phase = _phase_before_house
		animated_sprite.play(_animation_before_house)
		if not _animation_before_house_playing:
			animated_sprite.stop()
		if _pending_discoveries > 0:
			_begin_next_discovery_celebration()
		return
	_discovery_plays_remaining -= 1
	if _discovery_plays_remaining > 0:
		animated_sprite.play(&"fish_discovery")
		animated_sprite.set_frame_and_progress(0, 0.0)
		return
	_phase = _phase_before_discovery
	if _pending_discoveries > 0:
		_begin_next_discovery_celebration()
		return
	if _phase == Phase.FISHING and _is_fishing_active():
		animated_sprite.play(&"fishing")
	elif _phase == Phase.COMMAND:
		_sync_command()
	elif _phase == Phase.REST:
		_begin_rest()
	elif _phase == Phase.WALK:
		_play_direction(_wander_direction)
	else:
		_start_idle_from_here()
	if _house_celebration_pending:
		_house_celebration_pending = false
		_begin_house_celebration()


# 判断是否满足 fishing_active 对应的条件。
func _is_fishing_active() -> bool:
	var state = get_node_or_null("/root/GameState")
	return state != null and bool(state.flags.get("fishing_active", false))


# 封装 idle_fishing_enabled 的处理，供相关流程复用。
func _idle_fishing_enabled() -> bool:
	var state = get_node_or_null("/root/GameState")
	return state != null and bool(state.settings.get("idle_auto_fish", false))


# 封装 idle_fishing_is_active 的处理，供相关流程复用。
func _idle_fishing_is_active() -> bool:
	var state = get_node_or_null("/root/GameState")
	return state != null and bool(state.flags.get("fishing_started_by_idle", true))


# 封装 wander 的处理，供相关流程复用。
func _wander(delta: float) -> void:
	_phase_seconds -= delta
	var road: Dictionary = RoutePlanner.road_at(_world, global_position, wander_vertical_radius)
	var next := global_position + _wander_direction * move_speed * delta
	var x_min := minf(maxf(_worker_min_x(), _wander_origin.x - wander_horizontal_radius), _wander_origin.x)
	var x_max := maxf(minf(world_x_limits.y, _wander_origin.x + wander_horizontal_radius), _wander_origin.x)
	var y_min := minf(maxf(world_y_limits.x, _wander_origin.y - wander_vertical_radius), _wander_origin.y)
	var y_max := maxf(minf(world_y_limits.y, _wander_origin.y + wander_vertical_radius), _wander_origin.y)
	if not road.is_empty():
		x_min = maxf(x_min, float(road["left"]) + wander_edge_margin)
		x_max = minf(x_max, float(road["right"]) - wander_edge_margin)
		if x_min > x_max:
			x_min = global_position.x
			x_max = global_position.x
		next.y = move_toward(global_position.y, float(road["y"]), move_speed * delta)
	if next.x < x_min or next.x > x_max:
		_wander_direction.x = -_wander_direction.x
		next.x = clampf(next.x, x_min, x_max)
	if road.is_empty() and (next.y < y_min or next.y > y_max):
		_wander_direction.y = -_wander_direction.y
		next.y = clampf(next.y, y_min, y_max)
	var collision: KinematicCollision2D = move_and_collide(next - global_position)
	if collision != null:
		_wander_direction = _wander_direction.bounce(collision.get_normal()).normalized()
	_play_direction(_wander_direction)
	if _phase_seconds <= 0.0:
		_begin_rest()


# 封装 begin_rest 的处理，供相关流程复用。
func _begin_rest() -> void:
	_phase = Phase.REST
	_phase_seconds = _random.randf_range(wander_rest_seconds.x, wander_rest_seconds.y)
	var choices: Array[StringName] = [&"idle_hat", &"idle_yawn", &"idle_scratch"]
	var selected: StringName = choices[_random.randi_range(0, choices.size() - 1)]
	animated_sprite.play(selected)
	animated_sprite.set_frame_and_progress(0, 0.0)
	var frames := animated_sprite.sprite_frames
	var animation_seconds := 0.0
	for index in range(frames.get_frame_count(selected)):
		animation_seconds += frames.get_frame_duration(selected, index) / frames.get_animation_speed(selected)
	_phase_seconds = maxf(_phase_seconds, animation_seconds)


# 更新 fishing_progress，供调用方继续处理。
func _update_fishing_progress() -> void:
	var state = get_node_or_null("/root/GameState")
	if state == null or _phase != Phase.FISHING or global_position.distance_to(_destination) > arrival_distance:
		fishing_progress.hide()
		return
	var cast: Dictionary = state.fishing_cast
	if cast.is_empty():
		fishing_progress.hide()
		return
	var started_at := float(cast.get("started_at", 0))
	var ready_at := float(cast.get("ready_at", 0))
	if ready_at <= started_at:
		fishing_progress.hide()
		return
	fishing_progress.value = clampf((Time.get_unix_time_from_system() - started_at) / (ready_at - started_at) * 100.0, 0.0, 100.0)
	fishing_progress.show()


# 用竿尖和水面标记实时连接鱼线。收竿前鱼漂缩入水面并完全隐藏。
func _update_fishing_line(delta: float) -> void:
	var active := fishing_progress.visible and animated_sprite.animation == &"fishing"
	fishing_line.visible = active
	if not active:
		fishing_bobber.hide()
		fishing_water_effect.update_surface(Vector2.ZERO, false, false, 0.0, delta)
		return
	var tip: Vector2 = FISHING_ROD_TIPS[animated_sprite.frame]
	var start := to_local(animated_sprite.to_global(tip - Vector2(512, 512) + animated_sprite.offset))
	var water := to_local(_marker("FishingFloatPoint"))
	var cast: Dictionary = get_node("/root/GameState").fishing_cast
	var now := Time.get_unix_time_from_system()
	var remaining := float(cast["ready_at"]) - now
	var surface := clampf((remaining - 0.16) / 0.4, 0.0, 1.0)
	var elapsed := now - float(cast["started_at"])
	var bob := sin(elapsed * TAU * 1.45)
	fishing_water_effect.update_surface(water, surface > 0.0, surface <= 0.0, elapsed, delta)
	fishing_bobber.position = water + Vector2(0.0, bob * 1.4 * surface)
	fishing_bobber.scale.y = maxf(surface, 0.01)
	fishing_bobber.visible = surface > 0.0
	var end := fishing_bobber.position + Vector2(0.0, -3.0 * surface)
	fishing_line.points = PackedVector2Array([start, (start + end) * 0.5 + Vector2(0, 2), end])


# 更新 action_progress，供调用方继续处理。
func _update_action_progress() -> void:
	if _phase != Phase.EXECUTING:
		action_progress.hide()
		return
	action_progress.value = clampf((_action_total_seconds - _phase_seconds) / maxf(_action_total_seconds, 0.001) * 100.0, 0.0, 100.0)
	action_progress.show()


# 封装 command_duration 的处理，供相关流程复用。
func _command_duration() -> float:
	match _command_action:
		"plant_cell", "plant":
			return maxf(0.1, GameConfig.get_float("farming", "plant_action_seconds"))
		"water_cell":
			return maxf(0.1, GameConfig.get_float("farming", "water_action_seconds"))
		"harvest_cell", "harvest":
			return maxf(0.1, GameConfig.get_float("farming", "harvest_action_seconds"))
	if _command_action != "craft_bait" or _job_manager == null:
		return action_seconds
	var command := _job_manager.get_next_command()
	var args: Array = command.get("args", []) if command.get("args", []) is Array else []
	if args.is_empty():
		return action_seconds
	var registry := get_node_or_null("/root/DataRegistry")
	if registry == null:
		return action_seconds
	var recipe: Dictionary = registry.get_recipe(str(args[0]))
	return maxf(0.1, float(recipe.get("craft_seconds", action_seconds)))


# 封装 align_action_frame 的处理，供相关流程复用。
func _align_action_frame() -> void:
	var cutoff := Vector2(2.0, 2.0)
	if animated_sprite.animation == &"fishing":
		var tip: Vector2 = FISHING_ROD_TIPS[animated_sprite.frame]
		cutoff = (tip - Vector2(40, 1)) / 1024.0
	(animated_sprite.material as ShaderMaterial).set_shader_parameter("line_cutoff", cutoff)
	if animated_sprite.animation == &"fishing" and animated_sprite.frame < fishing_frame_x_offsets.size():
		animated_sprite.offset = Vector2(fishing_frame_x_offsets[animated_sprite.frame], 0.0)
	elif animated_sprite.animation == &"watering" and animated_sprite.frame < watering_frame_x_offsets.size():
		animated_sprite.offset = Vector2(watering_frame_x_offsets[animated_sprite.frame], 0.0)
	else:
		animated_sprite.offset = Vector2.ZERO


# 封装 begin_wander 的处理，供相关流程复用。
func _begin_wander() -> void:
	if _route_to_nearest_road():
		return
	_phase = Phase.WALK
	_phase_seconds = _random.randf_range(wander_walk_seconds.x, wander_walk_seconds.y)
	var horizontal := -1.0 if _random.randi_range(0, 1) == 0 else 1.0
	var x_min := maxf(_worker_min_x(), _wander_origin.x - wander_horizontal_radius)
	var x_max := minf(world_x_limits.y, _wander_origin.x + wander_horizontal_radius)
	if global_position.x <= x_min + wander_edge_margin:
		horizontal = 1.0
	elif global_position.x >= x_max - wander_edge_margin:
		horizontal = -1.0
	if RoutePlanner.road_at(_world, global_position, wander_vertical_radius).is_empty():
		_wander_direction = Vector2(horizontal, _random.randf_range(-wander_vertical_bias, wander_vertical_bias)).normalized()
	else:
		_wander_direction = Vector2(horizontal, 0.0)


# 启动 idle_from_here，供调用方继续处理。
func _start_idle_from_here() -> void:
	if _route_to_nearest_road():
		return
	_route.clear()
	_wander_origin = global_position
	_begin_wander()


# 封装 route_to_nearest_road 的处理，供相关流程复用。
func _route_to_nearest_road() -> bool:
	var road_point: Vector2 = RoutePlanner.nearest_road_point(_world, global_position, wander_horizontal_radius)
	if global_position.distance_to(road_point) > arrival_distance:
		_set_route(road_point)
		if not _route.is_empty():
			_phase = Phase.RETURNING
			return true
	return false


# 设置 route，供调用方继续处理。
func _set_route(target: Vector2) -> void:
	if target.x < _worker_min_x():
		_route.clear()
		return
	_destination = target
	_route = RoutePlanner.plan(self, _world, target, road_travel_cost, route_corner_clearance)
	_route_index = 0
	_route_replan_attempted = false
	_route_blocked_reported = false
	if _route.is_empty() and global_position.distance_to(target) > arrival_distance:
		push_warning(TextDB.text("ui.5bba8486af"))


# 封装 advance_route 的处理，供相关流程复用。
func _advance_route(delta: float) -> bool:
	if global_position.distance_to(_destination) <= arrival_distance:
		_route_index = _route.size()
		return true
	while _route_index < _route.size():
		var waypoint: Vector2 = _route[_route_index]
		var travel := waypoint - global_position
		if travel.length() <= arrival_distance:
			_route_index += 1
			continue
		var step := travel.normalized() * minf(move_speed * delta, travel.length())
		var collision: KinematicCollision2D = move_and_collide(step)
		if collision != null:
			if not _route_replan_attempted:
				_route_replan_attempted = true
				_route = RoutePlanner.plan(self, _world, _destination, road_travel_cost, route_corner_clearance)
				_route_index = 0
			elif not _route_blocked_reported:
				push_warning(TextDB.text("ui.8a83411e04"))
				_route_blocked_reported = true
			return false
		_play_direction(travel)
		return false
	return global_position.distance_to(_destination) <= arrival_distance


# 封装 worker_min_x 的处理，供相关流程复用。
func _worker_min_x() -> float:
	if _world == null:
		return world_x_limits.x
	var pasture := _world.get_node_or_null("PastureAreas") as PastureManager
	if pasture != null and pasture.is_unlocked():
		var last_stone := _world.get_node_or_null("PathLayer/PastureSegments/PasturePath06") as Sprite2D
		if last_stone != null and last_stone.texture != null:
			var left_edge := last_stone.global_position.x - float(last_stone.texture.get_width()) * absf(last_stone.global_scale.x) * 0.5
			return minf(world_x_limits.x, left_edge + wander_edge_margin)
		return world_x_limits.x
	var boundary := _world.get_node_or_null("PathLayer/PastureSegments/AccessBoundary") as Marker2D
	return maxf(world_x_limits.x, boundary.global_position.x + 2.0) if boundary != null else world_x_limits.x


# 加载 tuning，供调用方继续处理。
func _load_tuning() -> void:
	move_speed = GameConfig.get_float("worker", "move_speed")
	action_seconds = GameConfig.get_float("worker", "action_seconds")
	wander_horizontal_radius = GameConfig.get_float("worker", "wander_horizontal_radius")
	wander_vertical_radius = GameConfig.get_float("worker", "wander_vertical_radius")
	world_x_limits = Vector2(GameConfig.get_float("worker", "world_x_min"), GameConfig.get_float("worker", "world_x_max"))
	world_y_limits = Vector2(GameConfig.get_float("worker", "world_y_min"), GameConfig.get_float("worker", "world_y_max"))
	wander_walk_seconds = Vector2(GameConfig.get_float("worker", "wander_walk_min_seconds"), GameConfig.get_float("worker", "wander_walk_max_seconds"))
	wander_rest_seconds = Vector2(GameConfig.get_float("worker", "wander_rest_min_seconds"), GameConfig.get_float("worker", "wander_rest_max_seconds"))
	arrival_distance = GameConfig.get_float("worker", "arrival_distance")
	fish_break_count = Vector2i(GameConfig.get_int("worker", "fish_break_min_count"), GameConfig.get_int("worker", "fish_break_max_count"))
	fish_break_seconds = Vector2(GameConfig.get_float("worker", "fish_break_min_seconds"), GameConfig.get_float("worker", "fish_break_max_seconds"))
	fish_retry_seconds = Vector2(GameConfig.get_float("worker", "fish_retry_min_seconds"), GameConfig.get_float("worker", "fish_retry_max_seconds"))
	reset_rest_seconds = GameConfig.get_float("worker", "reset_rest_seconds")
	wander_edge_margin = GameConfig.get_float("worker", "wander_edge_margin")
	wander_vertical_bias = GameConfig.get_float("worker", "wander_vertical_bias")
	road_travel_cost = GameConfig.get_float("worker", "road_travel_cost")
	route_corner_clearance = GameConfig.get_float("worker", "route_corner_clearance")


# 封装 target_for_command 的处理，供相关流程复用。
func _target_for_command(command: Dictionary) -> Vector2:
	match str(command.get("target", "")):
		"plot":
			if _world != null:
				var target_parts := str(command.get("target_id", "-1")).split(":")
				var index := int(target_parts[0])
				if target_parts.size() == 2:
					return _world.get_plot_cell_position(index, int(target_parts[1]))
				var centers := _world.get_plot_centers()
				if index >= 0 and index < centers.size():
					var center: Vector2 = centers[index]
					return Vector2(center.x, _marker("FarmPoint").y)
		"house":
			return _marker("HomePoint")
		"workbench":
			return _marker("WorkbenchPoint")
		"pond":
			return _marker("FishingPoint")
		"shop":
			return _marker("ShopPoint")
		"pasture":
			var target_parts := str(command.get("target_id", "")).split(":")
			if target_parts.size() == 2 and _world != null:
				var approach := _world.get_node_or_null("PastureAreas/PastureArea%02d/FeedApproach" % int(target_parts[0])) as Marker2D
				if approach != null:
					return approach.global_position
	return _marker("HomePoint")


# 封装 marker 的处理，供相关流程复用。
func _marker(marker_name: String) -> Vector2:
	var marker := get_parent().get_node_or_null("WorkerTargets/" + marker_name) as Marker2D
	return marker.global_position if marker else global_position


# 封装 play_direction 的处理，供相关流程复用。
func _play_direction(vector: Vector2) -> void:
	animated_sprite.scale = _normal_sprite_scale
	if absf(vector.x) >= absf(vector.y):
		_facing = "right" if vector.x > 0.0 else "left"
	else:
		_facing = "down" if vector.y > 0.0 else "up"
	if animated_sprite.animation != _facing or not animated_sprite.is_playing():
		animated_sprite.play(_facing)


# 封装 stand 的处理，供相关流程复用。
func _stand() -> void:
	animated_sprite.scale = _normal_sprite_scale
	if animated_sprite.animation != _facing:
		animated_sprite.play(_facing)
	animated_sprite.stop()
	# Frame 3 is the passing pose with both feet near the body; it reads as rest.
	animated_sprite.set_frame_and_progress(2, 0.0)
