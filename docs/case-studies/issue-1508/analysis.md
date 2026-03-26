# Case Study: Issue #1508 — Drone Spiral Search Movement

## Issue Summary

**Title:** update дрон и дроновод
**Author:** Jhon-Crow
**Linked issue:** Continues from #1417
**Reported:** 2026-03-26

**Problem statement (translated from Russian):**
> The drone spawns but stands still (until it enters combat mode). It should move in an expanding spiral around the enemy in the VR headset.

---

## Timeline / Sequence of Events

| Time | Event |
|------|-------|
| ~06:18:56 | `EnemyDroneOperator` spawns, reaches cover, begins deploy timer |
| 06:18:58 | Drone spawned at (509, 900); `_ready` completes — `state=SEARCHING` |
| 06:18:58 | `DroneOperator` transitions to `CONTROLLING` phase |
| 06:18:58–06:19:01 | **Drone hovers stationary** — no movement logged |
| 06:19:01 | Player comes within LOS; drone transitions to `COMBAT` immediately |
| 06:19:03 | Drone explodes at (655, 816) after kamikaze flight (~2 s after spawn) |

The window between spawn and combat was ~3 seconds in log 1, ~0 seconds in log 3 (player already in LOS on spawn). In none of the logs does the drone move during `SEARCHING` state.

---

## Root Cause Analysis

### Code location
**File:** `scripts/objects/drone.gd`
**Function:** `_update_searching()` (prior to fix: lines ~118–130)

### Root cause
The `_update_searching()` function set `velocity = Vector2.ZERO` unconditionally whenever the player was not in line-of-sight:

```gdscript
# BEFORE fix (Issue #1508)
func _update_searching() -> void:
    if _player.has_method("is_invisible") and _player.is_invisible():
        velocity = Vector2.ZERO
        move_and_slide()
        return

    if _has_line_of_sight():
        _transition_to_combat()
        return

    velocity = Vector2.ZERO   # <-- drone stands still
    move_and_slide()
```

No patrol, orbit, or movement path was calculated. The `_operator` reference (set by `initialize_drone()`) was never used during the `SEARCHING` state — it was only used to pass context, not to drive movement.

### Why the operator reference existed but wasn't used
Issue #1417 established the drone's two-state behavior (SEARCHING / COMBAT). The SEARCHING state was described as "vision like a normal enemy, 360° FOV" in #1417, with no explicit movement requirement — the original intent was for the drone to hover and scan. Issue #1508 extends this requirement to add active spiral search behavior.

---

## Evidence from Game Logs

All three logs confirm the drone does not move during SEARCHING:
- No position change logged between spawn and combat transition
- `_update_searching()` never emits any movement log messages (confirmed by absence)
- `COMBAT mode activated` fires 1–3 s after spawn, always from a stationary position matching the spawn offset

From `game_log_20260326_062242.txt`:
```
[06:22:53] [INFO] [Drone] _ready complete (state=SEARCHING, player=Player, nav=found)
[06:22:53] [INFO] [DroneOperator] Drone deployed at (364, 357)
...
[06:22:55] [INFO] [Drone] COMBAT mode activated — kamikaze flight toward player!
```
The drone jumped directly from spawn to COMBAT with no movement in between.

---

## Solution Implemented

### Approach: Archimedean Spiral orbit around operator

The drone orbits the operator (the enemy wearing the VR headset) in an expanding spiral using parametric circular motion with a linearly increasing radius:

```
angle(t)  = angle(0) + SPIRAL_ANGULAR_SPEED × t
radius(t) = min(SPIRAL_START_RADIUS + SPIRAL_EXPAND_RATE × t, SPIRAL_MAX_RADIUS)
target(t) = operator_pos + Vector2(cos(angle), sin(angle)) × radius
velocity  = normalize(target - drone_pos) × SEARCH_SPEED
```

### Constants chosen
| Constant | Value | Rationale |
|----------|-------|-----------|
| `SPIRAL_START_RADIUS` | 60 px | Small enough to stay near the operator at spawn |
| `SPIRAL_MAX_RADIUS` | 350 px | Covers the typical room width; stops unbounded drift |
| `SPIRAL_EXPAND_RATE` | 25 px/s | ~11 s to reach max radius; gives the player time to react |
| `SPIRAL_ANGULAR_SPEED` | 1.8 rad/s | ~0.29 rev/s — fast enough to look active, slow enough to not feel erratic |

### Files changed
- `scripts/objects/drone.gd` — spiral constants, state variables, `_update_searching(delta)` implementation
- `tests/unit/test_drone.gd` — 8 new tests covering spiral constants, angle advance, radius expansion, capping, velocity magnitude, and geometry

### Fallback behavior
If the operator node becomes invalid (freed before the drone), the drone reverts to hovering in place — preserving prior safe behavior.

---

## Alternative Solutions Considered

