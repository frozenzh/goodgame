extends Node

## Configurable gameplay clock and the single owner of offline elapsed time.

@onready var GameConfig: Node = get_node("/root/GameConfig")
var _timer: Timer
var _last_tick_unix := 0
var _pending_offline: Dictionary = {}
var _menu_pause_unix := 0


# 打开开始菜单时冻结生产时钟；暂停时间不属于离线结算。
func begin_menu_pause() -> void:
	if _menu_pause_unix == 0:
		_menu_pause_unix = now_unix()


# 读档前将植物时间轴平移到当前时刻，保留保存瞬间的生长进度。
# 使用完整有符号间隔，不受离线结算上限限制，也兼容电脑时间回拨；不修改其他系统。
func restore_crop_runtime(data: Dictionary) -> void:
	var saved_at := int(data.get("last_save_unix", 0))
	if saved_at <= 0:
		return
	var offset := now_unix() - saved_at
	for plot in data.get("plots", []):
		for cell in plot.get("cells", []):
			for key in ["planted_at", "leaf_at", "mature_at"]:
				if int(cell.get(key, 0)) > 0:
					cell[key] = int(cell[key]) + offset
		for key in ["planted_at", "mature_at"]:
			if int(plot.get(key, 0)) > 0:
				plot[key] = int(plot[key]) + offset


# 只平移生产、天气、施工及商店倒计时，成就获取时间和存档时间保持真实电脑时间。
func _shift_active_times(data: Dictionary, seconds: int) -> void:
	if seconds <= 0:
		return
	if int(data.get("shop_refresh_at", 0)) > 0:
		data["shop_refresh_at"] = int(data["shop_refresh_at"]) + seconds
	for plot in data.get("plots", []):
		for cell in plot.get("cells", []):
			for key in ["planted_at", "leaf_at", "mature_at"]:
				if int(cell.get(key, 0)) > 0:
					cell[key] = int(cell[key]) + seconds
		for key in ["planted_at", "mature_at"]:
			if int(plot.get(key, 0)) > 0:
				plot[key] = int(plot[key]) + seconds
	var timed_records: Array = [data.get("weather_state", {}), data.get("fishing_cast", {}), data.get("flags", {}).get("cottage_construction", {})]
	timed_records.append_array(data.get("crafting_jobs", []))
	for record in timed_records:
		for key in ["started_at", "ends_at", "ready_at", "finish_at"]:
			if int(record.get(key, 0)) > 0:
				record[key] = int(record[key]) + seconds


# 保存暂停中的快照时只修改副本，避免重复保存累加偏移。
func adjust_paused_snapshot(data: Dictionary) -> void:
	if _menu_pause_unix > 0:
		_shift_active_times(data, maxi(0, now_unix() - _menu_pause_unix))


# 继续当前游戏时平移活动状态的时间戳，并重置 tick 基准以排除菜单停留时间。
func end_menu_pause() -> void:
	if _menu_pause_unix > 0:
		var state: Variant = get_node("/root/GameState")
		var data := {"plots": state.plots, "weather_state": state.weather_state, "fishing_cast": state.fishing_cast, "flags": state.flags, "crafting_jobs": state.crafting_jobs, "shop_refresh_at": state.shop_refresh_at}
		_shift_active_times(data, maxi(0, now_unix() - _menu_pause_unix))
		state.shop_refresh_at = int(data["shop_refresh_at"])
	clear_menu_pause()


# 新游戏或读取另一存档时丢弃旧菜单暂停信息。
func clear_menu_pause() -> void:
	_menu_pause_unix = 0
	_last_tick_unix = now_unix()


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	_last_tick_unix = now_unix()
	_timer = Timer.new()
	_timer.name = "GameplayTick"
	_timer.wait_time = GameConfig.get_float("time_save", "tick_seconds")
	_timer.one_shot = false
	_timer.autostart = true
	_timer.timeout.connect(_on_tick)
	add_child(_timer)


# 封装 now_unix 的处理，供相关流程复用。
func now_unix() -> int:
	return int(Time.get_unix_time_from_system())


# 准备 offline，供调用方继续处理。
func prepare_offline(last_save_unix: int) -> int:
	var current := now_unix()
	var elapsed := clampi(current - maxi(0, last_save_unix), 0, GameConfig.get_int("time_save", "offline_cap_seconds"))
	_pending_offline = {
		"seconds": elapsed,
		"from_unix": current - elapsed,
		"to_unix": current
	}
	if elapsed > 0:
		_emit("offline_settlement_requested", [elapsed, current - elapsed, current])
	return elapsed


# 判断是否具有 pending_offline 对应的条件。
func has_pending_offline() -> bool:
	return int(_pending_offline.get("seconds", 0)) > 0


# 封装 peek_pending_offline 的处理，供相关流程复用。
func peek_pending_offline() -> Dictionary:
	return _pending_offline.duplicate(true)


# 封装 consume_pending_offline 的处理，供相关流程复用。
func consume_pending_offline() -> Dictionary:
	var result := _pending_offline.duplicate(true)
	_pending_offline.clear()
	return result


# 封装 publish_offline_result 的处理，供相关流程复用。
func publish_offline_result(result: Dictionary) -> void:
	_emit("offline_result_ready", [result])


# 响应 tick 对应的事件或条件。
func _on_tick() -> void:
	var current := now_unix()
	var delta := clampi(current - _last_tick_unix, 1, GameConfig.get_int("time_save", "offline_cap_seconds"))
	_last_tick_unix = current
	_emit("tick", [current, delta])


# 封装 emit 的处理，供相关流程复用。
func _emit(signal_name: String, arguments: Array = []) -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus == null or not bus.has_signal(signal_name):
		return
	match arguments.size():
		0: bus.emit_signal(signal_name)
		1: bus.emit_signal(signal_name, arguments[0])
		2: bus.emit_signal(signal_name, arguments[0], arguments[1])
		3: bus.emit_signal(signal_name, arguments[0], arguments[1], arguments[2])

