shader_type canvas_item;

// ============================================================================
// CINEMA FILM EFFECT SHADER v5.3
// Simulates vintage film look with grain, warm tones, and film defects
// v5.0: Added micro scratches, cigarette burn, and end of reel death effects
// v5.1: Issue #431 fixes - increased grain, realistic micro dots, death effects
// v5.2: Issue #431 feedback - top-right corner, expanding spots, visible specks
// v5.3: Issue #440 fix - simplified end of reel to ~80x80 white circle ring
//       that blinks exactly 2 times (updated: made 2x smaller per feedback)
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
// Issue #431: Increased from 0.07 to 0.15 for more visible grain
uniform float grain_intensity : hint_range(0.0, 0.5) = 0.15;
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

// --- Micro Specks/Dots Parameters (tiny dust-like particles on old film) ---
// Issue #431: White specks/motes like dust on old film - now more visible
uniform bool micro_scratches_enabled = true;
// Increased intensity from 0.35 to 0.7 for visibility
uniform float micro_scratch_intensity : hint_range(0.0, 1.0) = 0.7;
// Increased probability from 0.015 to 0.04 for more frequent appearance
uniform float micro_scratch_probability : hint_range(0.0, 0.2) = 0.04;

// --- Death Effects Parameters ---
// Cigarette burn: circular burn mark that appears on death
uniform bool cigarette_burn_enabled = false;
uniform float cigarette_burn_intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec2 cigarette_burn_position = vec2(0.5, 0.5);
uniform float cigarette_burn_size : hint_range(0.0, 0.5) = 0.15;

// End of reel: white circle ring in the corner on death
// Issue #431: Position changed to top-RIGHT corner
// Issue #440: Simplified to ~80x80 pixel white ring that blinks 2 times (updated: 2x smaller)
uniform bool end_of_reel_enabled = false;
uniform float end_of_reel_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float end_of_reel_time : hint_range(0.0, 10.0) = 0.0;

// --- Expanding Death Spots Parameters ---
// Issue #431: Spots that gradually expand and multiply on death
uniform bool death_spots_enabled = false;
uniform float death_spots_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float death_spots_time : hint_range(0.0, 10.0) = 0.0;


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
// MICRO SCRATCHES (small dots/specks like on old film, Issue #431)
// White/light specks (motes) like dust particles on vintage film.
// Issue #431 feedback: Made more visible with larger size and higher intensity.
// ============================================================================

