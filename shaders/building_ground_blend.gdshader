shader_type canvas_item;

// Keep the packed-earth edge uneven at pixel-art scale while the building moves.
varying vec2 ground_local_pos;

// 在光栅化前调整顶点坐标或准备插值数据。
void vertex() {
	ground_local_pos = VERTEX;
}

// 逐像素计算片元颜色和透明度。
void fragment() {
	vec2 cell = floor(ground_local_pos / 3.0);
	float grain = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
	COLOR.rgb *= 0.94 + grain * 0.10;
	COLOR.a *= 0.55 + grain * 0.45;
}
