# Case Study: Issue #1510 — Drone Combat Movement Physics

## Problem Statement

The drone in combat mode has two main physics problems:

1. **No acceleration/deceleration** — velocity is set instantly to `COMBAT_SPEED` (450 px/s) on the first frame of combat. There is no ramp-up or ramp-down.
2. **Fixed drift** — `DRIFT_FACTOR = 0.85` controls only the direction interpolation blending ratio; it does not scale with actual speed. At low speed the drone "drifts" the same proportion as at high speed, which is physically incorrect for an air vehicle.
3. **Wall-stuck at spawn** — because the drone immediately moves at full speed with `_current_move_dir = desired_dir` on frame 1, if the navigation agent's first path point is blocked by a wall, the drone rams into it with no momentum built up for steering.

## Root Cause Analysis

### Current Code (drone.gd `_update_combat`)

```gdscript
if _current_move_dir == Vector2.ZERO:
    _current_move_dir = desired_dir
else:
    _current_move_dir = (_current_move_dir * DRIFT_FACTOR + desired_dir * (1.0 - DRIFT_FACTOR)).normalized()

velocity = _current_move_dir * COMBAT_SPEED
move_and_slide()
```

**Problems:**
- Direction is interpolated (weighted blend), but speed is always `COMBAT_SPEED` — instant acceleration from 0.
- `DRIFT_FACTOR` only affects direction turning, not how much the existing velocity "carries" at high speed.
- On the very first frame `_current_move_dir == Vector2.ZERO`, so it snaps directly to `desired_dir` and moves at full speed.

## Physics Background: Real Drone/Air Vehicle Motion

### Acceleration Model
Real quadcopter drones accelerate by increasing rotor thrust. Key characteristics:
- **Ramp-up time:** A typical racing drone reaches max speed in ~0.3–1.5 seconds (depending on throttle aggression).
- **Ramp-down:** Without active braking, air drag is the main deceleration force, which is proportional to velocity squared. Simple linear deceleration is a good game approximation.
- For game feel, a simple `lerp(current_speed, target_speed, acceleration_rate * delta)` gives smooth ramp-up.

### Drift / Inertia Model
"Drift" in game physics means: how much does the previous velocity carry forward even when the desired direction changes?

For an air vehicle vs. a ground vehicle:
- **Ground vehicle:** Friction with surface applies strong lateral correction — low drift.
- **Air vehicle:** Only air drag acts laterally, which is weaker — high drift (more inertia).
- **Speed-dependent drift:** At higher speeds, the inertial force is larger relative to the steering force, so effective drift increases with speed.

A simple model: blend current direction with desired direction, but scale the blend ratio by `(1 - speed_factor * drift_strength)`, where `speed_factor = current_speed / max_speed`.

### Existing Game Patterns
Looking at similar implementations in the codebase:
- `scripts/characters/player.gd` uses `lerp(velocity, target_velocity, friction * delta)` for smooth deceleration.
- `scripts/components/drone_operator_component.gd` uses a speed-lerp pattern for its dash evasion.
- The existing `DRIFT_FACTOR` pattern is a good foundation — it just needs to be speed-scaled.

## Proposed Solution

### 1. Acceleration / Deceleration

Add a `_current_speed` float variable. Each frame, lerp it toward the target speed:

```gdscript
const COMBAT_ACCEL: float = 900.0   # px/s² (reaches full speed in ~0.5s)
const COMBAT_DECEL: float = 600.0   # px/s² (slower decel = more overshoot = air feel)

_current_speed = move_toward(_current_speed, COMBAT_SPEED, COMBAT_ACCEL * delta)
velocity = _current_move_dir * _current_speed
```

`move_toward` is GDScript's built-in for clamped linear step — ideal for this.

### 2. Speed-Scaled Drift

Scale the direction-blend weight by current speed ratio:

```gdscript
const BASE_DRIFT: float = 0.85       # base carry (same as old DRIFT_FACTOR)
const AIR_DRIFT_EXTRA: float = 0.10  # additional drift at max speed

var speed_ratio: float = _current_speed / COMBAT_SPEED
var drift: float = clampf(BASE_DRIFT + AIR_DRIFT_EXTRA * speed_ratio, 0.0, 0.97)
_current_move_dir = (_current_move_dir * drift + desired_dir * (1.0 - drift)).normalized()
```

At 0 speed: drift = 0.85 (same as before)
At full speed: drift = 0.95 (much harder to turn — feels like it's flying through air)

### 3. Wall-Stuck Fix

The wall-stuck issue is caused by instant max-speed + first-frame snap. With acceleration, the drone starts at near-zero speed and builds up, so the nav agent has time to compute a proper path around obstacles. No separate fix needed — acceleration naturally solves this.

## Implementation Summary

Changes to `scripts/objects/drone.gd`:

| What | How |
|---|---|
| Add `_current_speed: float = 0.0` state variable | Init to 0 so drone starts from rest |
| Replace `velocity = _current_move_dir * COMBAT_SPEED` | `_current_speed = move_toward(...)` then `velocity = _current_move_dir * _current_speed` |
| Replace fixed `DRIFT_FACTOR` blend | Speed-scaled drift formula |
| Reset `_current_speed = 0.0` in `_transition_to_combat()` | Clean start when entering combat |

## References

- GDScript `move_toward()`: https://docs.godotengine.org/en/stable/classes/class_@gdscript.html#class-gdscript-method-move-toward
- GDScript `clampf()`: https://docs.godotengine.org/en/stable/classes/class_@gdscript.html#class-gdscript-method-clampf
- Quadcopter dynamics overview: https://www.sciencedirect.com/science/article/pii/S2405896316301343
- Game feel / acceleration patterns: https://www.gamedeveloper.com/design/the-art-of-screenshake (impulse vs ramp)
- Related PR #1417 (drone AI merge): introduced the current `DRIFT_FACTOR = 0.85` and `COMBAT_SPEED = 450`.
