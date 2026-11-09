extends Node

var _player: AudioStreamPlayer

# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "BackgroundMusic"
	var music := load("res://assets/audio/pond_days.wav") as AudioStreamWAV
	music.loop_mode = AudioStreamWAV.LOOP_FORWARD
	music.loop_begin = 0
	music.loop_end = music.data.size() / 4
	_player.stream = music
	_player.volume_db = -14.0
	add_child(_player)
	get_node("/root/EventBus").connect("game_loaded", _sync)
	call_deferred("_sync")

# 判断是否满足 enabled 对应的条件。
func is_enabled() -> bool:
	return bool(get_node("/root/GameState").settings.get("music_enabled", true))

# 设置 enabled，供调用方继续处理。
func set_enabled(enabled: bool) -> void:
	get_node("/root/GameState").settings["music_enabled"] = enabled
	_sync()
	get_node("/root/SaveManager").request_save()

# 封装 sync 的处理，供相关流程复用。
func _sync() -> void:
	sync_effects()
	if is_enabled():
		if not _player.playing:
			_player.play()
	else:
		_player.stop()


# 同步 effects，供调用方继续处理。
func sync_effects() -> void:
	var bus := AudioServer.get_bus_index("SFX")
	if bus >= 0:
		AudioServer.set_bus_mute(bus, not bool(get_node("/root/GameState").settings.get("sfx_enabled", true)))
