shader_type canvas_item;

// Black Metal difficulty visual filter.
//
// APPROACH: OVERLAY-BASED (no hint_screen_texture)
// This shader creates a dark, desaturating overlay that blends on top of the
// rendered scene. It does NOT sample the screen texture, which avoids known bugs
// in Godot's gl_compatibility renderer that cause white screens on scene load.
//
// The black-and-white + red aesthetic is achieved architecturally:
//   - This CanvasLayer (layer 97) covers the game world with a dark desaturating overlay.
//   - Blood/hit effects and other vivid effects render on higher layers (100+) and appear
//     ABOVE this overlay in full color — naturally preserving red and fire tones.
//
// Visual effects:
//   - Dark vignette (edges darken heavily — grim, oppressive framing)
//   - Film grain (grainy, harsh texture)
//   - Desaturating dark overlay (scene appears muted and dark)
//
// References:
//   - cinema_film.gdshader v5.3 (overlay approach, no screen_texture)
//   - cinema_effects_manager.gd ARCHITECTURE note (why we avoid hint_screen_texture)
//   - GitHub Issue godotengine/godot#79914

// Intensity of the overall effect (0.0 = none, 1.0 = full).
uniform float intensity : hint_range(0.0, 1.0) = 1.0;

// Vignette: how dark the edges become (0.0 = no vignette, 1.0 = full black).
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.75;

// Vignette softness (0.0 = sharp edge, 1.0 = very soft gradient).
uniform float vignette_softness : hint_range(0.0, 1.0) = 0.35;

// Grain intensity (0.0 = no grain, 0.5 = heavy grain).
uniform float grain_intensity : hint_range(0.0, 0.5) = 0.12;

// Desaturation overlay darkness (0.0 = no overlay, 1.0 = completely black).
// A moderate value adds a dark grey overlay that makes the scene look washed out
// and muted, reinforcing the B&W feel.
uniform float desaturation_darkness : hint_range(0.0, 1.0) = 0.55;


// ============================================================================
// NOISE
// ============================================================================

float hash(vec2 p) {
	p += vec2(0.1, 0.1);
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float film_grain(vec2 uv, float seed) {
	float noise = hash(uv * 1200.0 + vec2(seed, seed * 0.7));
	return noise - 0.5;
}


// ============================================================================
// MAIN FRAGMENT
// Builds a transparent overlay — the scene underneath shows through the alpha.
// ============================================================================

void fragment() {
	// Start transparent
	vec4 overlay = vec4(0.0, 0.0, 0.0, 0.0);

	// --- Desaturating dark overlay ---
	// Adds a near-black transparent layer that mutes all scene colors.
	// Higher desaturation_darkness -> scene looks darker and more B&W.
	if (desaturation_darkness > 0.0) {
		// Dark grey-black overlay. Slightly blue-black for cold steel feel.
		overlay.rgb = vec3(0.02, 0.02, 0.04);
		overlay.a = desaturation_darkness * 0.7;
	}

	// --- Film grain ---
	if (grain_intensity > 0.0) {
		float seed = floor(TIME * 24.0 + 0.5);
		float grain = film_grain(UV, seed);
		float grain_alpha = abs(grain) * grain_intensity * 2.5;
		// Mix between black (for dark grain) and near-white (for light grain specks)
		vec3 grain_color = grain > 0.0 ? vec3(0.85, 0.85, 0.85) : vec3(0.0, 0.0, 0.0);
		overlay.rgb = mix(overlay.rgb, grain_color, grain_alpha * 0.4);
		overlay.a = max(overlay.a, grain_alpha * 0.35);
	}

	// --- Heavy vignette (oppressive black frame) ---
	if (vignette_intensity > 0.0) {
		vec2 centered_uv = UV - 0.5;
		float vignette_dist = length(centered_uv) * 1.414;
		float vignette = smoothstep(vignette_softness, 1.0, vignette_dist);
		// Add black overlay at edges
		overlay.rgb = mix(overlay.rgb, vec3(0.0), vignette * vignette_intensity);
		overlay.a = max(overlay.a, vignette * vignette_intensity * 0.95);
	}

	// Apply global intensity
	overlay.a *= intensity;

	COLOR = overlay;
}
