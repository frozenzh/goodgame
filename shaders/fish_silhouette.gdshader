shader_type canvas_item;

// 逐像素计算片元颜色和透明度。
void fragment() {
	float alpha = texture(TEXTURE, UV).a;
	COLOR = vec4(0.0, 0.0, 0.0, alpha);
}
