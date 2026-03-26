shader_type canvas_item;
// Weapon selection glint shader (Issue #1544).
// Renders a narrow diagonal light sweep across the weapon icon UV space.
// Because this shader runs on the TextureRect itself, the effect is inherently
// clipped to the icon — it cannot bleed onto the card or background.
//
// Animation (one-shot, triggered by resetting `time` uniform to 0.0 from GDScript):
//   0.00 – 0.06 s : glint fades in
//   0.06 – 0.18 s : narrow band sweeps left → right across the icon
//   0.18 – 0.22 s : glint fades out

// Progress of the animation: 0.0 = start, 1.0 = end. Driven by GDScript tween.
uniform float anim_progress : hint_range(0.0, 1.0) = 0.0;

// Colour of the glint stripe.
uniform vec4 glint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	// Only apply glint where the icon has actual pixels (alpha > 0).
	// This keeps the glint strictly on the weapon sprite silhouette.
	float mask = tex.a;

	// Sweep position: moves from -0.2 (off left) to 1.2 (off right) as progress 0→1.
	float sweep = mix(-0.2, 1.2, anim_progress);

	// Diagonal stripe: combination of X and (1-Y) so the band runs top-right → bottom-left.
	float diag = UV.x * 0.8 + (1.0 - UV.y) * 0.2;
	float dist = abs(diag - sweep);

	// Narrow, soft-edged stripe.
	float stripe = exp(-dist * dist * 200.0);

	// Fade in during first 20% and out during last 25% of animation.
	float fade = smoothstep(0.0, 0.20, anim_progress) * smoothstep(1.0, 0.75, anim_progress);

	float glint = stripe * fade * mask * 0.75;

	// Additive blend: brighten the existing pixel, do not cover it.
	COLOR = tex + glint_color * glint;
	COLOR.a = tex.a;
}
