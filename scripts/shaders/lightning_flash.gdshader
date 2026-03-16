shader_type canvas_item;
render_mode blend_add;
// Lightning flash shader for Black Metal difficulty mode.
//
// Draws actual horror-film style lightning bolts across the screen.
// Uses render_mode blend_add so the output is ADDED to the scene:
//   - Where the shader outputs black (vec3(0.0)), nothing is added → invisible
//   - Where it outputs bright colors, those pixels become brighter
//   - This means no white blink — only the bolt and its glow are visible
//
// Effect structure:
//   - One or two jagged main bolt streaks from a top point downward
//   - Several branches splitting off the main bolt
//   - A bright screen-wide illumination corona centered on the bolt origin
//     (simulates how lightning briefly lights up the area around the strike)
//   - Blue-white inner core, wider glow halo (classic horror lightning)
//   - Every strike looks different: randomized per-strike via seed uniform
//
// OVERLAY APPROACH (no hint_screen_texture):
//   Same as cinema_film.gdshader — compatible with gl_compatibility renderer.
//
// Issue #1023: Thunder and lightning effects for Black Metal mode.

// intensity: 0.0 = invisible, 1.0 = full effect. Animated by manager.
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

// progress: 0.0 = bolt just struck, 1.0 = fully faded (lifetime of this flash)
uniform float progress : hint_range(0.0, 1.0) = 0.0;

// seed: randomized per flash so each bolt looks different
uniform float seed : hint_range(0.0, 100.0) = 0.0;

// Number of bolt streaks to draw (1 = single bolt, 2 = two simultaneous bolts)
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
// LIGHTNING BOLT SDF
//
// The bolt travels from (sx, sy) to (ex, ey), displaced horizontally by
// multi-octave noise for a jagged look.
// Returns the distance from UV to the bolt centerline.
// ============================================================================

float bolt_sdf(vec2 uv, float sx, float sy, float ex, float ey,
               float noise_scale, float bolt_seed, float aspect) {
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

    // Distance from this pixel to the displaced bolt centerline
    float dist = abs(s_dist - disp);
    return dist;
}

// ============================================================================
// BRANCH SDF: shorter off-shoot from a point along the main bolt
// ============================================================================

float branch_sdf(vec2 uv, float start_t, float sx, float sy, float ex, float ey,
                 float branch_seed) {
    vec2 bolt_start = vec2(sx, sy);
    vec2 bolt_end   = vec2(ex, ey);
    vec2 bolt_dir   = bolt_end - bolt_start;

    // Branch starts at this position on the bolt
    vec2 branch_origin = bolt_start + bolt_dir * start_t;

    // Branch direction: angled off to the side from vertical
    float angle = (hash11(branch_seed) - 0.5) * 1.2 + 1.5707963; // ±35° from vertical
    float branch_len = 0.10 + hash11(branch_seed + 0.5) * 0.12;
    vec2 branch_end = branch_origin + vec2(cos(angle), sin(angle)) * branch_len;

    // Simple line segment distance
    vec2 bd = branch_end - branch_origin;
    float blen = length(bd);
    if (blen < 0.001) return 1.0;
    vec2 bdir_n = bd / blen;
    vec2 bperp  = vec2(-bdir_n.y, bdir_n.x);

    vec2 dv = uv - branch_origin;
    float bt = clamp(dot(dv, bdir_n) / blen, 0.0, 1.0);
    float bs = dot(dv, bperp);

    float bdisp = (smooth_noise(bt * 6.0 + branch_seed * 2.1, branch_seed + 1.0) - 0.5) * 0.015;
    float dist = abs(bs - bdisp);
    if (bt >= 1.0) return 1.0;
    return dist;
}

// ============================================================================
// MAIN FRAGMENT
// render_mode blend_add means:
//   final_pixel = scene_pixel + shader_output
//   black (0,0,0) adds nothing → invisible
//   bright colors add light to the scene → lightning glow
// ============================================================================

