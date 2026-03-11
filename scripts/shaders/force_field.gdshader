shader_type canvas_item;

// Force field bubble shader (Issue #906, #930)
// Creates a translucent glowing bubble/sphere visualization around the player.
// The effect mimics a force bubble: semi-transparent interior (frosted glass),
// bright glowing rim, iridescent color shifts, and a gentle pulse animation.

uniform float time_offset = 0.0;
uniform vec4 field_color : source_color = vec4(0.4, 0.7, 1.0, 0.85);
uniform float pulse_speed = 1.5;
// Reduced from 2.0 to 1.4 for softer bubble rim (Issue #912)
uniform float glow_intensity = 1.4;
// Interior fill opacity — keeps interior semi-transparent like frosted glass (Issue #930)
uniform float fill_opacity = 0.20;

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

	// Fresnel: very transparent center, bright glowing edge
	// pow(r, 2.0) gives a smooth quadratic falloff
	float fresnel = pow(r, 2.5);

	// Narrow bright rim at the very edge (r close to 1.0)
	float rim = 1.0 - abs(r - 0.92) / 0.08;
	rim = clamp(rim, 0.0, 1.0);
	rim = pow(rim, 1.5);

	// ---- Pulsing animation ----
	float pulse = sin(TIME * pulse_speed + time_offset) * 0.12 + 0.88;

	// ---- Iridescent color shift ----
	// Shift hue slightly based on angle and time for a rainbow shimmer
	float angle = atan(centered_uv.y, centered_uv.x);
	float shimmer = sin(angle * 4.0 + TIME * 0.8) * 0.5 + 0.5;

	// Iridescent tint: shift slightly toward cyan/purple based on shimmer
	vec3 tint_a = vec3(0.5, 0.8, 1.0);   // Cyan-blue
	vec3 tint_b = vec3(0.8, 0.6, 1.0);   // Lavender
	vec3 iridescent_tint = mix(tint_a, tint_b, shimmer * 0.35);

	// ---- Interior fill (translucent bubble look — Issue #930) ----
	// Soft fill that gives the interior a frosted-glass / bubble appearance.
	// (1 - pow(r, 2.5)) is highest at center and fades to 0 near the rim,
	// creating a gentle translucent interior visible through the shield.
	float fill = (1.0 - pow(r, 2.5)) * fill_opacity;

	// ---- Combined alpha ----
	// Rim + interior fill: bright edge with translucent interior bubble
	float combined = rim * glow_intensity * pulse + fill;
	combined = clamp(combined, 0.0, 1.0);

	// Smooth edge fade to avoid hard cutoff
	float edge_fade = 1.0 - smoothstep(0.46, 0.5, dist);
	combined *= edge_fade;

	// ---- Final color ----
	vec3 final_color = field_color.rgb * iridescent_tint;
	float final_alpha = combined * field_color.a;

	COLOR = vec4(final_color, final_alpha);
}
