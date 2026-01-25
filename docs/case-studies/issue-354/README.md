# Case Study: Issue #354 - Enemies Standing Still in SEARCHING State

## Problem Summary

In certain scenarios, enemies in the SEARCHING state would stop moving and stand still indefinitely, appearing frozen while still technically in the searching behavior. This occurred specifically after a "LastChance" effect teleported the player, causing multiple enemies to cluster in the same area and begin searching.

## Timeline of Events (from game_log_20260125_032528.txt)

1. **03:25:28** - Game starts with 10 enemies (Enemy1-10) initialized
2. **03:25:33** - Combat begins, multiple enemies engage player
3. **03:25:34** - Various enemy state transitions (PURSUING, RETREATING, SUPPRESSED, etc.)
4. **03:25:35** - LastChance effect triggers (player near death)
5. **03:25:41** - LastChance effect ends, enemies reset:
   - Enemy1: PURSUING -> SEARCHING at (570.5618, 700.6684)
   - Enemy2: COMBAT -> SEARCHING at (570.5618, 714.5018)
   - Enemy3: RETREATING -> SEARCHING at (570.5618, 700.6684)
   - Enemy4: SUPPRESSED -> SEARCHING at (570.5618, 700.6684)

6. **03:25:41 to 03:25:49** - Normal searching behavior:
   - Enemies generate 5 waypoints each
   - Corner check angles vary as enemies move around

7. **03:25:49** - Enemy3, Enemy4, Enemy1 expand search radius to r=175
   - **BUT Enemy2's angle becomes STUCK at 89.2 degrees**

8. **03:25:49 to 03:26:35** (~46 seconds) - Enemy2 stuck:
   - Corner check logs show Enemy2 at exactly 89.2 degrees every frame
   - Other enemies (1, 3, 4) also show periods of stuck behavior with angles converging to -180.0 degrees
   - Enemies are technically in "moving to waypoint" mode but not actually moving

9. **03:26:35** - Enemy2 finally expands to r=175, angles start changing again

## Root Cause Analysis

### The Bug

The SEARCHING state in `enemy.gd` lacks a **stuck detection mechanism**. When an enemy is navigating to a waypoint:

```gdscript
# From _process_searching_state() at line 2366-2380
else:
    _nav_agent.target_position = target_waypoint
    if _nav_agent.is_navigation_finished():
        _mark_zone_visited(target_waypoint)
        _search_current_waypoint_index += 1
        _search_moving_to_waypoint = true
    else:
        var next_pos := _nav_agent.get_next_path_position()
        var dir := (next_pos - global_position).normalized()
        velocity = dir * move_speed * 0.7
        move_and_slide()
        # ... rotation and corner check
```

**Problem**: When `is_navigation_finished()` returns `false` (indicating the enemy should still be moving), but `move_and_slide()` cannot actually move the enemy (due to collision or navigation issues), the enemy gets stuck indefinitely.

### Contributing Factors

1. **Multiple enemies at same location**: All 4 enemies started searching from nearly identical positions (~14 pixels apart), potentially causing:
   - Similar or identical waypoint generation
   - Competition for the same navigation paths

2. **NavigationAgent2D behavior**: The nav agent may return a valid "next position" that the enemy cannot actually reach due to:
   - Physics collisions not accounted for in navigation
   - Complex geometry at building corners
   - The navigation map not matching the collision shapes exactly

3. **No progress tracking**: Unlike the FLANKING state which has stuck detection (lines 1798-1826), SEARCHING has no mechanism to detect when an enemy is not making progress toward a waypoint.

### Comparison with FLANKING State

The FLANKING state correctly handles stuck detection:

```gdscript
# FLANKING stuck detection (lines 1798-1826)
var progress := global_position.distance_to(_flank_last_progress_position)
if progress < 10.0:  # Less than 10 pixels movement
    _flank_stuck_timer += delta
    if _flank_stuck_timer >= FLANK_STUCK_MAX_TIME:  # 2 seconds
        # Handle stuck condition - try alternative action
```

SEARCHING state lacks equivalent logic.

## Solution

Add stuck detection to the SEARCHING state:

1. Track the last position when moving to a waypoint
2. If the enemy doesn't move at least 10 pixels in 2 seconds, skip to the next waypoint
3. If all waypoints fail, regenerate waypoints from current position

## Evidence from Logs

### Enemy2 Stuck Pattern (excerpt from log)
```
[03:25:49] [ENEMY] [Enemy2] SEARCHING corner check: angle 89.2
[03:25:49] [ENEMY] [Enemy2] SEARCHING corner check: angle 89.2
...
(46 seconds of identical 89.2 angle)
...
[03:26:34] [ENEMY] [Enemy2] SEARCHING corner check: angle -4.9  # Finally unstuck
[03:26:35] [ENEMY] [Enemy2] SEARCHING: Expand outer ring r=175 wps=4
```

### Other Enemies Converging to -180.0
```
[03:25:50] [ENEMY] [Enemy3] SEARCHING corner check: angle -174.2
[03:25:50] [ENEMY] [Enemy3] SEARCHING corner check: angle -176.7
[03:25:51] [ENEMY] [Enemy3] SEARCHING corner check: angle -178.1
...
[03:25:53] [ENEMY] [Enemy3] SEARCHING corner check: angle -180.0
```

This convergence pattern indicates the enemy is trying to move in a constant direction but making no actual progress.

## Files Affected

- `scripts/objects/enemy.gd` - SEARCHING state implementation

## Related Issues

- Issue #322 - Original SEARCHING state implementation
- Issue #330 - Infinite search for engaged enemies
- Issue #332 - Corner checking during movement
- Issue #347 - Smooth rotation for corner checks