void fragment() {
    if (intensity <= 0.001) {
        COLOR = vec4(0.0);
        return;
    }

    vec2 uv = UV;

    // ---- derive per-flash random parameters from seed ----
    float s0 = seed;

    // Main bolt origin (top portion of screen, random X)
    float orig_x = 0.2 + hash11(s0 + 1.0) * 0.6;
    float orig_y = 0.0;

    // Main bolt end (lower portion of screen)
    float end_x = orig_x + (hash11(s0 + 2.0) - 0.5) * 0.45;
    float end_y = 0.65 + hash11(s0 + 3.0) * 0.3;

    // Jaggedness of the bolt
    float noise_scale = 0.03 + hash11(s0 + 4.0) * 0.04;

    // Second bolt (slightly offset)
    float orig_x2 = orig_x + (hash11(s0 + 11.0) - 0.5) * 0.2;
    float end_x2  = orig_x2 + (hash11(s0 + 12.0) - 0.5) * 0.35;
    float end_y2  = 0.6  + hash11(s0 + 13.0) * 0.35;
    float noise_scale2 = 0.025 + hash11(s0 + 14.0) * 0.035;

    // ---- bolt widths ----
    // With blend_add, these values control how much light the bolt adds.
    // Wider values ensure the bolt is always clearly visible on screen.
    float core_width  = 0.004;   // bright inner core
    float glow_width  = 0.018;   // blue-white glow halo
    float outer_width = 0.055;   // wide dim illumination aura

    float d1 = bolt_sdf(uv, orig_x, orig_y, end_x, end_y, noise_scale, s0, 1.0);
    float bolt_contrib = 0.0;

    // Core (white-blue, very bright)
    bolt_contrib += smoothstep(core_width, 0.0, d1) * 1.0;

    // Glow halo
    bolt_contrib += smoothstep(glow_width, core_width, d1) * 0.65;

    // Outer aura
    bolt_contrib += smoothstep(outer_width, glow_width, d1) * 0.25;

    // Second bolt if requested
    if (bolt_count >= 1.5) {
        float d2 = bolt_sdf(uv, orig_x2, orig_y, end_x2, end_y2, noise_scale2, s0 + 20.0, 1.0);
        bolt_contrib += smoothstep(core_width, 0.0, d2) * 1.0;
        bolt_contrib += smoothstep(glow_width, core_width, d2) * 0.55;
        bolt_contrib += smoothstep(outer_width, glow_width, d2) * 0.20;
    }

    // ---- branches off bolt 1 ----
    for (int b = 0; b < 4; b++) {
        float bs = s0 + float(b) * 7.39 + 50.0;
        float branch_t = 0.2 + hash11(bs) * 0.65;
        float bd = branch_sdf(uv, branch_t, orig_x, orig_y, end_x, end_y, bs);
        float branch_core = 0.003;
        float branch_glow = 0.010;
        bolt_contrib += smoothstep(branch_core, 0.0, bd) * 0.7;
        bolt_contrib += smoothstep(branch_glow, branch_core, bd) * 0.30;
    }

    // ---- directional corona near origin ----
    // A soft glow centered near the bolt origin point (top of screen).
    // With blend_add this ADDS light to the scene around the origin,
    // simulating the area near the lightning strike being extra bright.
    // Critically: this does NOT produce a screen-wide white blink.
    float flash_strength = (1.0 - progress) * (1.0 - progress);
    float dist_to_origin = length(uv - vec2(orig_x, orig_y));
    // Tight corona: falls off to 0 by distance 0.35 UV from origin
    float corona = smoothstep(0.35, 0.0, dist_to_origin) * flash_strength * 0.6;

    // ---- color ----
    // Lightning core: bright white with cool blue tint (classic horror)
    vec3 bolt_color_core = vec3(0.95, 0.97, 1.0);  // near-white, slightly cool
    vec3 bolt_color_glow = vec3(0.55, 0.70, 1.0);  // vivid blue-white glow
    vec3 corona_color    = vec3(0.75, 0.85, 1.0);  // cool corona near origin

    float bolt_val = clamp(bolt_contrib, 0.0, 1.0);

    // Blend from glow color to core color based on how close to bolt center
    vec3 bolt_rgb = mix(bolt_color_glow, bolt_color_core, smoothstep(0.3, 1.0, bolt_val));

    // Combine bolt and corona (additive; background is implicitly black = no addition)
    vec3 final_rgb = bolt_rgb * bolt_val + corona_color * corona;

    // Apply intensity (manager fades this from 1→0 over flash lifetime)
    COLOR = vec4(final_rgb * intensity, 1.0);
}
