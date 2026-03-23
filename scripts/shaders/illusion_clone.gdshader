shader_type canvas_item;

// Illusion clone shader (Issue #1353).
// Creates a ghostly, semi-transparent copy of an enemy sprite.
// The clone flickers and has a cyan-greenish tint to distinguish
// it from the real enemy. Uses no SCREEN_TEXTURE for maximum performance.

// Overall opacity of the illusion (0.0 = invisible, 1.0 = fully opaque).
uniform float opacity : hint_range(0.0, 1.0) = 0.55;

// Speed of the flickering animation.
uniform float flicker_speed : hint_range(0.1, 10.0) = 3.0;

// Intensity of the flickering (0.0 = no flicker, 1.0 = full flicker).
uniform float flicker_intensity : hint_range(0.0, 1.0) = 0.3;

// Tint color for the illusion (cyan-green by default).
uniform vec3 tint_color : source_color = vec3(0.4, 0.9, 0.7);

// How strongly the tint is applied (0.0 = original colors, 1.0 = full tint).
uniform float tint_strength : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	vec4 sprite_color = texture(TEXTURE, UV);

	if (sprite_color.a < 0.01) {
		discard;
	}

	// Apply tint: blend original color with tint color
	vec3 tinted = mix(sprite_color.rgb, tint_color, tint_strength);

	// Flickering: sine-based opacity variation
	float flicker = 1.0 - flicker_intensity * 0.5 * (1.0 + sin(TIME * flicker_speed * 6.2832 + UV.y * 8.0));

	// Edge glow: brighter at sprite edges (detected by alpha gradient)
	float edge = smoothstep(0.0, 0.4, sprite_color.a) * (1.0 - smoothstep(0.6, 1.0, sprite_color.a));
	tinted += tint_color * edge * 0.3;

	COLOR = vec4(tinted, sprite_color.a * opacity * flicker);
}
