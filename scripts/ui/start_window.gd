extends Window

## The authored start window stays above the cottage. Adjust these in Inspector.
@export_group("桌面定位")
@export var follow_main: bool = true
@export var desktop_offset: Vector2i = Vector2i(0, 64)
