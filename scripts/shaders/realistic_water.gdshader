shader_type canvas_item;
// Realistic 2D water shader (Issue #1445, enhanced in Issue #1550, distortion in Issue #1738)
// Simulates ocean waves on the Beach level with:
//   - Animated wave bands scrolling horizontally
//   - Foam / white-caps near wave crests
//   - Animated surf-foam streaks marching toward the shoreline (Issue #1550)
//   - Semi-transparent depth gradient (deeper = darker blue)
//   - Shore fade at the top edge for smooth sand/water transition
//   - Blood diffusion support via uniform parameters
//   - Wave interruption by obstacles (player/enemies) — Issue #1550
//     Mirrors the light-ray occlusion logic: wave amplitude is attenuated
//     within a radius around each obstacle UV coordinate.
//   - Screen-space refraction distortion (Issue #1738) — wave bands visibly distort
//     the background scene and the water's internal UV, producing a "lensing" shimmer.

// --- Wave animation (primary — broad horizontal bands) ---
uniform float wave_speed : hint_range(0.0, 5.0) = 0.3;
uniform float wave_frequency : hint_range(0.5, 20.0) = 4.0;
uniform float wave_amplitude : hint_range(0.0, 0.05) = 0.010;

// --- Secondary ripple (gentle surface undulation — wider, slower, subtler) ---
uniform float ripple_speed : hint_range(0.0, 5.0) = 0.5;
uniform float ripple_frequency : hint_range(1.0, 40.0) = 6.0;
uniform float ripple_amplitude : hint_range(0.0, 0.02) = 0.003;

// --- Surf-foam streaks marching toward shore (Issue #1550) ---
// These are horizontal bands that advance from the water body toward the top
// (shoreline) edge, simulating incoming surf.
uniform float surf_speed : hint_range(0.0, 5.0) = 0.5;
uniform float surf_frequency : hint_range(1.0, 30.0) = 5.0;
uniform float surf_width : hint_range(0.0, 0.3) = 0.12;
uniform float surf_intensity : hint_range(0.0, 1.0) = 0.25;

// --- Colors ---
uniform vec4 shallow_color : source_color = vec4(0.15, 0.55, 0.85, 0.88);
uniform vec4 deep_color    : source_color = vec4(0.04, 0.22, 0.52, 0.94);
uniform vec4 foam_color    : source_color = vec4(0.85, 0.92, 0.98, 0.70);

// --- Foam / white-cap threshold ---
uniform float foam_threshold : hint_range(0.0, 1.0) = 0.80;
uniform float foam_sharpness : hint_range(1.0, 20.0) = 4.0;

// --- Shore fade: top of the texture blends with transparent (shoreline edge) ---
uniform float shore_fade_width : hint_range(0.0, 0.5) = 0.08;

// --- Bottom shore wash (Issue #1573): wave gradient extends onto land at the bottom edge ---
// The water ColorRect is extended past the sand boundary; this fade makes the
// overlap transparent so only foam/wave crests show on the sand ("wet sand" look).
uniform float shore_wash_width : hint_range(0.0, 0.5) = 0.18;

// --- Blood diffusion overlay ---
uniform vec4 blood_tint : source_color = vec4(0.6, 0.05, 0.05, 0.0);

// --- Wave obstacle interruption (Issue #1550) ---
// Positions of up to 8 obstacles in UV space [0..1, 0..1].
// GDScript fills these from WaterBody each frame.
// obstacle_count tells how many entries are valid.
uniform int obstacle_count = 0;
uniform vec2 obstacle_uvs[8];
// Radius in UV space within which the wave is attenuated around an obstacle.
uniform float obstacle_radius : hint_range(0.0, 0.2) = 0.045;

// --- Screen-space refraction distortion (Issue #1738) ---
// Controls how strongly wave bands distort the screen-UV when sampling the background.
// 0.025 ≈ 2.5% of screen width ≈ ~27 px at 1080p — clearly visible wave-lensing shimmer.
// Pattern mirrors last_chance.gdshader (ripple_strength = 0.01) but stronger since water
// covers a large area and the effect needs to be prominent.
// Set to 0.0 by WaterBody.set_time_stopped() when time is paused.
uniform float distortion_strength : hint_range(0.0, 0.1) = 0.025;

// Screen texture for refraction sampling.
// filter_nearest + textureLod for gl_compatibility renderer support
// (matches the pattern used in last_chance.gdshader and invisibility_cloak.gdshader).
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

// Compute a [0..1] occlusion factor: 1.0 = fully occluded (wave stops),
// 0.0 = no occlusion.  Uses smooth falloff like a light shadow penumbra.
float wave_occlusion(vec2 uv) {
	float occ = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= obstacle_count) {
			break;
		}
		float dist = distance(uv, obstacle_uvs[i]);
		// smoothstep: 1.0 at center, 0.0 at obstacle_radius
		occ = max(occ, 1.0 - smoothstep(0.0, obstacle_radius, dist));
	}
	return occ;
}

