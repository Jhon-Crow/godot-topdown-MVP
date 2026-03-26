shader_type canvas_item;
// Weapon selection glint shader (Issue #1544, extended in Issue #1563).
// Renders two sequential light effects across the weapon icon UV space.
// Because this shader runs on the TextureRect itself, both effects are inherently
// clipped to the icon — they cannot bleed onto the card or background.
//
// Phase 1 – Diagonal sweep (Issue #1544):
//   0.00 – 0.06 s : glint fades in
//   0.06 – 0.18 s : narrow band sweeps left → right across the icon
//   0.18 – 0.22 s : glint fades out
//
// Phase 2 – Radial burst from center outward (Issue #1563):
//   0.22 – 0.26 s : burst fades in
//   0.26 – 0.38 s : expanding ring radiates from weapon-tip area toward edges
//   0.38 – 0.42 s : burst fades out

// Progress of the animation: 0.0 = start, 1.0 = end. Driven by GDScript tween.
uniform float anim_progress : hint_range(0.0, 1.0) = 0.0;

// Colour of the diagonal glint stripe (Phase 1).
uniform vec4 glint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Colour of the radial burst (Phase 2).
uniform vec4 burst_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	// Only apply effects where the icon has actual pixels (alpha > 0).
	// This keeps both effects strictly on the weapon sprite silhouette.
	float mask = tex.a;

	// ---- Phase 1: diagonal sweep (progress 0.0 → 0.524) ----
	// 0.22 s out of total 0.42 s = 52.4% of anim_progress
	float phase1_end = 0.524;  // 0.22 / 0.42

	float phase1_t = clamp(anim_progress / phase1_end, 0.0, 1.0);

	// Sweep position: moves from -0.2 (off left) to 1.2 (off right) as phase1_t 0→1.
	float sweep = mix(-0.2, 1.2, phase1_t);

	// Diagonal stripe: combination of X and (1-Y) so the band runs top-right → bottom-left.
	float diag = UV.x * 0.8 + (1.0 - UV.y) * 0.2;
	float dist_sweep = abs(diag - sweep);

	// Narrow, soft-edged stripe.
	float stripe = exp(-dist_sweep * dist_sweep * 200.0);

	// Fade in during first 20% and out during last 25% of phase 1.
	float fade1 = smoothstep(0.0, 0.20, phase1_t) * smoothstep(1.0, 0.75, phase1_t);

	float glint1 = stripe * fade1 * mask * 0.75;

	// ---- Phase 2: radial burst from center outward (progress 0.524 → 1.0) ----
	// 0.20 s burst phase out of total 0.42 s
	float phase2_start = 0.524;  // 0.22 / 0.42

	float phase2_t = clamp((anim_progress - phase2_start) / (1.0 - phase2_start), 0.0, 1.0);

	// Distance from icon center (UV 0.5, 0.5).
	float dx = UV.x - 0.5;
	float dy = UV.y - 0.5;
	float dist_center = sqrt(dx * dx + dy * dy);

	// Expanding ring: expands from center (0) to corners (~0.7) over the phase.
	float ring_radius = mix(0.0, 0.72, phase2_t);
	float ring_dist = abs(dist_center - ring_radius);
	float ring = exp(-ring_dist * ring_dist * 120.0);

	// Soft inner fill that collapses as ring expands (pixel-art "flash from center" feel).
	float fill = (1.0 - smoothstep(0.0, ring_radius + 0.05, dist_center))
	             * smoothstep(0.0, 0.2, phase2_t);

	// Fade in at phase start, fade out at phase end.
	float fade2 = smoothstep(0.0, 0.2, phase2_t) * smoothstep(1.0, 0.75, phase2_t);

	float glint2 = clamp(ring * 0.85 + fill * 0.4, 0.0, 1.0) * fade2 * mask;

	// Only one phase is active at a time — they do not overlap.
	float glint = glint1 + glint2;

	// Additive blend: brighten the existing pixel, do not cover it.
	COLOR = tex + glint_color * glint1 + burst_color * glint2;
	COLOR.a = tex.a;
}
