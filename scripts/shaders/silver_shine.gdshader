shader_type canvas_item;
render_mode blend_add;
// Silver shine shader for armory Apply button when pending changes exist (Issue #1762).
// Uses ADDITIVE blending so the glow adds on top of existing content.
//
// Animation phases (repeats every `cycle_duration` seconds):
//   Phase 0 (0.00–0.45): highlight stripe sweeps across the element
//                         (horizontal left→right when horizontal_sweep=true,
//                          diagonal top-right→bottom-left otherwise)
//   Phase 1 (0.45–0.65): radial silver burst expands from center, then contracts
//   Phase 2 (0.65–1.00): smooth fade back to zero (dark = no contribution in additive mode)

// Duration of one full shine cycle in seconds.
uniform float cycle_duration : hint_range(1.0, 10.0) = 3.5;

// Color of the sweep stripe (silver).
uniform vec4 sweep_color : source_color = vec4(0.85, 0.88, 0.95, 1.0);

// Color of the radial burst (silver).
uniform vec4 burst_color : source_color = vec4(0.75, 0.8, 0.9, 1.0);

// When true, Phase 0 sweeps horizontally (left → right) along UV.x.
uniform bool horizontal_sweep = false;

void fragment() {
	float phase = mod(TIME / cycle_duration, 1.0);

	float glow = 0.0;

	// ---- Phase 0 (0.00–0.45): stripe sweep ----
	if (phase < 0.45) {
		float t = phase / 0.45;  // 0 → 1
		float dist;
		if (horizontal_sweep) {
			float sweep_pos = mix(-0.3, 1.3, t);
			dist = abs((UV.x + 0.15 * UV.y) - sweep_pos);
		} else {
			// Diagonal sweep: stripe travels top-right → bottom-left.
			float sweep_pos = mix(-0.3, 2.3, t);
			float diag = (1.0 - UV.x) + UV.y;
			dist = abs(diag - sweep_pos);
		}
		// Narrow, bright stripe with soft edges.
		float sharpness = horizontal_sweep ? 60.0 : 30.0;
		float stripe = exp(-dist * dist * sharpness);
		// Fade in at start and out at end of sweep.
		float edge = smoothstep(0.0, 0.07, t) * smoothstep(1.0, 0.93, t);
		glow = stripe * edge * 0.85;
		COLOR = sweep_color * glow;
	}
	// ---- Phase 1 (0.45–0.65): radial burst from center ----
	else if (phase < 0.65) {
		float t = (phase - 0.45) / 0.20;  // 0 → 1
		// Distance from center (UV 0.5, 0.5).
		float dx = UV.x - 0.5;
		float dy = UV.y - 0.5;
		float dist_center = sqrt(dx * dx + dy * dy);
		// Expanding ring: ring expands from 0 to ~0.8 over the phase.
		float ring_radius = mix(0.0, 0.8, t);
		float ring_dist = abs(dist_center - ring_radius);
		float ring = exp(-ring_dist * ring_dist * 80.0);
		// Solid inner fill: fade in then fade out with the ring.
		float fill = (1.0 - smoothstep(0.0, ring_radius + 0.1, dist_center)) * smoothstep(0.0, 0.15, t);
		// Combine ring edge and fill, fade out toward end of phase.
		float fade_out = smoothstep(1.0, 0.7, t);
		glow = clamp(ring * 0.9 + fill * 0.5, 0.0, 1.0) * fade_out;
		COLOR = burst_color * glow;
	}
	// ---- Phase 2 (0.65–1.00): fade to zero ----
	else {
		float t = (phase - 0.65) / 0.35;  // 0 → 1
		glow = 1.0 - smoothstep(0.0, 1.0, t);
		// Subtle overall shimmer during fade-out (very dim).
		glow *= 0.25;
		COLOR = burst_color * glow;
	}
}