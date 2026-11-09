extends SceneTree

const NAMES := ["plot_locked", "plot_cleared", "plot_seed", "plot_leaf", "mature_carrot", "mature_wheat", "mature_cabbage", "mature_tomato", "mature_corn", "mature_strawberry"]


# 封装 initialize 的处理，供相关流程复用。
func _initialize() -> void:
	for name in NAMES:
		var image := Image.load_from_file(ProjectSettings.globalize_path("res://assets/hd/world/%s.png" % name))
		print(name, " ", image.get_size(), " ", image.get_used_rect())
	quit()
