shader_type canvas_item;

// Full-screen pause overlay that suggests scratched, cracked glass.
// It avoids screen_texture sampling so the effect stays reliable in Godot's
// Compatibility renderer and can sit behind the pause controls.

uniform vec3 glass_tint : source_color = vec3(0.78, 0.95, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.18;
uniform float darkness : hint_range(0.0, 1.0) = 0.42;
uniform float crack_intensity : hint_range(0.0, 1.0) = 0.82;
uniform float scratch_intensity : hint_range(0.0, 1.0) = 0.38;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.36;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float line_segment(vec2 uv, vec2 a, vec2 b, float width) {
	vec2 pa = uv - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	float d = length(pa - ba * h);
	return 1.0 - smoothstep(width, width * 2.6, d);
}

float crack_web(vec2 uv) {
	vec2 center = vec2(0.62, 0.38);
	float cracks = 0.0;

	for (int i = 0; i < 12; i++) {
		float fi = float(i);
		float angle = fi * 0.523599 + hash(vec2(fi, 7.0)) * 0.35;
		float length_scale = 0.22 + hash(vec2(fi, 11.0)) * 0.46;
		vec2 dir = vec2(cos(angle), sin(angle));
		vec2 start = center + dir * (0.035 + hash(vec2(fi, 13.0)) * 0.04);
		vec2 end = center + dir * length_scale;
		cracks = max(cracks, line_segment(uv, start, end, 0.0018));

		vec2 branch_dir = normalize(vec2(-dir.y, dir.x) * (hash(vec2(fi, 17.0)) > 0.5 ? 1.0 : -1.0) + dir * 0.35);
		vec2 branch_start = mix(start, end, 0.48 + hash(vec2(fi, 19.0)) * 0.28);
		vec2 branch_end = branch_start + branch_dir * (0.07 + hash(vec2(fi, 23.0)) * 0.14);
		cracks = max(cracks, line_segment(uv, branch_start, branch_end, 0.0013));
	}

	cracks = max(cracks, line_segment(uv, vec2(0.16, 0.72), vec2(0.42, 0.57), 0.0015));
	cracks = max(cracks, line_segment(uv, vec2(0.41, 0.58), vec2(0.56, 0.69), 0.0012));
	return cracks;
}

float scratches(vec2 uv) {
	float total = 0.0;
	for (int i = 0; i < 18; i++) {
		float fi = float(i);
		vec2 base = vec2(hash(vec2(fi, 31.0)), hash(vec2(fi, 37.0)));
		float len = 0.07 + hash(vec2(fi, 41.0)) * 0.18;
		float angle = -0.35 + hash(vec2(fi, 43.0)) * 0.7;
		vec2 dir = vec2(cos(angle), sin(angle));
		total = max(total, line_segment(uv, base, base + dir * len, 0.00075));
	}
	return total;
}

void fragment() {
	vec2 uv = UV;
	vec4 base = COLOR;

	float cracks = crack_web(uv);
	float scratch_marks = scratches(uv);
	float edge = smoothstep(0.34, 0.92, length(uv - vec2(0.5)));
	float haze = hash(floor(uv * 90.0)) * 0.045;

	vec3 tinted = mix(base.rgb, glass_tint, tint_strength);
	tinted *= 1.0 - darkness;
	tinted += haze;
	tinted += cracks * crack_intensity * vec3(0.58, 0.82, 0.95);
	tinted += scratch_marks * scratch_intensity * vec3(0.45, 0.62, 0.72);
	tinted *= 1.0 - edge * vignette_strength;

	float alpha = clamp(base.a + cracks * 0.16 + scratch_marks * 0.08, 0.0, 0.92);
	COLOR = vec4(tinted, alpha);
}
