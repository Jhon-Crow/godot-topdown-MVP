shader_type canvas_item;

// Force field shader with pulsing blue energy ring effect
// Creates a glowing shield visualization around the player

uniform float time_offset = 0.0;
uniform vec4 field_color : source_color = vec4(0.4, 0.6, 1.0, 0.8);
uniform float pulse_speed = 2.0;
uniform float glow_intensity = 1.5;

void fragment() {
	// Get distance from center (0.0 at center, 1.0 at edge)
	vec2 centered_uv = UV - vec2(0.5, 0.5);
	float dist = length(centered_uv);

	// Create ring pattern (strongest at specific radius)
	float ring_radius = 0.45;
	float ring_width = 0.15;
	float ring = 1.0 - abs(dist - ring_radius) / ring_width;
	ring = clamp(ring, 0.0, 1.0);

	// Pulsing animation
	float pulse = sin(TIME * pulse_speed + time_offset) * 0.3 + 0.7;
	ring *= pulse;

	// Add energy lines (animated rotation)
	float angle = atan(centered_uv.y, centered_uv.x);
	float line_pattern = sin(angle * 6.0 + TIME * 1.5) * 0.5 + 0.5;
	ring *= (0.7 + line_pattern * 0.3);

	// Glow effect - brighter at ring edge
	float glow = ring * glow_intensity;

	// Fade out at edges
	float edge_fade = 1.0 - smoothstep(0.35, 0.5, dist);
	glow *= edge_fade;

	// Apply color with glow
	vec4 color = field_color;
	color.a *= glow;

	COLOR = color;
}
