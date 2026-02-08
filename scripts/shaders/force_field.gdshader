shader_type canvas_item;

// Force field glowing shield shader.
// Creates a circular glowing energy barrier effect around the player.
// The shield pulses with energy and has a bright edge with semi-transparent interior.

uniform vec4 shield_color : source_color = vec4(0.3, 0.7, 1.0, 1.0);
uniform float pulse_speed : hint_range(0.5, 5.0) = 2.0;
uniform float edge_thickness : hint_range(0.01, 0.3) = 0.08;
uniform float glow_intensity : hint_range(0.0, 3.0) = 1.5;
uniform float inner_alpha : hint_range(0.0, 0.5) = 0.1;
uniform float time_offset : hint_range(0.0, 10.0) = 0.0;

void fragment() {
	// Calculate distance from center of the quad (UV centered)
	vec2 center = vec2(0.5, 0.5);
	float dist = distance(UV, center) * 2.0; // Normalize to 0-1 range for unit circle

	// Discard pixels outside the circle
	if (dist > 1.0) {
		discard;
	}

	// Pulsing animation
	float pulse = sin((TIME + time_offset) * pulse_speed) * 0.5 + 0.5;

	// Edge glow - bright ring at the shield boundary
	float edge_start = 1.0 - edge_thickness * 2.0;
	float edge_factor = smoothstep(edge_start, 1.0, dist);

	// Inner fill - very subtle transparent fill
	float inner_factor = 1.0 - dist;

	// Combine edge and inner
	float alpha = inner_alpha * inner_factor + edge_factor * (0.8 + pulse * 0.2);

	// Color with energy shimmer
	vec3 color = shield_color.rgb * (1.0 + pulse * 0.3) * glow_intensity;

	// Add bright spots along the edge for energy effect
	float angle = atan(UV.y - 0.5, UV.x - 0.5);
	float energy_pattern = sin(angle * 8.0 + TIME * 3.0) * 0.5 + 0.5;
	color += vec3(energy_pattern * edge_factor * 0.5);

	COLOR = vec4(color, alpha * shield_color.a);
}
