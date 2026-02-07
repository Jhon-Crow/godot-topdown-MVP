# Case Study: Issue #1 — ReplayManager Not Working in Exported Builds

## Summary

The ReplayManager system, implemented as a GDScript autoload (`replay_system.gd`), consistently fails to load its methods in exported Godot 4.3 builds with C# enabled. The symptom is that `has_method("start_recording")` returns `false` despite the script being attached to the node, and `GDScript.new()` returns `null`. This prevents replay recording from ever starting, resulting in the "Watch Replay" button always showing "no data".

## Timeline / Sequence of Events

| Date/Time | Log File | Error Pattern |
|-----------|----------|---------------|
| Feb 5, 03:00 | game_log_20260205_030057.txt | `ERROR: ReplayManager not found, replay recording disabled` |
| Feb 5, 03:23 | game_log_20260205_032338.txt | `ERROR: ReplayManager not found, replay recording disabled` (up to 10+ repeated errors) |
| Feb 6, 12:02 | game_log_20260206_120242.txt | `ERROR: ReplayManager not found, replay recording disabled` |
| Feb 6, 12:29 | game_log_20260206_122932.txt | `ERROR: ReplayManager not found` — Watch Replay button now appears but disabled |
| Feb 6, 13:14 | game_log_20260206_131432.txt | Same pattern, button shows "no data" |
| Feb 6, 14:14 | game_log_20260206_141414.txt | New: `WARNING: ReplayManager created but start_recording method not found` |
| Feb 6, 14:32 | game_log_20260206_143228.txt | Detailed: autoload exists, scene loaded, `script.new()` returned null, all 4 strategies fail |
| Feb 6, 18:51 | game_log_20260206_185149.txt | Same: all 4 loading strategies fail, same GDScript ID `<GDScript#-9223372007242988300>` |
| Feb 6, 20:15 | game_log_20260206_201555.txt | Same: all loading strategies fail, Watch Replay shows "no data" |
| Feb 6, 21:30 | game_log_20260206_213011.txt | C# ReplayManager loads, `_Ready` fires, but `has_method("start_recording")` returns false — PascalCase naming issue |

### Key Observations from Timeline

1. **ReplayManager autoload IS registered** (present at `/root/ReplayManager` since ~14:14)
2. **The GDScript resource IS loaded** (shows `<GDScript#-9223372007242988300>`)
3. **But methods are NOT accessible** — `has_method("start_recording")` returns `false`
4. **`_ready()` never fires** — the log message "ReplayManager ready (script loaded and _ready called)" never appears in any log
5. **`GDScript.new()` returns null** — the script cannot be instantiated
6. **Same GDScript ID across all attempts** — all 4 loading strategies produce the same broken script instance
7. **All 16+ other GDScript autoloads work perfectly** — only `replay_system.gd` fails

## Root Cause Analysis

### Direct Cause

The GDScript file `replay_system.gd` fails to **compile/parse** when loaded in an exported Godot 4.3 build with C# (Mono) enabled. The GDScript resource object is created (so `load()` succeeds and `get_script()` is non-null), but the bytecode is never compiled, so:
- `has_method()` returns `false` for all custom methods
- `GDScript.new()` returns `null`
- `_ready()` and other virtual functions never execute
- The node exists in the scene tree but is functionally inert

### Why This Specific Script Fails

