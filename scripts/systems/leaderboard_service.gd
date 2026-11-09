# 定义 LeaderboardService 的状态和可用操作。
class_name LeaderboardService
extends Node

## HTTP boundary for a shared weekly leaderboard. Steam identity can replace the
## generated player id without changing the fishing or UI code.
const MAX_ENTRIES := 50

var entries: Array = []
var week_start := ""
var status := "offline"
var _post_request: HTTPRequest
var _get_request: HTTPRequest
var _posting := false
var _fetching := false


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	_post_request = HTTPRequest.new()
	_get_request = HTTPRequest.new()
	add_child(_post_request)
	add_child(_get_request)
	_post_request.request_completed.connect(_on_post_completed)
	_get_request.request_completed.connect(_on_get_completed)
	EventBus.fish_size_caught.connect(_on_fish_size_caught)
	EventBus.game_loaded.connect(_on_game_loaded)
	EventBus.game_reset.connect(_on_game_reset)
	call_deferred("_on_game_loaded")


# 响应 game_loaded 对应的事件或条件。
func _on_game_loaded() -> void:
	_ensure_identity()
	_show_local_demo()
	_submit_next()
	refresh()


# 响应 game_reset 对应的事件或条件。
func _on_game_reset() -> void:
	_post_request.cancel_request()
	_get_request.cancel_request()
	_posting = false
	_fetching = false
	entries.clear()
	week_start = ""
	status = "offline"
	_ensure_identity()
	_show_local_demo()


# 封装 ensure_identity 的处理，供相关流程复用。
func _ensure_identity() -> void:
	if str(GameState.settings.get("leaderboard_player_id", "")).is_empty():
		GameState.settings["leaderboard_player_id"] = Crypto.new().generate_random_bytes(16).hex_encode()
		SaveManager.request_save()


# 封装 endpoint 的处理，供相关流程复用。
func _endpoint() -> String:
	return str(GameConfig.get_value("fishing", "leaderboard_url")).strip_edges().trim_suffix("/")


# 响应 fish_size_caught 对应的事件或条件。
func _on_fish_size_caught(fish_id: String, size_cm: int, _is_minimum: bool, _is_maximum: bool) -> void:
	_ensure_identity()
	var caught_at := int(Time.get_unix_time_from_system())
	var current_week := _utc_week_start(caught_at)
	if int(GameState.settings.get("leaderboard_week_start", 0)) != current_week:
		GameState.settings["leaderboard_week_start"] = current_week
		GameState.settings["leaderboard_best_cm"] = 0
		GameState.settings["leaderboard_best_fish_id"] = ""
	if size_cm <= int(GameState.settings.get("leaderboard_best_cm", 0)):
		return
	GameState.settings["leaderboard_best_cm"] = size_cm
	GameState.settings["leaderboard_best_fish_id"] = fish_id
	var player_id := str(GameState.settings.get("leaderboard_player_id", ""))
	GameState.leaderboard_pending.append({
		"player_id": player_id,
		"display_name": str(GameState.settings.get("leaderboard_display_name", TextDB.text("fishing.leaderboard.player") + "-" + player_id.substr(0, 4))),
		"fish_id": fish_id,
		"size_cm": size_cm,
		"caught_at": caught_at,
	})
	SaveManager.request_save()
	if status == "local":
		_show_local_demo()
	_submit_next()


