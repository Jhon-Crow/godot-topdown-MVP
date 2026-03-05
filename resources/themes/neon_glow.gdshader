shader_type canvas_item;

// Neon glow shader for text labels
// Creates a soft glow effect around text to simulate neon sign lighting

uniform vec4 glow_color : source_color = vec4(0.0, 0.8, 1.0, 1.0);
uniform float glow_intensity : hint_range(0.0, 5.0) = 2.0;
uniform float glow_size : hint_range(0.0, 20.0) = 4.0;
uniform int blur_iterations : hint_range(1, 16) = 8;
uniform bool enable_flicker = false;
uniform float flicker_speed : hint_range(0.1, 10.0) = 3.0;
uniform float flicker_intensity : hint_range(0.0, 0.5) = 0.1;

void fragment() {
	vec4 original = texture(TEXTURE, UV);

	// Calculate glow by sampling nearby pixels
	vec4 glow = vec4(0.0);
	float total_weight = 0.0;
	vec2 pixel_size = TEXTURE_PIXEL_SIZE * glow_size;

	for (int i = 0; i < blur_iterations; i++) {
		float angle = float(i) * 6.28318530718 / float(blur_iterations);
		for (float dist = 1.0; dist <= 3.0; dist += 1.0) {
			vec2 offset = vec2(cos(angle), sin(angle)) * pixel_size * dist;
			float weight = 1.0 / dist;
			glow += texture(TEXTURE, UV + offset) * weight;
			total_weight += weight;
		}
	}

	if (total_weight > 0.0) {
		glow /= total_weight;
	}

	// Apply glow color
	glow.rgb = glow_color.rgb * glow.a;
	glow.a *= glow_color.a;

	// Calculate intensity with optional flicker
	float intensity = glow_intensity;
	if (enable_flicker) {
		float flicker = sin(TIME * flicker_speed * 6.28318530718) * flicker_intensity;
		flicker += sin(TIME * flicker_speed * 1.7 * 6.28318530718) * flicker_intensity * 0.5;
		intensity *= (1.0 + flicker);
	}

	// Combine original with glow
	vec4 result = original;
	result.rgb = mix(glow.rgb * intensity, original.rgb, original.a);
	result.a = max(original.a, glow.a * intensity * 0.5);

	// Add inner brightness to text (neon tubes are brighter in center)
	if (original.a > 0.5) {
		result.rgb = mix(result.rgb, vec3(1.0), 0.3);
	}

	COLOR = result;
}
