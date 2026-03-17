shader_type canvas_item;

// Lightning flash shader for Black Metal difficulty mode.
//
// APPROACH: OVERLAY-BASED (no screen_texture) — same as cinema_film.gdshader.
//
// Why NOT hint_screen_texture:
//   Godot's gl_compatibility renderer has known bugs with hint_screen_texture
//   (GitHub Issues #79914, #66458). When the ColorRect becomes visible after
//   being hidden, hint_screen_texture can return white/empty on that first frame,
//   producing exactly the white blink symptom reported by the owner.
//   Every attempt to fix this (blend_add, warmup, delayed activation) still
//   exhibits the white blink because the screen capture is unreliable.
//
// Overlay approach:
//   The shader outputs the bolt as colored pixels with alpha — transparent
//   where no bolt, colored where the bolt is. Standard alpha blending in
//   the renderer composites this over the scene naturally and correctly.
//   At intensity=0.0: COLOR.a = 0 everywhere → fully transparent (no effect).
//   At bolt pixels: bright blue-white with alpha → visible over scene.
//
// Effect structure:
//   - One or two jagged main bolt streaks from a top point downward
//   - Several branches splitting off the main bolt
//   - A screen-wide corona flash (like area illumination from lightning)
//   - Blue-white inner core, wider glow halo (classic horror lightning)
//   - Every strike looks different: randomized per-strike via seed uniform
//
// Issue #1023: Thunder and lightning effects for Black Metal mode.

// intensity: 0.0 = invisible (no effect), 1.0 = full lightning. Animated by manager.
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
               float noise_scale, float bolt_seed) {
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
//
// OVERLAY APPROACH (no screen_texture):
//   Outputs the lightning bolt as an alpha-composited overlay.
//   Transparent pixels (alpha=0) let the scene show through unchanged.
//   Bolt pixels (alpha>0) are bright blue-white, composited over scene by renderer.
//
//   At intensity=0.0: alpha=0 everywhere → fully transparent, no effect visible.
//   This makes warmup and off-state completely safe with no visual artifacts.
// ============================================================================

void fragment() {
    // At intensity=0: fully transparent — safe for warmup and inactive state
    if (intensity <= 0.001) {
        COLOR = vec4(0.0, 0.0, 0.0, 0.0);
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
    float core_width  = 0.004;   // bright inner core
    float glow_width  = 0.020;   // blue-white glow halo
    float outer_width = 0.060;   // wide dim illumination aura

    float d1 = bolt_sdf(uv, orig_x, orig_y, end_x, end_y, noise_scale, s0);
    float bolt_contrib = 0.0;

    // Core (white-blue, very bright)
    bolt_contrib += smoothstep(core_width, 0.0, d1) * 1.0;

    // Glow halo
    bolt_contrib += smoothstep(glow_width, core_width, d1) * 0.65;

    // Outer aura
    bolt_contrib += smoothstep(outer_width, glow_width, d1) * 0.30;

    // Second bolt if requested
    if (bolt_count >= 1.5) {
        float d2 = bolt_sdf(uv, orig_x2, orig_y, end_x2, end_y2, noise_scale2, s0 + 20.0);
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
        float branch_glow = 0.012;
        bolt_contrib += smoothstep(branch_core, 0.0, bd) * 0.7;
        bolt_contrib += smoothstep(branch_glow, branch_core, bd) * 0.35;
    }

    // ---- screen-wide corona flash (simulates area illumination) ----
    // Fades quickly: strongest at bolt origin, falls off across screen
    float flash_strength = (1.0 - progress) * (1.0 - progress);
    float dist_to_origin = length(uv - vec2(orig_x, orig_y));
    // Screen-wide glow: 0.8 at origin, falls off to ~0.1 at screen edge
    float corona_wide = smoothstep(1.0, 0.0, dist_to_origin) * flash_strength * 0.35;
    // Tight corona near origin
    float corona_tight = smoothstep(0.35, 0.0, dist_to_origin) * flash_strength * 0.25;
    float corona = corona_wide + corona_tight;

    // ---- lightning color ----
    // Blue-white inner core, wider vivid blue-white glow (classic horror lightning)
    vec3 bolt_color_core = vec3(0.95, 0.97, 1.0);  // near-white, slightly cool
    vec3 bolt_color_glow = vec3(0.55, 0.70, 1.0);  // vivid blue-white glow
    vec3 corona_color    = vec3(0.75, 0.85, 1.0);  // cool area illumination

    float bolt_val = clamp(bolt_contrib, 0.0, 1.0);

    // Blend from glow color to core color based on how close to bolt center
    vec3 bolt_rgb = mix(bolt_color_glow, bolt_color_core, smoothstep(0.3, 1.0, bolt_val));

    // Apply intensity fade (manager animates 1→0 over flash duration)
    float fade = intensity;

    // --- Bolt overlay alpha ---
    // At bolt center: bright and mostly opaque
    // Away from bolt: transparent (scene shows through)
    float bolt_alpha = bolt_val * fade;

    // --- Corona (screen-wide illumination flash) alpha ---
    // Very subtle — just a hint of brightening across the full screen
    float corona_alpha = corona * fade;

    // Combine bolt and corona.
    // The corona adds a faint bright tint across the whole screen — like area illumination.
    // The bolt is the sharp visible streak.
    float total_alpha = clamp(bolt_alpha + corona_alpha, 0.0, 1.0);

    // Blend bolt_rgb toward white near bolt center (super-bright core)
    vec3 final_rgb = mix(bolt_color_glow, vec3(1.0), bolt_val * 0.6);
    // Mix in corona color for areas far from bolt
    if (bolt_val < 0.1) {
        final_rgb = corona_color;
    }

    // Output as transparent overlay — no screen_texture needed
    COLOR = vec4(final_rgb, total_alpha);
}
