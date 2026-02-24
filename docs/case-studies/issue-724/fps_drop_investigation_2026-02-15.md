# FPS Drop Investigation - Phase 2 (2026-02-15)

## Problem Statement

User reported FPS drops still occurring with:
- F-1 (frag) grenade explosions
- Shotgun with breaker bullets (14 pellets per shot)

The previous fix (disabling shadows on PointLight2D) was not sufficient.

## Analysis

### Game Log Analysis

Downloaded and analyzed `game_log_20260214_163442.txt`:

```
Total explosions during session: 221
Peak explosions per second:
  - 21 explosions at 16:35:06
  - 16 explosions at 16:35:03
  - 15 explosions at 16:35:32
  - 13 explosions at 16:35:21
```

The shotgun with breaker bullets fires 14 pellets, each creating a PointLight2D when it detonates. Multiple shots in quick succession can create 20+ lights simultaneously.

### Root Cause

Even with `shadow_enabled = false`, creating multiple PointLight2D objects causes FPS drops:

1. **Node Creation Overhead**: Each `PointLight2D.new()` call allocates memory and initializes GPU resources
2. **Scene Tree Operations**: Adding 12+ nodes to the scene tree in a single frame is expensive
3. **Tween Creation**: Each light creates a new Tween for fade-out animation
4. **GPU Draw Calls**: Each visible PointLight2D adds draw calls regardless of shadow state

### Research Sources

- [Godot Issue #4151: Improve 2D lights performance](https://github.com/godotengine/godot/issues/4151)
- [Godot Issue #79831: Light2D consumes too much CPU](https://github.com/godotengine/godot/issues/79831)
- [Godot Forum: Light2D and Particles2D causes FPS drop](https://forum.godotengine.org/t/light2d-and-particles2d-causes-incredibly-fps-drop/11508)

Community reports indicate 5-10 simultaneous PointLight2D objects can cause noticeable performance impact, even without shadows.

## Solution Implemented

### Phase 2 Optimization: PointLight2D Object Pooling

Instead of creating and destroying PointLight2D objects for each explosion, we now:

1. **Pre-create a Pool**: 12 PointLight2D objects are created at startup and stored in a pool
2. **Reuse Lights**: When an explosion needs a light, it retrieves one from the pool
3. **Return to Pool**: After fade-out, lights return to the pool instead of being freed
4. **Limit Concurrent Lights**: Maximum 8 active lights allowed; beyond this, new explosions skip the light effect

### Implementation Details

```gdscript
# Pool configuration
const MAX_CONCURRENT_EXPLOSION_LIGHTS: int = 8
const EXPLOSION_LIGHT_POOL_SIZE: int = 12

# Pool arrays
var _explosion_light_pool: Array[PointLight2D] = []
var _active_explosion_lights: Array[PointLight2D] = []
```

### Changes Made

- **`scripts/autoload/impact_effects_manager.gd`**:
  - Added explosion light pool (pre-created PointLight2D objects)
  - Added pool management functions (`_init_explosion_light_pool`, `_get_explosion_light_from_pool`, `_return_explosion_light_to_pool`)
  - Modified `_spawn_grenade_visual_effect` to check concurrent light limit
  - Modified `_create_grenade_light_with_occlusion` to use pooled lights

## Performance Impact

| Scenario | Before | After |
|----------|--------|-------|
| Shotgun breaker (14 pellets) | 14 new PointLight2D created | Up to 8 pooled lights reused |
| Multiple shots in 1 second | 20+ lights created | 8 lights max, rest skipped |
| Memory allocation | Per explosion | One-time at startup |
| Tween creation | Per explosion | Per explosion (no change) |

## Verification

The fix should be tested by:
1. Firing shotgun with breaker bullets rapidly at walls
2. Throwing F-1 grenades
3. Monitoring FPS during these actions

Expected result: No noticeable FPS drops, maximum 8 explosion lights visible at any time.

## Summary

The FPS drops were caused by creating too many PointLight2D objects simultaneously, not just by shadow rendering. The solution pools and limits concurrent lights to prevent performance degradation while maintaining acceptable visual quality.
