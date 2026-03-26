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
// Phase 2 – Top-edge glint sweep (Issue #1563):
//   0.22 – 0.38 s : edge glint fades in
//   0.38 – 0.84 s : bright highlight runs left → right along the upper edge of the weapon
//   0.84 – 1.02 s : edge glint fades out

// Progress of the animation: 0.0 = start, 1.0 = end. Driven by GDScript tween.
uniform float anim_progress : hint_range(0.0, 1.0) = 0.0;

// Colour of the diagonal glint stripe (Phase 1).
uniform vec4 glint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Colour of the top-edge glint sweep (Phase 2).
uniform vec4 edge_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// How many pixels to sample above/below a fragment to detect the top edge.
// Passed in from GDScript as vec2(1/texture_width, 1/texture_height).
uniform vec2 texel_size = vec2(0.015625, 0.015625);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	// Only apply effects where the icon has actual pixels (alpha > 0).
	// This keeps both effects strictly on the weapon sprite silhouette.
	float mask = tex.a;

	// ---- Phase 1: diagonal sweep (progress 0.0 → 0.216) ----
	// 0.22 s out of total 1.02 s = 21.6% of anim_progress
	float phase1_end = 0.216;  // 0.22 / 1.02

	float phase1_t = clamp(anim_progress / phase1_end, 0.0, 1.0);

	// Sweep position: moves from -0.2 (off left) to 1.2 (off right) as phase1_t 0→1.
	float sweep1 = mix(-0.2, 1.2, phase1_t);

	// Diagonal stripe: combination of X and (1-Y) so the band runs top-right → bottom-left.
	float diag = UV.x * 0.8 + (1.0 - UV.y) * 0.2;
	float dist_sweep1 = abs(diag - sweep1);

	// Narrow, soft-edged stripe.
	float stripe = exp(-dist_sweep1 * dist_sweep1 * 200.0);

	// Fade in during first 20% and out during last 25% of phase 1.
	float fade1 = smoothstep(0.0, 0.20, phase1_t) * smoothstep(1.0, 0.75, phase1_t);

	float glint1 = stripe * fade1 * mask * 0.75;

	// ---- Phase 2: top-edge glint sweep (progress 0.216 → 1.0) ----
	// A bright narrow highlight runs left → right along the topmost edge of the weapon.
	// The "top edge" is detected by checking whether the pixel just above is transparent —
	// meaning this fragment is at (or very near) the silhouette boundary on the upper side.
	float phase2_start = 0.216;  // 0.22 / 1.02

	float phase2_t = clamp((anim_progress - phase2_start) / (1.0 - phase2_start), 0.0, 1.0);

	// Sample pixel one texel above — if it is transparent, we are on the upper edge.
	float above_alpha = texture(TEXTURE, UV + vec2(0.0, -texel_size.y)).a;
	float is_top_edge = (1.0 - above_alpha) * mask;

	// The glint spot sweeps from left (X=0) to right (X=1) along that edge row.
	// Use a narrow Gaussian in X centred on the moving sweep position.
	float sweep2 = mix(-0.1, 1.1, phase2_t);
	float dist_x = UV.x - sweep2;
	float spot = exp(-dist_x * dist_x * 180.0);

	// Fade in/out envelope around the sweep.
	float fade2 = smoothstep(0.0, 0.2, phase2_t) * smoothstep(1.0, 0.75, phase2_t);

	float glint2 = spot * is_top_edge * fade2 * 1.0;

	// Only one phase is active at a time — they do not overlap.
	// Additive blend: brighten the existing pixel, do not cover it.
	COLOR = tex + glint_color * glint1 + edge_color * glint2;
	COLOR.a = tex.a;
}
