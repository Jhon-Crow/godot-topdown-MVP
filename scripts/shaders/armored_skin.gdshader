shader_type canvas_item;

// Armored Skin visual shader (Issue #1123).
// Gives enemies with the Armored Skin passive item the appearance of being
// covered in transparent crystal/glass armor:
//   - Bluish tint overlaid on the original sprite
//   - Semi-transparent glass sheen that preserves the body silhouette
//   - Shimmering rainbow iridescence that animates over time
//   - Bright glowing edge/rim highlight (Fresnel-like) for a hard-shell look

// Overall opacity of the glass armor overlay (0 = no effect, 1 = full glass).
uniform float armor_opacity : hint_range(0.0, 1.0) = 0.55;

// Base glass tint color (light blue, slightly transparent).
uniform vec4 armor_color : source_color = vec4(0.55, 0.80, 1.0, 0.45);

// Speed of the iridescent shimmer animation.
uniform float shimmer_speed : hint_range(0.1, 5.0) = 1.8;

// Intensity of the iridescent color shift.
uniform float iridescence : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	// Sample original sprite texture.
	vec4 original = texture(TEXTURE, UV);

	// Discard fully transparent pixels to keep sprite outlines clean.
	if (original.a < 0.01) {
		discard;
	}

	// ---- Rim / edge highlight ----
	// Simulate a Fresnel-like rim by detecting pixels close to the sprite edge.
	// We use screen-space pixel size to approximate an outline.
	float alpha_left  = texture(TEXTURE, UV + vec2(-TEXTURE_PIXEL_SIZE.x * 1.5, 0.0)).a;
	float alpha_right = texture(TEXTURE, UV + vec2( TEXTURE_PIXEL_SIZE.x * 1.5, 0.0)).a;
	float alpha_up    = texture(TEXTURE, UV + vec2(0.0, -TEXTURE_PIXEL_SIZE.y * 1.5)).a;
	float alpha_down  = texture(TEXTURE, UV + vec2(0.0,  TEXTURE_PIXEL_SIZE.y * 1.5)).a;

	// Edge strength: 1 near edge, 0 in center of sprite.
	float edge = 1.0 - min(min(alpha_left, alpha_right), min(alpha_up, alpha_down));
	edge = clamp(edge, 0.0, 1.0);

	// ---- Iridescent shimmer ----
	// Shift hue based on UV position and animated time.
	float t = TIME * shimmer_speed;
	float wave = sin(UV.x * 8.0 + UV.y * 5.0 + t) * 0.5 + 0.5;
	float wave2 = sin(UV.y * 10.0 - t * 0.7 + 1.2) * 0.5 + 0.5;

	// Two complementary iridescent tints (cyan-blue and icy lavender).
	vec3 irid_a = vec3(0.4, 0.75, 1.0);   // Icy blue
	vec3 irid_b = vec3(0.7, 0.90, 1.0);   // Icy white-blue
	vec3 irid_shimmer = mix(irid_a, irid_b, wave * wave2);

	// ---- Glass overlay color ----
	// Combine base armor color with the iridescent shimmer.
	vec3 glass_rgb = mix(armor_color.rgb, irid_shimmer, iridescence * wave);

	// Extra brightness on edges (rim glow).
	float rim_boost = 1.0 + edge * 1.2;
	glass_rgb *= rim_boost;
	glass_rgb = clamp(glass_rgb, 0.0, 1.5);

	// ---- Alpha for the glass overlay ----
	// Edge pixels get higher opacity for the hard-shell rim look.
	float glass_alpha = armor_color.a + edge * 0.35;
	glass_alpha = clamp(glass_alpha * armor_opacity, 0.0, 0.9);

	// ---- Blend glass over original sprite ----
	// Normal over compositing: glass on top of sprite.
	vec3 blended_rgb = mix(original.rgb, glass_rgb, glass_alpha);

	// Preserve original alpha so the sprite stays within its bounds.
	COLOR = vec4(blended_rgb, original.a);
}
