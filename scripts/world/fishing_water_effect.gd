extends Node2D

const SPLASH_SECONDS := 0.34
const WATER_COLOR := Color(0.79, 0.95, 1.0)

var _floating := false
var _wave_phase := 0.0
var _splash_age := SPLASH_SECONDS


# 波纹固定在水面落点，水花在鱼漂沉没后独立播放至结束。
func update_surface(point: Vector2, floating: bool, submerged: bool, elapsed: float, delta: float) -> void:
	if submerged and _floating:
		_splash_age = 0.0
	else:
		_splash_age = minf(_splash_age + delta, SPLASH_SECONDS)
	if floating or submerged:
		position = point
	_floating = floating
	_wave_phase = fposmod(elapsed * 1.45, 1.0)
	visible = _floating or _splash_age < SPLASH_SECONDS
	queue_redraw()


# 绘制俯视压扁的水纹，水滴向外飞散并落回水面。
func _draw() -> void:
	if _floating:
		_draw_ring(3.4 + _wave_phase * 4.5, (1.0 - _wave_phase) * 0.65)
	if _splash_age >= SPLASH_SECONDS:
		return
	var progress := _splash_age / SPLASH_SECONDS
	_draw_ring(4.0 + progress * 12.0, (1.0 - progress) * 0.9)
	var height := sin(progress * PI)
	var color := Color(WATER_COLOR, 1.0 - progress)
	for index in range(5):
		var spread := float(index - 2)
		var drop := Vector2(spread * (1.3 + progress * 4.0), -height * (9.0 - absf(spread) * 2.0))
		draw_circle(drop, 1.65 - progress * 0.65, color, true, -1.0, true)


# 水纹的纵轴压缩，贴合池塘的俯视角。
func _draw_ring(radius: float, opacity: float) -> void:
	var points := PackedVector2Array()
	for index in range(25):
		var angle := float(index) * TAU / 24.0
		points.append(Vector2(cos(angle), sin(angle) * 0.38) * radius)
	draw_polyline(points, Color(WATER_COLOR, opacity), 0.85, true)
