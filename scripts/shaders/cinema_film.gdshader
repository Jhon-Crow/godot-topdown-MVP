shader_type canvas_item;

// ============================================================================
// CINEMA FILM EFFECT SHADER v3.0
// Simulates vintage film look with grain, warm tones, and film defects
// Fixed: White screen issue in gl_compatibility mode
// Fix: Use textureLod() and filter_nearest for Compatibility renderer support
// Reference: https://github.com/godotengine/godot/issues/79914
// ============================================================================

// Screen texture sampler for reading the rendered scene
// IMPORTANT: Use filter_nearest and repeat_disable for gl_compatibility mode
// Using filter_linear_mipmap can cause issues (pink lines, white screen) in Compatibility renderer
// The textureLod() function must be used instead of texture() for proper sampling
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

// --- Film Grain Parameters ---
uniform float grain_intensity : hint_range(0.0, 0.5) = 0.04;
uniform bool grain_enabled = true;

// --- Warm/Sunny Color Tint Parameters ---
uniform vec3 warm_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float warm_intensity : hint_range(0.0, 1.0) = 0.12;
uniform bool warm_enabled = true;

// --- Sunny/Bright Effect Parameters ---
uniform float sunny_intensity : hint_range(0.0, 0.5) = 0.08;
uniform float sunny_highlight_boost : hint_range(1.0, 2.0) = 1.15;
uniform bool sunny_enabled = true;

// --- Vignette Parameters ---
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.25;
uniform float vignette_softness : hint_range(0.0, 1.0) = 0.45;
uniform bool vignette_enabled = true;

// --- Master Brightness/Contrast ---
uniform float brightness : hint_range(0.5, 1.5) = 1.05;
uniform float contrast : hint_range(0.5, 2.0) = 1.05;

// --- Film Defects Parameters (rare effects) ---
uniform bool defects_enabled = true;
uniform float defect_probability : hint_range(0.0, 0.1) = 0.015;
uniform float scratch_intensity : hint_range(0.0, 1.0) = 0.6;
uniform float dust_intensity : hint_range(0.0, 1.0) = 0.5;
uniform float flicker_intensity : hint_range(0.0, 0.3) = 0.03;


// ============================================================================
// NOISE FUNCTIONS
// Robust hash functions that work well with any input
// ============================================================================

