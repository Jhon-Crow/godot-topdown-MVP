# Case Study: Issue #257 - Blood Splatters Not Appearing

## Issue Description

When bullets hit enemies (not hitting armor/when non-lethal hit sound plays), blood splatter effects should appear on the floor and walls near the hit location, with position depending on the bullet angle.

Reference: [Reddit blood effect demo](https://www.reddit.com/r/godot/comments/ffvamw/made_a_blood_effect_using_render_textures_as_a/?tl=ru)

## Timeline of Events

1. **Initial Implementation** (commit `f7e837e`): Added blood splatters on floor and walls
   - Modified `spawn_blood_effect()` to always spawn floor decals (not just lethal hits)
   - Added `_spawn_wall_blood_splatter()` method for wall detection
   - Added constants: `WALL_SPLATTER_CHECK_DISTANCE` (100px) and `WALL_COLLISION_LAYER` (1)

2. **User Testing Round 1**: User reported "не добавилось" (nothing was added) with game log file

3. **Bug Fix** (commit `217efa2`): Fixed WALL_COLLISION_LAYER from 1 to 4

4. **User Testing Round 2**: User reported "не вижу изменений" (I don't see changes) with second game log file
   - Log analysis revealed NO `[ImpactEffects]` entries at all
   - This indicated either the autoload wasn't loading or the logging wasn't working

5. **Investigation Round 2** (current):
   - Found that `_log_info()` only wrote to FileLogger, not console
   - If FileLogger was null for any reason, NO logging occurred
   - Added always-print logging for diagnostics
   - Added diagnostic logging in enemy.gd to track ImpactEffectsManager lookups

## Root Cause Analysis

### Investigation Process

1. **Log Analysis**: The game log (`game_log_20260122_194241.txt`) showed:
   - Enemies receiving hits: `[ENEMY] [Enemy3] Hit taken, health: 3/4`
   - No blood/decal/splatter related log entries
   - No error messages about ImpactEffectsManager

2. **Code Flow Tracing**:
   - Bullet hits `HitArea` (Area2D) → calls `on_hit_with_bullet_info()`
   - `HitArea` script forwards to parent Enemy
   - Enemy's `on_hit_with_bullet_info()` calls `ImpactEffectsManager.spawn_blood_effect()`
   - ImpactEffectsManager spawns blood particle effect and floor decal

3. **Key Finding**: The `ImpactEffectsManager` has `_debug_effects = false`, so no logging was output. This made it impossible to see if the function was being called.

### Issues Identified

1. **Incorrect Wall Collision Layer** (Bug):
   - `WALL_COLLISION_LAYER` was set to `1` (player layer)
   - Should be `4` (bitmask for layer 3 = obstacles)
   - Layer mapping from project.godot:
     - Layer 1 = player (bitmask 1)
     - Layer 2 = enemies (bitmask 2)
     - Layer 3 = obstacles (bitmask 4)
     - Layer 4 = pickups (bitmask 8)
     - Layer 5 = projectiles (bitmask 16)
     - Layer 6 = targets (bitmask 32)

2. **No Diagnostic Logging** (Issue):
   - ImpactEffectsManager didn't log to FileLogger
   - Made it impossible to diagnose issues from game logs
   - Debug mode was off by default

3. **Potential Rendering Issue** (Consideration):
   - Project uses `gl_compatibility` rendering mode
   - Known issues with GPUParticles2D in compatibility mode
   - However, blood decals use Sprite2D (should work regardless)

## Solutions Implemented

### 1. Fixed Wall Collision Layer

```gdscript
# Before (incorrect):
const WALL_COLLISION_LAYER: int = 1

# After (correct):
const WALL_COLLISION_LAYER: int = 4
```

### 2. Added FileLogger Integration with Always-Print Logging

```gdscript
var _file_logger: Node = null

func _ready() -> void:
    _file_logger = get_node_or_null("/root/FileLogger")
    if _file_logger == null:
        print("[ImpactEffectsManager] WARNING: FileLogger not found at /root/FileLogger")
    _preload_effect_scenes()
    _log_info("ImpactEffectsManager ready - scenes loaded")

func _log_info(message: String) -> void:
    var log_message := "[ImpactEffects] " + message
    # Always print to console for debugging exported builds
    print(log_message)
    # Also write to file logger if available
    if _file_logger and _file_logger.has_method("log_info"):
        _file_logger.log_info(log_message)
```

### 3. Added Diagnostic Logging in Enemy Hit Handler

```gdscript
# In enemy.gd on_hit_with_bullet_info():
var impact_manager: Node = get_node_or_null("/root/ImpactEffectsManager")

# Log blood effect call for diagnostics
if impact_manager:
    _log_to_file("ImpactEffectsManager found, calling spawn_blood_effect")
else:
    _log_to_file("WARNING: ImpactEffectsManager not found at /root/ImpactEffectsManager")
```

### 4. Added Diagnostic Logging

- Log when scenes are loaded/missing
- Log when `spawn_blood_effect()` is called
- Log when blood decals are spawned
- Log when wall splatters are found
- Log when ImpactEffectsManager is (or isn't) found by enemy.gd

## Verification

### Expected Log Output After Fix

When a bullet hits an enemy, the log should now show:
```
[ImpactEffects] ImpactEffectsManager ready - scenes loaded
[ImpactEffects] Scenes loaded: DustEffect, BloodEffect, SparksEffect, BloodDecal
[ENEMY] [Enemy3] ImpactEffectsManager found, calling spawn_blood_effect
[ImpactEffects] spawn_blood_effect at (300, 350), dir=(0.707, 0.707), lethal=false
[ImpactEffects] Blood decal spawned at (320, 370) (total: 1)
[ImpactEffects] Blood effect spawned at (300, 350) (scale=1.0)
```

If ImpactEffectsManager is not loading, you would see:
```
[ENEMY] [Enemy3] WARNING: ImpactEffectsManager not found at /root/ImpactEffectsManager
```

### Important Note for Users

**You must re-export the game after merging these changes.** If you're running an old exported build, the changes won't take effect. Steps:
1. Pull/merge the latest changes from the PR branch
2. Open the project in Godot Editor
3. Export the game (Project → Export → your platform)
4. Run the new exported build
5. Check the game log for the new diagnostic messages

### Test Cases

1. Unit test added: `test_wall_collision_layer_is_correct_bitmask()`
2. Existing tests verify method existence and parameter handling

## Lessons Learned

1. **Always validate collision layer constants** against project settings
2. **Add diagnostic logging** for autoload managers to aid debugging
3. **Use FileLogger** for persistent logging visible in game log files
4. **Document layer mappings** in comments near collision layer constants

## Related Files

- `scripts/autoload/impact_effects_manager.gd` - Main effect manager
- `scripts/objects/enemy.gd` - Enemy hit handling
- `scripts/objects/hit_area.gd` - Hit detection forwarding
- `scripts/projectiles/bullet.gd` - Bullet collision handling
- `scenes/effects/BloodDecal.tscn` - Blood decal scene
- `scenes/effects/BloodEffect.tscn` - Blood particle effect scene
- `project.godot` - Physics layer definitions

## References

- [Godot Issue #84072](https://github.com/godotengine/godot/issues/84072) - GPU Particles in compatibility mode
- [Godot Issue #85945](https://github.com/godotengine/godot/issues/85945) - GPUParticles2D not rendering in compatibility mode
- [Reddit Reference](https://www.reddit.com/r/godot/comments/ffvamw/made_a_blood_effect_using_render_textures_as_a/?tl=ru) - Blood effect using render textures
