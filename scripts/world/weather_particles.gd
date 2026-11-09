# 定义 WeatherParticles 的状态和可用操作。
class_name WeatherParticles
extends Node2D

## One draw call owner for a bounded set of weather marks; no per-mark nodes.
@export_enum("rain", "snow") var kind := "rain"
@export var bounds := Rect2(0, 88, 1280, 150)
@export var particle_count := 40

var _positions: Array[Vector2] = []
var _phases: Array[float] = []
var _rng := RandomNumberGenerator.new()
var _elapsed := 0.0
var _speed := 100.0
var _drift := 0.0


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	_rng.randomize()
	configure(particle_count, _speed, _drift)
	set_process(false)


# 封装 configure 的处理，供相关流程复用。
func configure(count: int, speed: float, drift: float) -> void:
	particle_count = maxi(0, count)
	_speed = speed
	_drift = drift
	while _positions.size() > particle_count:
		_positions.pop_back()
		_phases.pop_back()
	while _positions.size() < particle_count:
		_positions.append(Vector2(_rng.randf_range(bounds.position.x, bounds.end.x), _rng.randf_range(bounds.position.y, bounds.end.y)))
		_phases.append(_rng.randf_range(0.0, TAU))
	queue_redraw()


# 随渲染帧更新状态，时间增量以秒计。
func _process(delta: float) -> void:
	_elapsed += delta
	for index in range(_positions.size()):
		var point := _positions[index]
		point.y += _speed * delta * (0.72 + float(index % 7) * 0.07)
		point.x += _drift * delta
		if kind == "snow":
			point.x += sin(_elapsed * 1.8 + _phases[index]) * _drift * delta
		if point.y > bounds.end.y:
			point.y = bounds.position.y
			point.x = _rng.randf_range(bounds.position.x, bounds.end.x)
		if point.x > bounds.end.x:
			point.x = bounds.position.x
		elif point.x < bounds.position.x:
			point.x = bounds.end.x
		_positions[index] = point
	queue_redraw()


# 提交本节点的自定义绘制命令。
func _draw() -> void:
	for point in _positions:
		if kind == "rain":
			draw_line(point, point + Vector2(2.4, 7.0), Color(0.78, 0.9, 1.0, 0.65), 1.1, false)
		else:
			draw_circle(point, 1.4, Color(0.98, 0.99, 1.0, 0.9))
