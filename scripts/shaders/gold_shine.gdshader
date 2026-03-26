shader_type canvas_item;
// Gold shine shader for armory "condition met" UI slots and armory button (Issue #1536).
// Animates a 4-phase shine cycle:
//   Phase 0 (0.0–0.3): diagonal highlight sweep across the panel
//   Phase 1 (0.3–0.6): glowing pulsing border
//   Phase 2 (0.6–0.8): full gold background wash
//   Phase 3 (0.8–1.0): fade back to base gold state
// The cycle repeats every `cycle_duration` seconds.

// Duration of one full shine cycle in seconds.
uniform float cycle_duration : hint_range(1.0, 10.0) = 3.5;

// Base gold background color.
uniform vec4 gold_base : source_color = vec4(0.28, 0.22, 0.08, 0.85);

// Bright highlight color used for the diagonal sweep and border glow.
uniform vec4 gold_bright : source_color = vec4(1.0, 0.9, 0.3, 1.0);

// Border thickness as fraction of the smaller UV dimension (0 = no border).
uniform float border_frac : hint_range(0.0, 0.15) = 0.06;

void fragment() {
	// Normalised phase within [0, 1) driven by TIME.
	float phase = mod(TIME / cycle_duration, 1.0);

	// ---- Base background colour (always present) ----
	vec4 base = gold_base;

	// ---- Phase 0 (0.0–0.3): diagonal highlight sweep ----
	// A bright stripe sweeps from top-left to bottom-right.
	float sweep_contrib = 0.0;
	if (phase < 0.3) {
		float t = phase / 0.3;  // 0→1 during sweep
		// Position of the sweep centre along the diagonal (UV.x + UV.y goes 0→2).
		float sweep_pos = mix(-0.4, 2.4, t);
		float diag = UV.x + UV.y;
		float dist = abs(diag - sweep_pos);
		// Gaussian-like falloff; width ≈ 0.35 diagonal units.
		sweep_contrib = exp(-dist * dist * 25.0) * 0.85;
		// Smooth in/out at phase edges.
		float fade = smoothstep(0.0, 0.08, t) * smoothstep(1.0, 0.92, t);
		sweep_contrib *= fade;
	}

	// ---- Phase 1 (0.3–0.6): glowing border pulse ----
	// Detect proximity to panel edge via UV.
	float border_glow = 0.0;
	if (phase >= 0.3 && phase < 0.6) {
		float t = (phase - 0.3) / 0.3;  // 0→1 during border phase
		// Distance to nearest edge in UV space.
		float dx = min(UV.x, 1.0 - UV.x);
		float dy = min(UV.y, 1.0 - UV.y);
		float edge_dist = min(dx, dy);
		// Glow falloff inside the border_frac zone.
		float raw = smoothstep(border_frac, 0.0, edge_dist);
		// Pulse: sin reaches maximum near t=0.5.
		float pulse = sin(t * 3.14159265);
		border_glow = raw * pulse * 0.9;
	}

	// ---- Phase 2 (0.6–0.8): full gold wash ----
	float wash = 0.0;
	if (phase >= 0.6 && phase < 0.8) {
		float t = (phase - 0.6) / 0.2;
		wash = sin(t * 3.14159265) * 0.55;
	}

	// ---- Combine all effects ----
	float bright_blend = clamp(sweep_contrib + border_glow + wash, 0.0, 1.0);
	vec4 result = mix(base, gold_bright, bright_blend);

	COLOR = result;
}
