extends SceneTree


# 封装 initialize 的处理，供相关流程复用。
func _initialize() -> void:
	call_deferred("_run")


# 封装 run 的处理，供相关流程复用。
func _run() -> void:
	var main: Node = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	main.call("_open_codex")
	await process_frame
	var panel := main.get_node("Overlay/ContextPanel") as PanelContainer
	var surface := panel.get_node("ContentSurface") as Control
	var scroll := surface.get_node("ContentScroll") as ScrollContainer
	var close := surface.get_node("CloseButton") as Button
	print("MODAL_LAYOUT: panel=", panel.size, " surface=", surface.size, " scroll=", scroll.size, " close=", close.position, " ", close.size)
	var ui_font := (main.theme as Theme).default_font
	var has_codex_glyphs := ui_font.has_char("图".unicode_at(0)) and ui_font.has_char("鉴".unicode_at(0))
	print("CODEX_GLYPHS: 图鉴=", has_codex_glyphs)
	if panel.size.x < 500.0 or surface.size.y <= 0.0 or scroll.size.x < 450.0 or not close.visible or not has_codex_glyphs:
		push_error("Codex modal layout is invalid")
		quit(1)
		return
	quit(0)
