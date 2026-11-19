@tool
extends Node2D

## 静态落点跟随栅栏或屋顶精灵完整变换，子 Marker 的坐标使用贴图像素，可直接贴着画面拖动。
@export_node_path("Sprite2D") var surface_path: NodePath


# 目标可能只存在于 Main 的实例覆盖中（例如第二、第三段后排栅栏），缺失时不报错也不提供落点。
func get_surface_target() -> Sprite2D:
	return get_node_or_null(surface_path) as Sprite2D


# 编辑器预览和运行时使用相同变换，建筑升级、世界缩放或横移后落脚点继续贴合资源。
func _process(_delta: float) -> void:
	var target := get_surface_target()
	if target != null and not global_transform.is_equal_approx(target.global_transform):
		global_transform = target.global_transform
