shader_type canvas_item;

// Score-screen rank shine for pre-rendered transparent letter textures.
// Samples the rank glyph texture first and only adds shine where texture alpha exists.

uniform float cycle_duration : hint_range(1.0, 10.0) = 2.8;
uniform vec4 sweep_color : source_color = vec4(1.0, 0.88, 0.25, 1.0);
uniform vec4 burst_color : source_color = vec4(1.0, 0.72, 0.08, 1.0);
uniform bool horizontal_sweep = true;
uniform vec2 texel_size = vec2(0.01, 0.01);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float mask = tex.a;
	float phase = mod(TIME / cycle_duration, 1.0);
	float glow = 0.0;

	if (phase < 0.45) {
		float t = phase / 0.45;
		float sweep_pos = mix(-0.3, 1.3, t);
		float track = horizontal_sweep ? (UV.x + 0.15 * UV.y) : ((1.0 - UV.x) + UV.y);
		float dist = abs(track - sweep_pos);
		float stripe = exp(-dist * dist * 80.0);
		float edge = smoothstep(0.0, 0.07, t) * smoothstep(1.0, 0.93, t);

		float above_alpha = texture(TEXTURE, UV + vec2(0.0, -texel_size.y)).a;
		float below_alpha = texture(TEXTURE, UV + vec2(0.0, texel_size.y)).a;
		float left_alpha = texture(TEXTURE, UV + vec2(-texel_size.x, 0.0)).a;
		float right_alpha = texture(TEXTURE, UV + vec2(texel_size.x, 0.0)).a;
		float edge_mask = max(max(abs(mask - above_alpha), abs(mask - below_alpha)), max(abs(mask - left_alpha), abs(mask - right_alpha)));
		glow = stripe * edge * mix(0.35, 1.0, edge_mask) * mask;
		COLOR = tex + sweep_color * glow;
	} else if (phase < 0.65) {
		float t = (phase - 0.45) / 0.20;
		float dist_center = distance(UV, vec2(0.5, 0.5));
		float ring_radius = mix(0.0, 0.8, t);
		float ring = exp(-abs(dist_center - ring_radius) * abs(dist_center - ring_radius) * 100.0);
		float fade_out = smoothstep(1.0, 0.7, t);
		glow = ring * fade_out * mask * 0.65;
		COLOR = tex + burst_color * glow;
	} else {
		float t = (phase - 0.65) / 0.35;
		glow = (1.0 - smoothstep(0.0, 1.0, t)) * mask * 0.12;
		COLOR = tex + burst_color * glow;
	}

	COLOR.a = tex.a;
}
