# 定义 NewDiscoveryCelebration 的状态和可用操作。
class_name NewDiscoveryCelebration
extends Node2D

@export var discovery_type := "fish"
@onready var icon: Sprite2D = $Icon
var icon_texture: Texture2D
var world_position := Vector2.ZERO
var _age := 0.0


# 封装 configure 的处理，供相关流程复用。
func configure(kind: String, texture: Texture2D, at: Vector2) -> void:
	discovery_type = kind
	icon_texture = texture
	world_position = at


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	global_position = world_position
	icon.texture = icon_texture
	if icon_texture != null:
		icon.scale = Vector2.ONE * (33.0 / maxf(float(icon_texture.get_width()), float(icon_texture.get_height())))
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - 43.0, 1.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 0.7).set_delay(0.95)
	tween.finished.connect(queue_free)


# 随渲染帧更新状态，时间增量以秒计。
func _process(delta: float) -> void:
	_age += delta
	queue_redraw()


# 提交本节点的自定义绘制命令。
func _draw() -> void:
	for i in range(12):
		var angle := TAU * float(i) / 12.0 + _age * 0.35
		var direction := Vector2.from_angle(angle)
		var shine := Color("#fff2a8", 0.65 * (1.0 - minf(_age / 1.65, 1.0)))
		draw_line(direction * 18.0, direction * (29.0 + sin(_age * 7.0 + i) * 3.0), shine, 2.0)
