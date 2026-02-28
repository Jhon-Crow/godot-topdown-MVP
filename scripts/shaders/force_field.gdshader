shader_type canvas_item;

// Force field bubble shader (Issue #906, #930)
// Creates a translucent glowing bubble/sphere visualization around the player.
// The effect mimics a force bubble: semi-transparent interior, bright glowing rim,
// with iridescent color shifts, surface energy shimmer, and a gentle pulse animation.

uniform float time_offset = 0.0;
uniform vec4 field_color : source_color = vec4(0.4, 0.7, 1.0, 0.85);
uniform float pulse_speed = 1.5;
// Reduced from 2.0 to 1.4 for softer bubble rim (Issue #912)
uniform float glow_intensity = 1.4;
// Interior fill opacity — keeps interior semi-transparent like frosted glass (Issue #930)
uniform float fill_opacity = 0.22;

void fragment() {
	// Distance from center: 0.0 at center, ~0.5 at edge of 256x256 texture
	vec2 centered_uv = UV - vec2(0.5, 0.5);
	float dist = length(centered_uv);

	// Discard pixels outside the circle entirely
	if (dist > 0.5) {
		COLOR = vec4(0.0);
		return;
	}

	// ---- Bubble rim effect (Fresnel-like) ----
	// Normalize distance to [0, 1] range within the circle
	float r = dist / 0.5;  // 0 at center, 1 at edge

	// ---- Pulsing animation ----
	float pulse = sin(TIME * pulse_speed + time_offset) * 0.12 + 0.88;

	// ---- Interior fill (translucent bubble interior) ----
	// Soft fill that gives the interior a frosted-glass / bubble look.
	// pow(r, 1.5) ramps from 0 at center to 1 at edge — most opaque near rim.
	// We invert it so the INTERIOR (low r) has some fill, not just the edge.
	// fill = smoothstep toward rim, creating diffuse interior glow.
	float fill = (1.0 - pow(r, 2.5)) * fill_opacity;
	// Add a subtle inner bubble layer: a secondary soft ring near 60% radius
	float inner_ring = 1.0 - abs(r - 0.60) / 0.30;
	inner_ring = clamp(inner_ring, 0.0, 1.0);
	inner_ring = pow(inner_ring, 3.0) * 0.12 * pulse;
	fill += inner_ring;
	fill = clamp(fill, 0.0, fill_opacity * 1.5);

	// ---- Narrow bright rim at the very edge (r close to 1.0) ----
	float rim = 1.0 - abs(r - 0.92) / 0.08;
	rim = clamp(rim, 0.0, 1.0);
	rim = pow(rim, 1.5);

	// ---- Surface energy shimmer (animated swirling pattern) ----
	float angle = atan(centered_uv.y, centered_uv.x);
	// Two overlapping sin waves at different frequencies for energy pattern
	float shimmer_a = sin(angle * 4.0 + TIME * 0.8) * 0.5 + 0.5;
	float shimmer_b = sin(angle * 7.0 - TIME * 1.3 + r * 6.0) * 0.5 + 0.5;
	float surface_energy = (shimmer_a * 0.6 + shimmer_b * 0.4);
	// Surface energy only visible near the rim and on the bubble surface
	float energy_band = smoothstep(0.5, 0.85, r) * (1.0 - smoothstep(0.88, 1.0, r));
	float energy_detail = surface_energy * energy_band * 0.18 * pulse;

	// ---- Iridescent color shift ----
	// Shift hue slightly based on angle and time for a rainbow shimmer
	float shimmer = sin(angle * 4.0 + TIME * 0.8) * 0.5 + 0.5;

	// Iridescent tint: shift slightly toward cyan/purple based on shimmer
	vec3 tint_a = vec3(0.5, 0.8, 1.0);   // Cyan-blue
	vec3 tint_b = vec3(0.8, 0.6, 1.0);   // Lavender
	vec3 iridescent_tint = mix(tint_a, tint_b, shimmer * 0.35);

	// ---- Combined alpha ----
	// Rim + interior fill + surface energy
	float combined = rim * glow_intensity * pulse + fill + energy_detail;
	combined = clamp(combined, 0.0, 1.0);

	// Smooth edge fade to avoid hard cutoff
	float edge_fade = 1.0 - smoothstep(0.46, 0.5, dist);
	combined *= edge_fade;

	// ---- Final color ----
	vec3 final_color = field_color.rgb * iridescent_tint;
	float final_alpha = combined * field_color.a;

	COLOR = vec4(final_color, final_alpha);
}
