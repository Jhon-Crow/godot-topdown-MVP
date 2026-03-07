shader_type canvas_item;

// Black Metal difficulty visual filter.
// Creates a high-contrast black-and-white look with vivid red and fire/explosion colors preserved.
// Based on ghost_replay.gdshader — the same stylized filter the game already uses for Ghost mode.
//
// Rules:
//   - Red-dominant pixels stay vivid red (blood, health indicators)
//   - Warm/fiery pixels (orange, yellow) stay vivid (explosions, muzzle flashes, bullets)
//   - Everything else is converted to high-contrast black-and-white
//
// WHITE SCREEN FIX (Issue #958):
//   The manager using this shader performs warmup with intensity=0.0 (invisible pass-through)
//   before going live. On scene transitions, it defers activation by 3+ frames to ensure
//   the framebuffer is fully populated before hint_screen_texture is read.
//   This is the same warmup pattern used by hit_effects_manager and last_chance_effects_manager.
//
// Uses hint_screen_texture for fullscreen post-processing via a ColorRect overlay.
// Uses textureLod for gl_compatibility renderer support.

// Intensity of the overall effect (0.0 = pass-through, 1.0 = full effect).
// Set to 0.0 during warmup to make the overlay invisible.
uniform float intensity : hint_range(0.0, 1.0) = 1.0;

// Minimum red dominance over green+blue to classify as "red" pixel.
uniform float red_threshold : hint_range(0.0, 1.0) = 0.15;

// Boost applied to the red channel on red-dominant pixels.
uniform float red_boost : hint_range(1.0, 3.0) = 1.8;

// Minimum "warmth" (red+green combined vs blue) to classify as fire/explosion.
uniform float fire_threshold : hint_range(0.0, 1.0) = 0.25;

// Contrast boost applied to the grayscale channel (higher = darker blacks/brighter whites).
uniform float contrast : hint_range(0.5, 3.0) = 1.5;

// Screen texture sampler for reading the rendered scene.
// hint_screen_texture is safe here because:
//   1. Warmup runs at intensity=0.0 so even if screen is white, the output is pass-through.
//   2. Activation is deferred by ACTIVATION_DELAY_FRAMES frames after scene transitions,
//      ensuring the framebuffer is populated before we read it.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

void fragment() {
	vec4 original = textureLod(screen_texture, SCREEN_UV, 0.0);

	// Calculate luminance (grayscale)
	float lum = dot(original.rgb, vec3(0.299, 0.587, 0.114));

	// High-contrast grayscale
	float gray = clamp((lum - 0.5) * contrast + 0.5, 0.0, 1.0);

	// Detect red-ish pixels: high red channel relative to green and blue
	float red_dominance = original.r - max(original.g, original.b);
	float is_red = step(red_threshold, red_dominance) * step(0.1, original.r);

	// Detect warm/fiery pixels: high red+green relative to blue (orange, yellow)
	float warmth = (original.r + original.g) * 0.5 - original.b;
	float is_fire = step(fire_threshold, warmth) * step(0.2, original.r) * (1.0 - is_red);

	// Build final color:
	// - Red pixels: vivid red
	// - Fire/explosion pixels: keep original color
	// - Everything else: high-contrast B&W
	vec3 red_color = vec3(min(original.r * red_boost, 1.0), gray * 0.15, gray * 0.15);
	vec3 bw_color = vec3(gray);

	vec3 result = bw_color;
	result = mix(result, red_color, is_red);
	result = mix(result, original.rgb, is_fire);

	// Apply intensity: 0.0 = original scene (invisible pass-through), 1.0 = full B&W+red effect.
	// This allows safe warmup (intensity=0 → no visual change even if screen_texture is white).
	COLOR.rgb = mix(original.rgb, result, intensity);
	COLOR.a = original.a;
}
