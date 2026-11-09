shader_type canvas_item;

uniform float sway_pixels : hint_range(0.0, 48.0, 0.5) = 30.0;
uniform float cycle_seconds : hint_range(1.0, 10.0, 0.1) = 2.8;
uniform int frame_count : hint_range(4, 16, 1) = 8;

// 封装 region_mask 的处理，供相关流程复用。
float region_mask(vec2 uv, vec2 top_left, vec2 bottom_right) {
	vec2 enter = smoothstep(top_left, top_left + vec2(0.006), uv);
	vec2 leave = 1.0 - smoothstep(bottom_right - vec2(0.006), bottom_right, uv);
	return enter.x * enter.y * leave.x * leave.y;
}

// 封装 leaf_mask 的处理，供相关流程复用。
float leaf_mask(vec4 pixel_color) {
	float green_over_red = pixel_color.g - pixel_color.r * 1.15;
	float green_over_blue = pixel_color.g - pixel_color.b * 1.3;
	// 封装 smoothstep 的处理，供相关流程复用。
	return smoothstep(0.0, 0.12, green_over_red) * smoothstep(0.0, 0.12, green_over_blue);
}

// 逐像素计算片元颜色和透明度。
void fragment() {
	vec2 uv = UV;
	vec4 still = texture(TEXTURE, uv);
	float frames = max(float(frame_count), 1.0);
	float frame = floor(mod(TIME / max(cycle_seconds, 0.1) * frames, frames));
	float phase = frame * 6.2831853 / frames;
	float left_back = region_mask(uv, vec2(0.184, 0.06), vec2(0.309, 0.35));
	float right_back = region_mask(uv, vec2(0.765, 0.0), vec2(0.924, 0.47));
	float left_front = region_mask(uv, vec2(0.098, 0.665), vec2(0.216, 0.905));
	float right_front = region_mask(uv, vec2(0.782, 0.62), vec2(0.917, 0.90));
	float sway = sin(phase) * left_back * clamp((0.35 - uv.y) / 0.27, 0.0, 1.0);
	sway += sin(phase + 1.3) * right_back * clamp((0.47 - uv.y) / 0.40, 0.0, 1.0);
	sway += sin(phase + 2.0) * left_front * clamp((0.905 - uv.y) / 0.24, 0.0, 1.0);
	sway += sin(phase + 0.7) * right_front * clamp((0.90 - uv.y) / 0.28, 0.0, 1.0);
	vec4 shifted = texture(TEXTURE, uv + vec2(sway * sway_pixels * TEXTURE_PIXEL_SIZE.x, 0.0));
	float leaves = max(leaf_mask(still), leaf_mask(shifted));
	vec2 outline_step = TEXTURE_PIXEL_SIZE * 3.0;
	leaves = max(leaves, leaf_mask(texture(TEXTURE, uv + vec2(outline_step.x, 0.0))));
	leaves = max(leaves, leaf_mask(texture(TEXTURE, uv - vec2(outline_step.x, 0.0))));
	leaves = max(leaves, leaf_mask(texture(TEXTURE, uv + vec2(0.0, outline_step.y))));
	leaves = max(leaves, leaf_mask(texture(TEXTURE, uv - vec2(0.0, outline_step.y))));
	COLOR = mix(still, shifted, step(0.01, abs(sway)) * leaves);
}
