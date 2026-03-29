shader_type canvas_item;
render_mode unshaded;

// Applied to the PuddleManager CanvasGroup node (NOT to individual puddle children).
//
// Problem: When multiple semi-transparent puddle sprites overlap inside a
// CanvasGroup, their alpha values accumulate in the group's internal buffer
// (standard Porter-Duff "over" compositing), making intersection areas appear
// darker/more opaque than individual puddle areas.
//
// Solution: This shader reads the CanvasGroup's composited backbuffer result,
// then CLAMPS the accumulated alpha to a maximum equal to the highest alpha
// any single puddle can reach (MAX_PUDDLE_ALPHA = 0.55, matching the phase-3
// cap in puddle_effect.gd). This makes overlapping and non-overlapping puddle
// areas look identical — one uniform body of water.
//
// How it works:
//   Without shader: two 0.34-alpha puddles overlap → intersection alpha ≈ 0.56
//   With shader:    two 0.34-alpha puddles overlap → intersection alpha clamped
//                   to min(0.56, 0.55) = 0.55 ≈ same as single large puddle
//   Result: no visible darker intersection — puddles merge into one body.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

// Must match the maximum alpha any single puddle can reach (phase-3 cap in
// puddle_effect.gd: minf(0.55, modulate.a + 0.04)).
uniform float max_alpha : hint_range(0.0, 1.0) = 0.55;

void fragment() {
	vec4 c = textureLod(screen_texture, SCREEN_UV, 0.0);

	// Fully transparent pixels (no puddle covers this area) — stay transparent.
	if (c.a < 0.001) {
		COLOR = vec4(0.0);
		return;
	}

	// Un-premultiply to recover the actual puddle color the children wrote.
	// All puddles use the same dark gray color so this is always consistent.
	vec3 rgb = c.rgb / c.a;

	// Clamp the accumulated alpha to the single-puddle maximum.
	// This neutralises the intersection darkening without changing lone puddles.
	// Multiply by COLOR.a so the CanvasGroup's own self_modulate still works.
	float clamped_alpha = min(c.a, max_alpha) * COLOR.a;

	COLOR = vec4(rgb * clamped_alpha, clamped_alpha);
}
