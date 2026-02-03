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

## Implementation Notes

### Performance Considerations
- Shader warmup on startup to prevent first-frame stutter (Issue #343 pattern)
- Modulo-based noise function (efficient, no texture lookups)
- Single pass shader combining all effects
- Film defects use probability-based triggering to minimize calculations

### Compatibility
- Uses `canvas_item` shader type (2D compatible)
- Uses `hint_screen_texture` for screen sampling
- Works with GL Compatibility rendering mode

### Key Technical Decisions

1. **Modulo-based noise over sine-based**: Eliminates visible wave patterns
2. **Frame-quantized time**: Prevents smooth transitions that can look like waves
3. **Multiplicative warm tint**: Preserves more color detail than luminance-based
4. **Probability-based defects**: Realistic rare occurrence, minimal performance impact
5. **Hash function for randomness**: High-quality pseudo-random without patterns
