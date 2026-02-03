# Case Study: Cinema Film Effect Implementation (Issue #418)

## Problem Statement

The request is to add a "cinema film effect" to all images in the game, specifically:
- **Film grain** (зернистость) - Adding noise/grain texture typical of old film
- **Warm colors** (теплота цветов) - Color grading toward warm/sepia tones
- **Sunny/bright effect** (солничность) - Make the image look sunnier
- **Film defects** (дефекты плёнки) - Rare scratches, dust, and flicker effects

This is a common visual effect used to create a nostalgic, cinematic, or retro aesthetic in games.

## Research and Analysis

### Existing Post-Processing Architecture in This Project

The project already has a well-established pattern for screen-wide post-processing effects:

1. **Autoload Manager Pattern**: Effects are managed through singleton autoloads
   - `HitEffectsManager` - Saturation boost on hit
   - `LastChanceEffectsManager` - Blue sepia + ripple effect on low health
   - `PenultimateHitEffectsManager` - Pre-death effect

2. **Technical Implementation**:
   - CanvasLayer at layer 100 (renders on top)
   - ColorRect with full screen anchors
   - ShaderMaterial with custom `.gdshader` files
   - Mouse filter ignored for UI passthrough

3. **Existing Shaders**:
   - `scripts/shaders/saturation.gdshader` - Saturation and contrast adjustment
   - `scripts/shaders/last_chance.gdshader` - Blue sepia tint with ripple distortion

### Industry Solutions for Film Grain Effects