This is documented behavior in Godot issues:
- [godotengine/godot#96065](https://github.com/godotengine/godot/issues/96065): `load()` returns a `GDScript` even with parse errors, but `new()` fails and errors are undetectable
- [godotengine/godot#94150](https://github.com/godotengine/godot/issues/94150): GDScript export mode breaks builds with binary tokenization
- [godotengine/godot#91713](https://github.com/godotengine/godot/issues/91713): Scripts fail to load with parse errors on exported projects

The script `replay_system.gd` is one of the larger and more complex GDScript files (~819 lines), using:
- Typed function parameters (`level: Node2D`, `player: Node2D`, etc.)
- Complex dictionary and array operations
- Scene loading via `load()` at runtime
- Signal definitions
- Multiple method signatures with return types

While each of these is valid GDScript, the combination appears to trigger a silent parse failure in the binary tokenization pipeline. Setting `script_export_mode=0` (text mode) was attempted but did NOT resolve the issue — the script still fails to parse in the exported build.

### Why Other GDScript Autoloads Work

The 16+ other GDScript autoloads in this project are simpler scripts (typically 50-200 lines) that use basic constructs. The `replay_system.gd` is significantly more complex and likely hits an edge case in the GDScript parser/compiler during the export process.

### Previous Fix Attempts (All Failed)

| Attempt | Fix | Result |
|---------|-----|--------|
| 1 | Remove inner classes from replay_system.gd | Still fails |
| 2 | Rename replay_manager.gd to replay_system.gd (avoid naming collision with autoload) | Still fails |
| 3 | Use scene-based autoload (ReplayManager.tscn) instead of script-based | Still fails |
| 4 | Multi-strategy loading: autoload, scene instantiate, script.new(), Node+set_script() | All 4 strategies fail |
| 5 | Set `script_export_mode=0` (text mode instead of binary tokens) | Still fails |
| 6 | Re-export after text mode change | Still fails |

## Solution

### Chosen Approach: Rewrite ReplayManager in C#

Since this is a mixed C#/GDScript project where C# scripts (Player.cs, Enemy.cs, weapons, etc.) all work reliably in exported builds, the solution is to rewrite the ReplayManager as a C# class.

**File:** `Scripts/Autoload/ReplayManager.cs`

C# scripts are compiled by the .NET SDK into a DLL, completely bypassing the GDScript parser/tokenizer. This eliminates the root cause entirely.

### Changes Made

1. **New file: `Scripts/Autoload/ReplayManager.cs`**
   - Faithful port of all functionality from `replay_system.gd`
   - Uses C# PascalCase conventions (GDScript callers must use PascalCase for user-defined methods)
   - Same recording, playback, ghost entity, and UI features
   - `[GlobalClass]` attribute for Godot integration

2. **Modified: `project.godot`**
   - Changed autoload from: `ReplayManager="*res://scenes/autoload/ReplayManager.tscn"`
   - Changed autoload to: `ReplayManager="*res://Scripts/Autoload/ReplayManager.cs"`

3. **Modified: `scripts/levels/building_level.gd`**
   - Removed complex 4-strategy `_get_or_create_replay_manager()` function
   - Replaced with simple autoload accessor: `get_node_or_null("/root/ReplayManager")`

4. **Modified: `scripts/levels/test_tier.gd`**
   - Same simplification as building_level.gd

### Why This Solution Works

- C# scripts are compiled by the .NET SDK, not the GDScript tokenizer
- The GrenadeTimerHelper.cs autoload already works reliably in exports (same pattern)
- GDScript callers use `has_method("StartRecording")` to access C# methods with PascalCase names
- GDScript calling code updated to use PascalCase method names (Godot does NOT auto-convert user-defined C# method names)

## Bug #2: GDScript-to-C# Method Naming (PascalCase Required)

After the C# rewrite was deployed, the ReplayManager C# class loaded successfully (`_Ready` fired, line 58 in log 20260206_213011), but GDScript's `has_method("start_recording")` still returned `false`.

### Root Cause

In Godot 4.x, user-defined C# methods exposed to GDScript retain their original PascalCase names. The automatic snake_case-to-PascalCase conversion **only applies to built-in Godot engine methods**, NOT to user-defined methods. This is documented in the [Godot cross-language scripting docs](https://docs.godotengine.org/en/4.3/tutorials/scripting/cross_language_scripting.html).

The GDScript code was using:
```gdscript
replay_manager.has_method("start_recording")  # WRONG — returns false
replay_manager.start_recording(...)            # WRONG — method not found
```

When it should use:
```gdscript
replay_manager.has_method("StartRecording")    # CORRECT — returns true
replay_manager.StartRecording(...)             # CORRECT — calls C# method
```

### Evidence from Codebase

Other C# methods in the same project are already called with PascalCase from GDScript:
- `weapon.has_method("GetMagazineAmmoCounts")` → works
- `_player.has_method("EquipWeapon")` → works
- `weapon.has_method("ConfigureAmmoForEnemyCount")` → works

### Fix

Updated all ReplayManager method calls in `building_level.gd` and `test_tier.gd` from snake_case to PascalCase:
- `start_recording` → `StartRecording`
- `stop_recording` → `StopRecording`
- `has_replay` → `HasReplay`
- `get_replay_duration` → `GetReplayDuration`
- `start_playback` → `StartPlayback`
- `clear_replay` → `ClearReplay`

## Supporting Evidence

### From Godot Documentation and Issues

- [godotengine/godot#96065](https://github.com/godotengine/godot/issues/96065): Confirms that `load()` returns GDScript objects even with parse errors, and `new()` returns null silently
- [godotengine/godot#94150](https://github.com/godotengine/godot/issues/94150): Confirms GDScript export mode issues in Godot 4.3
- [Godot Forum: Autoload Script Functions Not Called](https://forum.godotengine.org/t/autoload-script-functions-not-being-called-in-exported-build/127658): Confirms autoload methods don't work in exported builds

### From Game Logs

All 10 game logs collected in `docs/case-studies/issue-1/logs/` show the progression:
- ReplayManager GDScript fails to provide methods
- Recording never starts
- No replay data is ever available
- Watch Replay button consistently shows "no data"

## Logs

All game logs from user testing sessions are preserved in `docs/case-studies/issue-1/logs/`:

- `game_log_20260205_030057.txt` — First report: ReplayManager not found
- `game_log_20260205_032338.txt` — Repeated errors
- `game_log_20260206_120242.txt` — After autoload registration
- `game_log_20260206_122932.txt` — Button appears, shows "no data"
- `game_log_20260206_131432.txt` — Still "no data"
- `game_log_20260206_141414.txt` — Method not found despite script attached
- `game_log_20260206_143228.txt` — All 4 loading strategies documented failing
- `game_log_20260206_185149.txt` — Same failure, player controls issue also reported
- `game_log_20260206_201555.txt` — All strategies still fail
- `game_log_20260206_213011.txt` — C# ReplayManager loads, but snake_case `has_method()` fails (PascalCase naming fix needed)
- `game_log_20260206_235558.txt` — PascalCase fix applied: recording and playback start successfully, but replay is not visible (score screen UI overlay obscures ghosts)

## Bug #3: Score Screen UI Obscures Replay Playback

After Bugs #1 and #2 were fixed, a third bug was identified from `game_log_20260206_235558.txt`:

### Symptoms

- Recording works perfectly (3866 frames / 60.94s in first session, 2200 frames / 34.32s in second)
- `HasReplay()` returns `true`
- "Watch Replay" button is enabled and clickable
- `StartPlayback()` executes successfully ("Started replay playback. Frames: 3866, Duration: 60,94s")
- Speed controls work (user changes between 1.0x and 2.0x)
- **But the replay is NOT visible** — user reports "на экране всё ещё результаты и не видно самого реплея" (the results are still on screen and the replay is not visible)

### Root Cause

The score screen UI is displayed inside `CanvasLayer/UI` (CanvasLayer at default layer 1), which renders **on top of** the game world. The replay ghost entities are added as children of the level's Node2D tree, which renders in the game world coordinate system — **below** any CanvasLayer.

When `StartPlayback()` is called:
1. Ghost entities are created as children of level → render in game world (below CanvasLayer)
2. Original entities are hidden (player, enemies, projectiles) — but they were already behind the score screen
3. Replay UI is created at CanvasLayer layer 100 — visible on top
4. **The score screen at CanvasLayer layer 1 is NEVER hidden** — it completely obscures the ghost entities

Additionally, the camera stays stationary because the original player's `Camera2D` doesn't track the ghost player. The ghost player has its own `Camera2D` (from Player.tscn instantiation), but `DisableNodeProcessing()` disabled its processing, preventing it from following the ghost.

### Fix

Two changes in `ReplayManager.cs`:

1. **`HideOriginalEntities()`**: Also hide the level's `CanvasLayer` node to remove the score screen overlay
2. **`CreateGhostEntities()`**: After creating the ghost player, re-enable its `Camera2D` (set ProcessMode to Always, re-enable process/physics_process, make current) so the camera follows the ghost player during replay

### Evidence from Log

```
[23:57:15] [ReplayManager] has_replay() will return: True
[23:57:15] [BuildingLevel] Replay status: has_replay=true, duration=60.94s
[23:57:15] [ScoreManager] Level completed! Final score: 28080, Rank: B
[23:57:23] [BuildingLevel] Watch Replay button created (replay data available)
[23:57:24] [BuildingLevel] Watch Replay triggered
[23:57:24] [ReplayManager] Started replay playback. Frames: 3866, Duration: 60,94s
[23:57:30] [ReplayManager] Playback speed set to 1,00x
[23:57:35] [ReplayManager] Playback speed set to 1,00x
[23:57:43] [ReplayManager] Playback speed set to 2,00x
[23:57:44] [ReplayManager] Playback speed set to 1,00x
[23:57:48] [ReplayManager] Stopped replay playback
```

The log shows playback started and speed was changed, confirming the replay system is functioning internally — only the visual presentation was broken.

## Bug #4: Replay Missing Animations (Rotation, Shooting, Deaths)

After Bugs #1–#3 were fixed (replay recording works, PascalCase naming resolved, score screen hidden), a fourth issue was reported: the replay shows only position movement and enemy disappearances — no rotation animations, shooting effects, death effects, or other visual interactions.

### Symptoms (from `game_log_20260207_002734.txt`)

- Recording works (1905 frames / 29.75s)
- Ghost camera follows player
- Score screen is hidden during replay
- **But ghosts show no animations**: no aiming rotation, no walking bob, no shooting flashes, enemies just vanish instantly when killed

### Root Cause

The `DisableNodeProcessing()` method strips ALL scripts from ghost entities and disables all processing. Since all animations in this game are **procedural/script-driven** (not AnimatedSprite2D or AnimationPlayer), the ghosts are completely static:

1. **Walking animation**: Uses sine wave calculations in `_update_walk_animation()` — requires `_physics_process()` running
2. **Aiming rotation**: PlayerModel/EnemyModel `global_rotation` set by `_update_player_model_rotation()` / `_update_enemy_model_rotation()` — requires script running
3. **Death animation**: DeathAnimationComponent runs keyframe + ragdoll physics — requires script running
4. **Muzzle flash**: Spawned by ImpactEffectsManager on each shot — never triggered during replay

Additionally, the original FrameData only recorded:
- Player: position, rotation (root node), model scale, alive state
- Enemy: position, rotation (root node), alive state

It did NOT record:
- PlayerModel/EnemyModel `global_rotation` (the actual aim direction)
- PlayerModel/EnemyModel `scale` (the left/right flip state)
- Velocity (needed to derive walking animation)
- Shooting events

### Fix

Extended the replay recording and playback system:

1. **Extended FrameData to record animation state:**
   - `PlayerVelocity` — for walking animation derivation
   - `PlayerModelRotation` — the PlayerModel's global rotation (aim direction)
   - `PlayerModelScale` — replaces old field, now explicitly for model scale
   - `PlayerShooting` — detected by comparing bullet counts between frames
   - `EnemyFrameData.Velocity` — for enemy walking animation
   - `EnemyFrameData.ModelRotation` — the EnemyModel's global rotation
   - `EnemyFrameData.ModelScale` — the EnemyModel's scale (left/right flip)
   - `EnemyFrameData.Shooting` — from enemy `_is_shooting` variable

2. **Procedural walking animation during playback:**
   - `ApplyWalkAnimation()` — replicates the sine wave formulas from `player.gd`/`enemy.gd`
   - Body bob: `sin(time * 2.0) * 1.5 * intensity`
   - Head bob: `sin(time * 2.0) * 0.8 * intensity`
   - Arm swing: `sin(time) * 3.0 * intensity`
   - Speed-dependent animation with smooth idle return

3. **Aim rotation during playback:**
   - Applies recorded `PlayerModelRotation` and `PlayerModelScale` to ghost's PlayerModel
   - Same for EnemyModel on ghost enemies
   - This restores the visual aiming direction and left/right sprite flip

4. **Death fade effect:**
   - When enemy alive state transitions from `true` to `false`, instead of instant hide:
     - Flash red (`Color(1.5, 0.3, 0.3, 1.0)`)
     - Fade out over 0.4 seconds
     - Then hide the ghost

5. **Muzzle flash effects:**
   - Spawns a radial gradient flash sprite at the entity's aim direction
   - Fades out over 0.05 seconds
   - Player shooting detected via bullet count changes
   - Enemy shooting detected via `_is_shooting` variable

6. **Close button (X) for exiting replay:**
   - Added `✕` button in top-right corner of replay UI
   - Supplements the existing "Exit Replay (ESC)" button and keyboard shortcut

### Log Files

- `game_log_20260207_002734.txt` — Shows successful recording with shotgun, invincibility mode, grenade kills, and replay playback (1905 frames, 29.75s)
- `game_log_20260207_005613.txt` — User testing session showing 3 remaining visual issues in replay (2154 frames, 32.68s)

## Bug #5: Player Weapon Not Visible in Replay

### Symptoms (from user feedback on PR #421)

- Player weapon (rifle/shotgun/etc.) is not visible on the ghost player during replay
- Player model looks wrong — arms appear to be in wrong positions ("руки вперёд и назад" — arms forward and back)

### Root Cause

**Weapon sprite not baked into Player.tscn.** The `Player.tscn` scene has an empty `PlayerModel/WeaponMount` node with no weapon sprite child. Weapons are dynamically added by level scripts (`building_level.gd`) at runtime via `_setup_selected_weapon()`. When the ghost player is instantiated from `Player.tscn` and has all scripts stripped by `DisableNodeProcessing()`, the weapon detection code never runs and the `WeaponMount` remains empty.

**Arm drift bug.** The `ApplyWalkAnimation()` method used additive positioning for arms:
```csharp
// BUG: adds to current X position every frame, causing infinite drift
leftArm.Position = new Vector2(leftArm.Position.X + armSwing * delta * 10.0f, ...)
```
This accumulated the arm swing offset every frame, causing arms to drift further and further from their base positions.

### Fix

1. **Weapon detection at recording start:** `DetectPlayerWeapon()` checks for weapon children (MiniUzi, Shotgun, SniperRifle, SilencedPistol, or default AssaultRifle) and stores the correct texture path and offset.
2. **Weapon sprite added to ghost:** `AddWeaponSpriteToGhost()` creates a `Sprite2D` with the detected weapon texture and adds it to `PlayerModel/WeaponMount`.
3. **Fixed arm positioning:** Changed to absolute positioning using base positions from the scene file:
```csharp
// FIX: use absolute position (base + offset) to prevent drift
leftArm.Position = new Vector2(baseLeftArmX + armSwing, leftArm.Position.Y);
```

## Bug #6: Bullets/Projectiles Not Visible in Replay

### Symptoms

- No bullet tracers visible during replay playback
- Both player and enemy projectiles are missing

### Root Cause

**Wrong bullet detection path.** The ReplayManager searched for bullets at `Entities/Projectiles` and `Projectiles` paths, but bullets are actually spawned as **direct children of the level root** via `GetTree().CurrentScene.AddChild(bullet)` in all weapon scripts (`BaseWeapon.cs`, `SilencedPistol.cs`, `SniperRifle.cs`, `Shotgun.cs`). The `Entities/Projectiles` path does not exist in `BuildingLevel.tscn`.

Since no bullets were found at the expected path, 0 bullets were ever recorded, resulting in empty `frame.Bullets` arrays.

### Fix

Changed bullet recording to scan level root children for `Area2D` nodes with `collision_layer & 16 != 0` (bullet collision layer). This matches how `last_chance_effects_manager.gd` identifies bullets:
```csharp
foreach (var child in _levelNode.GetChildren())
{
    if (child is Area2D area2D && (area2D.CollisionLayer & BulletCollisionLayer) != 0)
        frame.Bullets.Add(...);
}
```

Also enlarged the ghost bullet sprite from 8x3 to 16x4 pixels with a gradient trail effect for better visibility.

## Bug #7: Enemy Death Animations Missing in Replay

### Symptoms

- Enemies simply vanish when killed during replay (instant disappear or minimal fade)
- No body displacement, rotation, or ragdoll-like fall animation

### Root Cause

The previous implementation only did a 0.4s red flash + fade-out when enemies died. The real `DeathAnimationComponent` uses a complex two-phase system (0.8s fall animation + ragdoll physics) with 24-directional body displacement, but this requires active scripts which are stripped by `DisableNodeProcessing()`.

Additionally, the hit direction (`_last_hit_direction`) was not being recorded, so even a simplified death animation couldn't know which direction the enemy was hit from.

### Fix

1. **Record hit direction:** Added `LastHitDirection` field to `EnemyFrameData`, read from `_last_hit_direction` GDScript variable during recording.
2. **Extended death animation (0.8s):** Increased `DeathFadeDuration` from 0.4s to 0.8s (matching `death_animation_component.gd`'s `fall_animation_duration`).
3. **Body displacement:** Ghost enemy moves 25px away from hit (matching `fall_distance = 25` from the component).
4. **Body rotation:** Model rotates partially toward fall direction with ease-out curve.
5. **Arm swing:** Arms rotate outward (±30 degrees) during fall animation.
6. **Color transition:** Red flash → dark fade-out → hide.

### Log Evidence

From `game_log_20260207_005613.txt`:
```
[00:56:59] [ReplayManager] Started replay playback. Frames: 2154, Duration: 32,68s
```
Replay ran for ~36 seconds (00:56:59 to 00:57:35) with no errors, confirming the system works but lacked visual fidelity.
