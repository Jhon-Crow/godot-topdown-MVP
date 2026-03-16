shader_type canvas_item;
// Lightning flash shader for Black Metal difficulty mode.
//
// Draws actual horror-film style lightning bolts across the screen:
//   - One or two jagged main bolt streaks from a top point downward
//   - Several branches splitting off the main bolt
//   - A bright screen-wide illumination pulse (simulates the instant
//     the lightning lights up the entire scene like old horror films)
//   - The bolt itself is thin and white with a blue-white inner core
//   - The whole effect fades out quickly after impact
//
// OVERLAY APPROACH (no hint_screen_texture):
//   Same as cinema_film.gdshader — we output an overlay with alpha.
//   The CanvasLayer blend mode handles compositing with the scene.
//   This avoids gl_compatibility renderer issues with screen textures.
//
// Issue #1023: Thunder and lightning effects for Black Metal mode.

// intensity: 0.0 = invisible, 1.0 = full effect. Animated by manager.
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

// progress: 0.0 = bolt just struck, 1.0 = fully faded (lifetime of this flash)
uniform float progress : hint_range(0.0, 1.0) = 0.0;

// seed: randomized per flash so each bolt looks different
uniform float seed : hint_range(0.0, 100.0) = 0.0;

// Number of branches to draw (1 = single bolt, 2 = two bolts from same origin)
uniform float bolt_count : hint_range(1.0, 2.0) = 1.0;

// ============================================================================
// HASH / NOISE HELPERS
// ============================================================================

float hash11(float n) {
    n = fract(n * 0.1031);
    n *= n + 33.33;
    n *= n + n;
    return fract(n);
}

float hash21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Smooth 1D noise for bolt path displacement
float smooth_noise(float t, float s) {
    float i = floor(t);
    float f = fract(t);
    float a = hash11(i + s * 37.3);
    float b = hash11(i + 1.0 + s * 37.3);
    // Hermite interpolation
    float u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u);
}

// ============================================================================
// LIGHTNING BOLT DISTANCE
//
// The bolt travels from a start point (sx, sy) to end point (ex, ey).
// Along the way it jags horizontally using layered noise.
// Returns the minimum distance from UV to the bolt centerline,
// plus a glow falloff scaled by bolt_thickness.
// ============================================================================

float bolt_sdf(vec2 uv, float sx, float sy, float ex, float ey,
               float noise_scale, float bolt_seed, float aspect) {
    // Direction vector of the bolt
    vec2 start = vec2(sx, sy);
    vec2 end_  = vec2(ex, ey);
    vec2 dir = end_ - start;
    float len = length(dir);
    if (len < 0.001) return 1.0;
    vec2 dir_n = dir / len;

    // Perpendicular direction
    vec2 perp = vec2(-dir_n.y, dir_n.x);

    // Project uv onto the bolt's local coordinate
    vec2 d = uv - start;
    float t = dot(d, dir_n) / len;      // 0..1 along bolt
    float s_dist = dot(d, perp);        // signed distance perpendicular

    if (t < 0.0 || t > 1.0) return 1.0;

    // Multiple octaves of horizontal displacement for a jagged look
    float disp = 0.0;
    float amp = noise_scale;
    float freq = 4.0;
    for (int i = 0; i < 4; i++) {
        disp += (smooth_noise(t * freq + bolt_seed * 3.7 + float(i), bolt_seed) - 0.5)
                 * amp;
        amp *= 0.5;
        freq *= 2.2;
    }

    // Account for aspect ratio so the bolt looks correct
    float dist = abs(s_dist - disp * (1.0 / aspect));
    return dist;
}

// ============================================================================
// BRANCH: shorter off-shoot from a point along the main bolt
// Returns distance to the branch line
// ============================================================================

float branch_sdf(vec2 uv, float start_t, float sx, float sy, float ex, float ey,
                 float branch_seed, float aspect) {
    // Find the point along the main bolt axis at parameter start_t
    vec2 bolt_start = vec2(sx, sy);
    vec2 bolt_end   = vec2(ex, ey);
    vec2 bolt_dir   = bolt_end - bolt_start;

    // Branch starts at this position on the bolt
    vec2 branch_origin = bolt_start + bolt_dir * start_t;

    // Branch direction: angled off to the side
    float angle = (hash11(branch_seed) - 0.5) * 1.2 + 1.5707963; // ~±35° from vertical
    float branch_len = 0.12 + hash11(branch_seed + 0.5) * 0.15;
    vec2 branch_end = branch_origin + vec2(cos(angle), sin(angle)) * branch_len;

    // Simple line segment distance for branches (less displacement)
    vec2 bd = branch_end - branch_origin;
    float blen = length(bd);
    if (blen < 0.001) return 1.0;
    vec2 bdir_n = bd / blen;
    vec2 bperp  = vec2(-bdir_n.y, bdir_n.x);

    vec2 dv = uv - branch_origin;
    float bt = clamp(dot(dv, bdir_n) / blen, 0.0, 1.0);
    float bs = dot(dv, bperp);

    // Small displacement on branch
    float bdisp = (smooth_noise(bt * 6.0 + branch_seed * 2.1, branch_seed + 1.0) - 0.5) * 0.02;
    float dist = abs(bs - bdisp * (1.0 / aspect));
    if (bt < 0.0 || bt >= 1.0) return 1.0;
    return dist;
}

