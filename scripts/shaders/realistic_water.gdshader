shader_type canvas_item;
// Realistic 2D water shader (Issue #1445)
// Simulates ocean waves on the Beach level with:
//   - Animated wave bands scrolling horizontally
//   - Light refraction (distortion of underlying pixels)
//   - Foam / white-caps near wave crests
//   - Semi-transparent depth gradient (deeper = darker blue)

// --- Wave animation ---
uniform float wave_speed : hint_range(0.0, 5.0) = 0.6;
uniform float wave_frequency : hint_range(0.5, 20.0) = 6.0;
uniform float wave_amplitude : hint_range(0.0, 0.05) = 0.012;

// --- Secondary ripple (finer detail) ---
uniform float ripple_speed : hint_range(0.0, 5.0) = 1.4;
uniform float ripple_frequency : hint_range(1.0, 40.0) = 18.0;
uniform float ripple_amplitude : hint_range(0.0, 0.02) = 0.005;

// --- Refraction (screen-space distortion sampled via SCREEN_TEXTURE) ---
uniform float refraction_strength : hint_range(0.0, 0.05) = 0.018;

// --- Colors ---
uniform vec4 shallow_color : source_color = vec4(0.18, 0.62, 0.90, 0.82);
uniform vec4 deep_color    : source_color = vec4(0.04, 0.28, 0.62, 0.92);
uniform vec4 foam_color    : source_color = vec4(0.92, 0.97, 1.00, 0.85);

// --- Foam / white-cap threshold ---
uniform float foam_threshold : hint_range(0.0, 1.0) = 0.72;
uniform float foam_sharpness : hint_range(1.0, 20.0) = 8.0;

// --- Shore fade: top of the texture blends with transparent (shoreline edge) ---
uniform float shore_fade_width : hint_range(0.0, 0.5) = 0.08;

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

	// ---- Combined displacement ----
	float total_disp = wave1 * wave_amplitude + wave2 * ripple_amplitude;

	// ---- Light refraction via screen texture distortion ----
	// Build a 2D displacement vector from perpendicular wave normals
	float dx = cos(uv.x * wave_frequency + TIME * wave_speed) * wave_amplitude
	         + cos((uv.x + uv.y * 0.4) * ripple_frequency + TIME * ripple_speed) * ripple_amplitude;
	float dy = cos(uv.y * wave_frequency * 0.8 - TIME * wave_speed * 0.5) * wave_amplitude * 0.6;
	vec2 refract_offset = vec2(dx, dy) * refraction_strength;

	vec4 screen_col = texture(SCREEN_TEXTURE, SCREEN_UV + refract_offset);

	// ---- Depth gradient (y=0 top = shallow, y=1 bottom = deep) ----
	float depth = uv.y;
	vec4 water_base = mix(shallow_color, deep_color, depth);

	// ---- Foam / white-caps ----
	// Foam appears where wave1 is near its positive peak
	float foam_val = smoothstep(foam_threshold, 1.0,
	                            pow(clamp(wave1 * 0.5 + 0.5, 0.0, 1.0), foam_sharpness));
	vec4 water_col = mix(water_base, foam_color, foam_val);

	// ---- Blend refracted screen with water tint ----
	// Water is semi-transparent so the refracted background shows through
	vec3 blended = mix(screen_col.rgb, water_col.rgb, water_col.a);
	float alpha   = water_col.a;

	// ---- Shore fade at the top edge (transition from land to water) ----
	float shore_fade = smoothstep(0.0, shore_fade_width, uv.y);
	alpha *= shore_fade;

	COLOR = vec4(blended, alpha);
}
