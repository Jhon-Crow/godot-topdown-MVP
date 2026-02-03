shader_type canvas_item;

// ============================================================================
// CINEMA FILM EFFECT SHADER v5.0
// Simulates vintage film look with grain, warm tones, and film defects
// v5.0: Added micro scratches, cigarette burn, and end of reel death effects
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
uniform float grain_intensity : hint_range(0.0, 0.5) = 0.07;
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

// --- Small Scratches Parameters (short micro-scratches, max 2px) ---
uniform bool micro_scratches_enabled = true;
uniform float micro_scratch_intensity : hint_range(0.0, 1.0) = 0.4;
uniform float micro_scratch_probability : hint_range(0.0, 0.2) = 0.03;

// --- Death Effects Parameters ---
// Cigarette burn: circular burn mark that appears on death
uniform bool cigarette_burn_enabled = false;
uniform float cigarette_burn_intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec2 cigarette_burn_position = vec2(0.5, 0.5);
uniform float cigarette_burn_size : hint_range(0.0, 0.5) = 0.15;

// End of reel: flickering countdown effect in the corner on death
uniform bool end_of_reel_enabled = false;
uniform float end_of_reel_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float end_of_reel_time : hint_range(0.0, 10.0) = 0.0;


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
// MICRO SCRATCHES (small, max 2px length)
// ============================================================================

// Generate small micro-scratches (max 2px long)
float micro_scratches(vec2 uv, float time_val) {
	float scratch_total = 0.0;
	float frame = floor(time_val * 12.0) + 1.0;

	// Generate multiple tiny scratches
	for (int i = 0; i < 8; i++) {
		float seed = float(i) * 73.156 + 1.0;
		float scratch_seed = hash(vec2(frame + seed, frame * 0.3 + seed));

		if (scratch_seed < micro_scratch_probability) {
			// Random position for the scratch
			vec2 scratch_start = hash2(vec2(frame + seed + 0.7, seed + 0.3));

			// Calculate scratch length (max ~2px, which is about 0.003 in UV space for 640px width)
			float scratch_length = 0.001 + hash(vec2(seed + 0.5, frame + 0.5)) * 0.002;

			// Random angle for the scratch (mostly vertical with slight variation)
			float angle = 3.14159 * 0.5 + (hash(vec2(seed + 0.8, frame + 0.8)) - 0.5) * 0.5;
			vec2 scratch_dir = vec2(cos(angle), sin(angle));

			// Calculate distance from point to line segment
			vec2 to_point = uv - scratch_start;
			float proj_length = dot(to_point, scratch_dir);
			proj_length = clamp(proj_length, 0.0, scratch_length);
			vec2 closest_point = scratch_start + scratch_dir * proj_length;
			float dist = length(uv - closest_point);

			// Thin scratch (about 1px wide = 0.0015 in UV space)
			float scratch_width = 0.0015;
			float scratch = 1.0 - smoothstep(0.0, scratch_width, dist);

			// Only show if we're within the scratch segment
			if (proj_length > 0.0 && proj_length < scratch_length) {
				scratch_total = max(scratch_total, scratch * 0.6);
			}
		}
	}

	return scratch_total;
}


// ============================================================================
// DEATH EFFECTS
// ============================================================================

// Cigarette burn effect - circular burn mark with charred edge
float cigarette_burn(vec2 uv, vec2 center, float size, float intensity, float time_val) {
	if (intensity <= 0.0) return 0.0;

	vec2 to_center = uv - center;
	float dist = length(to_center);

	// Normalize distance by size
	float norm_dist = dist / size;

	// Create irregular edge using noise
	float edge_noise = hash(to_center * 50.0 + vec2(floor(time_val * 2.0), 0.0)) * 0.3;
	norm_dist += edge_noise * 0.2;

	// Inner dark hole (burnt through)
	float inner_hole = 1.0 - smoothstep(0.0, 0.3, norm_dist);

	// Charred brown/orange ring
	float char_ring = smoothstep(0.2, 0.5, norm_dist) * (1.0 - smoothstep(0.5, 1.0, norm_dist));

	// Outer burnt edge
	float outer_edge = smoothstep(0.7, 1.0, norm_dist) * (1.0 - smoothstep(1.0, 1.3, norm_dist));

	// Flickering/burning animation
	float flicker = 0.8 + 0.2 * hash(vec2(floor(time_val * 8.0), center.x));

	return (inner_hole * 0.9 + char_ring * 0.5 + outer_edge * 0.3) * intensity * flicker;
}