// High-quality hash function with better distribution
// Avoids returning 0 for zero inputs by adding offset
float hash(vec2 p) {
	// Add small offset to avoid zero-input issues
	p += vec2(0.1, 0.1);
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// 2D hash returning vec2
vec2 hash2(vec2 p) {
	p += vec2(0.1, 0.1);
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// Simple, stable film grain noise
// Returns value in range [-0.5, 0.5]
float film_grain(vec2 uv, float seed) {
	// Simple hash-based noise that's stable across all frame times
	float noise = hash(uv * 1000.0 + vec2(seed, seed * 0.7));
	return noise - 0.5;  // Center around zero
}


// ============================================================================
// FILM DEFECT FUNCTIONS
// ============================================================================

// Generate vertical scratch line (rare)
float vertical_scratch(vec2 uv, float time_val) {
	float frame = floor(time_val * 8.0) + 1.0;  // +1 to avoid frame 0
	float scratch_seed = hash(vec2(frame, frame * 0.7));

	// Only show scratch very occasionally
	if (scratch_seed > defect_probability * 4.0) {
		return 0.0;
	}

	// Random X position for the scratch
	float scratch_x = hash(vec2(frame * 1.3 + 0.5, frame + 0.5));

	// Scratch width
	float scratch_width = 0.002 + hash(vec2(frame + 0.1, 0.5)) * 0.003;
	float dist_to_scratch = abs(uv.x - scratch_x);

	// Scratch visibility (sharp edges)
	float scratch = 1.0 - smoothstep(0.0, scratch_width, dist_to_scratch);

	// Add Y variation
	scratch *= 0.7 + 0.3 * hash(vec2(uv.y * 50.0 + 0.1, frame + 0.1));

	return scratch;
}

// Generate dust particles (rare)
float dust_particles(vec2 uv, float time_val) {
	float frame = floor(time_val * 6.0) + 1.0;
	float dust = 0.0;

	for (int i = 0; i < 3; i++) {
		float seed = float(i) * 123.456 + 1.0;
		float dust_seed = hash(vec2(frame + seed, frame * 0.5 + seed));

		if (dust_seed < defect_probability * 3.0) {
			vec2 dust_pos = hash2(vec2(frame + seed + 0.5, seed + 0.5));
			float dist = length(uv - dust_pos);
			float size = 0.003 + hash(vec2(seed + 0.2, frame + 0.2)) * 0.008;
			dust += (1.0 - smoothstep(0.0, size, dist)) * 0.4;
		}
	}

	return min(dust, 0.8);  // Cap at 0.8 to prevent too dark spots
}

// Frame brightness flicker
float projector_flicker(float time_val) {
	float flicker_frame = floor(time_val * 24.0) + 1.0;
	float strong_flicker = hash(vec2(flicker_frame + 0.5, flicker_frame * 0.3 + 0.5));

	// Occasional stronger flicker
	if (strong_flicker < defect_probability) {
		return 0.92 + hash(vec2(flicker_frame + 0.7, 0.5)) * 0.16;  // Range: 0.92-1.08
	}

	// Subtle base flicker
	float slow_flicker = hash(vec2(floor(time_val * 2.0) + 0.5, 0.5)) * 0.04 + 0.98;  // Range: 0.98-1.02
	return mix(1.0, slow_flicker, flicker_intensity);
}


// ============================================================================
// MAIN FRAGMENT SHADER
// ============================================================================

void fragment() {
	// Sample the screen texture using textureLod for gl_compatibility mode support
	// Using texture() instead of textureLod() can cause white screen or pink grid lines
	// in Compatibility renderer (Issue #79914)
	vec4 screen_color = textureLod(screen_texture, SCREEN_UV, 0.0);
	vec3 color = screen_color.rgb;

	// Early exit if screen_color alpha is 0 (no content rendered yet)
	// This can happen on the first frame before the scene is fully rendered
	if (screen_color.a < 0.001) {
		COLOR = screen_color;
		return;
	}

	// Calculate pixel brightness for effects that depend on it
	float pixel_brightness = dot(color, vec3(0.299, 0.587, 0.114));

	// --- Apply Film Grain ---
	if (grain_enabled && grain_intensity > 0.0) {
		// Use frame-based seed for animated grain
		float seed = floor(TIME * 24.0 + 0.5);  // +0.5 to avoid exact zero
		float grain = film_grain(SCREEN_UV, seed);

		// Apply grain more strongly to mid-tones
		float grain_weight = 1.0 - abs(pixel_brightness - 0.5) * 0.6;
		color += vec3(grain * grain_intensity * grain_weight);
	}

	// --- Apply Sunny/Bright Effect ---
	if (sunny_enabled && sunny_intensity > 0.0) {
		// Boost highlights gently
		float highlight_mask = smoothstep(0.5, 1.0, pixel_brightness);
		float boost_amount = highlight_mask * sunny_intensity;
		color = mix(color, color * sunny_highlight_boost, boost_amount);

		// Subtle warm bloom
		vec3 sunny_tint = vec3(1.0, 0.98, 0.92);
		color += sunny_tint * sunny_intensity * 0.05;  // Reduced from 0.1
	}

	// --- Apply Warm Color Tint ---
	if (warm_enabled && warm_intensity > 0.0) {
		vec3 warm_tinted = color * warm_color;
		color = mix(color, warm_tinted, warm_intensity);
	}

	// --- Apply Vignette ---
	if (vignette_enabled && vignette_intensity > 0.0) {
		vec2 centered_uv = SCREEN_UV - 0.5;
		float vignette_dist = length(centered_uv) * 1.414;
		float vignette = 1.0 - smoothstep(vignette_softness, 1.0, vignette_dist);
		vignette = mix(1.0, vignette, vignette_intensity);
		color *= vignette;
	}

	// --- Apply Film Defects (rare effects) ---
	if (defects_enabled) {
		// Scratches (add slight brightness)
		float scratch = vertical_scratch(SCREEN_UV, TIME);
		color = mix(color, vec3(0.85, 0.83, 0.8), scratch * scratch_intensity * 0.5);

		// Dust particles (darken)
		float dust = dust_particles(SCREEN_UV, TIME);
		color = mix(color, color * 0.3, dust * dust_intensity);

		// Projector flicker
		float flicker = projector_flicker(TIME);
		color *= flicker;
	}

	// --- Apply Brightness and Contrast ---
	// Apply contrast (expand around 0.5)
	color = (color - 0.5) * contrast + 0.5;

	// Apply brightness
	color *= brightness;

	// Clamp to valid color range
	COLOR = vec4(clamp(color, 0.0, 1.0), screen_color.a);
}
