# Case Study: Issue #597 - Fix Memory Replay Mode

## Issue Summary

**Title**: fix memory replay mode
**Reporter**: Jhon-Crow
**Date**: 2026-02-07

### Reported Problems (translated from Russian)

1. Last chance and explosion effects do not turn off during replay
2. Effects do not turn on stably

### Follow-up Feedback

After initial fix attempt (visual effects completely disabled):
- **"визуальные эффекты не появились"** = "Visual effects did not appear"
- The initial fix was too aggressive - it removed ALL visual effects during replay

## Timeline of Events (from game log)

### Session 1 (game_log_20260207_180552.txt) - Original Bug

| Time | Event |
|------|-------|
| 18:05:52 | Game starts, BuildingLevel loads with 10 enemies |
| 18:05:52 | Replay recording begins |
| 18:05:52-18:06:40 | Player completes level (multiple restarts, final run ~37.7s) |
| 18:06:40 | Level completed, replay recording stops (2418 frames, 37.70s) |
| 18:06:43 | "Watch Replay" button created |
| 18:06:46 | User clicks "Watch Replay" - Ghost mode starts |
| 18:06:46 | DisableAllReplayEffects called (correct behavior) |
| 18:06:53 | **User switches to Memory mode** |
| 18:06:53 | DisableAllReplayEffects called, CinemaEffects enabled (correct) |
| 18:07:01 | **BUG**: PowerFantasy triggers 300ms time slowdown during replay |
| 18:07:08 | Playback speed set to 4x |
| 18:07:24 | **BUG**: PowerFantasy grenade triggers LastChance 2s full scene freeze |
| 18:07:24 | LastChance freezes ALL scene nodes (walls, casings, replay ghosts) |
| 18:07:24 | LastChance applies sepia shader overlay |
| 18:07:26 | LastChance effect ends, unfreezes ~80 casings |
| 18:07:29 | **BUG**: PowerFantasy triggers another 300ms time slowdown |
| 18:07:32 | **BUG**: PowerFantasy triggers yet another 300ms time slowdown |
| 18:07:38 | Log ends with only 42/55 footprints spawned (replay incomplete) |

### Session 2 (game_log_20260207_202720.txt) - After First Fix Attempt

The first fix attempt completely disabled penultimate, power fantasy kill, and
grenade effects during replay. While this prevented the time freeze bugs, it
removed all visual effects, making the replay feel flat and lifeless.

## Root Cause Analysis

### Root Cause 1: Scene Tree Freeze During Replay

In `ReplayManager.cs`, the `TriggerReplayPowerFantasyGrenade()` method called
`PowerFantasyEffectsManager.on_grenade_exploded()` during Memory mode replay.
This triggered `LastChanceEffectsManager.trigger_grenade_last_chance()` which:

1. **Froze the entire scene tree** by setting all nodes (including replay ghosts) to `PROCESS_MODE_DISABLED`
2. **Applied a blue sepia shader overlay** (`sepia_intensity=0.70`, `brightness=0.60`)
3. Set the player to `PROCESS_MODE_ALWAYS` (irrelevant during replay)
4. Connected to `node_added` signal to freeze new nodes

The replay ghost entities are children of the level scene, so they got frozen too.
During the 2-second freeze, replay playback was completely halted.

### Root Cause 2: Time Scale Manipulation During Replay

`TriggerReplayPowerFantasyKill()` called `PowerFantasyEffectsManager.on_enemy_killed()`
which set `Engine.time_scale = 0.1` for 300ms. This slowed the entire game engine,
including replay playback, to 10% speed.

Similarly, `TriggerReplayHitEffect()` called `HitEffectsManager.on_player_hit_enemy()`
which set `Engine.time_scale = 0.8`.

And `TriggerReplayPenultimateEffect()` called `_start_penultimate_effect()` which
set `Engine.time_scale = 0.1`.

### Root Cause 3: Effects Not Aware of Replay State

Neither `LastChanceEffectsManager`, `PowerFantasyEffectsManager`, `HitEffectsManager`,
nor `PenultimateHitEffectsManager` had any concept of replay mode. They performed
full gameplay effects (time freeze, time scale, process mode changes) regardless
of whether the game was in actual gameplay or replay playback.

## Fix Applied (v2 - replay_mode flag approach)

### Strategy: replay_mode Flag on Effect Managers

Instead of disabling effects entirely in ReplayManager.cs, we added a `replay_mode`
flag to each GDScript effect manager. When `replay_mode = true`:

- `Engine.time_scale` changes are **skipped** (prevents replay slowdown/freeze)
- `process_mode` changes are **skipped** (prevents scene tree freezing)
- **All visual effects still apply**: shader overlays, saturation boosts, enemy coloring,
  player saturation, fade-out animations

### Files Changed

1. **`scripts/autoload/hit_effects_manager.gd`**: Added `replay_mode` flag, guarded
   `Engine.time_scale` in `_start_slow_effect()` and `_end_slow_effect()`

2. **`scripts/autoload/penultimate_hit_effects_manager.gd`**: Added `replay_mode` flag,
   guarded `Engine.time_scale` in `_start_penultimate_effect()`, `_end_penultimate_effect()`,
   and `reset_effects()`

