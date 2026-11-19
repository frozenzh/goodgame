@tool
extends Node2D

## 活动区域跟随实际地块中心，Area 和落点仍是可单独拖动的静态子节点。
@export_node_path("Node2D") var plot_path: NodePath


# 编辑器与运行时均跟随地块位移；不继承地块的 0.55 缩放，区域尺寸以世界逻辑像素计。
func _process(_delta: float) -> void:
	var plot := get_node_or_null(plot_path) as Node2D
	if plot != null and not global_position.is_equal_approx(plot.global_position):
		global_position = plot.global_position
