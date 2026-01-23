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

5. **Investigation Round 2** (commit `1b38ffe`):
   - Found that `_log_info()` only wrote to FileLogger, not console
   - If FileLogger was null for any reason, NO logging occurred
   - Added always-print logging for diagnostics
   - Added diagnostic logging in enemy.gd to track ImpactEffectsManager lookups

6. **User Testing Round 3** (game_log_20260122_221039.txt):
   - User reported "не вижу изменений" (I don't see changes)
   - **CRITICAL FINDING**: Log shows `[ENEMY] WARNING: ImpactEffectsManager not found at /root/ImpactEffectsManager`
   - This means our enemy.gd diagnostic code IS running
   - But ImpactEffectsManager autoload is NOT being instantiated at all

7. **Investigation Round 3** (current):
   - Confirmed enemy.gd has our diagnostic changes (shows [ENEMY] warnings)
   - Confirmed ImpactEffectsManager._ready() is NEVER called (no [ImpactEffects] messages)
   - Comparing autoload initialization sequence:
     - `[SoundPropagation] autoload initialized` ✓ (autoload #7)
     - `[ImpactEffects] ImpactEffectsManager ready` ✗ MISSING (autoload #10)
     - `[PenultimateHit] ready` ✓ (autoload #11)
   - ImpactEffectsManager is specifically failing to load while others succeed

8. **Investigation Round 4** (commit `d157ef6`):
   - Created minimal ImpactEffectsManager test version
   - Temporarily replaced full script with minimal version that only loads essential scenes
   - Minimal version was deployed to test if autoload loading was the issue

9. **User Testing Round 5** (game_log_20260123_214856.txt, game_log_20260123_214912.txt):
   - User reported "спрайтов крови не видно" (blood sprites are not visible)
   - **CRITICAL FINDING**: Log shows `[INFO] [ImpactEffects] spawn_blood_effect called at (689.5863, 752.3096)`
   - This means the minimal ImpactEffectsManager IS LOADING and being called
   - BUT the minimal version has an INCOMPLETE `spawn_blood_effect()` function!
   - The function only logs but does NOT actually spawn blood effects or decals

10. **Investigation Round 5** (current):
    - Root cause identified: `project.godot` points to `minimal_impact_effects_manager.gd`
    - The minimal version was created for debugging but never reverted back to the full version
    - The minimal `spawn_blood_effect()` function only has logging, no actual effect spawning code
    - Fix: Changed `project.godot` to use `impact_effects_manager.gd` instead of `minimal_impact_effects_manager.gd`

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

1. **Minimal ImpactEffectsManager Left in Place** (CRITICAL - RESOLVED):
   - During Investigation Round 4, a minimal test version was created to debug autoload loading
   - `project.godot` was changed to point to `minimal_impact_effects_manager.gd`
   - **The minimal version was never reverted to the full version**
   - The minimal `spawn_blood_effect()` function only logs calls, it doesn't actually spawn effects:
     ```gdscript
     func spawn_blood_effect(position: Vector2, hit_direction: Vector2, caliber_data: Resource = null, is_lethal: bool = true) -> void:
         _log_info("spawn_blood_effect called at %s" % position)
         print("[ImpactEffectsManager] spawn_blood_effect called")
         # MISSING: actual blood effect spawning code!
     ```
   - Fix: Changed `project.godot` line 22 from:
     ```
     ImpactEffectsManager="*res://scripts/autoload/minimal_impact_effects_manager.gd"
     ```
     to:
     ```
     ImpactEffectsManager="*res://scripts/autoload/impact_effects_manager.gd"
     ```

2. **Previous Issue - ImpactEffectsManager Autoload Not Loading** (RESOLVED):
   - The original autoload was registered in `project.godot` at `*res://scripts/autoload/impact_effects_manager.gd`
   - But `get_node_or_null("/root/ImpactEffectsManager")` was returning `null`
   - Root cause was script compilation errors preventing the autoload from loading
   - Fixed by resolving type annotation issues in impact_effects_manager.gd

2. **Incorrect Wall Collision Layer** (Bug):
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

### 5. Added First-Line Diagnostic (Investigation Round 3)

```gdscript
func _ready() -> void:
    # CRITICAL: First line diagnostic - if this doesn't appear, script failed to load
    print("[ImpactEffectsManager] _ready() STARTING...")
    ...
```

### 6. Added Autoload List Diagnostic (Investigation Round 3)

```gdscript
# In enemy.gd when ImpactEffectsManager not found:
var root_node := get_node_or_null("/root")
if root_node:
    var autoload_names: Array = []
    for child in root_node.get_children():
        if child.name != get_tree().current_scene.name:
            autoload_names.append(child.name)
    _log_to_file("Available autoloads: " + ", ".join(autoload_names))
```

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
5. **Godot autoloads can fail silently** - always add first-line diagnostics
6. **When an autoload isn't found, list available autoloads** to help diagnose which are loading

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
- [Godot Issue #78230](https://github.com/godotengine/godot/issues/78230) - Autoload scripts compile error are not reported
- [Godot Issue #83119](https://github.com/godotengine/godot/issues/83119) - AutoLoad fails to load in an unintuitive way
- [Reddit Reference](https://www.reddit.com/r/godot/comments/ffvamw/made_a_blood_effect_using_render_textures_as_a/?tl=ru) - Blood effect using render textures

## User Logs

- `game_log_20260122_194241.txt` - First test, no [ImpactEffects] entries
- `game_log_20260122_201222.txt` - Second test, still no [ImpactEffects] entries
- `game_log_20260122_221039.txt` - Third test, [ENEMY] WARNING confirms autoload not found
- `game_log_20260123_003241.txt` - Fourth test, same issue persists (minimal version not tested yet)
- `game_log_20260123_214856.txt` - Fifth test, shows `spawn_blood_effect called` but no effects spawned (minimal version)
- `game_log_20260123_214912.txt` - Fifth test (continued), same behavior (minimal version)

## Root Cause Summary

### Investigation Round 6 (Final - 2026-01-23)

The blood effects were still not appearing after the full ImpactEffectsManager was restored. User reported "не вижу изменений" (I don't see changes) with a new game log showing:

```
[ENEMY] [Enemy3] WARNING: ImpactEffectsManager not found at /root/ImpactEffectsManager
Available autoloads: FileLogger, InputSettings, GameManager, ScoreManager, HitEffectsManager,
  AudioManager, SoundPropagation, ScreenShakeManager, DifficultyManager, PenultimateHitEffectsManager,
  LastChanceEffectsManager, StatusEffectsManager, GrenadeManager
```

**Root cause discovered**: The `ImpactEffectsManager` autoload was failing to load silently due to a GDScript compile error.

**The actual bug**: The code used `Particles2D` as a type, but **in Godot 4.x, the `Particles2D` class does not exist**! It was renamed to:
- `GPUParticles2D` - for GPU-based particles
- `CPUParticles2D` - for CPU-based particles

The error was hidden because Godot autoloads fail silently when there are script compilation errors (see [Godot Issue #78230](https://github.com/godotengine/godot/issues/78230)).

**Evidence from CI logs** (`ci-logs/build-windows-21296302716.log`):
```
SCRIPT ERROR: Parse Error: Could not find type "Particles2D" in the current scope.
SCRIPT ERROR: Parse Error: Could not find base class "Particles2D".
```

**Fix applied**:
1. Changed all `Particles2D` type references to `CPUParticles2D` in GDScript code
2. Changed effect scenes from `type="Particles2D"` to `type="CPUParticles2D"`
3. Updated `effect_cleanup.gd` from `extends Node` with cast to `extends CPUParticles2D`
4. Converted particle properties to CPUParticles2D format (different from ParticleProcessMaterial)

### Previous Issues (Now Resolved)

1. **Minimal ImpactEffectsManager left in place** - Fixed by restoring full version
2. **Incorrect wall collision layer** - Fixed by changing from 1 to 4 (obstacles bitmask)
3. **Silent autoload failure** - Now fixed by using correct class names

### Key Lessons

1. **Godot 4 class renames**: `Particles2D` → `GPUParticles2D`/`CPUParticles2D`
2. **Autoload silent failures**: Script compilation errors prevent autoloads from loading without clear error messages
3. **gl_compatibility mode**: `CPUParticles2D` is more reliable than `GPUParticles2D` in compatibility mode
4. **CI logs are critical**: The error was visible in CI build logs but not in the user's game logs

### Investigation Round 7 (2026-01-24)

After the Particles2D fix, user tested and reported new issues:
- "на стенах появляется гигантская капля крови" (Giant blood drops appear on walls)
- "на полу не появляется" (Floor blood doesn't appear)
- "старые эффекты крови (от попадания) исчезли" (Old hit blood effects disappeared)

**Log analysis** showed that blood effects WERE being spawned in code:
- `Blood particle effect instantiated successfully`
- `Blood decal instantiated successfully`
- `Blood decal spawned at (x, y) (total: N)`

**Root cause identified** - z_index rendering issues:

1. **Floor blood decals not visible**:
   - `BloodDecal.tscn` had `z_index = -1`
   - Floor (`ColorRect`) has default `z_index = 0`
   - Blood decals were being rendered BEHIND the floor!
   - **Fix**: Changed `BloodDecal.tscn` z_index from -1 to 1

2. **BloodEffect particles potentially hidden**:
   - `BloodEffect.tscn` had no explicit z_index (defaults to 0)
   - Same z_index as floor, might not always be visible
   - **Fix**: Added `z_index = 2` to BloodEffect

3. **Wall blood splatters too large**:
   - Scale calculation: `intensity * distance_factor * randf_range(0.4, 0.8)`
   - With intensity=1.5 and high distance_factor, scale could reach ~1.5
   - 32x32 texture at scale 1.5 = ~50px - visually "giant"
   - **Fix**: Reduced scale range from `0.4-0.8` to `0.15-0.35`
   - Also reduced multipliers: lethal from 1.3 to 1.2, non-lethal from 0.6 to 0.5

**z_index hierarchy after fix**:
- Floor (ColorRect): z_index = 0 (default)
- Blood decals: z_index = 1 (visible above floor)
- Characters/Enemies: z_index = 1+
- BloodEffect particles: z_index = 2 (visible above floor and decals)
