shader_type canvas_item;
render_mode blend_mix;

// Widths are measured in source-texture pixels. Each building uses its own
// material so the visible outline stays similar after Sprite2D scaling.
uniform vec4 outline_color : source_color = vec4(0.10, 0.065, 0.045, 1.0);
uniform vec4 hover_outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float resting_width_texels : hint_range(0.0, 64.0, 1.0) = 15.0;
uniform float hover_width_texels : hint_range(0.0, 96.0, 1.0) = 30.0;
uniform float hovered : hint_range(0.0, 1.0) = 0.0;

// 沿透明轮廓采样四周；悬停时切换黑边，贴图外按透明处理，避免采到对侧边缘。
void fragment() {
	vec4 original = texture(TEXTURE, UV);
	float radius = mix(resting_width_texels, hover_width_texels, hovered);
	float neighbor_alpha = 0.0;
	for (int i = 0; i < 16; i++) {
		float angle = float(i) * 6.28318530718 / 16.0;
		vec2 offset = vec2(cos(angle), sin(angle)) * TEXTURE_PIXEL_SIZE * radius;
		vec2 sample_uv = UV + offset;
		if (sample_uv.x >= 0.0 && sample_uv.x <= 1.0 && sample_uv.y >= 0.0 && sample_uv.y <= 1.0) {
			neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, sample_uv).a);
		}
	}
	float outline = (1.0 - step(0.12, original.a)) * step(0.5, neighbor_alpha);
	vec4 border_color = mix(outline_color, hover_outline_color, hovered);
	float strength = mix(0.62, 1.0, hovered) * outline * border_color.a;
	float combined_alpha = original.a + strength * (1.0 - original.a);
	vec3 combined_rgb = (original.rgb * original.a + border_color.rgb * strength * (1.0 - original.a)) / max(combined_alpha, 0.0001);
	COLOR = vec4(combined_rgb, combined_alpha);
}
