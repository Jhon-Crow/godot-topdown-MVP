# Case Study: Issue #1654 — Eternal Time Stop After Drone Explosion

**Game:** godot-topdown-MVP
**Issue:** `fix вечная остановка времени после взрыва дрона` (fix eternal time stop after drone explosion)
**File:** `scripts/autoload/last_chance_effects_manager.gd`
**Severity:** Critical — renders the game unplayable until scene restart
**Log file:** `docs/case-studies/issue-1654/game_log_20260327_223931.txt`

---

## Overview

The `LastChanceEffectsManager` singleton provides a dramatic time-freeze effect used on hard difficulty. In addition to the threat-triggered variant (once per life), it can be triggered by grenade and drone explosions multiple times. When a new LastChance effect begins at the same moment a previous effect's 400ms visual fade-out is still running, the state machine enters an inconsistent combination: `_is_fading_out = true` and `_is_effect_active = true` simultaneously. The fade-out completion path then calls `set_process(false)` unconditionally, terminating the per-frame timer that drives the new effect. Because `_is_effect_active` is never cleared and all non-player nodes remain disabled, the game world freezes permanently until the player restarts the scene.

---

## Timeline

All timestamps are wall-clock time from `game_log_20260327_223931.txt`.

| Time     | Log line | Event |
|----------|----------|-------|
| 22:40:30 | —        | 1st drone explodes; 1st LastChance effect triggered (2s duration) |
| 22:40:32 | —        | 1st LastChance ends normally; fade-out begins |
| 22:40:32 | —        | Fade-out completes; `set_process(false)` called safely |
| 22:40:43 | —        | 2nd drone explodes; 2nd LastChance triggered after fade-out already done |
| 22:40:45 | 5210     | "Ending last chance effect" — 2nd effect ends; `_is_effect_active = false` |
| 22:40:45 | 5569     | "Starting visual effects fade-out over 400ms" — `_is_fading_out = true` |
| 22:40:45 | 5573     | "Drone EXPLODED" — 3rd drone detonates, ~same frame as fade-out start |
| 22:40:45 | 5575     | "Grenade explosion triggering last chance effect for 2.00 seconds" — guard `_is_effect_active == false` passes |
| 22:40:45 | 5576     | "Starting last chance effect:" — `_is_effect_active = true`; now both flags are `true` simultaneously |
| 22:40:46 | 6036     | "Visual effects fade-out complete" — `_complete_fade_out()` calls `set_process(false)` **unconditionally** |
| 22:40:46 | —        | `_process` disabled; 3rd effect timer never fires; time frozen permanently |
| 22:41:06 | 6582     | "GameManager restart_scene()" — player restarts after 21 seconds of frozen game |
| 22:41:06 | 6596     | "Resetting all effects (scene change detected)" — `reset_effects()` finally clears state |

---

## Root Cause Analysis

The `LastChanceEffectsManager` manages two pieces of state that are treated as mutually exclusive but are not protected against simultaneous activation:

- `_is_effect_active` — indicates a time-freeze effect is running and its timer must be polled in `_process`.
- `_is_fading_out` — indicates the 400ms visual fade-out from a *previous* effect is running.

The `_process` function gives priority to the fade-out path via an early `return`:

```gdscript
if _is_fading_out:
    _update_fade_out()
    return          # <-- new effect's timer check is never reached
```

When both flags are `true` at the same time, every call to `_process` exits early, and the new effect's elapsed-time check is bypassed indefinitely. After approximately 400ms, `_complete_fade_out()` fires:

```gdscript
func _complete_fade_out() -> void:
    _is_fading_out = false
    _remove_visual_effects()
    set_process(false)   # <-- unconditional; kills the timer for the new effect
```

After this point:

1. `_process` is disabled.
2. `_is_effect_active` is still `true`.
3. The duration check that would call `_end_last_chance_effect()` never runs.
4. All non-player nodes remain in `PROCESS_MODE_DISABLED`.
5. The game world is permanently frozen.

The race condition is not timing-sensitive in the strict sense — it requires only that a drone explodes during the 400ms window between `_end_last_chance_effect()` and `_complete_fade_out()`. With multiple drones in the arena this window is hit routinely.

---

## Code Analysis

### State machine entry point: `trigger_grenade_last_chance`

```gdscript
func trigger_grenade_last_chance(duration_seconds: float) -> void:
    if _is_effect_active:
        return
    # ...
    _start_last_chance_effect(duration_seconds, true)
```

