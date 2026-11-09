@tool
extends Node2D

@export_range(0.0, 1.0) var opacity := 0.23
@export_range(0.1, 1.0) var width_ratio := 0.72

static var _bounds_cache: Dictionary = {}
var _texture: Texture2D
var _bounds := Rect2()


# 使用当前帧的不透明边界定位脚底；缓存每个纹理，兼容四向行走和小狗睡姿。
func _process(_delta: float) -> void:
	var sprite := get_parent() as Sprite2D
	if sprite == null or sprite.texture == null:
		hide()
		return
	show()
	if _texture == sprite.texture:
		return
	_texture = sprite.texture
	if not _bounds_cache.has(_texture):
		var image := _texture.get_image()
		_bounds_cache[_texture] = Rect2(image.get_used_rect()) if image != null else Rect2()
	_bounds = _bounds_cache[_texture]
	queue_redraw()


# 半透明椭圆随父精灵移动和缩放，并绘制在动物后面。
func _draw() -> void:
	var sprite := get_parent() as Sprite2D
	if sprite == null or _texture == null or _bounds.size == Vector2.ZERO:
		return
	var origin := sprite.offset
	if sprite.centered:
		origin -= _texture.get_size() * 0.5
	var contact := origin + Vector2(_bounds.get_center().x, _bounds.end.y - _bounds.size.y * 0.025)
	if sprite.flip_h:
		contact.x = -contact.x
	var radius := _bounds.size.x * width_ratio * 0.5
	draw_set_transform(contact, 0.0, Vector2(1.0, 0.27))
	draw_circle(Vector2.ZERO, radius, Color(0.16, 0.12, 0.07, opacity * 0.35), true, -1.0, true)
	draw_circle(Vector2.ZERO, radius * 0.82, Color(0.16, 0.12, 0.07, opacity * 0.5), true, -1.0, true)
	draw_circle(Vector2.ZERO, radius * 0.6, Color(0.16, 0.12, 0.07, opacity * 0.6), true, -1.0, true)
