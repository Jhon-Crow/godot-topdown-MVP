shader_type canvas_item;

// Predator-style invisibility cloak shader (Issue #673).
// Creates a transparent ripple distortion effect on the player's sprites.
// The background is sampled with time-varying chromatic offsets per RGB channel,
// producing the classic "cloaking device" shimmer.

// How strongly the sprite is invisible (0.0 = fully visible, 1.0 = fully cloaked).
uniform float mix_amount : hint_range(0.0, 1.0) = 0.0;

// Pixel offset distance for the chromatic distortion ripple.
uniform float distortion_strength : hint_range(0.0, 32.0) = 12.0;

// Speed multiplier for the ripple animation.
uniform float ripple_speed : hint_range(0.1, 5.0) = 1.5;

// Screen texture sampler for reading the rendered scene behind the sprite.
// Use filter_nearest and textureLod for gl_compatibility mode support.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

void fragment() {
	// Sample the original sprite texture
	vec4 sprite_color = texture(TEXTURE, UV);

	// If the pixel is transparent in the original sprite, discard it
	if (sprite_color.a < 0.01) {
		discard;
	}

	// Calculate time-varying offsets for each RGB channel
	// Each channel uses different frequency/phase for chromatic aberration
	float t = TIME * ripple_speed;
	float dist = distortion_strength * SCREEN_PIXEL_SIZE.x;

	vec2 offset_r = vec2(
		dist * cos(t * 6.2832),
		dist * cos(t * 0.7 * 6.2832)
	);
	vec2 offset_g = vec2(
		dist * cos(1.0 + t * 6.2832),
		dist * cos(3.0 + t * 0.7 * 6.2832)
	);
	vec2 offset_b = vec2(
		dist * cos(t * 1.5 * 3.14159),
		dist * cos(t * 0.9 * 6.2832)
	);

	// Sample screen behind the sprite with chromatic offsets
	float bg_r = textureLod(screen_texture, SCREEN_UV + offset_r, 0.0).r;
	float bg_g = textureLod(screen_texture, SCREEN_UV + offset_g, 0.0).g;
	float bg_b = textureLod(screen_texture, SCREEN_UV + offset_b, 0.0).b;

	vec4 cloaked_color = vec4(bg_r, bg_g, bg_b, sprite_color.a);

	// Mix between original sprite and cloaked version
	COLOR = mix(sprite_color, cloaked_color, mix_amount);
}
