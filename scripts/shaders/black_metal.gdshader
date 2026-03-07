shader_type canvas_item;

// Black Metal difficulty visual filter.
// Creates a high-contrast black-and-white look with vivid red and fire/explosion colors preserved.
//
// Rules:
//   - Red-dominant pixels stay red (blood, health indicators)
//   - Warm/fiery pixels (orange, yellow) stay vivid (explosions, muzzle flashes, bullets)
//   - Everything else is converted to high-contrast black-and-white
//
// Uses hint_screen_texture for fullscreen post-processing via a ColorRect overlay.
// Uses textureLod for gl_compatibility renderer support.

uniform float intensity : hint_range(0.0, 1.0) = 1.0;

## Minimum red dominance over green+blue to classify as "red" pixel.
uniform float red_threshold : hint_range(0.0, 1.0) = 0.15;

## Boost applied to the red channel on red-dominant pixels.
uniform float red_boost : hint_range(1.0, 3.0) = 1.8;

## Minimum "warmth" (red+green combined vs blue) to classify as fire/explosion.
uniform float fire_threshold : hint_range(0.0, 1.0) = 0.25;

## Contrast boost applied to the grayscale channel (higher = darker blacks/brighter whites).
uniform float contrast : hint_range(0.5, 3.0) = 1.5;

// Screen texture sampler
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

void fragment() {
	vec4 original = textureLod(screen_texture, SCREEN_UV, 0.0);

	// --- Luminance (perceived brightness) ---
	float lum = dot(original.rgb, vec3(0.299, 0.587, 0.114));

	// --- Detect red-dominant pixels (blood, health bars) ---
	// red_dominance > 0 means red channel is stronger than both green and blue.
	float red_dominance = original.r - max(original.g, original.b);
	float is_red = step(red_threshold, red_dominance) * step(0.1, original.r);

	// --- Detect warm/fiery pixels (explosions, muzzle flashes, bullets) ---
	// Fire pixels have high red+green but low blue — i.e. orange/yellow.
	float warmth = (original.r + original.g) * 0.5 - original.b;
	float is_fire = step(fire_threshold, warmth)
		* step(0.3, original.r + original.g)  // must be reasonably bright
		* (1.0 - is_red);                      // don't double-count red pixels

	// --- High-contrast grayscale ---
	float gray = clamp((lum - 0.5) * contrast + 0.5, 0.0, 1.0);

	// --- Red output: keep red vivid, suppress other channels ---
	vec3 red_color = vec3(min(original.r * red_boost, 1.0), gray * 0.1, gray * 0.1);

	// --- Fire output: keep warm colors vivid ---
	vec3 fire_color = original.rgb;

	// --- Compose final color ---
	// Priority: fire > red > grayscale
	vec3 bw = vec3(gray);
	vec3 result = mix(bw, red_color, is_red);
	result = mix(result, fire_color, is_fire);

	// Blend with original based on intensity
	COLOR.rgb = mix(original.rgb, result, intensity);
	COLOR.a = 1.0;
}