// ============================================================================
// MAIN FRAGMENT
// ============================================================================

void fragment() {
    if (intensity <= 0.001) {
        COLOR = vec4(0.0);
        return;
    }

    vec2 uv = UV;

    // Approximate aspect ratio (1280x720)
    float aspect = 1.777;

    // ---- derive per-flash random parameters from seed ----
    float s0 = seed;

    // Main bolt origin (top portion of screen, random X)
    float orig_x = 0.2 + hash11(s0 + 1.0) * 0.6;
    float orig_y = 0.0;

    // Main bolt end (bottom or side of screen)
    float end_x = orig_x + (hash11(s0 + 2.0) - 0.5) * 0.5;
    float end_y = 0.65 + hash11(s0 + 3.0) * 0.3; // goes 65-95% down the screen

    // How noisy/jagged the bolt is
    float noise_scale = 0.04 + hash11(s0 + 4.0) * 0.05;

    // Second bolt (offset seed, slightly different position)
    float orig_x2 = orig_x + (hash11(s0 + 11.0) - 0.5) * 0.25;
    float end_x2  = orig_x2 + (hash11(s0 + 12.0) - 0.5) * 0.4;
    float end_y2  = 0.6  + hash11(s0 + 13.0) * 0.35;
    float noise_scale2 = 0.035 + hash11(s0 + 14.0) * 0.04;

    // ---- compute bolt distances ----
    float core_width  = 0.003;   // bright inner core
    float glow_width  = 0.012;   // outer blue-white glow
    float outer_width = 0.04;    // wide dim illumination halo

    float d1 = bolt_sdf(uv, orig_x, orig_y, end_x, end_y, noise_scale, s0, aspect);
    float bolt_contrib = 0.0;

    // Core (white-blue)
    bolt_contrib += smoothstep(core_width, 0.0, d1);

    // Glow
    bolt_contrib += smoothstep(glow_width, core_width, d1) * 0.55;

    // Outer halo
    bolt_contrib += smoothstep(outer_width, glow_width, d1) * 0.18;

    // Second bolt if requested
    if (bolt_count >= 1.5) {
        float d2 = bolt_sdf(uv, orig_x2, orig_y, end_x2, end_y2, noise_scale2, s0 + 20.0, aspect);
        bolt_contrib += smoothstep(core_width, 0.0, d2);
        bolt_contrib += smoothstep(glow_width, core_width, d2) * 0.45;
        bolt_contrib += smoothstep(outer_width, glow_width, d2) * 0.12;
    }

    // ---- branches off bolt 1 ----
    for (int b = 0; b < 4; b++) {
        float bs = s0 + float(b) * 7.39 + 50.0;
        float branch_t = 0.2 + hash11(bs) * 0.65; // somewhere along the main bolt
        float bd = branch_sdf(uv, branch_t, orig_x, orig_y, end_x, end_y, bs, aspect);
        float branch_width = 0.002;
        float branch_glow  = 0.007;
        bolt_contrib += smoothstep(branch_width, 0.0, bd) * 0.7;
        bolt_contrib += smoothstep(branch_glow, branch_width, bd) * 0.25;
    }

    // ---- screen-wide illumination flash ----
    // A diffuse light that fills the whole screen at the moment of strike,
    // fading quickly — simulates how lightning briefly lights up everything.
    // Progress 0 = just struck; use it to make the flash stronger at start.
    float flash_strength = (1.0 - progress) * (1.0 - progress); // ease-out^2
    float screen_glow = flash_strength * 0.35;

    // Extra bright near the bolt origin (the source point near the top)
    float dist_to_origin = length(uv - vec2(orig_x, orig_y)) * aspect;
    float corona = smoothstep(0.5, 0.0, dist_to_origin) * flash_strength * 0.5;

    // ---- color composition ----
    // Lightning core: white with slight blue tint (classic horror lightning)
    vec3 bolt_color_core   = vec3(0.95, 0.97, 1.0);  // near-white, slightly cool
    vec3 bolt_color_glow   = vec3(0.65, 0.75, 1.0);  // blue-white glow
    vec3 screen_flash_color = vec3(0.88, 0.92, 1.0); // cool white screen fill

    float bolt_alpha = clamp(bolt_contrib, 0.0, 1.0);
    float screen_alpha = clamp(screen_glow + corona, 0.0, 1.0);

    // Combine: screen flash first, bolt on top
    vec3 final_color = mix(screen_flash_color, bolt_color_glow, bolt_alpha * 0.5);
    final_color = mix(final_color, bolt_color_core, clamp(bolt_contrib - 0.5, 0.0, 1.0));
    float final_alpha = clamp(screen_alpha + bolt_alpha * 0.9, 0.0, 1.0);

    // Apply overall intensity (animated fade)
    COLOR = vec4(final_color, final_alpha * intensity);
}
