# Case Study: Issue #450 - Enemy Grenade Reaction Behavior

## Problem Statement

**Original Issue (Russian):** "враг должен примерно предполагать, где приземлится граната, когда её видит, в зависимости от этого убегать от неё."

**Translation:** "The enemy should approximately predict where the grenade will land when they see it, and run away from it depending on that."

## Observed Symptoms

From the game logs (`game_log_20260203_215858.txt`), we observed a pattern of rapid state cycling:

```
[21:59:01] [ENEMY] [Enemy3] EVADING_GRENADE: Escaped to safe distance
[21:59:01] [ENEMY] [Enemy3] State: EVADING_GRENADE -> COMBAT
[21:59:01] [ENEMY] [Enemy3] GRENADE DANGER: Entering EVADING_GRENADE state from COMBAT
[21:59:01] [ENEMY] [Enemy3] EVADING_GRENADE started: escaping to (1100.202, 820.3436)
```

The enemy was cycling between `EVADING_GRENADE` and `COMBAT` states multiple times per second, creating a "jittery" escape behavior instead of a smooth, committed flee.

## Timeline of Events (Reconstructed)

1. **21:59:00** - Player throws a flashbang grenade at position (450, 1089) toward target (694, 760)
2. **21:59:01** - Grenade in flight, enemy detects danger at grenade's current position
3. **21:59:01** - Enemy starts fleeing, calculates escape to (1076, 812)
4. **21:59:01** - Grenade moves forward, enemy recalculates new danger zone
5. **21:59:01** - Enemy "escaped" from old position, returns to COMBAT
6. **21:59:01** - Enemy re-detects grenade at NEW position, re-enters EVADING_GRENADE
7. **Repeat** - This cycle continues 15+ times until grenade lands at (701, 760)

## Root Cause Analysis

### The Core Problem

The enemy AI was calculating danger zones based on the **grenade's current position** instead of its **predicted landing position**.

**Affected Code Location:** `scripts/components/grenade_avoidance_component.gd`

```gdscript
# Line 194 (before fix):
var distance := _enemy.global_position.distance_to(grenade.global_position)
```

### Why This Causes Jitter

1. Grenade flies at ~375 pixels/second toward enemy
2. Each physics frame (~16ms), grenade moves ~6 pixels
3. Enemy calculates escape vector from current grenade position
4. Enemy starts running in calculated direction
5. Next frame: grenade has moved, danger zone shifted
6. Enemy re-calculates, new escape direction may differ
7. If enemy momentarily moves outside old danger zone, state changes to COMBAT
8. New grenade position triggers new danger detection, back to EVADING_GRENADE

### Physics Background

The game uses constant friction deceleration for grenades:

```gdscript
# From grenade_base.gd
@export var ground_friction: float = 300.0

# Physics formula for stopping distance:
# d = v² / (2 * f)
# where v = velocity, f = friction
```

At 375 px/s initial velocity with 300 px/s² friction:
- Stopping distance = 375² / (2 × 300) = 234 pixels from throw point

## Solution Implementation

### 1. Grenade Landing Prediction (grenade_base.gd)

Added new method to predict landing position:

```gdscript
## Issue #450: Predict where the grenade will land based on current velocity and friction.
func get_predicted_landing_position() -> Vector2:
    var velocity := linear_velocity
    var speed := velocity.length()

    # If grenade is nearly stopped or frozen, return current position
    if speed < landing_velocity_threshold or freeze:
        return global_position

    # Calculate stopping distance: d = v² / (2 * f)
    var stopping_distance := (speed * speed) / (2.0 * ground_friction)

    # Calculate predicted landing position
    var direction := velocity.normalized()
    return global_position + direction * stopping_distance
```

### 2. Target Locking System (grenade_avoidance_component.gd)

Added "locking" mechanism to prevent jitter:

```gdscript
## Issue #450: Whether we've locked onto a grenade target
var _locked_grenade: Node2D = null
var _locked_position: Vector2 = Vector2.ZERO
```

Once an enemy commits to fleeing from a grenade:
1. The predicted landing position is "locked"
2. Enemy continues fleeing from this locked position
3. Lock only releases when enemy is safe OR grenade explodes

### 3. Updated Danger Zone Calculation

Changed danger detection to use predicted landing position:

```gdscript
# Issue #450: Get predicted landing position instead of current position
var grenade_danger_pos: Vector2 = grenade.global_position
if grenade.has_method("get_predicted_landing_position"):
    grenade_danger_pos = grenade.get_predicted_landing_position()

# Calculate distance to PREDICTED landing position
var distance := _enemy.global_position.distance_to(grenade_danger_pos)
```

## Expected Behavior After Fix

1. Player throws grenade toward enemy
2. Enemy sees grenade, predicts landing at position X
3. Enemy calculates escape route away from position X
4. Enemy commits to escape route (locked target)
5. Enemy runs smoothly in one direction until safe
6. State changes once: COMBAT → EVADING_GRENADE → COMBAT

## Files Modified

1. `scripts/projectiles/grenade_base.gd`
   - Added `get_predicted_landing_position()` method
   - Added `is_moving()` helper method

2. `scripts/components/grenade_avoidance_component.gd`
   - Added `predicted_landing_position` variable
   - Added `_locked_grenade` and `_locked_position` for target locking
   - Updated `update()` to use predicted positions and locking
   - Updated `calculate_evasion_target()` to use predicted positions
   - Updated `is_at_safe_distance()` to use predicted positions
   - Updated `reset()` to clear new variables

## Technical Considerations

### Wall Collisions

The current prediction does not account for wall bounces. This is acceptable because:
1. Grenades have low bounce coefficient (0.4)
2. Most throws are direct, not ricochets
3. Predicting bounces would require complex raycast calculations
4. "Close enough" prediction is better than no prediction

### Multiple Grenades

The locking system focuses on the most dangerous (closest predicted landing) grenade. If multiple grenades are thrown:
1. Enemy locks onto closest predicted threat
2. After escaping first, re-evaluates for additional threats
3. This is realistic - humans prioritize immediate danger

## Verification

To verify the fix works correctly:
1. Throw a grenade toward a visible enemy
2. Enemy should immediately start fleeing in a consistent direction
3. No rapid state cycling in logs
4. Enemy should reach safe distance before grenade lands
5. Enemy should return to COMBAT after grenade explodes
