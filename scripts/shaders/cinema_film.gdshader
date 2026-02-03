shader_type canvas_item;

// Film grain effect parameters
// The grain creates a noise pattern that animates over time, simulating film grain
uniform float grain_intensity : hint_range(0.0, 0.5) = 0.05;
uniform float grain_speed : hint_range(0.0, 100.0) = 15.0;

// Warm color tint parameters
// Creates a vintage/cinematic look by shifting colors toward warm tones
uniform vec3 warm_color : source_color = vec3(1.0, 0.9, 0.7);
uniform float warm_intensity : hint_range(0.0, 1.0) = 0.15;

// Master brightness control
uniform float brightness : hint_range(0.5, 1.5) = 1.0;

// Effect toggles for flexibility
uniform bool grain_enabled = true;
uniform bool warm_enabled = true;

// Screen texture sampler for reading the rendered scene
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;


// Pseudo-random noise function based on UV coordinates and time
// Returns value in range [-1, 1]
float random_noise(vec2 uv, float time_seed) {
	// Use sine-based hash function for pseudo-random values
	// The large constant creates high-frequency variation
	float noise = fract(sin(dot(uv + vec2(time_seed, time_seed * 0.7), vec2(12.9898, 78.233))) * 43758.5453);
	// Convert from [0, 1] to [-1, 1] range
	return (noise - 0.5) * 2.0;
}


void fragment() {
	// Sample the screen texture at the current screen UV position
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	vec3 final_color = screen_color.rgb;

	// Apply film grain effect
	if (grain_enabled && grain_intensity > 0.0) {
		// Generate animated noise using TIME for variation
		// Multiply UV by screen position for consistent grain size
		float noise = random_noise(SCREEN_UV * 100.0, TIME * grain_speed);

		// Add noise to the color - this creates the film grain look
		final_color += vec3(noise * grain_intensity);
	}

	// Apply warm color tint effect
	if (warm_enabled && warm_intensity > 0.0) {
		// Calculate luminance (grayscale value) using standard perceptual weights
		// These weights account for human eye sensitivity to different colors
		float luminance = dot(final_color, vec3(0.299, 0.587, 0.114));

		// Create warm tinted version by multiplying luminance with warm color
		vec3 warm_tinted = luminance * warm_color;

		// Blend between original and warm-tinted based on intensity
		// Low intensity preserves most color, high intensity shifts toward warm
		final_color = mix(final_color, warm_tinted, warm_intensity);

		// Alternative approach: additive tint that preserves more original color
		// Uncomment below for a subtler warm shift:
		// final_color = final_color * mix(vec3(1.0), warm_color, warm_intensity);
	}

	// Apply brightness adjustment
	final_color *= brightness;

	// Clamp to valid color range to prevent artifacts
	COLOR = vec4(clamp(final_color, 0.0, 1.0), screen_color.a);
}
