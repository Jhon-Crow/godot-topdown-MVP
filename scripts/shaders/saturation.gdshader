shader_type canvas_item;

// Amount of saturation boost to apply (0.0 = normal, 2.0 = 3x saturation, etc.)
// Formula: multiplier = 1.0 + saturation_boost, so boost of 2.0 = 3x saturation
uniform float saturation_boost : hint_range(0.0, 10.0) = 0.0;

// Amount of contrast boost to apply (0.0 = normal, 1.0 = 2x contrast)
// Formula: contrast_factor = 1.0 + contrast_boost
uniform float contrast_boost : hint_range(0.0, 10.0) = 0.0;

// Screen texture sampler for reading the rendered scene
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	// Sample the screen texture at the current screen UV position
	vec4 screen_color = texture(screen_texture, SCREEN_UV);

	// Calculate luminance (grayscale value) using standard weights
	float luminance = dot(screen_color.rgb, vec3(0.299, 0.587, 0.114));

	// Increase saturation by moving away from grayscale
	// saturation_boost of 2.0 means 3x more vivid colors (1 + 2 = 3)
	float saturation_multiplier = 1.0 + saturation_boost;
	vec3 saturated = mix(vec3(luminance), screen_color.rgb, saturation_multiplier);

	// Apply contrast adjustment
	// contrast_boost of 1.0 means 2x contrast (1 + 1 = 2)
	float contrast_factor = 1.0 + contrast_boost;
	vec3 contrasted = (saturated - 0.5) * contrast_factor + 0.5;

	// Clamp to valid color range
	COLOR = vec4(clamp(contrasted, 0.0, 1.0), screen_color.a);
}
