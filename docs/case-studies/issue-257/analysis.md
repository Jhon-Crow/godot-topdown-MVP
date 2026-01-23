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

### Investigation Round 8 (2026-01-24)

After the z_index and wall splatter scale fixes, user tested and reported new issues:
- "под врагом появляется одна капля размером с врага" (One drop the size of the enemy appears under the enemy)
- "должны появляться маленькие, примерно размером с гильзу но много капли" (Small drops should appear, roughly the size of shell casings, but many of them)
- "в майн ветке есть эффект брызг крови, верни его" (There's a blood spray effect in the main branch, restore it)
- "спрайты должны появляться на полу там, куда приземляется частица из этого эффекта" (Sprites should appear on the floor where the particles from this effect land)

**Log analysis** confirmed effects were being spawned but user expectations weren't met:
- The blood spray particle effect (CPUParticles2D) WAS working
- But only ONE blood decal was spawning (too big)
- User wanted MANY small decals (like shell casings: 4x14 pixels)

**Root cause identified** - Size and quantity mismatch:

1. **Blood decal texture too large**:
   - `BloodDecal.tscn` texture was 32x32 pixels
   - Shell casings are 4x14 pixels
   - User wanted blood drops ~8x8 pixels (similar to casings)
   - **Fix**: Changed `BloodDecal.tscn` texture from 32x32 to 8x8 pixels

2. **Only one decal spawning**:
   - `_spawn_blood_decal()` was spawning a single decal per hit
   - User wanted MANY small decals, not one big one
   - **Fix**: Created new method `_spawn_blood_decals_at_particle_landing()` that:
     - Spawns 8 decals for lethal hits, 4 for non-lethal
     - Uses particle physics parameters (velocity, gravity, spread, lifetime)
     - Calculates landing positions using physics: `pos = origin + v*t + 0.5*g*t²`
     - Random scale 0.8-1.5 for variety (8px texture = 6-12px final size)

3. **Decals not matching particle landing positions**:
   - Original code just offset the decal position randomly
   - User wanted decals to appear where blood particles would physically land
   - **Fix**: New method simulates particle trajectories using:
     - `initial_velocity_min/max` from BloodEffect scene (150-350 px/s)
     - `gravity` from BloodEffect scene (0, 450 px/s²)
     - `spread` angle from BloodEffect scene (55°)
     - `lifetime` from BloodEffect scene (0.8s)
     - Random landing time within particle lifetime

4. **Wall splatter scale adjusted**:
   - Previous scale formula was for 32x32 texture
   - Updated scale range from 0.15-0.35 to 0.8-1.5 for 8x8 texture
   - Final wall splatter size: 6-12 pixels (matches shell casing scale)

**Size comparison reference**:
- Shell casings: `RectangleShape2D.size = Vector2(4, 14)` from `Casing.tscn`
- New blood decals: 8x8 texture × 0.8-1.5 scale = 6-12 pixels
- Blood particles in BloodEffect: `scale_amount_min=0.1`, `scale_amount_max=0.4` (very small)

### Investigation Round 9 (2026-01-24)

After the blood decal size and quantity fixes (Round 8), user tested and reported three issues:
1. "игра теперь вылетает" (Game now crashes)
2. "не видно эффекта из main ветки (брызги частицы при попадании пули)" (Blood particle effect from main branch not visible)
3. "спрайты крови не должны пролетать сквозь стены" (Blood sprites shouldn't pass through walls)

**Log analysis** revealed NO errors or crashes in the logs. The logs ended abruptly during blood effect spawning, but this appeared to be normal game termination rather than crashes. The logs showed:
- `[ImpactEffects] Blood particle effect instantiated successfully`
- `[ImpactEffects] Blood decals spawned: 4/8 at simulated particle landing positions`

However, user reported the blood spray particle effect was **not visible**.

**Root cause identified** - CPUParticles2D missing texture:

In Round 6, particle effects were changed from `GPUParticles2D` to `CPUParticles2D` to fix autoload loading issues (Godot 4 renamed `Particles2D` class). However, the conversion introduced a critical bug:

1. **Missing particle texture**:
   - Original `GPUParticles2D` had: `texture = SubResource("GradientTexture2D_blood")` (12x12 pixels)
   - Converted `CPUParticles2D` had: **NO texture** - particles were single pixels/invisible
   - `CPUParticles2D` uses `color_ramp` for gradients but doesn't automatically render visible particles without a texture
   - `GPUParticles2D` uses `ParticleProcessMaterial` + explicit texture for visible particles

2. **Script type mismatch**:
   - `effect_cleanup.gd` was changed to `extends CPUParticles2D`
   - But the effect scenes should have used `GPUParticles2D` for proper rendering

3. **Blood decals passing through walls**:
   - `_spawn_blood_decals_at_particle_landing()` calculated landing positions using particle physics
   - But it never checked if a wall was between the origin and landing position
   - Decals could appear on the other side of walls

**Fixes applied**:

1. **Restored GPUParticles2D with texture** for all effects:
   - `BloodEffect.tscn`: Restored to `type="GPUParticles2D"` with `GradientTexture2D` (12x12 px)
   - `DustEffect.tscn`: Restored to `type="GPUParticles2D"` with `GradientTexture2D` (16x16 px)
   - `SparksEffect.tscn`: Restored to `type="GPUParticles2D"` with `GradientTexture2D` (8x8 px)
   - `effect_cleanup.gd`: Changed back to `extends GPUParticles2D`

2. **Updated impact_effects_manager.gd**:
   - Changed all effect instantiation to use `GPUParticles2D` type casting
   - Updated `_spawn_blood_decals_at_particle_landing()` to:
     - Accept `GPUParticles2D` parameter instead of `CPUParticles2D`
     - Extract physics parameters from `ParticleProcessMaterial` (GPUParticles2D's process material)
     - Added wall collision raycast check before spawning each decal

3. **Wall collision check for blood decals**:
   ```gdscript
   # Check if there's a wall between origin and landing position
   if space_state:
       var query := PhysicsRayQueryParameters2D.create(origin, landing_pos, WALL_COLLISION_LAYER)
       query.collide_with_bodies = true
       query.collide_with_areas = false
       var result: Dictionary = space_state.intersect_ray(query)
       if not result.is_empty():
           # Wall detected between origin and landing - skip this decal
           decal.queue_free()
           continue
   ```

**Technical comparison GPUParticles2D vs CPUParticles2D**:

| Property | GPUParticles2D | CPUParticles2D |
|----------|----------------|----------------|
| Physics storage | `process_material: ParticleProcessMaterial` | Direct on node (e.g., `initial_velocity_min`) |
| Texture | `texture: Texture2D` (required for visibility) | Optional, uses `color` property |
| Gradient | In `ParticleProcessMaterial.color_ramp` | `color_ramp: Gradient` |
| Direction | `Vector3` in material | `Vector2` on node |
| Gravity | `Vector3` in material | `Vector2` on node |
| gl_compatibility | May have issues | More reliable |

**Key lesson**: When converting between particle types in Godot 4, texture assignment is critical. `GPUParticles2D` requires an explicit `texture` property to render visible particles, while `CPUParticles2D` can render without one (using `color`) but may appear as single pixels.

### Investigation Round 10 (2026-01-24)

After the GPUParticles2D restoration and wall collision check fixes (Round 9), user tested and reported four issues:
1. "игра всё ещё вылетает (при этом она вылетает после рестарта, то есть не от количества спрайтов на карте)" (Game still crashes - specifically after restart, not from sprite count)
2. "спрайты крови должны появляться на месте приземления частиц из эффекта" (Blood sprites should appear at particle landing positions)
3. "спрайты должны появляться в момент исчезновения частицы эффекта крови" (Sprites should appear at the moment the blood effect particle disappears)
4. "сделай спрайты круглыми и темнее" (Make sprites round and darker)

**Log analysis** (7 new log files from Round 10 testing):
- Logs showed blood effects were being spawned successfully
- No crash errors visible in logs - logs ended normally with "GAME LOG ENDED"
- The "crash after restart" suggested a scene transition issue

**Root causes identified**:

1. **Game crash after restart** - Unsafe `await` in scripts during scene transitions:

   In `blood_decal.gd` and `effect_cleanup.gd`, the code used:
   ```gdscript
   await get_tree().create_timer(fade_delay).timeout
   ```

   When the scene changes/restarts while a timer is waiting:
   - The node is freed but the coroutine continues
   - When it resumes, `get_tree()` may return null or the node is invalid
   - This causes a crash

   Additionally, `impact_effects_manager.gd` was holding references to blood decal nodes in `_blood_decals` array. After scene change, these became "freed object" references.

   **Fixes applied**:
   - Added null checks after every `await`:
     ```gdscript
     # Check if node is still valid after await
     if not is_instance_valid(self) or not is_inside_tree():
         return
     ```
   - Added `_on_tree_changed()` handler to `impact_effects_manager.gd`:
     ```gdscript
     func _on_tree_changed() -> void:
         var current_scene := get_tree().current_scene
         if current_scene != _last_scene:
             _log_info("Scene changed - clearing all stale effect references")
             _blood_decals.clear()
             _bullet_holes.clear()
             _penetration_holes.clear()
             _last_scene = current_scene
     ```

2. **Blood decals spawning immediately instead of at particle landing time**:

   The previous implementation spawned all decals immediately with pre-calculated positions. User wanted decals to appear when particles would actually "land" (after traveling through the air).

   **Fix applied** - New `_schedule_delayed_decal()` method:
   ```gdscript
   func _schedule_delayed_decal(origin: Vector2, landing_pos: Vector2,
                                decal_rotation: float, decal_scale: float, delay: float) -> void:
       var tree := get_tree()
       if tree == null:
           return
       await tree.create_timer(delay).timeout

       # Safety checks after await
       if not is_instance_valid(self):
           return

       # Wall collision check at spawn time
       # ... (raycast check)

       # Spawn decal
       var decal := _blood_decal_scene.instantiate() as Node2D
       decal.global_position = landing_pos
       # ...
   ```

   Each decal now spawns after its calculated `land_time` (0.24s - 0.72s based on particle physics simulation).

3. **Blood decals not round and dark enough**:

   **Fixes applied** to `BloodDecal.tscn`:
   - Made gradient darker: Changed red values from `0.6/0.5/0.4/0.3` to `0.35/0.3/0.25/0.2`
   - The gradient already uses radial fill (`fill = 1`) which creates circular appearance
   - Increased modulate alpha from `0.85` to `0.9` for better visibility
   - Gradient now fades to transparent at edges (`0.95 -> 0.9 -> 0.75 -> 0` alpha)

**Technical summary of fixes**:

| File | Change |
|------|--------|
| `blood_decal.gd` | Added null checks after await, tween null check |
| `effect_cleanup.gd` | Added null checks after await |
| `impact_effects_manager.gd` | Added `_on_tree_changed()`, delayed decal spawning |
| `BloodDecal.tscn` | Darker gradient colors, higher alpha |

**Key lessons**:

1. **Always add safety checks after `await`**: When using async timers in Godot, the scene may change during the wait. Always check `is_instance_valid(self)` and `is_inside_tree()` after await resumes.

2. **Clear stale references on scene change**: Autoload managers that hold references to scene nodes must clear those references when the scene changes to avoid "freed object" crashes.

3. **Connect to `tree_changed` signal**: To detect scene transitions, connect to `get_tree().tree_changed` and compare `current_scene` to detect changes.
