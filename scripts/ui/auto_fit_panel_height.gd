@tool
extends PanelContainer


# 内容最小高度变化后重新收紧背景；延迟到容器完成布局，宽度及静态位置保持编辑器设置。
func _ready() -> void:
	minimum_size_changed.connect(_queue_fit)
	resized.connect(_queue_fit)
	_queue_fit()


# 文本换行、控件显隐和宽度变化都可能触发重排，统一在当前帧布局后处理。
func _queue_fit() -> void:
	call_deferred("fit_content_height")


# 高度包含可见子控件及背景内边距；允许由业务刷新立即调用，避免固定高度留下空白。
func fit_content_height() -> void:
	var height := ceilf(get_combined_minimum_size().y)
	if height > 0.0 and not is_equal_approx(size.y, height):
		size = Vector2(size.x, height)
