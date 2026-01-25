# Case Study: Issue #386 - Enemy Faces Wrong Direction During FLANKING State

## Problem Summary
When an enemy is in the FLANKING state (attempting to flank the player's cover position), they face in the opposite direction from the player - looking backwards while moving around cover.

## Timeline of Events (from game_log_20260125_113829.txt)

1. **11:38:48** - Enemy4 transitions from PURSUING to FLANKING state
   - Target: (1000.812, 871.2692), Side: left, Position: (799.5685, 825.1296)

2. **11:38:48** - First corner check triggered with angle 122.2 degrees
   - This angle is perpendicular to movement direction
   - Enemy starts looking sideways instead of towards player

3. **11:38:49 to 11:38:53** - Multiple corner check angles logged:
   - -170.3 degrees, -134.2 degrees, -120.8 degrees, 127.5 degrees, etc.
   - Enemy constantly changes facing direction to perpendicular openings

4. **11:38:53** - FLANKING timeout after 5 seconds
   - Enemy transitions back to PURSUING
   - The flanking maneuver failed to achieve its purpose

This pattern repeats multiple times in the log with Enemy4.

## Root Cause Analysis

### The Rotation Priority System

The `_update_enemy_model_rotation()` function determines which direction the enemy model faces. The original priority order was:

1. Player visible: Face the player
2. Corner check active: Face the corner check angle (perpendicular direction)
3. Moving: Face velocity direction
4. IDLE state: Use idle scan targets

### The Problem

During FLANKING state:
- The enemy cannot see the player (they're behind cover, executing a flank)
- Corner checks are triggered frequently by `_process_corner_check()` during movement
- The corner check angle is set to a perpendicular direction (to detect openings)
- This causes the enemy to constantly look sideways/backwards

The corner check mechanism was designed for PATROL state, where enemies walk patrol routes and briefly glance at openings. This makes sense for patrol where there's no target to focus on.

However, during FLANKING, the enemy has a clear target (the player) and should face towards them while executing the flanking maneuver. The corner checks were overriding the velocity-based facing, causing the unnatural backwards-facing behavior.

### Code Location

File: `scripts/objects/enemy.gd`
Function: `_update_enemy_model_rotation()` (lines 931-966)

Original problematic code:
```gdscript
elif _corner_check_timer > 0:
    target_angle = _corner_check_angle  # Corner check: smooth rotation (Issue #347)
    has_target = true
elif velocity.length_squared() > 1.0:
    target_angle = velocity.normalized().angle()
    has_target = true
```

The corner check had higher priority than velocity direction, so during FLANKING, the enemy would face the corner check angle instead of their movement direction.

## Solution

Modified the rotation priority in `_update_enemy_model_rotation()` to add a special case for FLANKING state:

```gdscript
# Issue #386: During FLANKING, face the player (even if not visible) instead of corner check.
# This prevents the enemy from facing backwards/sideways while flanking.
elif _current_state == AIState.FLANKING and _player != null:
    target_angle = (_player.global_position - global_position).normalized().angle()
    has_target = true
```

This change:
1. Preserves the existing behavior for all other states
2. During FLANKING, the enemy now faces towards the player's position
3. This makes the flanking maneuver look intentional and tactical
4. The enemy appears to be watching the player while moving around their cover

### New Priority Order

1. Player visible: Face the player
2. **FLANKING state: Face the player (even if not visible)** [NEW]
3. Corner check active: Face the corner check angle
4. Moving: Face velocity direction
5. IDLE state: Use idle scan targets

## Visual Result

Before fix:
- Enemy moves around cover to flank
- Enemy constantly looks sideways or backwards
- Appears buggy and unintentional

After fix:
- Enemy moves around cover to flank
- Enemy faces towards the player while moving
- Appears tactical and intentional, like a proper flanking maneuver

## Files Changed

- `scripts/objects/enemy.gd`: Modified `_update_enemy_model_rotation()` function

## Related Issues

- Issue #332: Corner checking during movement (introduced the corner check system)
- Issue #347: Smooth rotation for enemy model (improved rotation smoothness)
- Issue #386: This fix addresses the unintended interaction between corner checks and FLANKING state
