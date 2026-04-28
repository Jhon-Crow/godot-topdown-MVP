shader_type canvas_item;
// Puddle alpha-clamp shader for CanvasGroup composite (Issue #1626).
//
// Applied to the CanvasGroup child of PuddleManager. All puddle Sprite2Ds are
// children of that CanvasGroup, so Godot composites them into a single premultiplied
// RGBA texture before calling this shader. TEXTURE here is that composited buffer —
// NOT the screen framebuffer. This makes the shader renderer-independent.
//
// Problem solved: when N semi-transparent puddles overlap, standard Porter-Duff "over"
// compositing stacks their alphas: α_combined = 1 - Π(1-αi). Two puddles at α=0.34
// produce α≈0.56 at the intersection — visibly darker than a single puddle, which
// looks unrealistic (real puddles merge into one connected water body).
//
// Solution: clamp the composited alpha to MAX_PUDDLE_ALPHA so any overlap, whether
// from 2 or 10 puddles, shows the same opacity as a single fully-grown puddle.
// The pixel colour (grey water) is unchanged; only the opacity is clamped.
//
// Safe on gl_compatibility: reads only TEXTURE (always populated by CanvasGroup),
// never reads hint_screen_texture or SCREEN_TEXTURE.

/// Maximum alpha any puddle area can reach, regardless of overlap count.
/// Matches the maximum modulate:a used in phase 3 of puddle_effect.gd.
uniform float max_alpha : hint_range(0.0, 1.0) = 0.55;

void fragment() {
	// TEXTURE is the CanvasGroup's premultiplied composite of all puddle children.
	vec4 c = texture(TEXTURE, UV);

	// Skip fully-transparent pixels (no puddle here) so the CanvasGroup bounding
	// quad remains invisible in empty areas.
	if (c.a < 0.001) {
		COLOR = vec4(0.0);
		return;
	}

	// Un-premultiply to recover the puddle's flat grey color channel.
	vec3 rgb = c.rgb / c.a;

	// Clamp composited alpha — this is the core fix for junction darkening.
	// Multiply by COLOR.a so the CanvasGroup node's own self_modulate still works.
	float clamped_alpha = min(c.a, max_alpha) * COLOR.a;

	// Output straight (non-premultiplied) RGBA.
	// Godot's default 2D blend (SRC_ALPHA, ONE_MINUS_SRC_ALPHA) expects this.
	COLOR = vec4(rgb, clamped_alpha);
}
