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

## Data Files

- `game_log_20260207_180552.txt` - Full game log from the issue reporter (original bug)
- `game_log_20260207_202720.txt` - Game log after first fix attempt (effects missing)
