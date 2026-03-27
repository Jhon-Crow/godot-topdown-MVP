# Case Study: Issue #1542 — Drone Miss Behavior in Combat Mode

## Summary

In combat mode, after the drone misses the player, it fails to slow down and re-aim. Instead, it continues at full speed (675 px/s) with high momentum (drift factor 0.93), causing it to overshoot repeatedly. A player standing still can survive 4–5 miss passes without dodging.

## Root Cause Analysis

### The `_update_combat()` function (drone.gd lines 200–238)

```gdscript
var desired_dir: Vector2 = to_player.normalized()  # or nav agent direction
_current_move_dir = (_current_move_dir * DRIFT_FACTOR + desired_dir * (1.0 - DRIFT_FACTOR)).normalized()
velocity = _current_move_dir * COMBAT_SPEED  # always full speed
```

**Problems:**
1. **No miss detection**: The drone never checks whether it has flown past the player.
2. **Always full speed**: `COMBAT_SPEED = 675.0` is applied unconditionally — no phase for deceleration/re-aiming.
3. **High drift makes re-orienting slow**: With `DRIFT_FACTOR = 0.93`, the drone corrects its direction at only 7% per frame. At 60 fps it takes ~40 frames (~0.67 s) to re-aim after an overshoot.

### Miss Geometry

A "miss" occurs when the drone has passed the player — i.e., the dot product of `_current_move_dir` and `direction_to_player` becomes negative. This means the drone is flying away from the player.

```
dot(velocity_dir, to_player_dir) < 0  →  drone is moving away → it missed
```

## Known Solutions / Patterns

### 1. State-machine approach (common in game AI)
Add a sub-state `COMBAT_REAIMING` that activates on miss detection and applies a reduced speed + stronger steering correction, then returns to full-speed attack once re-aligned.

### 2. Speed-scaling by alignment angle (continuous)
Instead of a hard sub-state, scale speed continuously:
```
speed = COMBAT_SPEED * max(0.3, dot(move_dir, to_player_dir))
```
When aligned (dot=1): full speed. When perpendicular (dot=0): 30% speed. When pointing away (dot<0): 30% speed.

### 3. Reset drift on miss
When a miss is detected, partially or fully reset `_current_move_dir` toward the player to allow faster re-aiming.

## Proposed Solution

**Combined approach** (state machine + continuous speed scaling):

1. Detect miss: when `dot(_current_move_dir, to_player_dir) < MISS_THRESHOLD` (e.g., -0.2), enter `_is_reaiming = true`.
2. While re-aiming: use a lower drift factor (`REAIM_DRIFT_FACTOR = 0.7`) so steering correction happens in ~3–5 frames instead of 40.
3. Scale speed down: `REAIM_SPEED = 200.0` (≈SEARCH_SPEED × 1.33) — slow enough to allow correction.
4. Exit re-aiming: when dot product exceeds `REAIM_EXIT_THRESHOLD` (e.g., 0.7), resume full-speed attack.

This preserves the "dangerous kamikaze drone" feel while making misses meaningful — the player must dodge because the drone will slow down, turn, and charge again.

## Parameters

| Parameter | Value | Rationale |
|---|---|---|
| `MISS_DOT_THRESHOLD` | -0.2 | Drone must be clearly flying away before slowing |
| `REAIM_DRIFT_FACTOR` | 0.70 | ~30% correction per frame → ~5 frames to align |
| `REAIM_SPEED` | 220.0 | Visible slowdown, still threatening |
| `REAIM_EXIT_DOT` | 0.70 | Re-enters full attack when roughly aimed at player |

## Post-Merge Feedback (PR #1543, 2026-03-26)

The owner (Jhon-Crow) tested the initial fix and reported two additional bugs:

### Bug 1: Re-aiming triggered mid-overshoot ("zanос")

**Observed behavior:** Slowdown and re-aiming began as soon as `alignment < -0.2`, while the drone's skid/overshoot was still in progress. The owner expected re-aiming to begin only **after** the full zanос (skid) completes.

**Root cause:** The original miss-detection condition `alignment < MISS_DOT_THRESHOLD` fires on the first frame the dot drops below threshold — but the drone's drift is still carrying it further away at that point. The overshoot bottom (where the drone naturally starts turning back under the existing drift) had not been reached yet.

**Fix:** Added `_prev_alignment` tracking. Re-aim now triggers when `alignment < MISS_DOT_THRESHOLD AND alignment > _prev_alignment` — i.e., only after alignment has bottomed out and begun to recover. This ensures slowdown/re-aiming begins exactly when the zanос is complete.

### Bug 2: Drone gets stuck inside enemy bodies

**Observed behavior:** The drone could physically collide with and get stuck on other enemy characters.

**Root cause:** The Drone's `collision_mask = 7` (bits 1+2+4) included bit 2 (enemy layer). Ground-level enemies have `collision_layer = 2`, so the drone would collide with them physically. A real quadcopter drone flies **over** ground-level obstacles — it should not be blocked by them.

**Fix:** Changed `collision_mask` from `7` to `5` (bits 1+4 — walls and player only) in `Drone.tscn`. The drone's `HitArea` collision (mask=16 for bullet detection) is unchanged. Enemy bodies no longer block the drone's movement path.

## References

- Issue #1508 (prior drone work): established DRIFT_FACTOR=0.93, COMBAT_SPEED=675
- Game Log `game_log_20260326_113141.txt`: confirmed re-aim working in initial fix, revealed stuck-in-enemy and mid-zanос-trigger bugs
- Game AI Pro (Greg Costikyan): pursuer steering corrections
- "Programming Game AI by Example" (Buckland, Ch. 3): velocity-based steering behaviors
