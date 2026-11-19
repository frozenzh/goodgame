@tool
extends Node2D

# 翻土跟随父级成熟植株；位置/缩放/z_index 保留给编辑器手调。
# 锚点以不透明包围盒的 0..1 比例标定；负值使用底部 alpha 检测。
@export var root_anchor := Vector2(-1.0, -1.0):
	set(value):
		root_anchor = value
		_signature = []
@export_range(0.0, 1.0) var root_width_ratio := 0.0:
	set(value):
		root_width_ratio = value
		_signature = []
@export_range(0.04, 0.25) var thickness_ratio := 0.12:
	set(value):
		thickness_ratio = value
		_signature = []

# 悬挂果实不能作为茎部宽度；这些校正随换种按纹理名重新选择。
const ROOT_CORRECTIONS := {
	"blueberry": Vector3(0.50, 0.98, 0.22),
	"tomato": Vector3(0.50, 0.98, 0.26),
	"strawberry": Vector3(0.50, 0.97, 0.55),
	"eggplant": Vector3(0.51, 0.98, 0.16),
}
static var _contact_cache: Dictionary = {}
var _signature: Array = []


# 只在可见时检查纹理和父级缩放；支持成熟弹跳、变异换图和编辑器调整。
func _process(_delta: float) -> void:
	var plant := get_parent() as Sprite2D
	if plant == null or plant.texture == null or not is_visible_in_tree():
		return
	var signature: Array = [plant.texture, plant.offset, plant.centered, plant.flip_h, plant.flip_v, plant.global_scale]
	if signature == _signature:
		return
	_signature = signature
	_refresh_contact(plant)


# 用底部 8% 的实心像素求根宽，忽略透明画布、叶冠与稀薄抗锯齿边缘；每张纹理仅扫描一次。
func _measure_contact(texture: Texture2D) -> Dictionary:
	var key := texture.get_instance_id()
	if _contact_cache.has(key):
		return _contact_cache[key]
	var image := texture.get_image()
	if image == null or image.is_empty():
		return {}
	if image.is_compressed():
		image.decompress()
	var bounds := image.get_used_rect()
	if not bounds.has_area():
		return {}
	var left := bounds.end.x
	var right := bounds.position.x
	var bottom := bounds.position.y
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			if image.get_pixel(x, y).a >= 0.5:
				bottom = maxi(bottom, y)
	var band_top := bottom - maxi(2, roundi(bounds.size.y * 0.08))
	for y in range(maxi(bounds.position.y, band_top), bottom + 1):
		for x in range(bounds.position.x, bounds.end.x):
			if image.get_pixel(x, y).a >= 0.5:
				left = mini(left, x)
				right = maxi(right, x)
	var result := {"bounds": Rect2(bounds), "anchor": Vector2((left + right + 1) * 0.5, bottom + 0.5), "width": float(maxi(1, right - left + 1))}
	_contact_cache[key] = result
	return result


# 土圈裁到自身不透明区域；可见长度等于根宽，中心贴根底，厚度在世界坐标中保持低矮。
func _refresh_contact(plant: Sprite2D) -> void:
	var art := get_node_or_null("Texture") as Sprite2D
	if art == null:
		return
	var measured := _measure_contact(plant.texture)
	var soil := _measure_contact(art.texture)
	if measured.is_empty() or soil.is_empty():
		return
	var bounds: Rect2 = measured["bounds"]
	var anchor: Vector2 = measured["anchor"]
	var width: float = measured["width"]
	var name_key := plant.texture.resource_path.get_file().get_basename()
	if ROOT_CORRECTIONS.has(name_key):
		var correction: Vector3 = ROOT_CORRECTIONS[name_key]
		anchor = bounds.position + bounds.size * Vector2(correction.x, correction.y)
		width = bounds.size.x * correction.z
	if root_anchor.x >= 0.0 and root_anchor.y >= 0.0:
		anchor = bounds.position + bounds.size * root_anchor
	if root_width_ratio > 0.0:
		width = bounds.size.x * root_width_ratio
	var local_anchor := anchor + plant.offset
	if plant.centered:
		local_anchor -= plant.texture.get_size() * 0.5
	if plant.flip_h:
		local_anchor.x = -local_anchor.x
	if plant.flip_v:
		local_anchor.y = -local_anchor.y
	var soil_bounds: Rect2 = soil["bounds"]
	art.region_enabled = true
	art.region_rect = soil_bounds
	art.position = local_anchor
	var world_scale := plant.global_scale.abs()
	var height := width * thickness_ratio * world_scale.x / maxf(world_scale.y, 0.0001)
	art.scale = Vector2(width / soil_bounds.size.x, height / soil_bounds.size.y)
