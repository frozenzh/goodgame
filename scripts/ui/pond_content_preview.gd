@tool
extends Control

## Only selects which authored list is visible while arranging PondWindow in the editor.
@export_enum("鱼饵", "鱼竿", "排行") var editor_preview_tab: String = "鱼饵":
	set(value):
		editor_preview_tab = value
		if Engine.is_editor_hint() and is_node_ready():
			_apply_editor_preview()


# 节点及子节点就绪后完成初始化与信号绑定。
func _ready() -> void:
	if Engine.is_editor_hint():
		call_deferred("_apply_editor_preview")


# 应用 editor_preview，供调用方继续处理。
func _apply_editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	var bait_viewport := get_node_or_null("BaitViewport") as Control
	var rod_viewport := get_node_or_null("RodViewport") as Control
	var leaderboard := get_node_or_null("LeaderboardPage") as Control
	if bait_viewport != null:
		bait_viewport.visible = editor_preview_tab == "鱼饵"
	if rod_viewport != null:
		rod_viewport.visible = editor_preview_tab == "鱼竿"
	if leaderboard != null:
		leaderboard.visible = editor_preview_tab == "排行"
	for node_name in ["Status", "IdleAutoFish", "FishingButton", "outline", "outline2"]:
		var control := get_node_or_null(node_name) as Control
		if control != null:
			control.visible = editor_preview_tab != "排行"
