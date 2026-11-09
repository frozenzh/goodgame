extends Node2D

@onready var outer_ring: Line2D = $OuterRing
@onready var inner_ring: Line2D = $InnerRing


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	_make_ellipse(outer_ring, Vector2(16, 7))
	_make_ellipse(inner_ring, Vector2(10, 4))
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.8, 1.8), 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "modulate:a", 0.0, 0.55)
	tween.tween_callback(queue_free)


# 构造 ellipse，供调用方继续处理。
func _make_ellipse(ring: Line2D, radius: Vector2) -> void:
	var points := PackedVector2Array()
	for index in range(25):
		var angle := TAU * float(index) / 24.0
		points.append(Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	ring.points = points