# 封装 submit_next 的处理，供相关流程复用。
func _submit_next() -> void:
	if _posting or GameState.leaderboard_pending.is_empty() or _endpoint().is_empty():
		return
	var current_week := _utc_week_start(int(Time.get_unix_time_from_system()))
	while not GameState.leaderboard_pending.is_empty() and int(GameState.leaderboard_pending[0].get("caught_at", 0)) < current_week:
		GameState.leaderboard_pending.pop_front()
		SaveManager.request_save()
	if GameState.leaderboard_pending.is_empty():
		return
	var payload: Dictionary = GameState.leaderboard_pending[0]
	var error := _post_request.request(_endpoint() + "/v1/catches", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error == OK:
		_posting = true
	else:
		_show_local_demo()


# 封装 utc_week_start 的处理，供相关流程复用。
func _utc_week_start(unix_time: int) -> int:
	return floori(float(unix_time - 345600) / 604800.0) * 604800 + 345600


# 响应 post_completed 对应的事件或条件。
func _on_post_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_posting = false
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 201:
		GameState.leaderboard_pending.pop_front()
		SaveManager.request_save()
		if GameState.leaderboard_pending.is_empty():
			refresh()
		else:
			call_deferred("_submit_next")
	else:
		_show_local_demo()


# 封装 refresh 的处理，供相关流程复用。
func refresh() -> void:
	if _endpoint().is_empty():
		_show_local_demo()
		return
	if _fetching:
		return
	if status != "ready":
		_show_local_demo()
	var error := _get_request.request(_endpoint() + "/v1/weekly?limit=%d" % MAX_ENTRIES)
	if error != OK:
		_show_local_demo()
	else:
		_fetching = true
	_submit_next()


# 响应 get_completed 对应的事件或条件。
func _on_get_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_fetching = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_show_local_demo()
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary or not parsed.get("entries") is Array:
		_show_local_demo()
		return
	entries = (parsed["entries"] as Array).slice(0, MAX_ENTRIES)
	week_start = str(parsed.get("week_start", ""))
	status = "ready"
	EventBus.leaderboard_updated.emit()


# 读取 self_entry，供调用方继续处理。
func get_self_entry() -> Dictionary:
	var player_id := str(GameState.settings.get("leaderboard_player_id", ""))
	for index in range(entries.size()):
		var value: Variant = entries[index]
		if value is Dictionary and str(value.get("player_id", "")) == player_id:
			var result: Dictionary = value.duplicate()
			result["rank"] = int(result.get("rank", index + 1))
			return result
	return _personal_entry()


# 封装 personal_entry 的处理，供相关流程复用。
func _personal_entry() -> Dictionary:
	var player_id := str(GameState.settings.get("leaderboard_player_id", ""))
	var current_week := _utc_week_start(int(Time.get_unix_time_from_system()))
	var best_size := 0
	var fish_id := ""
	if int(GameState.settings.get("leaderboard_week_start", 0)) == current_week:
		best_size = int(GameState.settings.get("leaderboard_best_cm", 0))
		fish_id = str(GameState.settings.get("leaderboard_best_fish_id", ""))
	return {
		"player_id": player_id,
		"display_name": str(GameState.settings.get("leaderboard_display_name", TextDB.text("fishing.leaderboard.player") + "-" + player_id.substr(0, 4))),
		"fish_id": fish_id,
		"size_cm": best_size,
		"rank": 0,
	}


# 显示 local_demo，供调用方继续处理。
func _show_local_demo() -> void:
	var current_week := _utc_week_start(int(Time.get_unix_time_from_system()))
	week_start = Time.get_date_string_from_unix_time(current_week)
	var player_id := str(GameState.settings.get("leaderboard_player_id", ""))
	var rng := RandomNumberGenerator.new()
	rng.seed = current_week + (hash(player_id) & 0x7fffffff)
	var fish_catalog: Array = DataRegistry.get_all("fish")
	entries.clear()
	var bot_count := clampi(GameConfig.get_int("fishing", "leaderboard_demo_bot_count"), 0, MAX_ENTRIES - 1)
	for bot_index in range(bot_count):
		var fish: Dictionary = fish_catalog[rng.randi_range(0, fish_catalog.size() - 1)] if not fish_catalog.is_empty() else {}
		var rarity := str(fish.get("rarity", "common"))
		var minimum := GameConfig.get_int("fishing", rarity + "_size_min_cm")
		var maximum := GameConfig.get_int("fishing", rarity + "_size_max_cm")
		entries.append({
			"player_id": "bot_%02d" % (bot_index + 1),
			"display_name": TextDB.text("fishing.leaderboard.bot") % (bot_index + 1),
			"fish_id": str(fish.get("id", "")),
			"size_cm": rng.randi_range(minimum, maximum),
		})
	entries.append(_personal_entry())
	entries.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_size := int(left.get("size_cm", 0))
		var right_size := int(right.get("size_cm", 0))
		return left_size > right_size if left_size != right_size else str(left.get("player_id", "")) < str(right.get("player_id", ""))
	)
	for index in range(entries.size()):
		(entries[index] as Dictionary)["rank"] = index + 1
	status = "local"
	EventBus.leaderboard_updated.emit()
