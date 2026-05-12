shader_type canvas_item;

// Score-screen rank shine for pre-rendered transparent letter textures.
// Animates a silver glint that sweeps along letter contour edges only,
// matching the weapon-selection glint style (weapon_select_glint.gdshader).
// COLOR.a = tex.a ensures the shine never bleeds outside glyph boundaries.

uniform float cycle_duration : hint_range(1.0, 10.0) = 2.8;
uniform vec4 sweep_color : source_color = vec4(0.85, 0.92, 1.0, 1.0);
uniform vec4 burst_color : source_color = vec4(0.75, 0.88, 1.0, 1.0);
uniform bool horizontal_sweep = true;
uniform vec2 texel_size = vec2(0.01, 0.01);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float mask = tex.a;
	float phase = mod(TIME / cycle_duration, 1.0);

	// Detect contour: a pixel is on the edge if at least one neighbour is transparent.
	// This mirrors the top-edge detection in weapon_select_glint.gdshader but for all edges.
	float above_alpha = texture(TEXTURE, UV + vec2(0.0, -texel_size.y)).a;
	float below_alpha = texture(TEXTURE, UV + vec2(0.0,  texel_size.y)).a;
	float left_alpha  = texture(TEXTURE, UV + vec2(-texel_size.x, 0.0)).a;
	float right_alpha = texture(TEXTURE, UV + vec2( texel_size.x, 0.0)).a;

	// Edge strength: 1.0 at the silhouette boundary, 0.0 in the interior.
	float edge_mask = mask * (1.0 - min(above_alpha, min(below_alpha, min(left_alpha, right_alpha))));

	float glow = 0.0;

	if (phase < 0.45) {
		// Phase 0: horizontal glint sweeps left→right along letter contour edges.
		float t = phase / 0.45;
		float sweep_pos = mix(-0.1, 1.1, t);
		float dist_x = UV.x - sweep_pos;
		float spot = exp(-dist_x * dist_x * 180.0);
		float fade = smoothstep(0.0, 0.12, t) * smoothstep(1.0, 0.88, t);
		glow = spot * edge_mask * fade * 1.2;
		COLOR = tex + sweep_color * glow;
	} else if (phase < 0.65) {
		// Phase 1: diagonal sweep across contour edges.
		float t = (phase - 0.45) / 0.20;
		float sweep_pos = mix(-0.2, 1.2, t);
		float diag = UV.x * 0.8 + (1.0 - UV.y) * 0.2;
		float dist_diag = abs(diag - sweep_pos);
		float stripe = exp(-dist_diag * dist_diag * 200.0);
		float fade = smoothstep(0.0, 0.20, t) * smoothstep(1.0, 0.75, t);
		glow = stripe * edge_mask * fade * 0.9;
		COLOR = tex + burst_color * glow;
	} else {
		// Phase 2: gentle edge shimmer fade-out.
		float t = (phase - 0.65) / 0.35;
		glow = (1.0 - smoothstep(0.0, 1.0, t)) * edge_mask * 0.15;
		COLOR = tex + burst_color * glow;
	}

	COLOR.a = tex.a;
}
