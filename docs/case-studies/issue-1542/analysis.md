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

## References

- Issue #1508 (prior drone work): established DRIFT_FACTOR=0.93, COMBAT_SPEED=675
- Game AI Pro (Greg Costikyan): pursuer steering corrections
- "Programming Game AI by Example" (Buckland, Ch. 3): velocity-based steering behaviors
