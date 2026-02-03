shader_type canvas_item;

// ============================================================================
// CINEMA FILM EFFECT SHADER v4.0
// Simulates vintage film look with grain, warm tones, and film defects
//
// APPROACH: OVERLAY-BASED (no screen_texture)
// This shader creates visual overlays that blend on top of the rendered scene
// using blend modes, rather than sampling the screen texture.
//
// Why this approach:
// - gl_compatibility renderer has known bugs with hint_screen_texture
// - Multiple screen-reading shaders can conflict
// - Overlay approach is more reliable across all renderers
//
// References:
// - GitHub Issue #79914: screen_texture glitches in Compatibility mode
// - GitHub Issue #66458: OpenGL Compatibility renderer issues tracker
// ============================================================================

// --- Film Grain Parameters ---
uniform float grain_intensity : hint_range(0.0, 0.5) = 0.04;
uniform bool grain_enabled = true;

// --- Warm/Sunny Color Tint Parameters ---
// These use a warm overlay color that blends with the scene
uniform vec3 warm_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float warm_intensity : hint_range(0.0, 1.0) = 0.12;
uniform bool warm_enabled = true;

// --- Sunny/Bright Effect Parameters ---
uniform float sunny_intensity : hint_range(0.0, 0.5) = 0.08;
uniform bool sunny_enabled = true;

// --- Vignette Parameters ---
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.25;
uniform float vignette_softness : hint_range(0.0, 1.0) = 0.45;
uniform bool vignette_enabled = true;

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
float hash(vec2 p) {
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
	float noise = hash(uv * 1000.0 + vec2(seed, seed * 0.7));
	return noise - 0.5;
}


// ============================================================================
// FILM DEFECT FUNCTIONS
// ============================================================================

// Generate vertical scratch line (rare)
float vertical_scratch(vec2 uv, float time_val) {
	float frame = floor(time_val * 8.0) + 1.0;
	float scratch_seed = hash(vec2(frame, frame * 0.7));

	if (scratch_seed > defect_probability * 4.0) {
		return 0.0;
	}

	float scratch_x = hash(vec2(frame * 1.3 + 0.5, frame + 0.5));
	float scratch_width = 0.002 + hash(vec2(frame + 0.1, 0.5)) * 0.003;
	float dist_to_scratch = abs(uv.x - scratch_x);

	float scratch = 1.0 - smoothstep(0.0, scratch_width, dist_to_scratch);
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

	return min(dust, 0.8);
}

// Frame brightness flicker (returns multiplier)
float projector_flicker(float time_val) {
	float flicker_frame = floor(time_val * 24.0) + 1.0;
	float strong_flicker = hash(vec2(flicker_frame + 0.5, flicker_frame * 0.3 + 0.5));

	if (strong_flicker < defect_probability) {
		return 0.92 + hash(vec2(flicker_frame + 0.7, 0.5)) * 0.16;
	}

	float slow_flicker = hash(vec2(floor(time_val * 2.0) + 0.5, 0.5)) * 0.04 + 0.98;
	return mix(1.0, slow_flicker, flicker_intensity);
}


// ============================================================================
// MAIN FRAGMENT SHADER
// This shader creates an overlay effect that blends on top of the scene.
// It does NOT sample screen_texture, making it compatible with gl_compatibility.
// ============================================================================

void fragment() {
	// Start with a transparent base - we'll add our overlay effects
	vec4 overlay = vec4(0.0, 0.0, 0.0, 0.0);

	// --- Apply Film Grain as additive noise overlay ---
	if (grain_enabled && grain_intensity > 0.0) {
		float seed = floor(TIME * 24.0 + 0.5);
		float grain = film_grain(UV, seed);
		// Apply grain as a semi-transparent gray noise
		float grain_alpha = abs(grain) * grain_intensity * 2.0;
		vec3 grain_color = grain > 0.0 ? vec3(1.0) : vec3(0.0);
		overlay.rgb += grain_color * grain_alpha;
		overlay.a = max(overlay.a, grain_alpha * 0.5);
	}

	// --- Apply Warm/Sunny Color Overlay ---
	if (warm_enabled && warm_intensity > 0.0) {
		// Add a warm color overlay using multiply-like blending
		vec3 warm_overlay = warm_color;
		overlay.rgb = mix(overlay.rgb, warm_overlay, warm_intensity * 0.3);
		overlay.a = max(overlay.a, warm_intensity * 0.15);
	}

	// --- Apply Sunny Effect as light overlay ---
	if (sunny_enabled && sunny_intensity > 0.0) {
		// Subtle light golden overlay
		vec3 sunny_tint = vec3(1.0, 0.98, 0.92);
		overlay.rgb = mix(overlay.rgb, sunny_tint, sunny_intensity * 0.4);
		overlay.a = max(overlay.a, sunny_intensity * 0.1);
	}

	// --- Apply Vignette (darken edges) ---
	if (vignette_enabled && vignette_intensity > 0.0) {
		vec2 centered_uv = UV - 0.5;
		float vignette_dist = length(centered_uv) * 1.414;
		float vignette = smoothstep(vignette_softness, 1.0, vignette_dist);
		// Add black overlay at edges
		overlay.rgb = mix(overlay.rgb, vec3(0.0), vignette * vignette_intensity);
		overlay.a = max(overlay.a, vignette * vignette_intensity * 0.8);
	}

	// --- Apply Film Defects ---
	if (defects_enabled) {
		// Scratches (add as bright overlay)
		float scratch = vertical_scratch(UV, TIME);
		if (scratch > 0.0) {
			vec3 scratch_color = vec3(0.85, 0.83, 0.8);
			overlay.rgb = mix(overlay.rgb, scratch_color, scratch * scratch_intensity * 0.5);
			overlay.a = max(overlay.a, scratch * scratch_intensity * 0.3);
		}

		// Dust particles (add as dark overlay)
		float dust = dust_particles(UV, TIME);
		if (dust > 0.0) {
			overlay.rgb = mix(overlay.rgb, vec3(0.1), dust * dust_intensity);
			overlay.a = max(overlay.a, dust * dust_intensity * 0.6);
		}

		// Projector flicker - adjust overall alpha
		float flicker = projector_flicker(TIME);
		if (flicker < 1.0) {
			// Darken slightly on flicker
			overlay.rgb *= flicker;
			overlay.a = max(overlay.a, (1.0 - flicker) * 0.5);
		}
	}

	// Output the overlay with calculated alpha
	// The ColorRect's blend mode will handle how this combines with the scene
	COLOR = overlay;
}
