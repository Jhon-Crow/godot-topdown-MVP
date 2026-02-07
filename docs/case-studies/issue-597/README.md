# Case Study: Issue #597 - Fix Memory Replay Mode

## Issue Summary

**Title**: fix memory replay mode
**Reporter**: Jhon-Crow
**Date**: 2026-02-07

### Reported Problems (translated from Russian)

1. Last chance and explosion effects do not turn off during replay
2. Effects do not turn on stably

## Timeline of Events (from game log)

The game log (`game_log_20260207_180552.txt`) captures a complete session:

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

## Fix Applied

**File changed**: `Scripts/Autoload/ReplayManager.cs`

### Strategy: Visual-Only Effects During Replay

Instead of calling the full effect manager methods that modify `Engine.TimeScale`
and freeze the scene tree, the replay trigger methods now:

1. **`TriggerReplayHitEffect()`**: Only calls `_start_saturation_effect()` (visual-only)
   instead of `on_player_hit_enemy()` (which also sets `Engine.time_scale = 0.8`)

2. **`TriggerReplayPenultimateEffect()`**: Skipped entirely during replay.
   The penultimate effect sets `Engine.time_scale = 0.1` and modifies process modes.

3. **`TriggerReplayPowerFantasyKill()`**: Skipped entirely during replay.
   The hit saturation effect already provides visual feedback for kills.

4. **`TriggerReplayPowerFantasyGrenade()`**: Skipped entirely during replay.
   `SpawnExplosionFlash()` already provides the visual explosion effect.

### Why This Approach

- **Minimal change**: Only modified the replay trigger methods in ReplayManager.cs
- **No changes to effects managers**: Avoids introducing replay awareness into
  multiple GDScript singletons, which could cause regression
- **Preserves visual feedback**: Hit saturation and explosion flash still work
- **Prevents time manipulation**: No `Engine.TimeScale` changes during replay
- **Prevents scene freeze**: No `PROCESS_MODE_DISABLED` on replay ghost nodes

## Data Files

- `game_log_20260207_180552.txt` - Full game log from the issue reporter
