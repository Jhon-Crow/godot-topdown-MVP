shader_type canvas_item;
// Gold shine shader for armory "condition met" UI slots and armory button (Issue #1536).
// Animation phases:
//   Phase 0 (0.0–0.4): diagonal highlight sweep from top-right to bottom-left
//   Phase 1 (0.4–0.7): card holds at bright yellow
//   Phase 2 (0.7–1.0): fade back to base gold state
// The cycle repeats every `cycle_duration` seconds.

// Duration of one full shine cycle in seconds.
uniform float cycle_duration : hint_range(1.0, 10.0) = 3.5;

// Base gold background color.
uniform vec4 gold_base : source_color = vec4(0.28, 0.22, 0.08, 0.85);

// Bright yellow color used for the diagonal sweep and the hold phase.
uniform vec4 gold_bright : source_color = vec4(1.0, 0.9, 0.1, 1.0);

void fragment() {
	// Normalised phase within [0, 1) driven by TIME.
	float phase = mod(TIME / cycle_duration, 1.0);

	float bright_blend = 0.0;

	// ---- Phase 0 (0.0–0.4): diagonal sweep from top-right to bottom-left ----
	// UV.x goes left→right, UV.y goes top→bottom.
	// For a top-right to bottom-left diagonal: use (1.0 - UV.x) + UV.y
	// which equals 0 at top-right and 2 at bottom-left.
	if (phase < 0.4) {
		float t = phase / 0.4;  // 0→1 during sweep
		// Sweep centre travels from -0.4 (off top-right) to 2.4 (off bottom-left).
		float sweep_pos = mix(-0.4, 2.4, t);
		float diag = (1.0 - UV.x) + UV.y;
		float dist = abs(diag - sweep_pos);
		// Gaussian-like falloff; stripe width ~0.35 diagonal units.
		float stripe = exp(-dist * dist * 25.0) * 0.9;
		// Smooth in/out at phase edges.
		float fade = smoothstep(0.0, 0.08, t) * smoothstep(1.0, 0.92, t);
		bright_blend = stripe * fade;
	}
	// ---- Phase 1 (0.4–0.7): hold bright yellow ----
	else if (phase < 0.7) {
		bright_blend = 1.0;
	}
	// ---- Phase 2 (0.7–1.0): fade back to base gold ----
	else {
		float t = (phase - 0.7) / 0.3;  // 0→1 during fade-out
		bright_blend = 1.0 - smoothstep(0.0, 1.0, t);
	}

	bright_blend = clamp(bright_blend, 0.0, 1.0);
	COLOR = mix(gold_base, gold_bright, bright_blend);
}
