shader_type canvas_item;

uniform float hop_height : hint_range(0.0, 8.0, 0.25) = 3.0;
uniform float cycle_seconds : hint_range(0.4, 3.0, 0.05) = 0.95;

// 以编辑器摆放的位置为落点。hop_height 使用贴图局部像素，cycle_seconds 为一次跳动的秒数。
void vertex() {
	float phase = fract(TIME / cycle_seconds);
	float lift = sin(phase * PI);
	VERTEX.y -= hop_height * lift * lift;
}
