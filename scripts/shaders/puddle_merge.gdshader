shader_type canvas_item;
render_mode unshaded;

// Applied to the PuddleManager CanvasGroup node (NOT to individual puddle children).
//
// Problem: When multiple semi-transparent puddle sprites overlap inside a
// CanvasGroup, their alpha values accumulate in the group's internal buffer
// (standard Porter-Duff "over" compositing), making intersection areas appear
// darker/more opaque than individual puddle areas.
//
// Solution: A CanvasGroup composites its children into an offscreen buffer
// using premultiplied alpha. That buffer is bound to the canvas item as
// TEXTURE — we sample it here, un-premultiply, then CLAMP the accumulated
// alpha to the highest alpha any single puddle can reach (MAX_PUDDLE_ALPHA
// = 0.55, matching the phase-3 cap in puddle_effect.gd). This makes
// overlapping and non-overlapping puddle areas look identical — one uniform
// body of water.
//
// How it works:
//   Without shader: two 0.34-alpha puddles overlap → intersection alpha ≈ 0.56
//   With shader:    two 0.34-alpha puddles overlap → intersection alpha clamped
//                   to min(0.56, 0.55) = 0.55 ≈ same as single large puddle
//   Result: no visible darker intersection — puddles merge into one body.
//
// NOTE: We read from TEXTURE (the CanvasGroup's internal composited buffer),
// NOT hint_screen_texture. Using hint_screen_texture on the gl_compatibility
// renderer is known to return uninitialised/white pixels when the backbuffer
// has not been populated, which produced a full-screen white rectangle over
// the playfield (see case study docs/case-studies/issue-1626/analysis.md).

// Must match the maximum alpha any single puddle can reach (phase-3 cap in
// puddle_effect.gd: minf(0.55, modulate.a + 0.04)).
uniform float max_alpha : hint_range(0.0, 1.0) = 0.55;

void fragment() {
	// Sample the CanvasGroup's composited (premultiplied) child buffer.
	vec4 c = texture(TEXTURE, UV);

	// Fully transparent pixels (no puddle covers this area) stay transparent.
	// This is critical: the CanvasGroup draws a quad sized to its bounding
	// rect, and most of that quad has no child coverage — those pixels must
	// output alpha = 0 so the floor shows through unchanged.
	if (c.a < 0.001) {
		COLOR = vec4(0.0);
		return;
	}

	// Un-premultiply to recover the actual puddle colour the children wrote.
	// All puddles use the same dark gray colour, so this is always consistent.
	vec3 rgb = c.rgb / c.a;

	// Clamp the accumulated alpha to the single-puddle maximum.
	// This neutralises the intersection darkening without changing lone puddles.
	// Multiply by COLOR.a so the CanvasGroup's own self_modulate still works.
	float clamped_alpha = min(c.a, max_alpha) * COLOR.a;

	// Output straight (non-premultiplied) colour; Godot's default canvas blend
	// (SRC_ALPHA, ONE_MINUS_SRC_ALPHA) will composite it correctly onto the scene.
	COLOR = vec4(rgb, clamped_alpha);
}