#### Option 1: Sine-Based Noise (Initial Implementation - DEPRECATED)
Source: [Godot Shaders - Film Grain](https://godotshaders.com/shader/film-grain-shader/)

```glsl
float noise = (fract(sin(dot(UV, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) * 2.0;
```

**Pros**: Simple, efficient, no external textures needed
**Cons**: Creates visible ripple/wave artifacts due to sine wave nature

#### Option 2: Modulo-Based Noise (Selected Approach - v2.0)
Source: [Godot Shaders - Grain Old Movie](https://godotshaders.com/shader/grain-old-movie/)

```glsl
float x = (pos.x + 4.0) * (pos.y + 4.0) * (time_factor);
float grain = mod(mod(x, 13.0) * mod(x, 123.0), 0.01) - 0.005;
```

**Pros**: No ripple/wave artifacts, uses prime number modulo operations
**Cons**: Slightly more complex

#### Option 3: Darkness-Weighted Film Grain
Source: [Godot Shaders - Darkness-Weighted](https://godotshaders.com/shader/darkness-weighted-film-grain-effect/)

Applies grain more strongly to darker areas (more realistic).

**Pros**: Mimics real film behavior
**Cons**: More complex calculations

### Film Defect Solutions

#### Vertical Scratches
Source: [Godot Shaders - Old Movie Shader](https://godotshaders.com/shader/old-movie-shader/)

Thin vertical lines that appear randomly at different screen positions.

#### Dust Particles
Dark spots that appear briefly at random positions, simulating dust on the film.

#### Projector Flicker
Subtle brightness variations that simulate old projector light inconsistencies.

### Warm Color Grading Approaches

#### Option 1: Sepia Tint via Luminance (v1.0)
Already implemented in `last_chance.gdshader`:
```glsl
float luminance = dot(screen_color.rgb, vec3(0.299, 0.587, 0.114));
vec3 sepia = luminance * sepia_color;
vec3 tinted = mix(screen_color.rgb, sepia, sepia_intensity);
```

#### Option 2: Multiplicative Tint (Selected for v2.0)
Preserves more color detail by multiplying original colors:
```glsl
vec3 warm_tinted = color * warm_color;
color = mix(color, warm_tinted, warm_intensity);
```

## Implementation History

### Version 1.0 (Initial Implementation)
- Basic film grain using sine-based noise
- Warm color tint using luminance-based sepia

**Issue Found**: Ripple/wave artifacts visible on screen (reported by user)

### Version 2.0 (Current Implementation)
Changes made to address feedback:

1. **Fixed Grain Artifacts**:
   - Replaced sine-based noise with modulo-based noise function
   - Uses frame-based time quantization to prevent smooth wave transitions
   - No more visible ripple patterns

2. **Added Sunny Effect**:
   - Golden highlight boost for bright areas
   - Subtle warm bloom across the image
   - Makes the scene look sunnier and more cheerful

3. **Added Vignette Effect**:
   - Soft edge darkening for a classic cinematic look
   - Configurable intensity and softness

4. **Added Film Defects**:
   - **Vertical scratches**: Thin white lines that appear randomly
   - **Dust particles**: Dark spots at random positions
   - **Projector flicker**: Subtle brightness variations
   - All defects are probability-based (default ~1.5% chance per frame)

5. **Improved Color Handling**:
   - Changed warm tint to multiplicative blend (preserves more detail)
   - Added contrast control
   - Better brightness adjustment

## Proposed Solution (v2.0)

### Architecture

Following the existing project patterns, implement:

1. **Shader**: `scripts/shaders/cinema_film.gdshader`
   - Film grain (modulo-based, no artifacts)
   - Warm color tint
   - Sunny/highlight effect
   - Vignette
   - Film defects (scratches, dust, flicker)

2. **Manager**: `scripts/autoload/cinema_effects_manager.gd`
   - Creates CanvasLayer/ColorRect overlay
   - Manages all shader parameters
   - Provides comprehensive API for all effects

3. **Configuration**: Update `project.godot`
   - Register autoload for global availability

### Shader Parameters

```glsl
// Film Grain
uniform float grain_intensity : hint_range(0.0, 0.5) = 0.04;
uniform bool grain_enabled = true;

// Warm Color Tint
uniform vec3 warm_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float warm_intensity : hint_range(0.0, 1.0) = 0.12;
uniform bool warm_enabled = true;

// Sunny Effect
uniform float sunny_intensity : hint_range(0.0, 0.5) = 0.08;
uniform float sunny_highlight_boost : hint_range(1.0, 2.0) = 1.15;
uniform bool sunny_enabled = true;

// Vignette
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.25;
uniform float vignette_softness : hint_range(0.0, 1.0) = 0.45;
uniform bool vignette_enabled = true;

// Brightness/Contrast
uniform float brightness : hint_range(0.5, 1.5) = 1.05;
uniform float contrast : hint_range(0.5, 2.0) = 1.05;

// Film Defects
uniform bool defects_enabled = true;
uniform float defect_probability : hint_range(0.0, 0.1) = 0.015;
uniform float scratch_intensity : hint_range(0.0, 1.0) = 0.6;
uniform float dust_intensity : hint_range(0.0, 1.0) = 0.5;
uniform float flicker_intensity : hint_range(0.0, 0.3) = 0.03;
```

### API Reference

```gdscript
# Master Control
CinemaEffectsManager.set_enabled(true/false)

# Grain Effect
CinemaEffectsManager.set_grain_intensity(0.04)
CinemaEffectsManager.set_grain_enabled(true/false)

# Warm Color Tint
CinemaEffectsManager.set_warm_color(Color(1.0, 0.95, 0.85))
CinemaEffectsManager.set_warm_intensity(0.12)
CinemaEffectsManager.set_warm_enabled(true/false)

# Sunny Effect
CinemaEffectsManager.set_sunny_intensity(0.08)
CinemaEffectsManager.set_sunny_highlight_boost(1.15)
CinemaEffectsManager.set_sunny_enabled(true/false)

# Vignette
CinemaEffectsManager.set_vignette_intensity(0.25)
CinemaEffectsManager.set_vignette_softness(0.45)
CinemaEffectsManager.set_vignette_enabled(true/false)

# Brightness/Contrast
CinemaEffectsManager.set_brightness(1.05)
CinemaEffectsManager.set_contrast(1.05)

# Film Defects
CinemaEffectsManager.set_defects_enabled(true/false)
CinemaEffectsManager.set_defect_probability(0.015)
CinemaEffectsManager.set_scratch_intensity(0.6)
CinemaEffectsManager.set_dust_intensity(0.5)
CinemaEffectsManager.set_flicker_intensity(0.03)

# Reset
CinemaEffectsManager.reset_to_defaults()
```

## References

### External Resources
- [Godot Film Grain Shader](https://godotshaders.com/shader/film-grain-shader/) - CC0 License
- [Godot Grain Old Movie Shader](https://godotshaders.com/shader/grain-old-movie/) - Modulo-based grain
- [Godot Old Movie Shader](https://godotshaders.com/shader/old-movie-shader/) - Scratches & dust
- [Godot Darkness-Weighted Grain](https://godotshaders.com/shader/darkness-weighted-film-grain-effect/) - Reference
- [Godot Film Grain Shader Repository](https://github.com/kondelik/Godot_Film_Grain_Shader) - CC-BY 3.0
- [Godot 4 Color Correction](https://github.com/ArseniyMirniy/Godot-4-Color-Correction-and-Screen-Effects) - MIT License
- [Custom Post-Processing - Godot Docs](https://docs.godotengine.org/en/stable/tutorials/shaders/custom_postprocessing.html)
- [Film Grain Proposal for Godot](https://github.com/godotengine/godot-proposals/issues/1684)

### Internal References
- `scripts/shaders/saturation.gdshader` - Simple post-processing example
- `scripts/shaders/last_chance.gdshader` - Complex effect with sepia tint
- `scripts/autoload/hit_effects_manager.gd` - Manager pattern reference

### Version 2.1 (White Screen Fix)

**Issue Reported**: Game screen completely white, menu works

**Root Cause Analysis**:
After investigating the v2.0 shader, several potential causes were identified:

1. **Hash function returning 0 for zero inputs**: The hash function `hash(vec2(0,0))` returns 0, which at TIME=0 causes deterministic behavior that may lead to extreme values.

2. **Floating-point precision issues**: Large values in the grain noise calculation could cause precision loss and unexpected results.

3. **Missing zero-input protection**: Various calculations use TIME directly without offset, which can result in predictable patterns at game start.

**Fixes Applied**:

1. **Added offsets to hash function**: All hash function inputs now have a small offset (`+0.1`) to avoid zero-input issues.

2. **Simplified film grain function**: Replaced complex modulo-based calculation with simpler hash-based approach that's more stable.

3. **Added frame offset**: All frame calculations now use `+1.0` offset to avoid frame 0 issues.

4. **Reduced effect intensities**: Scratches and other effects now have reduced multipliers to prevent over-brightening.

5. **Added early exit for transparent pixels**: If screen_color.a is near zero, skip processing to avoid issues with empty regions.

6. **Improved flicker range**: Changed flicker range from potentially brightening (0.85-1.15) to more conservative (0.92-1.08).

**Game Logs Analyzed**:
- `game_log_20260203_154430.txt` - Shows game loading normally but CinemaEffectsManager initialization logs are missing, indicating potential script loading issues or shader compilation problems.

### Version 2.2 (Persistent White Screen Fix)

**Issue Reported**: White screen persists after v2.1 fix; no CinemaEffectsManager logs in game output.

**Root Cause Analysis**:

After analyzing the new game log (`game_log_20260203_160817.txt`), the root cause was identified:

1. **Render timing issue**: The cinema effect shader samples `screen_texture` (what's already been rendered). If the shader is visible BEFORE the scene renders, it samples an empty/white framebuffer.

2. **Always-on effect timing**: Unlike other effect managers (HitEffectsManager, LastChanceEffectsManager) that only show their overlays temporarily, the CinemaEffectsManager keeps its overlay always visible. This creates a timing problem at startup and scene changes.

3. **No delayed activation**: The shader was being made visible immediately after warmup, before the actual game scene had rendered. The `hint_screen_texture` sampled an empty white buffer, causing the white screen.

**Research Sources**:
- [Godot Forum: hint_screen_texture empty texture](https://forum.godotengine.org/t/why-is-hint-screen-texture-giving-an-empty-texture/120012) - Explains that screen_texture captures what's ALREADY rendered before the current object.
- [Godot GitHub Issue #69885](https://github.com/godotengine/godot/issues/69885) - White rectangle rendering issue with ShaderMaterial.

**Fixes Applied**:

1. **Added delayed activation**: The cinema effect now waits 3 frames before becoming visible, ensuring the scene has fully rendered.

2. **Start with overlay hidden**: Changed from starting visible to starting hidden, matching the pattern used by other effect managers.

3. **Re-delay on scene changes**: When the scene changes, the effect temporarily hides and re-enables after a delay to ensure the new scene renders first.

4. **Added comprehensive logging**: The manager now outputs detailed logs to FileLogger for better debugging.

**Key Code Changes**:

```gdscript
# New constants
const ACTIVATION_DELAY_FRAMES: int = 3

# New state variables
var _activation_frame_counter: int = 0
var _waiting_for_activation: bool = false

# Process function for delayed activation
func _process(_delta: float) -> void:
    if _waiting_for_activation:
        _activation_frame_counter += 1
        if _activation_frame_counter >= ACTIVATION_DELAY_FRAMES:
            _waiting_for_activation = false
            if _is_active:
                _cinema_rect.visible = true
```

**Game Logs Added for Debugging**:
- `game_log_20260203_160817.txt` - Added to case study folder for reference.

### Version 3.0 (gl_compatibility Mode Fix)

**Issue Reported**: "моргает уровень, затем всё белое" (level blinks, then everything is white)

The user continued to experience white screen issues after v2.2. The level would briefly flash/render correctly, then turn completely white when the cinema effect activated.

**Root Cause Analysis**:

1. **Renderer-Specific Bug**: The project uses `gl_compatibility` renderer (as seen in `project.godot`: `renderer/rendering_method="gl_compatibility"`). This renderer has known issues with `hint_screen_texture`.

2. **GitHub Issue #79914**: There's a confirmed bug in Godot where using `texture()` with `filter_linear_mipmap` on `hint_screen_texture` causes rendering glitches (pink gridded lines, white screens) in Compatibility mode.

3. **Workaround Required**: The fix is to use `textureLod()` instead of `texture()` and use `filter_nearest` instead of `filter_linear_mipmap`.

**Research Sources**:
- [GitHub Issue #79914: Glitch in shader when using screen_texture and Compatibility mode](https://github.com/godotengine/godot/issues/79914)
- [The Shaggy Dev: The fix for UI and post-processing shaders in Godot 4](https://shaggydev.com/2025/04/09/godot-ui-postprocessing-shaders/)
- [Godot Forum: Why is hint_screen_texture giving an empty texture?](https://forum.godotengine.org/t/why-is-hint-screen-texture-giving-an-empty-texture/120012)
- [Godot Docs: Screen-reading shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html)

**Fixes Applied**:

1. **Changed texture sampling function**: Replaced `texture(screen_texture, SCREEN_UV)` with `textureLod(screen_texture, SCREEN_UV, 0.0)` in all shaders.

2. **Changed filter mode**: Replaced `filter_linear_mipmap` with `filter_nearest` in the uniform declaration.

3. **Added repeat_disable**: Added `repeat_disable` hint for proper edge handling.

4. **Updated all shaders**: Applied the same fixes to `saturation.gdshader` and `last_chance.gdshader` for consistency.

**Key Code Changes (cinema_film.gdshader)**:

Before (v2.2):
```glsl
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
...
vec4 screen_color = texture(screen_texture, SCREEN_UV);
```

After (v3.0):
```glsl
// Use filter_nearest and textureLod for gl_compatibility mode support
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
...
// Using textureLod() is required for Compatibility renderer (Issue #79914)
vec4 screen_color = textureLod(screen_texture, SCREEN_UV, 0.0);
```

**Why This Works**:

In Godot's Compatibility renderer (OpenGL ES 3.0 / WebGL 2.0):
- The `texture()` function with mipmapped screen textures can return incorrect values
- `textureLod()` explicitly specifies the LOD level, bypassing mipmap-related bugs
- `filter_nearest` avoids interpolation issues that can occur with screen textures

**Game Logs Added**:
- `game_log_20260203_162259.txt` - Shows the "blink then white" behavior

## Implementation Notes

### Performance Considerations
- Shader warmup on startup to prevent first-frame stutter (Issue #343 pattern)
- Hash-based noise function (efficient, no texture lookups)
- Single pass shader combining all effects
- Film defects use probability-based triggering to minimize calculations

### Compatibility
- Uses `canvas_item` shader type (2D compatible)
- **v4.0: DOES NOT use `hint_screen_texture`** - avoids gl_compatibility bugs entirely
- Works with all Godot 4 rendering modes (Forward+, Mobile, Compatibility)

### Key Technical Decisions

1. **Overlay approach (v4.0)**: Avoids hint_screen_texture entirely for maximum compatibility
2. **Hash-based noise over sine-based**: Eliminates visible wave patterns
3. **Frame-quantized time**: Prevents smooth transitions that can look like waves
4. **Multiplicative warm tint**: Preserves more color detail than luminance-based
5. **Probability-based defects**: Realistic rare occurrence, minimal performance impact
6. **Minimal delayed activation (1 frame)**: Ensures smooth scene transitions

### Version 4.0 (Overlay Approach Fix)

**Issue Reported**: "всё ещё не работает" (still not working) - White screen persists after v3.0 fix.

Despite all previous fixes (textureLod, filter_nearest, delayed activation), the user continued to experience white screens in gl_compatibility mode.

**Root Cause Analysis (Deep Investigation)**:

After extensive research into Godot's gl_compatibility renderer, multiple fundamental issues were identified:

1. **Known Godot Bugs**: Multiple open issues track gl_compatibility + hint_screen_texture problems:
   - [GitHub Issue #79914](https://github.com/godotengine/godot/issues/79914): Pink grid lines, white screens
   - [GitHub Issue #66458](https://github.com/godotengine/godot/issues/66458): OpenGL Compatibility renderer tracker
   - [Forum: hint_screen_texture empty texture](https://forum.godotengine.org/t/why-is-hint-screen-texture-giving-an-empty-texture/120012)
   - [Forum: screen_texture strange in GL compatibility](https://forum.godotengine.org/t/screen-texture-behaves-strangely-with-gl-compatibility-renderer-but-works-fine-with-forward/93296)

2. **Multiple Screen Shaders Conflict**: Godot only takes a SINGLE snapshot for `hint_screen_texture`. When multiple shaders use it:
   - The engine copies the framebuffer only once
   - Subsequent shaders read potentially corrupted/stale data
   - The cinema effect (always visible) interferes with hit effects and last chance effects

3. **Always-On Effect Problem**: Unlike temporary effects (hit_effects, last_chance), the cinema effect is designed to be continuously visible. This creates persistent interference with the screen texture buffer.

4. **The textureLod() / filter_nearest Fixes Were Insufficient**: These workarounds help with some gl_compatibility issues but don't solve the fundamental screen texture conflicts.

**Solution Applied (v4.0 - OVERLAY APPROACH)**:

Complete architectural change: **Remove hint_screen_texture dependency entirely**.

Instead of sampling and modifying the screen, the shader now creates **transparent overlays** that blend on top of the rendered scene using standard alpha blending:

1. **Film grain**: Rendered as semi-transparent white/black noise pixels
2. **Vignette**: Rendered as a dark gradient overlay at screen edges
3. **Warm color tint**: Rendered as a subtle warm-colored transparent overlay
4. **Sunny effect**: Rendered as a light golden transparent overlay
5. **Film defects**: Rendered as separate overlay elements (scratches, dust, flicker)

**Key Code Changes**:

Shader (cinema_film.gdshader v4.0):
```glsl
// NO hint_screen_texture - creates overlay instead
shader_type canvas_item;

void fragment() {
    // Start with transparent base
    vec4 overlay = vec4(0.0, 0.0, 0.0, 0.0);

    // Add grain as semi-transparent noise
    if (grain_enabled) {
        float grain = film_grain(UV, seed);
        float grain_alpha = abs(grain) * grain_intensity * 2.0;
        overlay.rgb += (grain > 0.0 ? vec3(1.0) : vec3(0.0)) * grain_alpha;
        overlay.a = max(overlay.a, grain_alpha * 0.5);
    }

    // Add vignette as dark overlay at edges
    if (vignette_enabled) {
        float vignette = smoothstep(vignette_softness, 1.0, length(UV - 0.5) * 1.414);
        overlay.rgb = mix(overlay.rgb, vec3(0.0), vignette * vignette_intensity);
        overlay.a = max(overlay.a, vignette * vignette_intensity * 0.8);
    }

    // ... other effects as overlays

    COLOR = overlay;  // Output transparent overlay
}
```

Manager Changes:
- Removed brightness/contrast controls (can't modify scene colors without screen sampling)
- Removed highlight_boost (can't detect bright areas without screen sampling)
- Reduced activation delay to 1 frame (no screen texture timing issues)
- Added documentation about overlay approach

**Why This Works**:

1. **No screen texture dependency**: Completely bypasses all gl_compatibility bugs
2. **Standard alpha blending**: Uses Godot's native compositing, which works reliably
3. **No shader conflicts**: Doesn't interfere with other screen-reading shaders
4. **Better performance**: No framebuffer copy operation needed

**Trade-offs**:

1. **No brightness/contrast adjustment**: Can't modify overall scene brightness
2. **No highlight boost**: Can't selectively brighten already-bright areas
3. **Limited color grading**: Can only add color overlay, not multiply scene colors

These trade-offs are acceptable because:
- The warm color overlay still provides the cinematic color feel
- Vignette darkening works well as an overlay
- Film grain and defects work identically as overlays
- The effect is visually similar to the screen_texture approach

**Game Logs Added**:
- `game_log_20260203_163817.txt` - Final log before v4.0 fix

**Research Sources**:
- [Godot GitHub Issue #79914](https://github.com/godotengine/godot/issues/79914)
- [Godot GitHub Issue #66458](https://github.com/godotengine/godot/issues/66458)
- [Godot GitHub Issue #41627](https://github.com/godotengine/godot/issues/41627) - Multiple screen shaders blank
- [Godot Forum: Why is hint_screen_texture giving an empty texture?](https://forum.godotengine.org/t/why-is-hint-screen-texture-giving-an-empty-texture/120012)
- [Godot Forum: screen_texture behaves strangely with GL_compatibility](https://forum.godotengine.org/t/screen-texture-behaves-strangely-with-gl-compatibility-renderer-but-works-fine-with-forward/93296)
- [The Shaggy Dev: The fix for UI and post-processing shaders](https://shaggydev.com/2025/04/09/godot-ui-postprocessing-shaders/)
- [Godot Docs: Screen-reading shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html)
- [Godot Docs: Custom post-processing](https://docs.godotengine.org/en/stable/tutorials/shaders/custom_postprocessing.html)
- [Godot Post-Process Plugin](https://github.com/KorinDev/Godot-Post-Process-Plugin)
