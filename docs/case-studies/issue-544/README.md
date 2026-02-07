# Case Study: Issue #544 - Memory Replay Mode Visual/Audio Fidelity

## Problem Statement

The Memory (replay) mode in the game had 7 major deficiencies that degraded the replay viewing experience:

1. **Bullets not visible** - Ghost bullets were tiny (8x3 GradientTexture2D) and lacked trails
2. **No sounds** - Events array was declared but never populated or played back
3. **Wrong colors** - Ghost entities used flat white modulate, hiding health-based color changes
4. **No hit brightness effect** - HitEffectsManager was not triggered during replay
5. **Static floor** - Blood decals and casings were either all present or all absent
6. **Wrong player model** - Ghost modulate override (0.9 alpha white) masked health colors
7. **No player trail** - No visual trail following the player ghost

## Timeline of Events

1. **Initial replay system** - Recorded basic entity positions, rotations, and alive state
2. **Ghost entity system** - Instantiated scene copies with disabled scripts
3. **Issue #544 filed** - Seven specific visual/audio problems identified

## Root Cause Analysis

### Root Cause 1: Insufficient Recording Data

The replay system only recorded:
- Player: position, rotation, model_scale, alive (bool)
- Enemies: position, rotation, alive (bool)
- Bullets: position, rotation (no visual info)
- Events: declared but never populated

**Missing data:** health colors, sound events, floor state (blood/casings)

### Root Cause 2: Ghost Entity Visual Override

`_set_ghost_modulate()` applied `Color(1.0, 1.0, 1.0, 0.9)` to ALL nodes recursively.
This overrode any health-based color that could be applied later.

### Root Cause 3: No Event System

The `events` array in frame data was always empty. There was:
- No code to detect when shots were fired
- No code to detect when enemies were hit or killed
- No code to play back sounds during replay

### Root Cause 4: Bullet Visual Inadequacy

Ghost bullets used `GradientTexture2D` with 8x3 pixel dimensions - nearly invisible at game scale.
No trail system was implemented for ghost bullets, unlike real bullets which use Line2D trails.

### Root Cause 5: No Floor State Management

The replay did not:
- Record blood decal positions
- Record casing positions
- Clean the floor at replay start
- Progressively re-add floor effects during playback

## Solution

### Enhanced Recording (`_record_frame`)

| Data Point | Before | After |
|-----------|--------|-------|
| Player color | Not recorded | `body_sprite.modulate` per frame |
| Enemy color | Not recorded | `enemy_body.modulate` per frame |
| Sound events | Always empty | Detected via bullet count changes and color flash detection |
| Blood decals | Not recorded | Positions from `blood_puddle` group |
| Casings | Not recorded | Positions from `casings` group |

### Enhanced Playback

| Feature | Before | After |
|---------|--------|-------|
| Bullet visibility | 8x3 GradientTexture2D | 12x4 solid sprite + Line2D trail |
| Sounds | None | Shot, hit, death sounds via AudioManager |
| Entity colors | Flat white override | Per-frame health color from recording |
| Hit effects | None | HitEffectsManager.on_player_hit_enemy() on hits |
| Floor state | Static | Clean at start, progressive re-addition |
| Player model | White modulate override | Actual health-based colors |
| Player trail | None | Line2D with gradient fade (20 points) |

### Event Detection Algorithm

Sound events are detected by comparing consecutive frames:
1. **Shots**: `frame.bullets.size() > prev_frame.bullets.size()`
2. **Hits**: Enemy color becomes white (flash) - `color.r > 0.95 && color.g > 0.95 && color.b > 0.95`
3. **Deaths**: `prev_frame.enemies[i].alive && !frame.enemies[i].alive`

## Files Modified

| File | Changes |
|------|---------|
| `scripts/autoload/replay_system.gd` | Enhanced recording, playback, ghost creation, event system |

## Testing

Unit tests cover:
- Frame data creation with new fields
- Sound event detection (shots, hits, deaths)
- Color application to ghost sprites
- Floor cleanup and progressive re-addition
- Ghost bullet trail creation
- Player trail creation and management

## Round 2: User Feedback (2026-02-07)

After the initial fix, the repository owner tested and reported 4 remaining issues:

1. **Projectiles still not visible** - Ghost bullets used programmatic 12x4 Image sprites, which were too small
2. **Blood and casings present from start** - `_clean_floor()` hid originals but `_update_replay_blood_decals()` immediately spawned all baseline decals from frame 0
3. **No visual effects for hits and last chance** - `HitEffectsManager.on_player_hit_enemy()` modified `Engine.time_scale` during replay, and penultimate hit effects were not recorded/replayed at all
4. **Grenade appears as square** - Grenade ghosts used 12x12 programmatic green squares instead of actual grenade textures

### Root Causes (Round 2)

| Issue | Root Cause |
|-------|-----------|
| Invisible bullets | Programmatic `Image.create(12, 4)` sprite is visually different from `Bullet.tscn` which uses `PlaceholderTexture2D(16, 4)` with modulate and Line2D trail |
| Blood/casings from start | Recording captures ALL existing blood/casings each frame; frame 0 already has baseline state. `_spawned_blood_count` started at 0, so all frame-0 decals were spawned immediately |
| No hit effects | `on_player_hit_enemy()` sets `Engine.time_scale = 0.8` which interferes with replay timing. Penultimate hit effect requires player health monitoring, not available during replay |
| Square grenade | `Image.create(12, 12)` filled with green creates a square, not a grenade sprite |

