shader_type canvas_item;
render_mode unshaded;

uniform sampler2D pond_texture : source_color, filter_nearest;
uniform sampler2D shore_distance_texture : filter_linear, repeat_disable;
uniform float freeze_progress : hint_range(0.0, 1.0) = 0.0;
uniform float melt_opacity : hint_range(0.0, 1.0) = 1.0;

// 逐像素计算片元颜色和透明度。
void fragment() {
	vec4 pond = texture(pond_texture, UV);
	vec4 ice = texture(TEXTURE, UV);
	// 原池塘的蓝色水域决定冰层边界，石头、芦苇和木板保持原样。
	float blue_excess = pond.b - max(pond.r * 1.45, pond.g * 1.08);
	float water_mask = pond.a * smoothstep(0.02, 0.11, blue_excess) * smoothstep(0.35, 0.48, pond.b);
	// 距岸遮罩从原水域轮廓生成，数值由岸边的 0 增至水域内部的 1。
	float shore_distance = texture(shore_distance_texture, UV).r;
	float frozen_side = 1.0 - smoothstep(freeze_progress - 0.025, freeze_progress + 0.025, shore_distance);
	if (freeze_progress <= 0.0) {
		frozen_side = 0.0;
	} else if (freeze_progress >= 1.0) {
		frozen_side = 1.0;
	}
	// 生图冰面的透明留白用同色浅冰补齐，实际轮廓仍由原池塘控制。
	vec3 ice_color = mix(vec3(0.59, 0.82, 0.91), ice.rgb, smoothstep(0.02, 0.3, ice.a));
	COLOR = vec4(mix(pond.rgb, ice_color, 0.9), water_mask * frozen_side * melt_opacity);
}
