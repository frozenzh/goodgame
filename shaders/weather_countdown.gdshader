shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float gray_strength : hint_range(0.0, 1.0) = 0.92;

// 逐像素计算片元颜色和透明度。
void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec2 position = UV - vec2(0.5);
	float angle = atan(position.x, -position.y);
	if (angle < 0.0) {
		angle += 6.2831853;
	}
	float covered = step(angle, progress * 6.2831853);
	float gray = dot(source.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(source.rgb, vec3(gray * 0.64), gray_strength), source.a * covered);
}
