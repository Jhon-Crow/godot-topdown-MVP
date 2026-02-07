shader_type canvas_item;

// Ghost replay filter: red/black/white color palette.
// Used in Ghost replay mode to create a stylized noir-like look
// with red highlights, similar to Sin City or Madworld aesthetics.

uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform float red_threshold : hint_range(0.0, 1.0) = 0.15;
uniform float red_boost : hint_range(1.0, 3.0) = 2.0;

void fragment() {
	vec4 original = texture(TEXTURE, UV);

	// Calculate luminance (grayscale)
	float lum = dot(original.rgb, vec3(0.299, 0.587, 0.114));

	// Detect red-ish pixels: high red channel relative to green and blue
	float red_dominance = original.r - max(original.g, original.b);
	float is_red = step(red_threshold, red_dominance) * step(0.1, original.r);

	// Grayscale base with contrast boost
	float contrast = 1.4;
	float gray = clamp((lum - 0.5) * contrast + 0.5, 0.0, 1.0);

	// Red channel for red-dominant pixels
	vec3 red_color = vec3(min(original.r * red_boost, 1.0), gray * 0.15, gray * 0.15);

	// Mix between grayscale and red
	vec3 result = mix(vec3(gray), red_color, is_red);

	// Apply intensity
	COLOR.rgb = mix(original.rgb, result, intensity);
	COLOR.a = original.a;
}