3. **`scripts/autoload/power_fantasy_effects_manager.gd`**: Added `replay_mode` flag,
   guarded `Engine.time_scale` in `_start_effect()`, `_end_effect()`, and `reset_effects()`

4. **`scripts/autoload/last_chance_effects_manager.gd`**: Added `replay_mode` flag,
   guarded `_freeze_time()`, `_push_threatening_bullets_away()`,
   `_grant_player_invulnerability()`, `_unfreeze_time()`, and `_reset_all_enemy_memory()`
   in `_start_last_chance_effect()`, `_end_last_chance_effect()`, and `reset_effects()`

5. **`Scripts/Autoload/ReplayManager.cs`**:
   - Added `SetEffectManagersReplayMode(bool)` to set the flag on all managers
   - Called in `StartPlayback()` (sets `true`) and `StopPlayback()` (sets `false`)
   - Restored full effect trigger calls in replay methods (no longer skipping effects)
   - `TriggerReplayPenultimateEffect()` calls `_start_penultimate_effect()` directly
   - `TriggerReplayPowerFantasyKill()` calls `_start_effect(300.0)` directly (bypasses difficulty check)
   - `TriggerReplayPowerFantasyGrenade()` calls `trigger_grenade_last_chance(2.0)` directly

### Why This Approach (v2) is Better Than v1

- **Full visual experience**: All shader effects, saturation, contrast, enemy/player
  coloring, and fade-out animations work during replay
- **Precise control**: Only time manipulation and process_mode changes are disabled
- **Proper cleanup**: Effect managers' internal timers still manage effect duration
  and cleanup, preventing orphaned visual effects
- **Minimal flag**: Single boolean per manager, checked only at the point of
  Engine.time_scale or process_mode modification

## Fix v3: Fixing Effects Not Appearing (2026-02-07)

### Additional Root Causes Found

After the v2 fix, the user still reported "визуальные эффекты не появились" (visual
effects did not appear). Deep analysis of both game logs revealed three additional bugs:

#### Bug 1: SeekTo() Does Not Reset _lastAppliedFrame

`SeekTo(float time)` in `ReplayManager.cs` updates `_playbackFrame` but does NOT
reset `_lastAppliedFrame`. When switching replay modes (Ghost→Memory) via
`SetReplayMode()`, `SeekTo(0.0f)` is called to restart from the beginning. But
`_lastAppliedFrame` retains the old value (e.g., 1875 for a fully-played Ghost replay).

In `PlaybackFrameUpdate()`, the condition `_playbackFrame > _lastAppliedFrame` is
checked before calling `PlayFrameEvents()`. Since `_playbackFrame` (reset to 0 by
SeekTo) is NOT greater than `_lastAppliedFrame` (still at 1875), `PlayFrameEvents()`
is NEVER called — meaning no Death/Hit events trigger effects during the entire
Memory replay after a mode switch.

**Fix**: Reset `_lastAppliedFrame = _playbackFrame - 1` in `SeekTo()`.

#### Bug 2: Effect Managers' process_mode Blocks Timers During Replay

During replay, the game tree is paused (`level.GetTree().Paused = true`). Effect
managers are autoload singletons with default `process_mode = Inherit`. When the tree
is paused, their `_process()` callbacks don't run. This means:

- Effect starts (shader becomes visible) ✓
- Timer in `_process()` never decrements → effect never ends → `_end_effect()` never called
- Fade-out animations don't play (they also run in `_process()`)

While effects technically start, their inability to properly end/fade leads to
visual artifacts and prevents subsequent effects from triggering (many effects check
`if _is_effect_active: return` at the start).

**Fix**: Set effect managers' `process_mode = Always` when entering replay mode,
restore to `Inherit` when exiting.

#### Bug 3: HasMethod May Not Find Underscore-Prefixed Methods

`TriggerReplayPowerFantasyKill()` and `TriggerReplayPenultimateEffect()` used
`HasMethod("_start_effect")` and `HasMethod("_start_penultimate_effect")` to check
before calling. GDScript methods prefixed with `_` are conventionally private, and
`HasMethod()` behavior for these may vary across Godot versions. If `HasMethod`
returns false, the effect call is silently skipped with no logging.

**Fix**: Remove `HasMethod` guard for these calls; call directly and add logging.

### Evidence from Game Logs

In **both** game logs (original bug and after v2 fix), during Memory replay playback
there are ZERO logs from any effect manager. Only `ReplayManager` logs for blood
decals, casings, and footprints appear. This pattern holds for:

- Ghost→Memory switch replays (SeekTo bug)
- Direct Memory mode replays (process_mode + HasMethod bugs)

### v3 Changes

1. **`Scripts/Autoload/ReplayManager.cs`**:
   - `SeekTo()`: Reset `_lastAppliedFrame = _playbackFrame - 1` after seeking
   - `SetEffectManagersReplayMode()`: Also set `process_mode` to `Always`/`Inherit`
   - `TriggerReplayPowerFantasyKill()`: Remove `HasMethod` guard, call directly
   - `TriggerReplayPenultimateEffect()`: Remove `HasMethod` guard, call directly
   - Added diagnostic logging to `PlayFrameEvents` and all trigger methods

## Data Files

- `game_log_20260207_180552.txt` - Full game log from the issue reporter (original bug)
- `game_log_20260207_202720.txt` - Game log after v2 fix (effects still missing)
