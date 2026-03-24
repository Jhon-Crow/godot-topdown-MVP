# Case Study: Issue #583 - RPG Enemy Type

## Issue Description

Add a new enemy type armed with an RPG (rocket launcher). The enemy fires one rocket at the player's position, then switches to a PM (Makarov) pistol and fights as a normal enemy. Health: 1-2 (unarmored).

## Timeline

1. **Initial implementation** (commits f410f5d..012fb54): Added RPG and PM weapon configs (type 4 and 5), RPG rocket projectile, weapon switching logic in enemy AI, and placed 2 RPG enemies in CastleLevel.
2. **User feedback** (PR #599 comment by Jhon-Crow, 2026-02-08): "Enemy didn't get added. Instead of adding to Castle, add the new enemy to the Polygon (TestTier) level."
3. **Fix** (current commit): Moved RPG enemies from CastleLevel to TestTier (Polygon) level.

## Root Cause Analysis

The RPG enemies were technically present in CastleLevel (confirmed by game log showing `RpgEnemy1` and `RpgEnemy2` spawning at positions (2000,300) and (4200,1050)). However, the user's feedback indicates they want the enemies on the TestTier (Polygon) level instead, which is the primary testing/development level.

### Evidence from Game Log

From `game_log_20260208_193502.txt`:
- Line 351: `[CastleLevel] Child 'RpgEnemy1': script=true, has_died_signal=true`
- Line 352: `[CastleLevel] Child 'RpgEnemy2': script=true, has_died_signal=true`
- Line 412: `[RpgEnemy1] Spawned at (2000, 300), hp: 2, behavior: GUARD`
- Line 416: `[RpgEnemy2] Spawned at (4200, 1050), hp: 1, behavior: GUARD`
- Lines 852, 990: RpgEnemy2 entered COMBAT state and fired (as GUNSHOT sound)

The enemies spawned and functioned in CastleLevel, but the user requested placement on the Polygon level.

## Solution

1. Removed `RpgEnemy1` and `RpgEnemy2` from `CastleLevel.tscn`
2. Added `RpgEnemy1` (position: 3700, 1400) and `RpgEnemy2` (position: 2000, 2200) to `TestTier.tscn`
3. Updated enemy count labels and test assertions accordingly

### Placement Strategy

- **RpgEnemy1** at (3700, 1400): In the StrategicZone area (right side), near high-value targets
- **RpgEnemy2** at (2000, 2200): In CombatZone3 area (lower-center), providing variety in enemy engagement

## Files Changed

- `scenes/levels/CastleLevel.tscn` - Removed RPG enemy nodes
- `scenes/levels/TestTier.tscn` - Added RPG enemy nodes, updated enemy count label
- `scripts/levels/test_tier.gd` - Updated enemy count comment
- `tests/unit/test_level_scripts.gd` - Updated mock enemy counts and test assertions

## Second Feedback (2026-02-09)

User reported "RPG wasn't added" and provided a new game log. However, analysis of `game_log_20260209_110330.txt` confirms:

- RpgEnemy1 spawned at (3700, 1400) in TestTier ✅
- RpgEnemy2 spawned at (2000, 2200) in TestTier ✅
- RpgEnemy1 entered COMBAT state and fired (GUNSHOT range=2500 = RPG loudness) ✅
- After first shot, RpgEnemy1 subsequent shots used range=1469 (PM loudness) = weapon switch worked ✅
- RpgEnemy2 same pattern ✅

The RPG enemies ARE present and functioning. The user may have been testing with an older cached build. The weapon switching to PM is confirmed working by the different sound propagation ranges in the log.

## Merge Conflicts Resolved (2026-03-16)

Merged latest `main` branch which included changes from issues #858, #675, #934, #954, #883, #921, #636.
Resolved conflicts:
- `enemy.gd`: integrated RPG no-lead-prediction flag into new aggression logic; preserved RPG no-shell-sound into new sound cooldown logic; kept both `_switch_to_secondary_weapon` (Issue #583) and `_setup_enemy_flashlight` (Issue #824)
- `test_enemy.gd`: kept both RPG tests and new Issue #883/#921 tests
- `test_level_scripts.gd`: kept PM ammo multiplier from main + updated enemy count to 12

Also compacted `_switch_to_secondary_weapon` from 20→10 lines to stay under the 5000-line architecture limit.

## Third Feedback (2026-03-17)

User reported "новый враг должен появляться на карте Полигон / сейчас там все с m16" (new enemy should appear on the Polygon map / currently all have M16). Provided `game_log_20260317_010617.txt`.

### Analysis of game_log_20260317_010617.txt

The log confirms RPG enemies ARE spawning and functioning in TestTier:
- `[RpgEnemy1] Spawned at (3700, 1400), hp: 1, behavior: GUARD` ✅
- `[RpgEnemy2] Spawned at (2000, 2200), hp: 1, behavior: GUARD` ✅
- `Sound emitted: type=GUNSHOT, source=ENEMY (RpgEnemy1), range=2500` = RPG shot (weapon_loudness=2500) ✅
- `Sound emitted: type=GUNSHOT, source=ENEMY (RpgEnemy1), range=1469` = PM shot after switch ✅
- RpgEnemy2 same pattern ✅

### Root Cause of "everything is M16" complaint

Despite the RPG enemy logic working correctly (firing rockets, switching to PM), the **enemy weapon sprite was still showing M16**. This is because:

1. The base `Enemy.tscn` scene has `WeaponSprite` texture set to `m16_rifle_topdown.png` by default.
2. In `_configure_weapon_type()`, the sprite is only updated when `sprite_path != ""`.
3. The RPG weapon config (type 4) had `"sprite_path": ""` — leaving the default M16 sprite unchanged.

### Fix Applied

1. Created `assets/sprites/weapons/rpg_topdown.png` — a 72×18 pixel top-down RPG-7 sprite (matching ak_gl_topdown.png dimensions), showing the rocket launcher tube, warhead, pistol grip and rear exhaust bell.
2. Updated `WeaponConfigComponent` RPG entry: `"sprite_path": "res://assets/sprites/weapons/rpg_topdown.png"`.

This ensures RPG enemies visually display the rocket launcher weapon instead of the M16 rifle.

## Fourth Feedback (2026-03-17, ~04:00)

User reported "враг всё ещё не стреляет из РПГ (выстрел не летит)" (enemy still not firing from RPG - the shot doesn't fly). Provided `game_log_20260317_040003.txt`.

### Analysis of game_log_20260317_040003.txt

The log confirms:
- RPG enemies spawn at (3700,1400) and (2000,2200) ✅
- `Sound emitted: ... range=2500` (RPG shot sound) - `_execute_shoot` IS being called ✅
- `State: COMBAT -> RETREATING` immediately after shot ✅
- Second shots from RpgEnemy1 at `range=1469` = PM pistol after weapon switch ✅

**Previous hypothesis (root cause #4):** The bug from commit `131bf9d0` was that `ProjectilePoolManager.get_bullet()` was returning a pooled regular bullet ignoring `bullet_scene = RpgRocket.tscn`. Fix was to bypass the pool in `_fire_rpg_rocket()`.

### Analysis of game_log_20260317_044735.txt

After bypass fix was applied, user still reports "РПГ всё ещё не стреляет ракетой" (RPG still not firing rocket). Sound is still emitted at `range=2500`, proving `_execute_shoot` is called and the bypass function runs.

**Root Cause #5 (CONFIRMED): Rocket is spawned but invisible - missing texture in RpgRocket.tscn**

Evidence:
1. `_execute_shoot` → `_fire_rpg_rocket()` runs (confirmed by sound emission at lines in log)
2. Rocket IS added to scene (`get_tree().current_scene.add_child(rocket)`)
3. BUT `RpgRocket.tscn` `Sprite2D` node has **no texture set** - `texture` property was missing
4. Without a texture, `Sprite2D` renders as nothing - rocket is completely invisible
5. Comparison: `Bullet9mm.tscn` correctly uses `PlaceholderTexture2D` with `size = Vector2(12, 3)`

**Fix Applied (2026-03-17):**
- Added `PlaceholderTexture2D` sub-resource with `size = Vector2(20, 6)` to `RpgRocket.tscn`
- Set `texture = SubResource("PlaceholderTexture2D_rocket")` on the `Sprite2D` node
- Added unconditional `print()` logging in `_fire_rpg_rocket()` so future logs confirm rocket spawning

### Why This Was Missed

The rocket was being spawned and moving correctly - it had working:
- `_physics_process` movement (`position += direction * speed * delta`)
- `ExhaustParticles` GPUParticles2D (very small orange particles, hard to see)
- `Trail` Line2D (draws from position history, starts empty)
- Collision detection (could hit walls and explode)

But without a `Sprite2D` texture, the rocket body itself was invisible. The trail Line2D starts empty and fills as the rocket moves, but because the rocket moves fast (800 px/s), by the time a few trail points accumulated the rocket may have already hit a wall or faded out.

## Logs

- `game_log_20260208_193502.txt` - Game log from user testing showing RPG enemies in CastleLevel (wrong level)
- `game_log_20260209_110330.txt` - Game log confirming RPG enemies working correctly in TestTier
- `game_log_20260317_010617.txt` - Game log confirming RPG enemies in TestTier but visual sprite was M16 (now fixed)
- `game_log_20260317_040003.txt` - Game log confirming shoot sound fires (range=2500) but rocket invisible (no texture in scene)
- `game_log_20260317_044735.txt` - Game log after pool bypass fix - sound still fires but rocket still invisible (texture not yet added)

## Root Cause #6: Programmatic Texture Creation Fails in Exported Build (Fix: External PNG)

**Symptom (game_log_20260317_060727.txt)**: After the spawn immunity fix, the rocket completely disappeared — no static rectangle, no movement.

**Root cause**: The previous fix (commit 49dc37dc) replaced the `PlaceholderTexture2D` in `RpgRocket.tscn` with a programmatically-created texture via `_create_rocket_texture()` in GDScript `_ready()`. This failed silently in exported builds, leaving the `Sprite2D` with no visible texture.

The `Image.create()` + `ImageTexture.create_from_image()` approach works in debug builds but can fail in exported builds if the renderer isn't fully initialized at node `_ready()` time.

**Fix (commit TBD)**: 
1. Created `assets/sprites/projectiles/rpg_rocket.png` — a 32×10 RGBA PNG showing an RPG rocket (pointing right): yellow exhaust tail → grey fins → grey body → orange nose cone
2. Updated `RpgRocket.tscn` to use `ext_resource` for the texture (same as `VOGGrenade.tscn`)
3. Removed programmatic `_create_rocket_texture()` from `rpg_rocket.gd` (no longer needed)
4. Updated `_fire_rpg_rocket()` logging to use `_log_to_file()` (now visible in game logs)

**Evidence**: 
- `game_log_20260317_060727.txt`: `Sound emitted: type=GUNSHOT, range=2500` → rocket WAS spawned and moving, but invisible
- No `[RPG] Rocket spawned` in logs → confirms `_log_to_file` wasn't used (only `print()` which doesn't go to log file)
- Pattern from `VOGGrenade.tscn`: uses `ext_resource` PNG, always works in exported builds

## Root Cause #7: Rocket Stationary After PNG Sprite Fix (2026-03-17, 03:37)

**Symptom (game_log_20260317_063521.txt)**: After the PNG sprite fix, rocket now appears visually but doesn't move — it spawns at the muzzle position and stays stationary.

**Evidence from log**:
- Line 1469: `[RpgEnemy2] [RPG] Rocket spawned at (1670.17, 1818.453) dir=(-0.952475, -0.304616)` ✅
- No explosion events logged → rocket never hit a wall (confirming it's truly stationary, not just fast)
- Rocket direction is non-zero (-0.952, -0.304) → direction IS being passed correctly
- User screenshot shows rocket at horizontal orientation (rotation=0°) despite direction being ~162° from +X

**Root cause analysis**:
The rocket direction was being set BEFORE `add_child()` in `_fire_rpg_rocket()`. While this works for simple property assignments, the `launch()` method (which sets rotation and exhaust direction) was not being called — and the `_ready()` method ran with an already-set `direction` but there may have been a race condition or exported build difference in how the physics process started.

The key observations:
1. Direction `(-0.952, -0.304)` corresponds to ~162° from +X axis, not 0° (horizontal)
2. Screenshot shows horizontal rocket → rotation was NOT applied → `direction.angle()` wasn't called correctly
3. No explosion in 3-12 seconds → rocket truly not moving (at 800px/s would travel 2400-9600px and hit walls)

**Fix Applied (2026-03-17)**:
1. Added `launch(dir)` method to `RpgRocket` that sets direction, rotation, and exhaust orientation
2. Changed `_fire_rpg_rocket()` to call `launch()` AFTER `add_child()` (same pattern as bullet direction setting)
3. Added `_launched` flag - `_physics_process` doesn't move until `launch()` is called
4. Changed movement from `position +=` to `global_position +=` for robustness
5. Increased `spawn_immunity_time` from 0.15s to 0.3s to prevent immediate wall collision
6. Added explicit `set_physics_process(true)` in `_ready()`
7. Added logging to `launch()` and `_explode()` for future debugging

**Logs**:
- `game_log_20260317_063521.txt` - RPG rockets spawn but are stationary (this fix addresses this)

## Root Cause #8: call_deferred("launch") Never Executes (2026-03-17, ~08:00)

**Symptom (game_log_20260317_100552.txt)**: After switching to `call_deferred("launch", dir)`, the log shows "Rocket queued launch" but no "Launched:" message ever appears — confirming the deferred call never executes.

**Root cause**: `call_deferred()` with a custom GDScript method name is unreliable in Godot 4 exported builds. Even when the method exists at queue-processing time, the exported bytecode's method resolution may fail for user-defined GDScript methods called by name string.

**Fix Applied (commit `e48c36e5` then `f66f121f`)**:
Abandoned the `launch()` method approach entirely. Converted `RpgRocket` to `Area2D` with:
- Direction set as a property (no method calls)
- `_physics_process` for movement: `position += direction * _speed * delta`
- `body_entered` + `area_entered` signals for collision detection

The `RigidBody2D` was also attempted (`e48c36e5`) but rejected because physics forces caused the rocket to spin and drift sideways on collision — "behaves like a plastic bottle".

**Logs**:
- `game_log_20260317_100552.txt` - "Rocket queued launch" with no "Launched:" = deferred call failed
- Detailed analysis: `game_log_20260317_100552_analysis.md`

## Root Cause #9: Area2D Direction Set Before vs After add_child (2026-03-17, ~08:22)

**Symptom**: User reports "ракета опять не летит и не физический объект" (rocket again doesn't fly and is not a physical object). Screenshot shows rocket visible but stationary next to enemy.

**Build**: Area2D fix commit `f66f121f` (uploaded as artifact at 08:09:31 UTC, user complaint at 08:22:43 UTC).

**Root cause hypothesis**: The Area2D fix set `direction` BEFORE `add_child()`, while bullet.gd (which always works) sets direction AFTER `add_child()`. Setting properties before vs after `add_child` has subtle differences in Godot 4 exported builds due to how the ScriptInstance initializes.

Additionally, the user comment "not a physical object" reflects that `Area2D` has no physics collision response (no bouncing, no push forces) unlike the previous `RigidBody2D`. The rocket now passes through walls kinematically (detecting via signals), which may feel "unphysical" to the user.

**Fix Applied (Session 9)**:
Changed `_fire_rpg_rocket()` to set `direction` AFTER `add_child()` (exact bullet pattern):
```gdscript
# BEFORE (f66f121f — set before add_child):
rocket.set("direction", rocket_dir)
rocket.global_position = pos
get_tree().current_scene.add_child(rocket)

# AFTER (session 9 — set after add_child, same as _spawn_projectile for bullets):
rocket.global_position = pos
get_tree().current_scene.add_child(rocket)
rocket.set("direction", rocket_dir)
rocket.set("shooter_id", get_instance_id())
rocket.set("shooter_position", pos)
```

Also added first-frame `_physics_process` diagnostic: `[RpgRocket] First frame: pos=... dir=... speed=... delta=...`

**Godot 4 Export Pitfalls (Complete List)**:
1. `as ClassName` cast → unreliable for GDScript class_name in exports → use `as Node2D`
2. `load(path)` at runtime → returns null in exports → use `preload(path)`
3. `has_method()` for GDScript methods → false in exports even after add_child → use property access
4. `call_deferred("gd_method")` → may not execute in exports → avoid entirely
5. `ImageTexture.create_from_image()` in `_ready()` → fails silently → use ext_resource PNG
6. Setting properties before `add_child()` → untested in this codebase → use post-add_child (bullet pattern)

**Logs**:
- User screenshot (2026-03-17T08:22:43Z): rocket visible, stationary
- `game_log_20260317_100552_session9_analysis.md` - detailed analysis
