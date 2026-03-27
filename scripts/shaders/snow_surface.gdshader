shader_type canvas_item;
// Snow surface shader (Issue #1627).
// Applies subtle procedural bumps and colour variation to the snow ground plane
// of the Winter Forest map, replacing the flat white ColorRect.
//
// Technique: layered value-noise (3 octaves) creates gentle uneven surface that
// reads as compressed snowdrift and small hollows when viewed top-down.
// No animation — snow surface is static (not falling flakes, which are in SnowEffect).

// --- Base snow colours ---
uniform vec4 snow_highlight : source_color = vec4(0.94, 0.96, 0.99, 1.0);
uniform vec4 snow_shadow    : source_color = vec4(0.74, 0.79, 0.88, 1.0);

// --- Noise scale (higher = finer detail) ---
uniform float noise_scale : hint_range(1.0, 50.0) = 8.0;

// --- Bump strength: how much light/dark variation the noise creates ---
uniform float bump_strength : hint_range(0.0, 1.0) = 0.38;

// 2D hash for value noise — no texture lookup needed.
float hash(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 19.19);
	return fract(p.x * p.y);
}

// Bilinear value noise in [0, 1].
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	// Quintic smoothstep for C2 continuity (no visible grid lines).
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Fractal Brownian Motion — 3 octaves.
float fbm(vec2 p) {
	float v = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	for (int i = 0; i < 3; i++) {
		v += amplitude * value_noise(p * frequency);
		amplitude *= 0.5;
		frequency *= 2.1;
	}
	return v;
}

void fragment() {
	// Scale UV by noise_scale so bumps appear at world-appropriate size.
	float n = fbm(UV * noise_scale);

	// Mix highlight → shadow based on noise.
	vec4 col = mix(snow_shadow, snow_highlight, n * bump_strength + (1.0 - bump_strength) * 0.5);

	COLOR = col;
}