void fragment() {
	vec2 uv = UV;

	// ---- Primary wave — drives the distortion bands ----
	// Two overlapping sine waves along X create irregular, ocean-like ripples.
	float wave1 = sin(uv.x * wave_frequency + TIME * wave_speed)
	            + sin(uv.x * wave_frequency * 0.73 - TIME * wave_speed * 0.6);
	wave1 *= 0.5; // normalise to [-1, 1]

	// ---- Secondary wave — vertical surf bands (Y-axis) ----
	// Runs along uv.y so it creates horizontal bands moving toward shore.
	// Combined with wave1 it produces a 2D irregular surface pattern.
	float wave2 = sin(uv.y * ripple_frequency + TIME * ripple_speed)
	            * sin(uv.x * ripple_frequency * 0.7 - TIME * ripple_speed * 0.5);

	// ---- Obstacle occlusion (wave interruption — Issue #1550) ----
	// Reduce both primary and secondary wave amplitude near obstacles,
	// simulating waves "breaking" against the body (same logic as light rays
	// stopping at LightOccluder2D nodes).
	float occ = wave_occlusion(uv);
	float occ_factor = 1.0 - occ;  // 0 = fully occluded, 1 = free

	float wave1_occ = wave1 * occ_factor;
	float wave2_occ = wave2 * occ_factor;

	// ---- Screen-space refraction distortion (Issue #1738) ----
	// Wave1 displaces in X; wave2 displaces in Y — together they produce a
	// 2D lensing shimmer visible as wavy bands across the whole water surface.
	// distortion_strength = 0.025 → ≈ 2.5% of screen width ≈ 27 px at 1080p.
	// This is the dominant visible effect: the background scene (sand, beach)
	// is bent by the wave surface exactly like looking through moving water.
	// wave1_occ / wave2_occ already carry occ_factor, so refraction is
	// automatically suppressed near obstacles.
	vec2 refract_offset = vec2(wave1_occ, wave2_occ) * distortion_strength;
	vec4 screen_col = textureLod(screen_texture, SCREEN_UV + refract_offset, 0.0);

	// ---- UV distortion for the water's own internal colour bands ----
	// Apply a smaller UV warp to the water colour lookup so the depth gradient
	// and foam also undulate — giving the water a "wavy glass" internal texture.
	float total_disp = wave1_occ * wave_amplitude + wave2_occ * ripple_amplitude;
	vec2 distorted_uv = uv + vec2(total_disp, total_disp * 0.5);

	// ---- Depth gradient (y=0 top = shallow, y=1 bottom = deep) ----
	float depth = distorted_uv.y;
	vec4 water_base = mix(shallow_color, deep_color, depth);

	// ---- Foam / white-caps ----
	float foam_val = smoothstep(foam_threshold, 1.0,
	                            pow(clamp(wave1_occ * 0.5 + 0.5, 0.0, 1.0), foam_sharpness));
	vec4 water_col = mix(water_base, foam_color, foam_val);

	// ---- Surf-foam streaks marching toward shore (Issue #1550) ----
	// Create bands that travel from deep (y=1) toward the shore (y=0).
	// Phase = uv.y * surf_frequency - TIME * surf_speed  →  bands move upward.
	float surf_phase = uv.y * surf_frequency - TIME * surf_speed;
	// Small x-variation for natural variation without creating diagonal artefacts
	surf_phase += sin(uv.x * 2.0 + TIME * 0.15) * 0.15;
	// Modulate into [0,1] and apply threshold to form discrete foam bands
	float surf_band = fract(surf_phase);
	float surf_foam = smoothstep(1.0 - surf_width, 1.0, surf_band)
	                + smoothstep(surf_width, 0.0, surf_band);
	// Attenuate near obstacles (waves also break here — Issue #1550)
	surf_foam *= occ_factor;
	// Attenuate at deep water (only visible in the upper / shallower portion)
	surf_foam *= (1.0 - depth * 0.8);
	// Blend surf foam on top of the water colour
	water_col = mix(water_col, foam_color, surf_foam * surf_intensity);

	// ---- Compose final colour ----
	// Blend distorted background (screen_col) with water colour using water alpha.
	// water_col.a ≈ 0.88–0.94 → ~10–12% of the distorted scene shows through.
	// The distortion is large enough (±27 px) that even 12% contribution is
	// clearly visible as wavy bands across the water surface.
	// When distortion_strength = 0 (time-stopped), refract_offset = vec2(0,0)
	// and screen_col is an unshifted sample — visually correct (frozen water).
	vec3 final_rgb = mix(screen_col.rgb, water_col.rgb, water_col.a);

	// ---- Blood diffusion tint ----
	final_rgb = mix(final_rgb, blood_tint.rgb, blood_tint.a);
	float alpha = water_col.a;

	// ---- Shore fade at the top edge (transition from land to water) ----
	float shore_fade = smoothstep(0.0, shore_fade_width, uv.y);
	alpha *= shore_fade;

	// ---- Bottom shore wash (Issue #1573): wave gradient onto land ----
	// In the bottom shore_wash_width fraction of the texture (the part that
	// overlaps the sand), fade the base water colour to transparent so only
	// the bright foam/surf bands remain visible — creating a "wave wash" look.
	float bottom_t = smoothstep(1.0, 1.0 - shore_wash_width, uv.y);
	// Attenuate the base water colour in the wash zone (foam already bright enough)
	float wash_water_alpha = mix(alpha, 0.0, (1.0 - bottom_t));
	// Surf foam in the wash zone: boost intensity so waves are clearly visible on sand
	float surf_wash = surf_foam * surf_intensity * (1.0 - bottom_t) * 1.8;
	// Blend: deep into wash zone = only foam, no base water
	float final_alpha = mix(wash_water_alpha, surf_wash, clamp(1.0 - bottom_t, 0.0, 1.0));
	final_alpha = max(final_alpha, surf_wash);  // foam always visible in wash zone

	COLOR = vec4(final_rgb, final_alpha);
}
