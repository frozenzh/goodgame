shader_type canvas_item;
render_mode blend_mix;

// Widths are measured in source-texture pixels. Each building uses its own
// material so the visible outline stays similar after Sprite2D scaling.
uniform vec4 outline_color : source_color = vec4(0.10, 0.065, 0.045, 1.0);
uniform float resting_width_texels : hint_range(0.0, 64.0, 1.0) = 15.0;
uniform float hover_width_texels : hint_range(0.0, 96.0, 1.0) = 30.0;
uniform float hovered : hint_range(0.0, 1.0) = 0.0;

// 逐像素计算片元颜色和透明度。
void fragment() {
	vec4 original = texture(TEXTURE, UV);
	float radius = mix(resting_width_texels, hover_width_texels, hovered);
	float neighbor_alpha = 0.0;
	for (int i = 0; i < 16; i++) {
		float angle = float(i) * 6.28318530718 / 16.0;
		vec2 offset = vec2(cos(angle), sin(angle)) * TEXTURE_PIXEL_SIZE * radius;
		neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + offset).a);
	}
	float outline = (1.0 - step(0.12, original.a)) * step(0.5, neighbor_alpha);
	float strength = mix(0.62, 0.95, hovered) * outline * outline_color.a;
	COLOR = vec4(mix(outline_color.rgb, original.rgb, original.a), max(original.a, strength));
}
