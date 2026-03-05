shader_type canvas_item;

// Neon glow shader for text labels
// Creates a realistic neon sign effect with bright core and multi-layered glow

uniform vec4 glow_color : source_color = vec4(1.0, 0.2, 0.6, 1.0); // Pink/magenta neon
uniform vec4 core_color : source_color = vec4(1.0, 0.9, 0.95, 1.0); // Bright white-pink core
uniform float glow_intensity : hint_range(0.0, 10.0) = 3.5;
uniform float inner_glow_size : hint_range(0.0, 10.0) = 2.0;
uniform float outer_glow_size : hint_range(0.0, 30.0) = 8.0;
uniform int blur_iterations : hint_range(4, 24) = 16;
uniform float core_brightness : hint_range(0.0, 2.0) = 1.2;
uniform bool enable_flicker = false;
uniform float flicker_speed : hint_range(0.1, 10.0) = 3.0;
uniform float flicker_intensity : hint_range(0.0, 0.3) = 0.05;

// Sample glow at a specific radius
vec4 sample_glow(sampler2D tex, vec2 uv, vec2 pixel_size, float radius, int samples) {
	vec4 glow = vec4(0.0);
	float total_weight = 0.0;

	for (int i = 0; i < samples; i++) {
		float angle = float(i) * 6.28318530718 / float(samples);
		vec2 offset = vec2(cos(angle), sin(angle)) * pixel_size * radius;
		vec4 sample_color = texture(tex, uv + offset);
		float weight = 1.0;
		glow += sample_color * weight;
		total_weight += weight;
	}

	return glow / max(total_weight, 1.0);
}

void fragment() {
	vec4 original = texture(TEXTURE, UV);
	vec2 pixel_size = TEXTURE_PIXEL_SIZE;

	// Calculate inner glow (tight, bright)
	vec4 inner_glow = vec4(0.0);
	for (float r = 1.0; r <= inner_glow_size; r += 1.0) {
		vec4 g = sample_glow(TEXTURE, UV, pixel_size, r, blur_iterations);
		float falloff = 1.0 - (r / (inner_glow_size + 1.0));
		inner_glow += g * falloff * falloff;
	}
	inner_glow /= inner_glow_size;

	// Calculate outer glow (diffuse, softer)
	vec4 outer_glow = vec4(0.0);
	for (float r = inner_glow_size; r <= outer_glow_size; r += 2.0) {
		vec4 g = sample_glow(TEXTURE, UV, pixel_size, r, blur_iterations / 2);
		float falloff = 1.0 - ((r - inner_glow_size) / (outer_glow_size - inner_glow_size + 1.0));
		outer_glow += g * falloff * falloff * falloff;
	}
	outer_glow /= (outer_glow_size - inner_glow_size) / 2.0;

	// Calculate intensity with optional flicker
	float intensity = glow_intensity;
	if (enable_flicker) {
		float flicker = sin(TIME * flicker_speed * 6.28318530718) * flicker_intensity;
		flicker += sin(TIME * flicker_speed * 2.3 * 6.28318530718) * flicker_intensity * 0.3;
		flicker += sin(TIME * flicker_speed * 5.7 * 6.28318530718) * flicker_intensity * 0.1;
		intensity *= (1.0 + flicker);
	}

	// Build the final color
	vec4 result = vec4(0.0);

	// Layer 1: Outer diffuse glow (colored, soft)
	float outer_alpha = outer_glow.a * intensity * 0.4;
	result.rgb = glow_color.rgb * outer_alpha;
	result.a = outer_alpha;

	// Layer 2: Inner glow (brighter colored glow)
	float inner_alpha = inner_glow.a * intensity * 0.8;
	result.rgb = mix(result.rgb, glow_color.rgb * 1.5, inner_alpha);
	result.a = max(result.a, inner_alpha);

	// Layer 3: Original text with bright core
	if (original.a > 0.1) {
		// Create bright neon core effect - white center fading to glow color
		vec3 neon_core = mix(glow_color.rgb * 1.2, core_color.rgb, original.a * core_brightness);
		result.rgb = mix(result.rgb, neon_core, original.a);
		result.a = max(result.a, original.a);
	}

	// Boost overall brightness for neon pop
	result.rgb *= 1.1;

	COLOR = result;
}
