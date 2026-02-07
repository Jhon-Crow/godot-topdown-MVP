shader_type canvas_item;

// Motion trail effect: creates a flame-like trail behind moving objects.
// Used in Memory replay mode to add visual flair to moving entities.
// Applied to trail sprites that follow entities during playback.

uniform vec4 trail_color : source_color = vec4(1.0, 0.6, 0.1, 0.7);
uniform float flicker_speed : hint_range(1.0, 20.0) = 8.0;
uniform float fade_power : hint_range(0.5, 4.0) = 2.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	// Fade from front to back (UV.x = 0 is front/newest, 1 is back/oldest)
	float fade = pow(1.0 - UV.x, fade_power);

	// Vertical taper (narrower at edges)
	float taper = 1.0 - abs(UV.y - 0.5) * 2.0;
	taper = clamp(taper, 0.0, 1.0);

	// Flicker effect for flame-like appearance
	float flicker = sin(TIME * flicker_speed + UV.x * 10.0) * 0.15 + 0.85;
	flicker *= sin(TIME * flicker_speed * 1.7 + UV.y * 8.0) * 0.1 + 0.9;

	COLOR = trail_color;
	COLOR.a *= fade * taper * flicker * tex.a;
}
