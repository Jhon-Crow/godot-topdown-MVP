# Case Study: Issue #1540 — Drone Operator dodges in place, should sidestep visibly

## Summary

The Drone Operator enemy (дроновод) in ACTIVE phase was performing an **aggressive closing dash toward the player** when threatened by bullets, instead of a visible **sideways evasion**. The result was that the dodge was hard to perceive — the operator was moving toward the player (already the expected combat behaviour) rather than stepping out of the bullet's path.

---

## Timeline / Sequence of Events

| Time | Event |
|------|-------|
| ~09:49:22 | EnemyDroneOperator spawned at (669, 360). VR headset + tablet confirmed. Drone deployed successfully. |
| ~09:49:37 | Drone entered COMBAT/kamikaze mode. |
| ~09:49:38 | Drone destroyed (2 hits). Operator → ACTIVE phase, silenced pistol, laser sight, reaction_delay=0. |
| ~09:49:58 | First bullet entered threat sphere. `try_dash_from_threat` called. |
| ~09:49:58 | Dash direction logged as `(-0.99, 0.14)` — pointing **toward the player**, not sideways. |
| ~09:49:58 | `[DroneOperator] Aggressive dash toward player` logged ~50+ times per second (log spam during active dash). |
| ~09:49:59 | Operator hit (hp 2→1), then killed. |
| ~09:50:06 | Second operator spawned. Cover seek timed out (3.0s). |
| ~09:50:19 | Same pattern: dash dir `(-0.84,-0.54)` toward player, operator killed. |

---

## Root Cause Analysis

### Primary Bug: Wrong Dash Direction

**File:** `scripts/components/drone_operator_component.gd`, function `try_dash_from_threat()` (line 271).

The function computed the dash direction as:
```gdscript
var to_player: Vector2 = (player.global_position - enemy_pos).normalized()
try_dash(to_player)
```

This is the **vector pointing directly at the player** — so the operator dashed *toward* the player whenever a bullet entered the threat sphere. The comment even stated "aggressive closing dash".

This direction was intentionally set in the previous fix (#1532, commit `3f67ac87`) to close the distance to the player. However, that created a new issue (#1540): a dash toward the player is indistinguishable from normal combat movement, making the evasion invisible to the player.

### Secondary Issue: Dash Distance Too Large

With `DASH_SPEED_MULTIPLIER=6.0` and `DASH_DURATION=0.2s` at `combat_move_speed≈320 px/s`:
```
displacement = 320 × 6.0 × 0.2 = 384 px
```
This is far too large for a "sidestep" — it would fling the operator across the room sideways.

---

## Fix Applied

### 1. Dash direction: perpendicular to bullet trajectory

`try_dash_from_threat()` now:
1. Reads the velocity of the first bullet in the threat sphere.
2. Computes both perpendicular directions (left and right of bullet travel).
3. Picks the side that moves **away from the player** (lower dot product with `to_player`).
4. Falls back to 90° perpendicular to the player direction if no bullet velocity is available.

This makes the evasion clearly visible — the operator visibly steps out of the bullet path.

### 2. Dash parameters tuned for 20-100 px sidestep

| Parameter | Before (Issue #1532) | After (Issue #1540) |
|-----------|---------------------|---------------------|
| `DASH_DURATION` | 0.20 s | 0.15 s |
| `DASH_SPEED_MULTIPLIER` | 6.0 | 1.25 |
| Displacement @ 320 px/s | 384 px | **60 px** ✓ |

60 px is within the requested 20–100 px range, clearly visible, and does not fling the operator across the map.

### 3. Log message updated

`"Aggressive dash toward player"` → `"Sideways evade: dir=(...)"` to reflect the new behaviour.

---

## Tests Added (`tests/unit/test_drone_operator.gd`)

- `test_operator_dash_duration_is_short_for_sidestep` — verifies `DASH_DURATION = 0.15s`
- `test_operator_sidestep_distance_within_range` — verifies 20–100 px at 320 px/s
- `test_evade_direction_is_perpendicular_to_bullet_velocity` — verifies perpendicularity
- `test_evade_picks_side_away_from_player` — verifies correct side selection

---

## References

- Issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1540
- Related fix (changed direction to toward player): commit `3f67ac87` (Issue #1532)
- Log file: `game_log_20260326_094908.txt`
