# 定义 SnowPile 的状态和可用操作。
class_name SnowPile
extends Sprite2D

## Authored world placement; WeatherVisual only changes visibility and opacity.
@export_range(0.0, 1.0, 0.01) var appear_fraction := 0.05
@export_range(0.01, 0.5, 0.01) var fade_fraction := 0.08
