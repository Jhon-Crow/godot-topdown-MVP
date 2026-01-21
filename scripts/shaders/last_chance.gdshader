shader_type canvas_item;

// Blue sepia tint color (blue-ish sepia for dramatic effect)
uniform vec3 sepia_color : source_color = vec3(0.3, 0.5, 0.8);

// How strong the sepia/blue tint is (0.0 = none, 1.0 = full)
uniform float sepia_intensity : hint_range(0.0, 1.0) = 0.7;

// Brightness reduction for everything (1.0 = normal, 0.0 = black)
uniform float brightness : hint_range(0.0, 1.0) = 0.6;

// Ripple effect parameters
uniform float ripple_strength : hint_range(0.0, 0.05) = 0.01;
uniform float ripple_frequency : hint_range(1.0, 50.0) = 20.0;
uniform float ripple_speed : hint_range(0.1, 10.0) = 2.0;
uniform float time_offset : hint_range(0.0, 1000.0) = 0.0;

// Screen texture sampler for reading the rendered scene
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	// Calculate ripple distortion
	vec2 center = vec2(0.5, 0.5);
	vec2 uv_from_center = SCREEN_UV - center;
	float dist = length(uv_from_center);

	// Create ripple wave based on distance from center and time
	float ripple = sin(dist * ripple_frequency - time_offset * ripple_speed) * ripple_strength;

	// Apply ripple distortion to UV coordinates
	vec2 distorted_uv = SCREEN_UV + normalize(uv_from_center) * ripple;

	// Sample the screen texture at the distorted UV position
	vec4 screen_color = texture(screen_texture, distorted_uv);

	// Calculate luminance (grayscale value) using standard weights
	float luminance = dot(screen_color.rgb, vec3(0.299, 0.587, 0.114));

	// Create blue sepia effect by mixing grayscale with sepia tint
	vec3 sepia = luminance * sepia_color;

	// Mix original color with sepia based on intensity
	vec3 tinted = mix(screen_color.rgb, sepia, sepia_intensity);

	// Apply brightness reduction
	vec3 final_color = tinted * brightness;

	// Clamp to valid color range
	COLOR = vec4(clamp(final_color, 0.0, 1.0), screen_color.a);
}
