extends Node

var _failures: Array[String] = []


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	call_deferred("_check_levels")


# 检查 levels，供调用方继续处理。
func _check_levels() -> void:
	var cloud := $CloudFog as CloudFog
	cloud.set_cottage_level(2, false)
	_check(cloud.plot_late.visible, "level 2 keeps late plot cloud")
	_check(cloud.pasture.visible, "level 2 keeps pasture cloud")
	cloud.set_cottage_level(3, false)
	_check(not cloud.plot_late.visible, "level 3 clears late plot cloud")
	_check(cloud.pasture.visible, "level 3 keeps pasture barn and its left side covered")
	cloud.set_cottage_level(4, false)
	_check(not cloud.pasture.visible, "level 4 clears pasture cloud")
	if _failures.is_empty():
		print("CLOUD_FOG_LEVEL_OK")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		get_tree().quit(1)


# 封装 check 的处理，供相关流程复用。
func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
