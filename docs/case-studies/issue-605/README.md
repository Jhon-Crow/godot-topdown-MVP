# Case Study: Issue #605 - Flashbang Player Screen Effect

## Problem Statement

The flashbang grenade already affects enemies (blindness + stun) but has no effect
on the player when they are in the blast zone. The issue requests a CS:GO-like
flashbang screen effect on the player with:

- Dark purple as the main color (instead of white)
- Bordeaux/burgundy border (like the afterimage from staring at bright light)
- Duration: 1-5 seconds depending on distance from explosion
- Intensity: also varies by distance

## Research

### CS:GO Flashbang Mechanics

Sources:
- https://counterstrike.fandom.com/wiki/Flashbang
- https://hellraisers.gg/article/5543-how-cs-go-flashbang-works-all-you-need-to-know/

Key findings:
1. The effect covers the entire screen with a bright flash
2. Duration scales linearly with distance (closer = longer)
3. Intensity also scales with distance (closer = more opaque)
4. The effect fades out gradually over time
5. At close range: up to ~5 seconds of total effect
6. At maximum range: ~1 second of effect

### Godot 4 Implementation Patterns

Sources:
- https://docs.godotengine.org/en/stable/tutorials/shaders/custom_postprocessing.html
- https://godotshaders.com/shader/screen-damage-flash-square-gradient-hit-effect/
- https://godotshaders.com/shader/color-vignetting/

The codebase already uses the CanvasLayer + ColorRect + ShaderMaterial pattern in:
- `LastChanceEffectsManager` (layer 102) - blue sepia with ripple
- `CinemaEffectsManager` - cinema film grain effect
- `PenultimateHitEffectsManager` - penultimate hit visual effects

### Existing Architecture

The flashbang grenade system is well-structured:
1. `flashbang_grenade.gd` - handles explosion logic, enemy effects, line-of-sight
2. `StatusEffectsManager` - tracks per-entity status effects (blindness, stun)
3. `ImpactEffectsManager` - spawns visual flash effects (PointLight2D with shadows)
4. `AudioManager` - plays zone-aware explosion sounds

The `_is_player_in_zone()` method already:
- Finds the player in the scene
- Checks if player is within effect radius
- Verifies line of sight (walls block effects, Issue #469)

## Solution Design

### Architecture

Create a new autoload singleton `FlashbangPlayerEffectsManager` that:
1. Uses a CanvasLayer (layer 103) with a ColorRect + custom shader
2. Reads the screen texture and applies a dark purple tint with bordeaux vignette
3. Calculates effect duration and intensity based on distance
4. Animates the fade-out over time

### Shader Design

The shader (`flashbang_player.gdshader`) uses:
- `hint_screen_texture` with `filter_nearest` for `gl_compatibility` mode
- `textureLod` for screen sampling (same as existing shaders)
- Distance-based vignette for the bordeaux border effect
- Radial blur (8-sample multi-tap) for the "long exposure / motion blur" look
- Sinusoidal UV distortion for the "swimming in eyes" waviness effect
- Uniform parameters for runtime control: `intensity`, `blur_intensity`, `time_offset`, `flash_color`, `border_color`

### Integration Points

1. `flashbang_grenade.gd._on_explode()` calls the new manager
2. The manager calculates distance factor and applies the effect
3. `_process()` handles the fade-out animation
4. Scene change detection resets the effect

### Distance-Based Scaling

```
distance_factor = 1.0 - clamp(distance / effect_radius, 0.0, 1.0)
duration = MIN_DURATION + (MAX_DURATION - MIN_DURATION) * distance_factor  // 1-5 seconds
intensity = distance_factor  // 0.0 to 1.0
```

## Files Created/Modified

### New Files
- `scripts/shaders/flashbang_player.gdshader` - screen overlay shader
- `scripts/autoload/flashbang_player_effects_manager.gd` - autoload manager
- `tests/unit/test_flashbang_player_effect.gd` - unit tests

### Modified Files
- `scripts/projectiles/flashbang_grenade.gd` - trigger player effect
- `project.godot` - register new autoload
