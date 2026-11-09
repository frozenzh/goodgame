shader_type canvas_item;

// 逐像素计算片元颜色和透明度。
void fragment() {
	vec4 texel = texture(TEXTURE, UV);
	float gray = dot(texel.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(vec3(gray) * 0.72, texel.a);
}
