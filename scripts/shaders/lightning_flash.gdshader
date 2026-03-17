shader_type canvas_item;

// Lightning flash shader for Black Metal difficulty mode.
//
// APPROACH v7: hint_screen_texture + correct startup sequence.
//
// The ColorRect starts HIDDEN (visible=false) in _ready(). After one warmup frame,
// it becomes permanently visible (visible=true, never toggled again). At intensity=0,
// the shader outputs the original scene unchanged (pure passthrough). This guarantees:
//   - No white flash on game startup (framebuffer populated before first sample)
//   - No white flash during gameplay (visible never toggled after warmup)
//   - No corruption of other shaders (passthrough, not transparent overlay)
//
// Why NOT starting visible=true immediately (v6):
//   On the very first game frame, the GL framebuffer is not yet populated and
//   hint_screen_texture returns white. Starting visible=true in _ready() before
//   the scene renders causes the passthrough to output white → white flash at startup.
//
// Why NOT toggling visible during gameplay (v1-v4):
//   Toggling visible=false→true on a hint_screen_texture ColorRect during gameplay
//   can produce a white frame on the first frame after the transition.
//   v7 avoids this by NEVER toggling after the initial warmup frame.
//
// Why NOT the pure overlay approach (v5, no screen_texture):
//   A full-screen transparent ColorRect at layer 98 causes visual corruption on ALL
//   difficulties. (Confirmed in game_log_20260317_032119.txt)
//
// Effect structure:
//   - One or two jagged main bolt streaks from a top point downward
//   - Several branches splitting off the main bolt
//   - A corona near the bolt origin (simulates area illumination from lightning)
//   - Blue-white inner core, wider glow halo (classic horror lightning)
//   - Every strike looks different: randomized per-strike via seed uniform
//
// Issue #1023: Thunder and lightning effects for Black Metal mode.

// intensity: 0.0 = passthrough (no effect), 1.0 = full lightning. Animated by manager.
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

// progress: 0.0 = bolt just struck, 1.0 = fully faded (lifetime of this flash)
uniform float progress : hint_range(0.0, 1.0) = 0.0;

// seed: randomized per flash so each bolt looks different
uniform float seed : hint_range(0.0, 100.0) = 0.0;

// Number of bolt streaks to draw (1 = single bolt, 2 = two simultaneous bolts)
uniform float bolt_count : hint_range(1.0, 2.0) = 1.0;

// Screen texture sampler for reading the rendered scene.
// hint_screen_texture is safe here because the ColorRect is ALWAYS VISIBLE —
// we never toggle visible=false→true, so the white-frame bug never triggers.
// At intensity=0.0: output = original (pure passthrough, identical to black_metal.gdshader warmup).
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

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
// Uses hint_screen_texture: reads the actual rendered scene, then additively
// brightens pixels near the lightning bolt.
//
// At intensity=0.0: COLOR = original (pure pass-through, no effect on any difficulty)
// Near bolt at peak: COLOR = original + bright blue-white additive light
// ============================================================================

void fragment() {
    // Read the actual scene pixel (same approach as black_metal.gdshader)
    vec4 original = textureLod(screen_texture, SCREEN_UV, 0.0);

    // At intensity=0: pure pass-through — safe for warmup and when inactive
    // This ensures no visual artifact on any difficulty when bolt is not firing
    if (intensity <= 0.001) {
        COLOR = original;
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

    // ---- directional corona near origin ----
    // Simulates the area near the lightning strike being extra bright.
    float flash_strength = (1.0 - progress) * (1.0 - progress);
    float dist_to_origin = length(uv - vec2(orig_x, orig_y));
    // Tight corona: falls off to 0 by distance 0.35 UV from origin
    float corona = smoothstep(0.35, 0.0, dist_to_origin) * flash_strength * 0.5;

    // ---- lightning color ----
    // Blue-white inner core, wider vivid blue-white glow (classic horror lightning)
    vec3 bolt_color_core = vec3(0.95, 0.97, 1.0);  // near-white, slightly cool
    vec3 bolt_color_glow = vec3(0.55, 0.70, 1.0);  // vivid blue-white glow
    vec3 corona_color    = vec3(0.75, 0.85, 1.0);  // cool corona near origin

    float bolt_val = clamp(bolt_contrib, 0.0, 1.0);

    // Blend from glow color to core color based on how close to bolt center
    vec3 bolt_rgb = mix(bolt_color_glow, bolt_color_core, smoothstep(0.3, 1.0, bolt_val));

    // Additive lightning contribution (added to scene, not replacing it)
    // bolt_rgb * bolt_val: 0 away from bolt, bright at bolt center
    // corona_color * corona: soft glow near strike point
    vec3 lightning_add = bolt_rgb * bolt_val + corona_color * corona;

    // Apply intensity fade (manager animates 1→0 over flash duration)
    lightning_add *= intensity;

    // Final: original scene + additive lightning light
    // Away from bolt: lightning_add ≈ 0 → output ≈ original (no white blink)
    // At bolt: output = original + bright blue-white (bolt visible over scene)
    vec3 final_rgb = original.rgb + lightning_add;

    COLOR = vec4(final_rgb, original.a);
}