| Approach | Pros | Cons |
|----------|------|------|
| **Random walk / Brownian motion** | Simple | Unpredictable, may cluster near spawn |
| **NavigationAgent2D path to player** | Uses existing nav mesh | Drone finds the player immediately — defeats the searching phase |
| **Fixed orbit (constant radius)** | Simple | Drone never expands coverage area |
| **Expanding spiral (chosen)** | Systematic area coverage, visually coherent, maps to real drone search patterns | Slightly more math |

The expanding spiral is the canonical algorithm for search-and-rescue drone coverage (Archimedean spiral sweep), making it the most authentic and gameplay-sensible choice.

---

---

## Follow-up: Obstacle Avoidance & Enemy Non-Collision (PR #1509 comment, 2026-03-26)

### New symptom reported (Jhon-Crow, 2026-03-26 07:01)

> "The drone should navigate around obstacles and not have collisions with (not push) other enemies. Right now when the drone hits the first obstacle it gets stuck against the wall."
>
> Evidence: `game_log_20260326_070154.txt` — drone spirals normally until it reaches a wall, then stops moving.

### Root cause (second issue)

The initial spiral implementation computed the orbit target using pure trigonometry and then set velocity directly toward that target:

```gdscript
var orbit_target = operator_pos + Vector2(cos(angle), sin(angle)) * radius
velocity = (orbit_target - global_position).normalized() * SEARCH_SPEED
```

This is a **straight-line move** — it does not use the navigation mesh. When the orbit target is on the other side of a wall, the drone tries to fly through the wall and `move_and_slide()` stops it cold.

Additionally, while the scene (`Drone.tscn`) already had `NavigationAgent2D.avoidance_enabled = true`, the `velocity_computed` signal was never connected, so ORCA never influenced the drone's velocity. The drone could still physically push other enemies.

### Fix applied (second iteration)

**Wall avoidance:** `_update_searching()` now sets `_nav_agent.target_position = orbit_target` and moves toward `_nav_agent.get_next_path_position()` rather than directly toward `orbit_target`. The nav agent computes a path that routes around walls using the scene's NavigationRegion2D mesh.

**Enemy non-collision (ORCA):** Added `_avoidance_velocity` state variable and `_on_avoidance_velocity_computed()` callback. The callback is connected to `_nav_agent.velocity_computed` in `_ready()` (only when `avoidance_enabled` is true). Each physics frame the intended velocity is fed to `_nav_agent.set_velocity()`, which triggers ORCA to compute a safe velocity that steers the drone away from other agents.

```gdscript
# Issue #1508 (second fix) — wall-avoiding + non-pushing spiral
if _nav_agent:
    _nav_agent.target_position = orbit_target
    var next_pos = _nav_agent.get_next_path_position()
    intended_dir = global_position.direction_to(next_pos)
else:
    intended_dir = global_position.direction_to(orbit_target)

var intended_vel = intended_dir * SEARCH_SPEED
if _nav_agent and _nav_agent.avoidance_enabled:
    _nav_agent.set_velocity(intended_vel)
    velocity = _avoidance_velocity if _avoidance_velocity.length_squared() > 0.01 else intended_vel
else:
    velocity = intended_vel
```

This pattern is identical to how `enemy.gd` handles ORCA-assisted searching movement (see `enemy.gd` line 2417).

### Evidence from new log

From `game_log_20260326_070154.txt`:

```
[07:02:07] [INFO] [Drone] NavigationAgent2D found and configured
[07:02:07] [INFO] [Drone] _ready complete (state=SEARCHING spiral, player=Player, nav=found)
[07:02:16] [INFO] [Drone] COMBAT mode activated — kamikaze flight toward player! (spiral_angle=16.20, spiral_radius=285.0)
```

The drone navigated for ~9 seconds (spiral_radius grew from 60 → 285 px, consistent with `SPIRAL_EXPAND_RATE=25 px/s × 9 s = 285`), suggesting the spiral itself worked. The stuck-at-wall issue is consistent with the direct-vector movement reaching a wall perpendicular to the orbit direction.

---

## References

- [Archimedean Spiral - Wikipedia](https://en.wikipedia.org/wiki/Archimedean_spiral)
- [Drone Search Pattern – UAV search and rescue literature](https://www.mdpi.com/2504-446X/3/1/26) — expanding spiral is a standard coverage pattern for single-UAV area search
- Godot 4 `CharacterBody2D.move_and_slide()` — used for collision-aware movement
- Godot 4 `NavigationAgent2D` — pathfinding + ORCA velocity obstacle avoidance
- Issue #1417 — original drone implementation (SEARCHING hover + COMBAT kamikaze)
- PR #1444 — merged fix for issue #1417 (drone AI merged into drone.gd)
- `scripts/objects/enemy.gd` line 2417 — reference pattern for ORCA-assisted searching movement
