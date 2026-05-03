shader_type canvas_item;

// Realistic cracked glass overlay for the pause menu background.
// Uses Voronoi cell-edge distance + FBM warp (ported from godotshaders.com/shader/cracked-glass/)
// to produce thin, organic-looking crack webs.
//
// Overlay-only approach (no hint_screen_texture) keeps compatibility with
// Godot's GL Compatibility renderer — same reasoning as cinema_film.gdshader.

uniform float crack_depth    : hint_range(0.0, 10.0) = 3.0;
uniform float crack_scale    : hint_range(1.0, 10.0) = 3.5;
uniform float crack_warp     : hint_range(0.0, 10.0) = 1.3;
uniform float crack_warp_scale : hint_range(0.0, 10.0) = 2.67;
uniform float crack_profile  : hint_range(0.0, 10.0) = 1.0;
uniform float crack_sharpness : hint_range(0.0, 100.0) = 55.0;
uniform float crack_width    : hint_range(0.0, 0.02) = 0.0015;

uniform vec4  crack_color    : source_color = vec4(0.72, 0.88, 1.0, 1.0);
uniform float crack_opacity  : hint_range(0.0, 1.0) = 0.80;
uniform float darkness       : hint_range(0.0, 1.0) = 0.45;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.35;

// ── Noise helpers ────────────────────────────────────────────────────────────

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

// ── Voronoi cell-edge distance (returns distance to nearest Voronoi border) ──

float voronoi_edge(vec2 u) {
	vec2 p = floor(u);
	vec2 f = fract(u);

	// Find nearest cell centre.
	float min_d = 8.0;
	vec2  min_c = vec2(0.0);
	vec2  min_r = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash2(p + g);
			vec2 r = g - f + o;
			float d = dot(r, r);
			if (d < min_d) { min_d = d; min_c = g; min_r = r; }
		}
	}

	// Distance to the nearest cell border.
	float edge_d = 8.0;
	for (int j = -2; j <= 2; j++) {
		for (int i = -2; i <= 2; i++) {
			vec2 g = min_c + vec2(float(i), float(j));
			vec2 o = hash2(p + g);
			vec2 r = g - f + o;
			if (dot(min_r - r, min_r - r) > 1e-5) {
				edge_d = min(edge_d, 0.5 * dot(min_r + r, normalize(r - min_r)));
			}
		}
	}
	return edge_d;
}

// ── Crack accumulation across several Voronoi scales ────────────────────────

float generate_cracks(vec2 uv) {
	vec2 U = uv * crack_scale;
	float result = 0.0;

	for (float i = 0.0; i < crack_depth; i++) {
		// FBM-warp the coordinates for organic, non-uniform cracks.
		vec2 warp = vec2(fbm(U / crack_warp_scale)) * crack_warp * crack_warp_scale;
		float d = voronoi_edge(U + warp);

		// Remap: values near the border (small d) become bright.
		float crack = 1.0 - min(1.0, crack_sharpness * pow(max(0.0, d - crack_width), crack_profile));
		result += crack / exp2(i);

		U *= 1.55;
	}
	return clamp(result, 0.0, 1.0);
}

// ── Main ─────────────────────────────────────────────────────────────────────

void fragment() {
	vec4 base = COLOR;

	float cracks = generate_cracks(UV);

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
