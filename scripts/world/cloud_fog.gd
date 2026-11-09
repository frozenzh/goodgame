# 定义 CloudFog 的状态和可用操作。
class_name CloudFog
extends Node2D

@onready var plot_early: TextureRect = $PlotEarlyCloud
@onready var plot_late: TextureRect = $PlotLateCloud
@onready var pasture: TextureRect = $PastureCloud
@export_range(0.1, 5.0, 0.1) var clear_duration := 1.5

var _current_level := 0
var _cloud_tweens: Dictionary = {}


# 设置 cottage_level，供调用方继续处理。
func set_cottage_level(level: int, animate: bool = true) -> void:
	var target := clampi(level, 1, 4)
	if target == _current_level and (animate or _cloud_tweens.is_empty()):
		return
	var should_animate := animate and _current_level > 0 and target > _current_level
	_current_level = target
	_stop_cloud_tweens()
	# 先显示较小的遮挡区，再从右向左揭开不再需要的云。
	_set_cloud(plot_early, target < 2, should_animate)
	_set_cloud(plot_late, target == 2, should_animate)
	# 3 级只把地块云退到牧场小屋边界；牧场小屋及其左侧到 4 级才揭开。
	_set_cloud(pasture, target < 4, should_animate)


# 设置 cloud，供调用方继续处理。
func _set_cloud(cloud: TextureRect, keep_covered: bool, animate: bool) -> void:
	if keep_covered:
		cloud.visible = true
		_set_cloud_progress(0.0, cloud)
	elif animate and cloud.visible:
		_set_cloud_progress(0.0, cloud)
		var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_cloud_tweens[cloud] = tween
		tween.tween_method(_set_cloud_progress.bind(cloud), 0.0, 1.0, clear_duration)
		tween.finished.connect(_finish_cloud_clear.bind(cloud))
	else:
		cloud.visible = false
		_set_cloud_progress(0.0, cloud)


# 设置 cloud_progress，供调用方继续处理。
func _set_cloud_progress(value: float, cloud: TextureRect) -> void:
	(cloud.material as ShaderMaterial).set_shader_parameter("clear_progress", value)


# 结束 cloud_clear，供调用方继续处理。
func _finish_cloud_clear(cloud: TextureRect) -> void:
	cloud.visible = false
	_set_cloud_progress(0.0, cloud)
	_cloud_tweens.erase(cloud)


# 停止 cloud_tweens，供调用方继续处理。
func _stop_cloud_tweens() -> void:
	for tween in _cloud_tweens.values():
		(tween as Tween).kill()
	_cloud_tweens.clear()


# 封装 covers_world_point 的处理，供相关流程复用。
func covers_world_point(world_point: Vector2) -> bool:
	for cloud in [plot_early, plot_late, pasture]:
		if not cloud.visible:
			continue
		var local_point: Vector2 = cloud.get_global_transform_with_canvas().affine_inverse() * world_point
		var bounds := Rect2(Vector2.ZERO, cloud.size)
		var clear_progress := float((cloud.material as ShaderMaterial).get_shader_parameter("clear_progress"))
		var distance_from_right := 1.0 - local_point.x / maxf(1.0, cloud.size.x)
		if bounds.has_point(local_point) and distance_from_right > clear_progress:
			return true
	return false
