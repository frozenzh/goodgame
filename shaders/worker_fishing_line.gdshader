shader_type canvas_item;

// 按当前帧裁掉竿尖下方的原鱼线，角色和鱼竿仍使用原贴图。
uniform vec2 line_cutoff = vec2(2.0);

void fragment() {
	if (UV.x >= line_cutoff.x && UV.y >= line_cutoff.y) {
		COLOR.a = 0.0;
	}
}
