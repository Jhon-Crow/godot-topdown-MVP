shader_type canvas_item;

// Realistic cracked glass overlay for the pause menu background.
// Uses a small deterministic fracture cluster: one hairline crack with two
// short branches. This keeps the effect visible without covering the screen.
//
// Overlay-only approach (no hint_screen_texture) keeps compatibility with
// Godot's GL Compatibility renderer — same reasoning as cinema_film.gdshader.

uniform float crack_scale    : hint_range(1.0, 10.0) = 2.2;
uniform float crack_warp     : hint_range(0.0, 10.0) = 0.018;
uniform float crack_warp_scale : hint_range(0.0, 10.0) = 8.0;
uniform float crack_profile  : hint_range(0.0, 10.0) = 1.35;
uniform float crack_sharpness : hint_range(0.0, 100.0) = 70.0;
uniform float crack_width    : hint_range(0.0, 0.02) = 0.0011;
uniform float crack_coverage : hint_range(0.0, 1.0) = 0.35;

uniform vec4  crack_color    : source_color = vec4(0.46, 0.55, 0.60, 1.0);
uniform float crack_opacity  : hint_range(0.0, 1.0) = 0.18;
uniform float darkness       : hint_range(0.0, 1.0) = 0.36;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.28;

// -- Noise helpers ------------------------------------------------------------

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	vec2 h00 = hash2(i + vec2(0.0, 0.0));
	vec2 h10 = hash2(i + vec2(1.0, 0.0));
	vec2 h01 = hash2(i + vec2(0.0, 1.0));
	vec2 h11 = hash2(i + vec2(1.0, 1.0));
	return mix(mix(dot(h00, f - vec2(0.0, 0.0)),
	               dot(h10, f - vec2(1.0, 0.0)), f.x),
	           mix(dot(h01, f - vec2(0.0, 1.0)),
	               dot(h11, f - vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 n) {
	float total = 0.0, amp = 1.0;
	for (int i = 0; i < 7; i++) {
		total += noise(n) * amp;
		n     += n;
		amp   *= 0.5;
	}
	return total;
}

// -- Sparse fracture field ----------------------------------------------------

float line_distance(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

float fracture_line(vec2 p, vec2 a, vec2 b, float width, float strength) {
	float len = length(b - a);
	float along = clamp(dot(p - a, b - a) / max(0.0001, len * len), 0.0, 1.0);
	float taper = smoothstep(0.0, 0.18, along) * (1.0 - smoothstep(0.72, 1.0, along));
	float d = line_distance(p, a, b);
	float line = 1.0 - smoothstep(width, width * 2.8, d);
	return line * taper * strength;
}

float generate_cracks(vec2 uv) {
	vec2 U = uv;
	float warp_a = fbm(U * crack_warp_scale + vec2(3.1, 1.7));
	float warp_b = fbm(U * (crack_warp_scale * 0.73) + vec2(8.6, 4.2));
	U += vec2(warp_a, warp_b) * crack_warp;

	float width = crack_width / max(0.1, crack_scale);
	float cracks = 0.0;
	cracks = max(cracks, fracture_line(U, vec2(0.18, 0.62), vec2(0.82, 0.33), width, 1.0));
	cracks = max(cracks, fracture_line(U, vec2(0.43, 0.51), vec2(0.31, 0.28), width * 0.74, 0.45));
	cracks = max(cracks, fracture_line(U, vec2(0.56, 0.45), vec2(0.73, 0.61), width * 0.68, 0.38));

	float chip = 1.0 - smoothstep(width * 2.0, width * 9.0, length(U - vec2(0.43, 0.51)));
	cracks = max(cracks, chip * 0.18);

	return clamp(pow(cracks, crack_profile) * crack_coverage, 0.0, 1.0);
}

// -- Main ---------------------------------------------------------------------

void fragment() {
	vec4 base = COLOR;

	vec2 aspect_uv = UV - vec2(0.5);
	aspect_uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	aspect_uv += vec2(0.5);
	float cracks = generate_cracks(aspect_uv);

	// Darken the background.
	vec3 col = base.rgb * (1.0 - darkness);

	// Tint crack lines toward the ice-blue crack color.
	col = mix(col, crack_color.rgb, cracks * crack_opacity);

	// Radial vignette to focus attention on the centre.
	float vign = smoothstep(0.35, 0.95, length(UV - vec2(0.5)));
	col *= 1.0 - vign * vignette_strength;

	float alpha = clamp(base.a + cracks * crack_opacity * 0.12, 0.0, 1.0);
	COLOR = vec4(col, alpha);
}
