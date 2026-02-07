shader_type canvas_item;

// Flashbang player screen effect shader.
// Creates a dark purple tint with bordeaux/burgundy border (vignette),
// similar to CS:GO flashbang but with custom colors.
// The effect simulates the retinal afterimage from staring at bright light.

// Overall effect intensity (0.0 = no effect, 1.0 = full effect).
// Animated from peak value down to 0.0 during fade-out.
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

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

void fragment() {
	// Sample the screen using textureLod for gl_compatibility mode support.
	vec4 screen_col = textureLod(screen_texture, SCREEN_UV, 0.0);

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
