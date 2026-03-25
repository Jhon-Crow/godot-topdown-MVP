shader_type canvas_item;
// Realistic 2D water shader (Issue #1445)
// Simulates ocean waves on the Beach level with:
//   - Animated wave bands scrolling horizontally
//   - Foam / white-caps near wave crests
//   - Semi-transparent depth gradient (deeper = darker blue)
//   - Shore fade at the top edge for smooth sand/water transition
//   - Blood diffusion support via uniform parameters

// --- Wave animation ---
uniform float wave_speed : hint_range(0.0, 5.0) = 0.6;
uniform float wave_frequency : hint_range(0.5, 20.0) = 6.0;
uniform float wave_amplitude : hint_range(0.0, 0.05) = 0.012;

// --- Secondary ripple (finer detail) ---
uniform float ripple_speed : hint_range(0.0, 5.0) = 1.4;
uniform float ripple_frequency : hint_range(1.0, 40.0) = 18.0;
uniform float ripple_amplitude : hint_range(0.0, 0.02) = 0.005;

// --- Colors ---
uniform vec4 shallow_color : source_color = vec4(0.15, 0.55, 0.85, 0.88);
uniform vec4 deep_color    : source_color = vec4(0.04, 0.22, 0.52, 0.94);
uniform vec4 foam_color    : source_color = vec4(0.85, 0.92, 0.98, 0.70);

// --- Foam / white-cap threshold ---
uniform float foam_threshold : hint_range(0.0, 1.0) = 0.72;
uniform float foam_sharpness : hint_range(1.0, 20.0) = 8.0;

// --- Shore fade: top of the texture blends with transparent (shoreline edge) ---
uniform float shore_fade_width : hint_range(0.0, 0.5) = 0.08;

// --- Blood diffusion overlay ---
// blood_intensity array handled in script via per-pixel SubViewport approach.
// For shader-based tinting, we use a simple uniform for global blood color mix.
uniform vec4 blood_tint : source_color = vec4(0.6, 0.05, 0.05, 0.0);

void fragment() {
	vec2 uv = UV;

	// ---- Primary wave ----
	// Horizontal sinusoidal bands scrolling to the right
	float wave1 = sin(uv.x * wave_frequency + TIME * wave_speed)
	            + sin(uv.x * wave_frequency * 0.73 - TIME * wave_speed * 0.6);
	wave1 *= 0.5; // normalise to [-1, 1]

	// ---- Secondary ripple (diagonal) ----
	float wave2 = sin((uv.x + uv.y * 0.4) * ripple_frequency + TIME * ripple_speed)
	            * sin((uv.x * 0.5 - uv.y) * ripple_frequency * 0.6 - TIME * ripple_speed * 0.8);

	// ---- UV distortion for wave motion ----
	float total_disp = wave1 * wave_amplitude + wave2 * ripple_amplitude;
	vec2 distorted_uv = uv + vec2(total_disp, total_disp * 0.5);

	// ---- Depth gradient (y=0 top = shallow, y=1 bottom = deep) ----
	float depth = distorted_uv.y;
	vec4 water_base = mix(shallow_color, deep_color, depth);

	// ---- Foam / white-caps ----
	// Foam appears where wave1 is near its positive peak
	float foam_val = smoothstep(foam_threshold, 1.0,
	                            pow(clamp(wave1 * 0.5 + 0.5, 0.0, 1.0), foam_sharpness));
	vec4 water_col = mix(water_base, foam_color, foam_val);

	// ---- Blood diffusion tint ----
	// When blood_tint.a > 0, mix blood color into the water
	vec3 final_rgb = mix(water_col.rgb, blood_tint.rgb, blood_tint.a);
	float alpha = water_col.a;

	// ---- Shore fade at the top edge (transition from land to water) ----
	float shore_fade = smoothstep(0.0, shore_fade_width, uv.y);
	alpha *= shore_fade;

	COLOR = vec4(final_rgb, alpha);
}