The guard `if _is_effect_active: return` correctly prevents a new effect from starting while one is already running. However it does **not** check `_is_fading_out`. At the moment the 3rd drone explodes, `_is_effect_active` is `false` (the 2nd effect has ended) while `_is_fading_out` is `true`, so the guard passes and `_start_last_chance_effect` is called.

### `_start_last_chance_effect` (before fix)

```gdscript
func _start_last_chance_effect(...) -> void:
    if _is_effect_active:
        return
    # _is_fading_out not cancelled here — BUG

    _is_effect_active = true
    set_process(true)
    # ...
```

`set_process(true)` re-enables processing correctly, but `_is_fading_out` is left as `true`, which means `_process` immediately routes to `_update_fade_out()` and returns before reaching the duration timer.

### `_complete_fade_out` (before fix)

```gdscript
func _complete_fade_out() -> void:
    _is_fading_out = false
    _remove_visual_effects()
    set_process(false)   # unconditional disable — BUG
```

This function has no awareness that a new effect may have started during its 400ms window. Calling `set_process(false)` here is safe only when no effect is active.

### `_process` early-return ordering

```gdscript
func _process(delta: float) -> void:
    if _player == null or not is_instance_valid(_player):
        _find_player()

    if _is_fading_out:
        _update_fade_out()
        return              # effect timer blocked by this return

    if _is_effect_active:
        # duration check here
```

The ordering itself is not inherently wrong — the fade-out should take visual priority. The defect is that the two flags are never prevented from being `true` simultaneously.

---

## Fix Description

Two targeted changes to `_start_last_chance_effect` and `_complete_fade_out` close the race condition.

### Change 1: Cancel any ongoing fade-out when a new effect starts

In `_start_last_chance_effect`, clear `_is_fading_out` before activating the new effect. This ensures `_process` will reach the duration timer check on the very next frame.

```gdscript
func _start_last_chance_effect(duration_seconds: float = FREEZE_DURATION_REAL_SECONDS, is_grenade: bool = false) -> void:
    if _is_effect_active:
        return

    # Cancel any ongoing fade-out from a previous effect before starting a new one
    if _is_fading_out:
        _is_fading_out = false
        _log("Cancelled ongoing fade-out for new effect")

    _is_effect_active = true
    # ...
```

The visual fade-out from the previous effect is discarded; the new effect's own fade-out will run in full when it ends. This is visually acceptable because the new time-freeze immediately re-applies the full shader effect.

### Change 2: Guard `set_process(false)` against a concurrently active effect

In `_complete_fade_out`, only disable `_process` when no new effect has started:

```gdscript
func _complete_fade_out() -> void:
    _is_fading_out = false
    _remove_visual_effects()

    # Issue #1157: Disable _process after effect is fully done — nothing to update.
    # But don't disable if a new effect started during the fade-out.
    if not _is_effect_active:
        set_process(false)
```

This is a defence-in-depth measure. With Change 1 in place, `_is_fading_out` is always cleared before `_is_effect_active` is set, so this guard would not have been needed for the exact scenario in the log. It protects against any future path where `_is_effect_active` could be set while `_is_fading_out` is still `true`.

Both changes were applied to `scripts/autoload/last_chance_effects_manager.gd` (lines 427–433 and 767–768 respectively).

---

## Test Coverage

The following scenarios should be verified to confirm the fix and guard against regression:

- **Happy path — isolated effect:** A single drone explodes; the LastChance effect runs for its full duration, fades out, and `set_process(false)` is called. All non-player nodes resume normal processing. Confirmed by existing behaviour before the bug was introduced.

- **Back-to-back explosions (no overlap):** A second drone explodes after the first effect's fade-out has fully completed (`_is_fading_out = false`). The second effect starts normally. This is the common case observed in the early log entries (1st and 2nd drones).

- **Explosion during fade-out window — the regression case:** A third drone explodes within the 400ms fade-out of the second effect. With the fix:
  - `_start_last_chance_effect` clears `_is_fading_out`.
  - `_process` reaches the duration timer on the next frame.
  - After 2s, `_end_last_chance_effect` is called and the 3rd effect ends normally.
  - `_complete_fade_out` eventually calls `set_process(false)` (guard passes because `_is_effect_active` is `false`).
  - No permanent freeze occurs.

- **Explosion during fade-out, immediately followed by another explosion:** Chain scenario — confirm that repeated overlap does not accumulate stale state.

- **Scene restart during an active effect:** Existing `reset_effects()` path; confirm `_is_fading_out` and `_is_effect_active` are both cleared and `set_process(true)` is called to resume player search.

- **Replay mode:** Verify that `replay_mode = true` continues to skip time-freeze and process-mode changes while the fade-out state is still managed correctly.
