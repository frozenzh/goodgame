# 定义 SparkleBurst 的状态和可用操作。
class_name SparkleBurst
extends Node2D

## Short, code-drawn pixel-style sparkles. No texture import or white edge.
@export var lifetime := 0.95
@export var radius := 30.0
@export_range(1, 30, 1) var sparkle_count := 10
@export var sparkle_color := Color("#ffd66b")

var _elapsed := 0.0
var _sparks: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


# 封装 configure 的处理，供相关流程复用。
func configure(new_radius: float, new_count: int, new_color: Color) -> void:
	radius = new_radius
	sparkle_count = new_count
	sparkle_color = new_color


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	_rng.randomize()
	for index in range(sparkle_count):
		var angle := _rng.randf_range(0.0, TAU)
		var distance := sqrt(_rng.randf()) * radius
		_sparks.append({
			"origin": Vector2(cos(angle), sin(angle) * 0.58) * distance,
			"delay": _rng.randf_range(0.0, 0.22),
			"duration": _rng.randf_range(0.42, 0.68),
			"size": _rng.randf_range(2.5, 5.5),
			"drift": Vector2(_rng.randf_range(-4.0, 4.0), _rng.randf_range(-12.0, -5.0)),
		})
	set_process(true)


# 随渲染帧更新状态，时间增量以秒计。
func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= lifetime:
		queue_free()
		return
	queue_redraw()


# 提交本节点的自定义绘制命令。
func _draw() -> void:
	for spark in _sparks:
		var age: float = _elapsed - float(spark["delay"])
		var duration: float = float(spark["duration"])
		if age <= 0.0 or age >= duration:
			continue
		var progress: float = age / duration
		var strength: float = sin(progress * PI)
		var center: Vector2 = spark["origin"] + spark["drift"] * progress
		var size: float = float(spark["size"]) * strength
		var halo := sparkle_color
		halo.a = strength * 0.22
		_draw_star(center, size * 1.7, halo)
		var ray := sparkle_color
		ray.a = strength * 0.95
		_draw_star(center, size, ray)
		draw_rect(Rect2(center - Vector2.ONE, Vector2(2.0, 2.0)), Color(1.0, 1.0, 0.95, strength))


# 绘制 star，供调用方继续处理。
func _draw_star(center: Vector2, size: float, color: Color) -> void:
	var thin := maxf(0.7, size * 0.22)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0.0, -size), center + Vector2(thin, -thin),
		center + Vector2(size, 0.0), center + Vector2(thin, thin),
		center + Vector2(0.0, size), center + Vector2(-thin, thin),
		center + Vector2(-size, 0.0), center + Vector2(-thin, -thin),
	]), color)
