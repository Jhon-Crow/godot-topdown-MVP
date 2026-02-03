# Case Study: Cinema Film Effect Implementation (Issue #418)

## Problem Statement

The request is to add a "cinema film effect" to all images in the game, specifically:
- **Film grain** (зернистость) - Adding noise/grain texture typical of old film
- **Warm colors** (теплота цветов) - Color grading toward warm/sepia tones

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

#### Option 1: Simple Sine-Based Noise (Selected Approach)
Source: [Godot Shaders - Film Grain](https://godotshaders.com/shader/film-grain-shader/)

```glsl
float noise = (fract(sin(dot(UV, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) * 2.0;
```

**Pros**: Simple, efficient, no external textures needed
**Cons**: Noise pattern may repeat

#### Option 2: Perlin Noise Based
Source: [Godot Film Grain Shader by kondelik](https://github.com/kondelik/Godot_Film_Grain_Shader)

Uses 3D Perlin noise with time-based animation for more organic grain.

**Pros**: More realistic film grain
**Cons**: More complex, higher performance cost

#### Option 3: Darkness-Weighted Film Grain
Source: [Godot Shaders - Darkness-Weighted](https://godotshaders.com/shader/darkness-weighted-film-grain-effect/)

Applies grain more strongly to darker areas (more realistic).

**Pros**: Mimics real film behavior
**Cons**: More complex calculations

### Warm Color Grading Approaches

#### Option 1: Sepia Tint via Luminance (Selected Approach)
Already implemented in `last_chance.gdshader`:
```glsl
float luminance = dot(screen_color.rgb, vec3(0.299, 0.587, 0.114));
vec3 sepia = luminance * sepia_color;
vec3 tinted = mix(screen_color.rgb, sepia, sepia_intensity);
```

#### Option 2: Color Temperature Shift
Shifts RGB balance toward warm (red/yellow) or cool (blue) tones.

#### Option 3: LUT-Based Color Grading
Uses lookup textures for precise color mapping.
Source: [Godot 4 Color Correction](https://github.com/ArseniyMirniy/Godot-4-Color-Correction-and-Screen-Effects)

## Proposed Solution

### Architecture

Following the existing project patterns, implement:

1. **Shader**: `scripts/shaders/cinema_film.gdshader`
   - Combined film grain + warm color tint
   - Configurable parameters for intensity

2. **Manager**: `scripts/autoload/cinema_effects_manager.gd`
   - Creates CanvasLayer/ColorRect overlay
   - Manages shader parameters
   - Provides API for toggling effect

3. **Configuration**: Update `project.godot`
   - Register autoload for global availability

### Shader Design

```glsl
shader_type canvas_item;

// Film grain parameters
uniform float grain_intensity : hint_range(0.0, 0.5) = 0.05;
uniform float grain_speed : hint_range(0.0, 100.0) = 15.0;

// Warm color tint parameters
uniform vec3 warm_color : source_color = vec3(1.0, 0.9, 0.7);
uniform float warm_intensity : hint_range(0.0, 1.0) = 0.2;

// Effect toggles
uniform bool grain_enabled = true;
uniform bool warm_enabled = true;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
```

### Key Features

1. **Time-animated grain**: Uses TIME built-in for continuously changing noise
2. **Configurable warm tint**: Default subtle warm shift (1.0, 0.9, 0.7)
3. **Toggle controls**: Can enable/disable grain and warm independently
4. **Follows project conventions**: Consistent with existing effect managers

## References

### External Resources
- [Godot Film Grain Shader](https://godotshaders.com/shader/film-grain-shader/) - CC0 License
- [Godot Film Grain Shader Repository](https://github.com/kondelik/Godot_Film_Grain_Shader) - CC-BY 3.0
- [Godot 4 Color Correction](https://github.com/ArseniyMirniy/Godot-4-Color-Correction-and-Screen-Effects) - MIT License
- [Custom Post-Processing - Godot Docs](https://docs.godotengine.org/en/stable/tutorials/shaders/custom_postprocessing.html)
- [Film Grain Proposal for Godot](https://github.com/godotengine/godot-proposals/issues/1684)

### Internal References
- `scripts/shaders/saturation.gdshader` - Simple post-processing example
- `scripts/shaders/last_chance.gdshader` - Complex effect with sepia tint
- `scripts/autoload/hit_effects_manager.gd` - Manager pattern reference

## Implementation Notes

### Performance Considerations
- Shader warmup on startup to prevent first-frame stutter (Issue #343 pattern)
- Simple noise function chosen over Perlin for performance
- Single pass shader combining both effects

### Compatibility
- Uses `canvas_item` shader type (2D compatible)
- Uses `hint_screen_texture` for screen sampling
- Works with GL Compatibility rendering mode