// Generate small dots/specks (tiny particles like dust on old film)
// Returns: positive values for white specks, negative for dark specks
float micro_scratches(vec2 uv, float time_val) {
	float scratch_total = 0.0;
	// Frame rate for appearance changes
	float frame = floor(time_val * 6.0) + 1.0;

	// Generate multiple specks (like white dust/motes on old film)
	for (int i = 0; i < 10; i++) {
		float seed = float(i) * 73.156 + 1.0;
		float scratch_seed = hash(vec2(frame + seed, frame * 0.3 + seed));

		if (scratch_seed < micro_scratch_probability) {
			// Random position for the speck
			vec2 speck_pos = hash2(vec2(frame + seed + 0.7, seed + 0.3));

			// Distance from current pixel to speck center
			float dist = length(uv - speck_pos);

			// Larger dot size for visibility (3-6px = 0.003 to 0.006 in UV space)
			float speck_size = 0.003 + hash(vec2(seed + 0.5, frame + 0.5)) * 0.003;

			// Create soft-edged dot
			float speck = 1.0 - smoothstep(0.0, speck_size, dist);

			// Most specks are white (like dust motes in projector light)
			// Some specks are dark (like film imperfections)
			float brightness_var = hash(vec2(seed + 0.9, frame + 0.9));
			if (brightness_var > 0.3) {
				// White/bright speck (dust motes in light) - more common
				scratch_total = max(scratch_total, speck * 0.8);
			} else {
				// Dark speck (film imperfection) - less common
				scratch_total = max(scratch_total, speck * 0.5);
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

// End of reel effect - simple white circle outline in corner
// Issue #440: Changed to a simple ~80x80 pixel white ring that blinks 2 times
// Position: top-RIGHT corner
float end_of_reel(vec2 uv, float intensity, float time_val, float reel_time) {
	if (intensity <= 0.0) return 0.0;

	// Position in top-RIGHT corner with some padding
	// Circle size: ~80x80 pixels on 1280x720 viewport
	// For an 80px circle: radius = 40px, in UV space ≈ 40/720 = 0.056 for Y
	// Using average for circle appearance on different aspect ratios
	float circle_radius = 0.055;  // ~80px diameter on 720p (2x smaller than before)
	float ring_thickness = 0.008;  // Thin ring outline (~6px)

	// Position: top-right corner with padding (circle center)
	// Padding of ~20px from edges: (1280-100)/1280 ≈ 0.92 for X, 100/720 ≈ 0.14 for Y
	vec2 corner = vec2(0.88, 0.16);

	// Adjust for aspect ratio to make circle appear round
	// Viewport is 1280x720, aspect = 1280/720 = 1.78
	vec2 aspect_adjusted_uv = uv;
	aspect_adjusted_uv.x *= 1.78;
	vec2 aspect_adjusted_corner = corner;
	aspect_adjusted_corner.x *= 1.78;

	vec2 to_corner = aspect_adjusted_uv - aspect_adjusted_corner;
	float dist = length(to_corner);

	// Adjust radius for aspect ratio
	float adjusted_radius = circle_radius;

	// Create single ring (circle outline)
	float ring = abs(dist - adjusted_radius);
	float circle = 1.0 - smoothstep(0.0, ring_thickness, ring);

	// Blinking effect: blink 2 times over the death sequence
	// Each blink cycle: 0.4s visible, 0.2s hidden = 0.6s per blink
	// Total: 2 blinks = 1.2s, then stay visible
	float blink = 1.0;
	if (reel_time < 1.2) {
		// During blinking period (first 1.2 seconds)
		float blink_cycle = mod(reel_time, 0.6);
		// Visible for 0.4s, hidden for 0.2s
		blink = step(blink_cycle, 0.4);
	}
	// After 1.2 seconds, circle stays visible (blink = 1.0)

	return circle * intensity * blink;
}


// ============================================================================
// EXPANDING DEATH SPOTS (Issue #431)
// Dark spots that gradually expand and multiply when player dies,
// simulating film damage/burning spreading across the frame.
// ============================================================================

float death_spots(vec2 uv, float intensity, float time_val) {
	if (intensity <= 0.0) return 0.0;

	float spots_total = 0.0;

	// Number of spots increases over time (starts with 2, grows to 8)
	int num_spots = int(2.0 + time_val * 2.0);
	num_spots = min(num_spots, 8);

	for (int i = 0; i < 8; i++) {
		if (i >= num_spots) break;

		float seed = float(i) * 37.891 + 1.0;

		// Each spot has a fixed position based on seed
		vec2 spot_pos = hash2(vec2(seed + 0.3, seed * 0.7 + 0.5));

		// Distance from current pixel to spot center
		float dist = length(uv - spot_pos);

		// Spot size grows over time
		// Each spot starts appearing at different times (staggered)
		float spot_delay = float(i) * 0.3;
		float spot_time = max(0.0, time_val - spot_delay);

		// Base size + growth over time (starts small, grows larger)
		float base_size = 0.02 + hash(vec2(seed + 0.1, 0.1)) * 0.03;
		float growth_rate = 0.015 + hash(vec2(seed + 0.2, 0.2)) * 0.01;
		float spot_size = base_size + spot_time * growth_rate;
		spot_size = min(spot_size, 0.15); // Cap maximum size

		// Create irregular edges for organic look
		float edge_noise = hash(uv * 30.0 + vec2(seed, spot_time)) * 0.3;
		float norm_dist = dist / spot_size;
		norm_dist += edge_noise * 0.2;

		// Dark center with charred edges
		float spot = 1.0 - smoothstep(0.0, 1.0, norm_dist);

		// Pulsing/flickering effect
		float pulse = 0.8 + 0.2 * sin(time_val * 3.0 + seed);

		spots_total = max(spots_total, spot * pulse);
	}

	return spots_total * intensity;
}

// Get color for death spots (dark charred appearance)
vec3 death_spots_color(vec2 uv, float time_val) {
	// Dark brown/black charred color
	vec3 center_color = vec3(0.02, 0.01, 0.005);
	vec3 edge_color = vec3(0.15, 0.08, 0.02);

	// Slight variation based on position
	float variation = hash(uv * 20.0);
	return mix(center_color, edge_color, variation * 0.5);
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

	// End of reel countdown effect (white circle in top-right corner)
	if (end_of_reel_enabled && end_of_reel_intensity > 0.0) {
		float reel = end_of_reel(UV, end_of_reel_intensity, TIME, end_of_reel_time);
		if (reel > 0.0) {
			// White/light color for the reel marker circle
			vec3 reel_color = vec3(0.95, 0.92, 0.88);
			overlay.rgb = mix(overlay.rgb, reel_color, reel);
			overlay.a = max(overlay.a, reel * 0.9);
		}
	}

	// Expanding death spots (Issue #431 - spots that grow and multiply)
	if (death_spots_enabled && death_spots_intensity > 0.0) {
		float spots = death_spots(UV, death_spots_intensity, death_spots_time);
		if (spots > 0.0) {
			vec3 spots_color = death_spots_color(UV, death_spots_time);
			overlay.rgb = mix(overlay.rgb, spots_color, spots);
			overlay.a = max(overlay.a, spots * 0.95);
		}
	}

	// Output the overlay with calculated alpha
	// The ColorRect's blend mode will handle how this combines with the scene
	COLOR = overlay;
}
