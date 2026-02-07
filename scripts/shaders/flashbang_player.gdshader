shader_type canvas_item;

// Flashbang player screen effect shader.
// Creates a dark purple tint with bordeaux/burgundy border (vignette),
// combined with blur and swimming distortion effects.
// Similar to CS:GO flashbang but with custom colors and motion blur.
// The effect simulates the retinal afterimage from staring at bright light,
// with objects appearing blurred and swimming as if seen through watery eyes.

// Overall effect intensity (0.0 = no effect, 1.0 = full effect).
// Animated from peak value down to 0.0 during fade-out.
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

// Blur strength (0.0 = no blur, 1.0 = maximum blur).
// Controls the radial blur that makes objects look out of focus,
// like a photo taken with long exposure / motion blur.
uniform float blur_intensity : hint_range(0.0, 1.0) = 0.0;

// Time value for animating the swimming distortion effect.
// Updated each frame from the effects manager.
uniform float time_offset : hint_range(0.0, 100000.0) = 0.0;

// Main flash color applied to the center of screen (dark purple).
uniform vec3 flash_color : source_color = vec3(0.15, 0.0, 0.25);

// Border/vignette color applied to screen edges (bordeaux/burgundy).
uniform vec3 border_color : source_color = vec3(0.45, 0.0, 0.12);

// How much of the screen center is covered by the main color vs border.
// Lower values = more border visible, higher = more center color.
uniform float center_coverage : hint_range(0.0, 1.0) = 0.5;

// Softness of the transition between center and border colors.
uniform float edge_softness : hint_range(0.01, 1.0) = 0.35;

// Screen texture sampler for reading the rendered scene.
// Use filter_nearest and textureLod for gl_compatibility mode support.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

// Number of blur samples (higher = smoother but more expensive).
// 8 samples gives a good quality/performance balance for radial blur.
const int BLUR_SAMPLES = 8;

// Maximum blur radius in UV space. Scaled by blur_intensity.
const float MAX_BLUR_RADIUS = 0.025;

// Swimming distortion strength. Scaled by blur_intensity.
const float SWIM_STRENGTH = 0.008;

// Swimming distortion wave frequency.
const float SWIM_FREQUENCY = 3.0;

// Swimming distortion animation speed.
const float SWIM_SPEED = 1.5;

void fragment() {
	// Calculate swimming distortion (wavy UV offset that makes things look like
	// they are floating/swimming, as if seen through tears or watery eyes).
	vec2 swim_offset = vec2(0.0);
	if (blur_intensity > 0.001) {
		float swim = blur_intensity * SWIM_STRENGTH;
		swim_offset.x = sin(SCREEN_UV.y * SWIM_FREQUENCY * 6.28 + time_offset * SWIM_SPEED) * swim;
		swim_offset.y = cos(SCREEN_UV.x * SWIM_FREQUENCY * 6.28 + time_offset * SWIM_SPEED * 0.7) * swim;
	}

	vec2 base_uv = SCREEN_UV + swim_offset;

	// Radial blur: sample the screen at multiple offsets from the center and average.
	// This creates a "long exposure / motion blur" effect centered on the screen.
	vec4 screen_col = vec4(0.0);
	if (blur_intensity > 0.001) {
		float blur_radius = MAX_BLUR_RADIUS * blur_intensity;
		vec2 center = vec2(0.5, 0.5);
		vec2 dir = base_uv - center;

		for (int i = 0; i < BLUR_SAMPLES; i++) {
			float t = float(i) / float(BLUR_SAMPLES - 1) - 0.5; // -0.5 to 0.5
			vec2 offset_uv = base_uv + dir * t * blur_radius;
			screen_col += textureLod(screen_texture, offset_uv, 0.0);
		}
		screen_col /= float(BLUR_SAMPLES);
	} else {
		screen_col = textureLod(screen_texture, base_uv, 0.0);
	}

	// Calculate distance from center of screen (0 at center, ~1.41 at corners).
	vec2 uv = UV * 2.0 - 1.0;
	float dist = length(uv);

	// Create vignette gradient: 0 at center, 1 at edges.
	// smoothstep creates a smooth transition between center and border regions.
	float vignette = smoothstep(center_coverage, center_coverage + edge_softness, dist);

	// Blend between flash color (center) and border color (edges).
	vec3 effect_color = mix(flash_color, border_color, vignette);

	// Calculate opacity: stronger at edges (bordeaux border), still visible at center.
	// At full intensity: center has ~70% opacity, edges have ~90% opacity.
	float base_opacity = 0.7;
	float edge_boost = 0.2;
	float opacity = mix(base_opacity, base_opacity + edge_boost, vignette) * intensity;

	// Mix effect color with the screen: at full intensity the screen is mostly covered.
	vec3 final_color = mix(screen_col.rgb, effect_color, opacity);

	COLOR = vec4(final_color, screen_col.a);
}
