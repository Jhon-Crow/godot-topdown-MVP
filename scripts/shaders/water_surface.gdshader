shader_type canvas_item;
// Dynamic water surface shader for spring-column simulation (Issue #1495).
//
// Applied to the Polygon2D rendered by WaterSurface. This shader adds:
//   - Animated wave detail on top of the physical deformation
//   - Depth-based color gradient (shallow near surface, deep below)
//   - Foam at the surface edge
//   - Semi-transparent blending
//
// The polygon itself is already deformed by the spring simulation,
// so this shader provides visual detail rather than surface shape.

// --- Wave animation (adds visual detail to the physically-deformed surface) ---
uniform float wave_speed : hint_range(0.0, 5.0) = 0.6;
uniform float wave_frequency : hint_range(0.5, 20.0) = 6.0;
uniform float wave_amplitude : hint_range(0.0, 0.05) = 0.008;

// --- Secondary ripple (finer detail) ---
uniform float ripple_speed : hint_range(0.0, 5.0) = 1.4;
uniform float ripple_frequency : hint_range(1.0, 40.0) = 18.0;
uniform float ripple_amplitude : hint_range(0.0, 0.02) = 0.003;

// --- Colors ---
uniform vec4 shallow_color : source_color = vec4(0.12, 0.50, 0.82, 0.85);
uniform vec4 deep_color    : source_color = vec4(0.04, 0.22, 0.52, 0.92);
uniform vec4 foam_color    : source_color = vec4(0.85, 0.92, 0.98, 0.65);

// --- Foam / white-cap threshold ---
uniform float foam_threshold : hint_range(0.0, 1.0) = 0.72;
uniform float foam_sharpness : hint_range(1.0, 20.0) = 8.0;

// --- Surface foam band (at the top of the polygon = the deformed surface) ---
uniform float surface_foam_width : hint_range(0.0, 0.2) = 0.06;

// --- Blood diffusion overlay ---
uniform vec4 blood_tint : source_color = vec4(0.6, 0.05, 0.05, 0.0);

void fragment() {
	vec2 uv = UV;

	// ---- Subtle wave animation (visual detail only) ----
	float wave1 = sin(uv.x * wave_frequency + TIME * wave_speed)
	            + sin(uv.x * wave_frequency * 0.73 - TIME * wave_speed * 0.6);
	wave1 *= 0.5;

	float wave2 = sin((uv.x + uv.y * 0.4) * ripple_frequency + TIME * ripple_speed)
	            * sin((uv.x * 0.5 - uv.y) * ripple_frequency * 0.6 - TIME * ripple_speed * 0.8);

	float total_disp = wave1 * wave_amplitude + wave2 * ripple_amplitude;
	vec2 distorted_uv = uv + vec2(total_disp, total_disp * 0.5);

	// ---- Depth gradient ----
	float depth = clamp(distorted_uv.y, 0.0, 1.0);
	vec4 water_base = mix(shallow_color, deep_color, depth);

	// ---- Foam at wave crests ----
	float foam_val = smoothstep(foam_threshold, 1.0,
	                            pow(clamp(wave1 * 0.5 + 0.5, 0.0, 1.0), foam_sharpness));
	vec4 water_col = mix(water_base, foam_color, foam_val);

	// ---- Surface foam band at the top edge ----
	float surface_foam = smoothstep(surface_foam_width, 0.0, uv.y);
	water_col = mix(water_col, foam_color, surface_foam * 0.5);

	// ---- Blood diffusion tint ----
	vec3 final_rgb = mix(water_col.rgb, blood_tint.rgb, blood_tint.a);
	float alpha = water_col.a;

	COLOR = vec4(final_rgb, alpha);
}