### Fixes Applied (Round 2)

| Fix | Description |
|-----|-------------|
| Bullet visibility | Load actual `Bullet.tscn` scene for ghost bullets, preserving original sprite and trail visuals |
| Floor baseline | Track `_baseline_blood_count` / `_baseline_casing_count` from frame 0; only spawn decals/casings that appeared AFTER recording started |
| Hit effects | `_trigger_replay_hit_effect()` calls `_start_saturation_effect()` directly without time slowdown; added penultimate hit event recording and replay |
| Grenade sprite | Load actual grenade texture from recorded `texture_path`; record grenade sprite texture path and rotation during recording |

### Data Files

- `game_log_20260207_064448.txt` - Game log from owner's testing session showing replay issues

## Round 3: C# ReplayManager Discovery (2026-02-07)

During self-review, the game log revealed `[ReplayManager] ReplayManager ready (C# version loaded and _Ready called)`,
proving the game uses `Scripts/Autoload/ReplayManager.cs` (registered in `project.godot`), **not** the GDScript
`scripts/autoload/replay_system.gd`. All Round 2 fixes were applied to the wrong file.

### Root Cause

`project.godot` line 31 registers: `ReplayManager="*res://Scripts/Autoload/ReplayManager.cs"`.
The C# version is a full rewrite of the GDScript for Godot 4.3 binary tokenization bug workarounds.
It had the exact same 4 issues as the GDScript version:

| Issue | C# Root Cause |
|-------|---------------|
| Invisible bullets | `CreateProjectileGhost("bullet")` used `GradientTexture2D(16, 4)` — no Line2D trail |
| Blood from start | `SpawnImpactEventsUpToTime()` started at index 0, spawning pre-existing blood decals |
| No hit effects | No call to HitEffectsManager/PenultimateHitEffectsManager during playback |
| Square grenade | `CreateProjectileGhost("grenade")` used `GradientTexture2D(12, 12)` radial green circle |
| No penultimate | Player health not recorded; no penultimate detection during replay |

### Fixes Applied (Round 3 — C# ReplayManager.cs)

| Fix | Description |
|-----|-------------|
| Bullet ghost | `CreateBulletGhost()` loads actual `Bullet.tscn` scene with `DisableNodeProcessing()` — preserves sprite, Line2D trail |
| Grenade ghost | `CreateGrenadeGhost(texturePath)` loads actual grenade texture; `GrenadeFrameData` records texture path and rotation during recording |
| Blood baseline | `_baselineImpactEventCount` computed from events at frame 0 time; `_nextImpactEventIndex` starts after baseline |
| Hit effects | `TriggerReplayHitEffect()` calls `_start_saturation_effect()` directly (no time slowdown) on enemy death |
| Penultimate effects | `PlayerHealth` recorded per frame; `TriggerReplayPenultimateEffect()` triggers visual effect (saturation+contrast) when health drops to ≤1 HP, immediately restoring `Engine.TimeScale` |

## Lessons Learned

1. **Record visual state, not just spatial state** - Replay fidelity requires capturing the full visual representation (colors, effects) not just positions
2. **Event detection via state diff** - When direct event hooking is impractical, state comparison between frames can reliably detect events
3. **Don't override visual properties globally** - Ghost entity modulate should be per-sprite, not recursive on the entire tree
4. **Progressive state matters** - Floor effects (blood, casings) need temporal tracking for realistic replay
5. **Use actual scene assets for ghosts** - Loading the real scene (Bullet.tscn) instead of creating programmatic sprites ensures visual fidelity
6. **Track baseline state** - Cumulative data (blood, casings) needs a baseline offset so only NEW items are spawned during replay
7. **Separate visual from timing effects** - During replay, screen effects (saturation) should work but time manipulation (Engine.time_scale) must not interfere with playback
8. **Verify which file is actually loaded** - Check `project.godot` autoload registrations and game logs to confirm the correct file is being modified
9. **C# type strictness** - Godot C# API uses `double` for `Engine.TimeScale`, not `float`. Always verify the return types when working across GDScript (which uses float/Variant) and C# (which enforces strict numeric types)

## Round 4: CI Build Failure - Windows Export (2026-02-07)

### Problem

The "Build Windows Portable EXE" workflow failed on the "Build .NET project" step with:

```
error CS0266: Cannot implicitly convert type 'double' to 'float'.
An explicit conversion exists (are you missing a cast?)
```

Location: `Scripts/Autoload/ReplayManager.cs` line 2141, column 44.

### Root Cause

In `TriggerReplayPenultimateEffect()`, the code saved `Engine.TimeScale` to a `float` variable:

```csharp
float savedTimeScale = Engine.TimeScale;  // ERROR: Engine.TimeScale returns double
```

In Godot's C# API, `Engine.TimeScale` is of type `double`, not `float`. C# does not allow implicit narrowing conversions from `double` to `float` (unlike GDScript where numeric types are loosely typed).

This error was introduced in the Round 3 fixes when the penultimate effect handling was added to the C# ReplayManager.

### Fix

Changed the variable type from `float` to `double`:

```csharp
double savedTimeScale = Engine.TimeScale;  // Correct: matches Engine.TimeScale's return type
```

### CI Logs

- `ci-build-failure-21778354821.log` - Full build log from the failed Windows Export workflow run
