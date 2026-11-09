shader_type canvas_item;
render_mode unshaded;

uniform vec2 tile_count = vec2(6.0, 1.5);
uniform float edge_width : hint_range(0.01, 0.3) = 0.08;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float clear_progress : hint_range(0.0, 1.0) = 0.0;
uniform float clear_softness : hint_range(0.01, 0.2) = 0.07;

// 逐像素计算片元颜色和透明度。
void fragment() {
	// 镜像重复：任一边界两侧会取到同一个像素，放大遮罩也不露接缝。
	vec2 repeated_uv = 1.0 - abs(mod(UV * tile_count, 2.0) - 1.0);
	vec4 cloud = texture(TEXTURE, repeated_uv);
	vec3 white_cloud = mix(vec3(1.0), cloud.rgb, cloud.a);
	float stepped_y = floor(UV.y * 38.0) / 38.0;
	float wobble = sin(stepped_y * 25.0) * 0.004 + sin(stepped_y * 57.0 + 0.8) * 0.002;
	float edge = smoothstep(0.0, edge_width, 1.0 - UV.x + wobble);
	float distance_from_right = 1.0 - UV.x + wobble;
	float clearing = smoothstep(clear_progress - clear_softness, clear_progress + clear_softness, distance_from_right);
	COLOR = vec4(white_cloud, edge * clearing * opacity);
}
