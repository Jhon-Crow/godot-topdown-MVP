shader_type canvas_item;

// Amount of saturation boost to apply (0.0 = normal, 1.0 = highly saturated)
uniform float saturation_boost : hint_range(0.0, 1.0) = 0.0;

// Screen texture sampler for reading the rendered scene
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	// Sample the screen texture at the current screen UV position
	vec4 screen_color = texture(screen_texture, SCREEN_UV);

	// Calculate luminance (grayscale value) using standard weights
	float luminance = dot(screen_color.rgb, vec3(0.299, 0.587, 0.114));

	// Increase saturation by moving away from grayscale
	// saturation_boost of 0.4 means 40% more vivid colors
	float saturation_multiplier = 1.0 + saturation_boost;
	vec3 saturated = mix(vec3(luminance), screen_color.rgb, saturation_multiplier);

	// Clamp to valid color range
	COLOR = vec4(clamp(saturated, 0.0, 1.0), screen_color.a);
}
