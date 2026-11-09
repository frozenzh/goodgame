extends Node2D

## Keeps the authored fish sprites and frame animation; only adds a slow swim and a hide/reappear cycle.
@export var broad_cycle_seconds: float = 10.0
@export var slender_cycle_seconds: float = 13.0
@export var broad_travel: Vector2 = Vector2(13.0, 3.0)
@export var slender_travel: Vector2 = Vector2(9.0, 2.0)

@onready var broad: AnimatedSprite2D = $BroadFishShadow
@onready var slender: AnimatedSprite2D = $SlenderFishShadow

var _broad_origin := Vector2.ZERO
var _slender_origin := Vector2.ZERO
var _broad_alpha := 1.0
var _slender_alpha := 1.0
var _elapsed := 0.0


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	_broad_origin = broad.position
	_slender_origin = slender.position
	_broad_alpha = broad.modulate.a
	_slender_alpha = slender.modulate.a
	_elapsed = randf_range(0.0, 3.0)


# 随渲染帧更新状态，时间增量以秒计。
func _process(delta: float) -> void:
	_elapsed += delta
	_animate_fish(broad, _broad_origin, _broad_alpha, broad_travel, broad_cycle_seconds, 0.0)
	_animate_fish(slender, _slender_origin, _slender_alpha, slender_travel, slender_cycle_seconds, 4.1)


# 封装 animate_fish 的处理，供相关流程复用。
func _animate_fish(fish: AnimatedSprite2D, origin: Vector2, base_alpha: float, travel: Vector2, cycle: float, offset: float) -> void:
	var phase := fposmod(_elapsed + offset, maxf(cycle, 1.0)) / maxf(cycle, 1.0)
	fish.position = origin + Vector2(sin(phase * TAU) * travel.x, sin(phase * TAU * 2.0 + offset) * travel.y)
	var opacity := 1.0
	if phase < 0.12:
		opacity = smoothstep(0.0, 0.12, phase)
	elif phase > 0.68:
		opacity = 1.0 - smoothstep(0.68, 0.82, phase)
	var tint := fish.modulate
	tint.a = base_alpha * opacity
	fish.modulate = tint
