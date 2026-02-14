# FPS Drop Investigation Report - February 14, 2026

## Issue Summary

User reported FPS drops when:
1. Shooting from shotgun with breaker bullets
2. F-1 (frag) grenade explosion

Despite object pooling being implemented, the FPS drops still occur.

## Investigation Methodology

1. Downloaded user-provided game log: `game_log_20260214_112401.txt` (12,057 lines)
2. Analyzed log patterns for explosion spawning frequency
3. Reviewed source code for performance bottlenecks
4. Searched online for Godot 4 PointLight2D shadow optimization

## Root Cause Analysis

### Primary Bottleneck: Shadow-Enabled PointLight2D per Explosion

**Location:** `scripts/autoload/impact_effects_manager.gd`, function `_create_grenade_light_with_occlusion()` (lines 1071-1104)

**Problem:** Every explosion visual effect creates:
1. A new `PointLight2D` node
2. With `shadow_enabled = true`
3. A new `GradientTexture2D` via `_create_light_texture()` (never cached)

**Why this is expensive:**

According to [Godot documentation](https://docs.godotengine.org/en/stable/tutorials/2d/2d_lights_and_shadows.html) and [community research](https://github.com/godotengine/godot/pull/100302):

> Rendering PointLight2D shadows creates 4 draw lists per light on screen and `4 × lights_on_screen × occluders_on_screen` draw calls. Each draw call comes with 4 other API calls.

For shotgun with breaker bullets:
- 14 pellets per shot
- Each pellet creates 1 explosion with shadow-enabled PointLight2D
- **14 shadow lights spawned in a single frame = 56+ draw lists + hundreds of draw calls**

### Secondary Bottleneck: Texture Recreation

The `_create_light_texture()` function creates a new `GradientTexture2D` for **every explosion**:

```gdscript
func _create_light_texture() -> GradientTexture2D:
    var gradient := Gradient.new()
    gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
    gradient.offsets = PackedFloat32Array([0.0, 1.0])

    var texture := GradientTexture2D.new()
    texture.gradient = gradient
    # ... creates new texture every call
```

This causes GPU texture uploads per explosion instead of reusing a cached texture.

### Log Evidence

From the game log, shotgun breaker explosions spawn rapidly:

```
[11:24:09] [INFO] [Shotgun.FIX#212] Firing 14 pellets with 15° spread
[11:24:09] [INFO] [ImpactEffects] Spawning explosion visual effect at (290.3923, 1005.102) (radius=15)
[11:24:09] [INFO] [ImpactEffects] Spawning explosion visual effect at (295.4845, 1005.888) (radius=15)
[11:24:09] [INFO] [ImpactEffects] Spawning explosion visual effect at (297.5, 1010.292) (radius=15)
... (14 total explosions in rapid succession)
```

## Solution

### Fix 1: Disable shadows for explosion effects (High Impact)

Explosion effects are brief visual flashes (0.3-0.4 seconds) and don't need accurate shadow casting. Disabling shadows eliminates the main performance bottleneck.

**Before:**
```gdscript
light.shadow_enabled = true  # Expensive!
```

**After:**
```gdscript
light.shadow_enabled = false  # Fast!
```

### Fix 2: Cache the light texture (Medium Impact)

Create the gradient texture once and reuse it:

```gdscript
var _cached_light_texture: GradientTexture2D = null

func _get_light_texture() -> GradientTexture2D:
    if _cached_light_texture == null:
        _cached_light_texture = _create_light_texture()
    return _cached_light_texture
```

### Fix 3: Add explosion light pooling (Future Enhancement)

For even better performance, pool the PointLight2D nodes and reuse them:

```gdscript
var _explosion_light_pool: Array[PointLight2D] = []
const EXPLOSION_LIGHT_POOL_SIZE: int = 20
```

## Performance Impact

| Scenario | Before Fix | After Fix |
|----------|------------|-----------|
| Shotgun breaker (14 pellets) | ~14 shadow lights = 56+ draw lists | 14 non-shadow lights = minimal overhead |
| F-1 grenade | 1 shadow light + 4 shrapnel | 1 non-shadow light + 4 pooled shrapnel |
| Texture uploads | 14+ per shotgun shot | 0 (cached) |

## References

- [Godot 2D Lights and Shadows Documentation](https://docs.godotengine.org/en/stable/tutorials/2d/2d_lights_and_shadows.html)
- [Optimize PointLight2D shadow rendering - Godot PR #100302](https://github.com/godotengine/godot/pull/100302)
- [Improve 2D lights performance - Issue #4151](https://github.com/godotengine/godot/issues/4151)
