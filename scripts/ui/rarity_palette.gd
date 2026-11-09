# 定义 RarityPalette 的状态和可用操作。
class_name RarityPalette
extends RefCounted

## 稀有度字段沿用目录中的英文值；资源卡的四种颜色由这里统一映射。
const COMMON := preload("res://assets/hd/ui/rarity_common.png")
const GOOD := preload("res://assets/hd/ui/rarity_good.png")
const EPIC := preload("res://assets/hd/ui/rarity_epic.png")
const RARE := preload("res://assets/hd/ui/rarity_rare.png")
const COMMON_WIDE := preload("res://assets/hd/ui/rarity_common_wide.png")
const GOOD_WIDE := preload("res://assets/hd/ui/rarity_good_wide.png")
const EPIC_WIDE := preload("res://assets/hd/ui/rarity_epic_wide.png")
const RARE_WIDE := preload("res://assets/hd/ui/rarity_rare_wide.png")


# 品质文字使用适合浅色面板的深色调，沿用普通绿、优秀蓝、稀有紫、史诗金的统一映射。
static func text_color_for(rarity: String) -> Color:
	match rarity:
		"good":
			return Color("#2f75ba")
		"rare":
			return Color("#9950b6")
		"epic":
			return Color("#af7919")
		_:
			return Color("#398942")


# 封装 texture_for 的处理，供相关流程复用。
static func texture_for(rarity: String, wide: bool = false) -> Texture2D:
	match rarity:
		"good":
			return GOOD_WIDE if wide else GOOD
		"epic":
			return EPIC_WIDE if wide else EPIC
		"rare":
			return RARE_WIDE if wide else RARE
		_:
			return COMMON_WIDE if wide else COMMON
