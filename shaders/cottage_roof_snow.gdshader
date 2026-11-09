shader_type canvas_item;

uniform float coverage : hint_range(0.0, 1.0) = 1.0;
uniform vec4 chimney_opening = vec4(0.0);

// coverage 控制从左到右的覆盖。chimney_opening 存储烟囱开口的 UV 中心和半尺寸。
void fragment() {
	vec2 uv = UV;
	float edge_detail = sin(uv.y * 38.0) * 0.035 + sin(uv.y * 109.0 + uv.x * 19.0) * 0.012;
	float threshold = clamp((uv.x - 0.14) / 0.72 + edge_detail, 0.025, 0.975);
	float settled = smoothstep(threshold - 0.021, threshold + 0.021, coverage);
	float snow_alpha = smoothstep(0.24, 0.77, COLOR.a);
	vec3 roof_rgb = texture(TEXTURE, uv).rgb;
	float warm_roof = smoothstep(0.14, 0.23, roof_rgb.r - roof_rgb.b);
	snow_alpha *= 1.0 - warm_roof;
	if (chimney_opening.z > 0.0) {
		float corner_radius = 15.0;
		vec2 corner = (abs(uv - chimney_opening.xy) - chimney_opening.zw) / TEXTURE_PIXEL_SIZE + corner_radius;
		float distance_to_chimney = length(max(corner, vec2(0.0))) + min(max(corner.x, corner.y), 0.0) - corner_radius;
		snow_alpha *= smoothstep(-2.0, 3.0, distance_to_chimney);
	}
	COLOR.a = snow_alpha * settled;
}