// Get cigarette burn color (dark center, orange/brown edge)
vec3 cigarette_burn_color(vec2 uv, vec2 center, float size) {
	vec2 to_center = uv - center;
	float dist = length(to_center);
	float norm_dist = dist / size;

	// Dark black center
	vec3 center_color = vec3(0.05, 0.02, 0.01);
	// Charred brown/orange edge
	vec3 edge_color = vec3(0.4, 0.2, 0.05);
	// Outer singed edge
	vec3 outer_color = vec3(0.3, 0.15, 0.05);

	vec3 burn_color = mix(center_color, edge_color, smoothstep(0.0, 0.5, norm_dist));
	burn_color = mix(burn_color, outer_color, smoothstep(0.5, 1.0, norm_dist));

	return burn_color;
}

// End of reel effect - flickering countdown markers in corner
float end_of_reel(vec2 uv, float intensity, float time_val, float reel_time) {
	if (intensity <= 0.0) return 0.0;

	// Position in top-right corner
	vec2 corner = vec2(0.85, 0.15);
	float corner_size = 0.12;

	vec2 to_corner = uv - corner;
	float dist = length(to_corner);

	// Create countdown circles (film reel markers)
	float markers = 0.0;
	float marker_count = floor(reel_time * 3.0); // 3 markers per second

	// Draw countdown circles
	for (float i = 0.0; i < 4.0; i++) {
		if (i >= mod(marker_count, 4.0) + 1.0) break;

		float ring_radius = corner_size * (0.3 + i * 0.2);
		float ring_width = 0.008;
		float ring = abs(dist - ring_radius);
		markers += (1.0 - smoothstep(0.0, ring_width, ring)) * 0.4;
	}

	// Add center dot
	float center_dot = 1.0 - smoothstep(0.0, corner_size * 0.15, dist);
	markers += center_dot * 0.6;

	// Add crosshairs
	float cross_h = 1.0 - smoothstep(0.0, 0.004, abs(to_corner.y));
	float cross_v = 1.0 - smoothstep(0.0, 0.004, abs(to_corner.x));
	cross_h *= step(abs(to_corner.x), corner_size * 0.8);
	cross_v *= step(abs(to_corner.y), corner_size * 0.8);
	markers += (cross_h + cross_v) * 0.3;

	// Flickering effect (classic projector countdown)
	float flicker = 0.6 + 0.4 * hash(vec2(floor(time_val * 18.0), reel_time));

	// Fade in/out based on reel_time fractional part
	float pulse = 0.5 + 0.5 * sin(reel_time * 6.28318);

	return markers * intensity * flicker * pulse;
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

	// --- Apply Micro Scratches (small, max 2px) ---
	if (micro_scratches_enabled && micro_scratch_intensity > 0.0) {
		float micro_scratch = micro_scratches(UV, TIME);
		if (micro_scratch > 0.0) {
			vec3 scratch_color = vec3(0.9, 0.88, 0.85);
			overlay.rgb = mix(overlay.rgb, scratch_color, micro_scratch * micro_scratch_intensity);
			overlay.a = max(overlay.a, micro_scratch * micro_scratch_intensity * 0.4);
		}
	}

	// --- Apply Death Effects ---
	// Cigarette burn effect
	if (cigarette_burn_enabled && cigarette_burn_intensity > 0.0) {
		float burn = cigarette_burn(UV, cigarette_burn_position, cigarette_burn_size, cigarette_burn_intensity, TIME);
		if (burn > 0.0) {
			vec3 burn_color = cigarette_burn_color(UV, cigarette_burn_position, cigarette_burn_size);
			overlay.rgb = mix(overlay.rgb, burn_color, burn);
			overlay.a = max(overlay.a, burn * 0.95);
		}
	}

	// End of reel countdown effect
	if (end_of_reel_enabled && end_of_reel_intensity > 0.0) {
		float reel = end_of_reel(UV, end_of_reel_intensity, TIME, end_of_reel_time);
		if (reel > 0.0) {
			vec3 reel_color = vec3(0.1, 0.08, 0.05); // Dark film leader color
			overlay.rgb = mix(overlay.rgb, reel_color, reel);
			overlay.a = max(overlay.a, reel * 0.8);
		}
	}

	// Output the overlay with calculated alpha
	// The ColorRect's blend mode will handle how this combines with the scene
	COLOR = overlay;
}
