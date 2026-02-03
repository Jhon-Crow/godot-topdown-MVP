shader_type canvas_item;

// ============================================================================
// CINEMA FILM EFFECT SHADER
// Simulates vintage film look with grain, warm tones, and film defects
// ============================================================================

// Screen texture sampler for reading the rendered scene
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

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
uniform float defect_probability : hint_range(0.0, 0.1) = 0.015;  // ~1.5% chance per frame
uniform float scratch_intensity : hint_range(0.0, 1.0) = 0.6;
uniform float dust_intensity : hint_range(0.0, 1.0) = 0.5;
uniform float flicker_intensity : hint_range(0.0, 0.3) = 0.03;


// ============================================================================
// NOISE FUNCTIONS
// Using modulo-based noise to avoid sine wave artifacts
// ============================================================================

// High-quality hash function - avoids sine-based ripple artifacts
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// 2D hash returning vec2
vec2 hash2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// Film grain noise - uses modulo operations to avoid wave patterns
// Based on the technique from godotshaders.com/shader/grain-old-movie/
float film_grain_noise(vec2 uv, float time_factor) {
	// Use FRAGCOORD-based calculation for consistent grain size
	vec2 resolution = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 pos = uv * resolution;

	// Modulo-based noise generation - no sine waves = no ripple artifacts
	float x = (pos.x + 4.0) * (pos.y + 4.0) * (time_factor);
	float grain = mod(mod(x, 13.0) * mod(x, 123.0), 0.01) - 0.005;

	return grain * 200.0;  // Scale to usable range
}


// ============================================================================
// FILM DEFECT FUNCTIONS
// ============================================================================

// Generate vertical scratch line
float vertical_scratch(vec2 uv, float time_val) {
	// Determine if a scratch should appear this frame (based on rounded time)
	float frame = floor(time_val * 8.0);  // ~8 potential scratches per second max
	float scratch_seed = hash(vec2(frame, frame * 0.7));

	// Only show scratch occasionally based on probability
	if (scratch_seed > defect_probability * 4.0) {
		return 0.0;
	}

	// Random X position for the scratch
	float scratch_x = hash(vec2(frame * 1.3, frame));

	// Scratch width and position
	float scratch_width = 0.002 + hash(vec2(frame, 0.0)) * 0.003;
	float dist_to_scratch = abs(uv.x - scratch_x);

	// Scratch visibility (sharp edges)
	float scratch = 1.0 - smoothstep(0.0, scratch_width, dist_to_scratch);

	// Add some variation in scratch brightness along Y
	scratch *= 0.7 + 0.3 * hash(vec2(uv.y * 50.0, frame));

	return scratch;
}

// Generate dust particles
float dust_particles(vec2 uv, float time_val) {
	float frame = floor(time_val * 6.0);  // Dust changes ~6 times per second
	float dust = 0.0;

	// Generate a few dust particles
	for (int i = 0; i < 3; i++) {
		float seed = float(i) * 123.456;
		float dust_seed = hash(vec2(frame + seed, frame * 0.5 + seed));

		// Only show dust based on probability
		if (dust_seed < defect_probability * 3.0) {
			vec2 dust_pos = hash2(vec2(frame + seed, seed));
			float dist = length(uv - dust_pos);
			float size = 0.003 + hash(vec2(seed, frame)) * 0.008;
			dust += (1.0 - smoothstep(0.0, size, dist)) * 0.5;
		}
	}

	return min(dust, 1.0);
}

// Frame brightness flicker (simulates projector variations)
float projector_flicker(float time_val) {
	// Slow base flicker
	float slow_flicker = hash(vec2(floor(time_val * 2.0), 0.0)) * 0.5 + 0.75;

	// Occasional stronger flicker
	float flicker_frame = floor(time_val * 24.0);
	float strong_flicker = hash(vec2(flicker_frame, flicker_frame * 0.3));

	if (strong_flicker < defect_probability) {
		return 0.85 + hash(vec2(flicker_frame, 0.0)) * 0.3;
	}

	return mix(1.0, slow_flicker, flicker_intensity);
}


// ============================================================================
// MAIN FRAGMENT SHADER
// ============================================================================

void fragment() {
	// Sample the screen texture
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	vec3 color = screen_color.rgb;

	// Calculate pixel brightness for effects that depend on it
	float pixel_brightness = dot(color, vec3(0.299, 0.587, 0.114));

	// --- Apply Film Grain ---
	if (grain_enabled && grain_intensity > 0.0) {
		// Use frame-based time to prevent smooth wave transitions
		float time_factor = floor(TIME * 24.0) * 0.5;  // ~24 fps grain update
		float grain = film_grain_noise(SCREEN_UV, time_factor);

		// Apply grain more strongly to mid-tones, less to very bright/dark areas
		float grain_weight = 1.0 - abs(pixel_brightness - 0.5) * 0.5;
		color += vec3(grain * grain_intensity * grain_weight);
	}

	// --- Apply Sunny/Bright Effect ---
	if (sunny_enabled && sunny_intensity > 0.0) {
		// Add subtle golden highlight to bright areas
		vec3 sunny_tint = vec3(1.0, 0.98, 0.9);  // Slight golden

		// Boost highlights
		float highlight_mask = smoothstep(0.5, 1.0, pixel_brightness);
		color = mix(color, color * sunny_highlight_boost, highlight_mask * sunny_intensity);

		// Add subtle warm bloom to the whole image
		color += sunny_tint * sunny_intensity * 0.1;
	}

	// --- Apply Warm Color Tint ---
	if (warm_enabled && warm_intensity > 0.0) {
		// Multiplicative warm tint - preserves more color detail than luminance-based
		vec3 warm_tinted = color * warm_color;
		color = mix(color, warm_tinted, warm_intensity);
	}

	// --- Apply Vignette ---
	if (vignette_enabled && vignette_intensity > 0.0) {
		// Distance from center (0,0 at center, 1.0 at corners)
		vec2 centered_uv = SCREEN_UV - 0.5;
		float vignette_dist = length(centered_uv) * 1.414;  // Normalize to ~1.0 at corners

		// Soft vignette falloff
		float vignette = 1.0 - smoothstep(vignette_softness, 1.0, vignette_dist);
		vignette = mix(1.0, vignette, vignette_intensity);

		color *= vignette;
	}

	// --- Apply Film Defects (rare effects) ---
	if (defects_enabled) {
		// Scratches
		float scratch = vertical_scratch(SCREEN_UV, TIME);
		color = mix(color, vec3(0.9, 0.88, 0.85), scratch * scratch_intensity);

		// Dust particles
		float dust = dust_particles(SCREEN_UV, TIME);
		color = mix(color, vec3(0.1, 0.1, 0.1), dust * dust_intensity);

		// Projector flicker
		float flicker = projector_flicker(TIME);
		color *= flicker;
	}

	// --- Apply Brightness and Contrast ---
	// Contrast adjustment (expand around 0.5)
	color = (color - 0.5) * contrast + 0.5;

	// Brightness adjustment
	color *= brightness;

	// Clamp to valid color range
	COLOR = vec4(clamp(color, 0.0, 1.0), screen_color.a);
}
