shader_type canvas_item;

// 逐像素计算片元颜色和透明度。
void fragment() {
	vec4 texel = texture(TEXTURE, UV);
	float brightness = dot(texel.rgb, vec3(0.299, 0.587, 0.114));
	float subject = smoothstep(0.20, 0.30, brightness);
	COLOR = vec4(vec3(0.0), texel.a * subject);
}
