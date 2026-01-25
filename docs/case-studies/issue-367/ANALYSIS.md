# Case Study: Issue #367 - Enemies Walk in Corner During FLANKING State

## Issue Summary

**Original Title (Russian):** "fix FLENKING враги ходят в углу" (fix FLANKING: enemies walk in corner)

**Description:** During FLANKING state, enemies get stuck walking in a corner behind a wall where the player is hiding. They repeatedly trigger corner checks but never make progress toward their flank target.

## Log Files Analyzed

- `game_log_20260125_073543.txt` (75KB) - Original log demonstrating FLANKING corner stuck
- `game_log_20260125_080920.txt` (374KB) - Second log demonstrating PURSUING state freeze

---

## Root Cause Analysis

### The Bug

When enemies enter FLANKING state to attempt flanking the player, they:
1. Calculate a flank target position on the side of the player
2. Use NavigationAgent2D to pathfind to that position
3. Get stuck at a specific wall corner (x=887.9) where navigation keeps them but they cannot make progress
4. Trigger repeated corner checks alternating between angles (~-142°, ~-132°, ~-120° and ~132°)
5. Time out after 5 seconds and return to PURSUING, then re-enter FLANKING - creating an infinite loop

### Evidence from Logs

**Pattern 1: All FLANKING timeouts occur at the same x-coordinate**

```
[07:35:59] [ENEMY] [Enemy3] FLANKING timeout (5.0s), target=(1119.361, 813.3628), pos=(887.9341, 754.4363)
[07:36:00] [ENEMY] [Enemy2] FLANKING timeout (5.0s), target=(1047.972, 786.6818), pos=(887.9336, 880.9666)
[07:36:06] [ENEMY] [Enemy4] FLANKING timeout (5.0s), target=(1119.357, 813.3604), pos=(887.9341, 754.4492)
[07:36:10] [ENEMY] [Enemy3] FLANKING timeout (5.0s), target=(1116.993, 811.9355), pos=(887.9341, 761.9493)
[07:36:12] [ENEMY] [Enemy2] FLANKING timeout (5.0s), target=(1120.372, 813.986), pos=(887.9332, 750.2993)
[07:36:17] [ENEMY] [Enemy4] FLANKING timeout (5.0s), target=(1116.993, 811.9355), pos=(887.9342, 761.9495)
[07:36:20] [ENEMY] [Enemy3] FLANKING timeout (5.0s), target=(1121.583, 814.7434), pos=(887.9348, 746.9026)
[07:36:22] [ENEMY] [Enemy2] FLANKING timeout (5.0s), target=(1118.068, 812.578), pos=(887.9333, 757.7293)
[07:36:27] [ENEMY] [Enemy4] FLANKING timeout (5.0s), target=(1121.583, 814.7435), pos=(887.9348, 746.9026)
[07:36:32] [ENEMY] [Enemy3] FLANKING timeout (5.0s), target=(1119.346, 813.3535), pos=(887.9343, 754.4866)
[07:36:32] [ENEMY] [Enemy2] FLANKING timeout (5.0s), target=(1118.057, 812.5715), pos=(887.9333, 757.7636)
```

All enemies get stuck at **x=887.9** (within 0.001 pixels of each other), strongly indicating a wall edge at this position.

**Pattern 2: Oscillating corner check angles**

```
[07:35:57] [ENEMY] [Enemy3] FLANKING corner check: angle -120.6°
[07:35:57] [ENEMY] [Enemy3] FLANKING corner check: angle 132.1°
[07:35:58] [ENEMY] [Enemy2] FLANKING corner check: angle -120.6°
[07:35:58] [ENEMY] [Enemy3] FLANKING corner check: angle -142.4°
[07:35:58] [ENEMY] [Enemy2] FLANKING corner check: angle 132.1°
[07:35:58] [ENEMY] [Enemy3] FLANKING corner check: angle -132.4°
```

The corner check angles oscillate between positive and negative values (~±120-142°), indicating the enemy is at a corner with perpendicular openings detected on alternating sides. This is the hallmark of being stuck in a corner.

**Pattern 3: Player position behind the wall**

From the flank targets, we can infer the player position:
- Flank targets: (~1119-1143, ~813-830)
- Given `flank_distance = 200` and `flank_angle = PI/3 (60°)`, player is approximately at (~1100-1140, ~810-830)

The player is at x=~1120 and the wall corner is at x=887.9, meaning there's a wall between enemies and the player.

### Code Analysis

#### 1. Flank Position Calculation (`_calculate_flank_position()` at line 3413)

```gdscript
func _calculate_flank_position() -> void:
    if _player == null:
        return
    var player_pos := _player.global_position
    var player_to_enemy := (global_position - player_pos).normalized()
    var flank_direction := player_to_enemy.rotated(flank_angle * _flank_side)
    _flank_target = player_pos + flank_direction * flank_distance
```

**Problem:** The flank target is calculated relative to the player position without considering:
1. Whether the path to the flank target requires going around obstacles
2. Whether the flank target itself is behind a wall relative to the enemy

#### 2. Flank Target Reachability Check (`_is_flank_target_reachable()` at line 2637)

```gdscript
func _is_flank_target_reachable() -> bool:
    _nav_agent.target_position = _flank_target
    if _nav_agent.is_navigation_finished():
        var distance: float = global_position.distance_to(_flank_target)
        if distance > 50.0:
            return false
    var path_distance: float = _nav_agent.distance_to_target()
    var straight_distance: float = global_position.distance_to(_flank_target)
    if path_distance > straight_distance * 3.0 and path_distance > 500.0:
        return false
    return true
```

**Problem:** The reachability check only validates:
1. Navigation is not immediately finished (target not unreachable)
2. Path distance is not more than 3x the straight-line distance

It does NOT check:
1. Whether the enemy is already at or near a wall that would block progress
2. Whether the navigation path actually makes progress toward the target

#### 3. FLANKING State Processing (`_process_flanking_state()` at line 1757)

```gdscript
func _process_flanking_state(delta: float) -> void:
    _flank_state_timer += delta
    if _flank_state_timer >= FLANK_STATE_MAX_TIME:
        # Timeout handling...
        return

    # Stuck detection
    var distance_moved := global_position.distance_to(_flank_last_position)
    if distance_moved < FLANK_PROGRESS_THRESHOLD:
        _flank_stuck_timer += delta
        if _flank_stuck_timer >= FLANK_STUCK_MAX_TIME:
            # Stuck handling...
            return
    else:
        _flank_stuck_timer = 0.0
        _flank_last_position = global_position

    _move_to_target_nav(_flank_target, combat_move_speed)
```

**Problem:** The stuck detection exists but:
1. The enemy IS moving (triggering corner checks repeatedly), just not making net progress
2. The movement is along the wall rather than toward the target
3. The wall avoidance may be keeping the enemy moving just enough to avoid stuck detection

---

## Timeline of Events

1. **07:35:43** - Game starts, enemies initialized
2. **07:35:47** - Combat begins (gunshots fired)
3. **07:35:54** - Enemy3 enters FLANKING state targeting right flank of player at (~1210, 802)
4. **07:35:55** - Enemy3 starts corner checking at angles ~140°, ~135°, ~133°, ~118°
5. **07:35:55** - Enemy2 enters FLANKING state
6. **07:35:55-07:35:59** - Multiple enemies get stuck at x=887.9, corner checking repeatedly
7. **07:35:59** - Enemy3 times out after 5s at position (887.9341, 754.4363)
8. **07:35:59** - Enemy3 transitions FLANKING -> PURSUING
9. **07:36:05** - Enemy3 re-enters FLANKING (the loop continues)
10. **07:36:37** - Log ends, enemies still stuck in FLANKING->PURSUING loop

---

## Wall Geometry Analysis

Based on enemy positions and behavior:

```
                    Wall
                     |
    Enemy pos        |          Player pos
    (887.9, 750)     |          (~1120, 815)
         *---------->|              *
                     |
    x=887.9          |          x=~1120
         (stuck      |
          here)      |
```

The wall runs approximately north-south at x=~888, blocking direct access. The navigation mesh likely has a path around the wall (north or south), but:
1. The flank target calculation places the target BEHIND the wall
2. The enemy tries to move toward the target but gets deflected by wall avoidance
3. At the corner, perpendicular openings are detected, triggering corner checks
4. The enemy oscillates at the corner instead of going around

---

## Proposed Solution

### Solution: Enhanced Flank Position Validation with Line-of-Sight Check

When calculating a flank position, ensure the position is:
1. Reachable via navigation (already checked)
2. Has line-of-sight to the player (NEW CHECK)
3. Is on the same "side" of obstacles as the enemy (NEW CHECK)

If the flank target fails these checks, either:
1. Try the opposite flank side
2. Fall back to PURSUING directly
3. Calculate a new flank position that IS reachable with LOS

### Implementation

```gdscript
## Calculate flank position and validate it has LOS to player
func _calculate_flank_position() -> void:
    if _player == null:
        return

    var player_pos := _player.global_position
    var player_to_enemy := (global_position - player_pos).normalized()

    # Calculate potential flank position
    var flank_direction := player_to_enemy.rotated(flank_angle * _flank_side)
    var candidate_target := player_pos + flank_direction * flank_distance

    # Validate the flank position has LOS to player
    if _flank_position_has_los_to_player(candidate_target, player_pos):
        _flank_target = candidate_target
    else:
        # Try reduced flank distance
        var reduced_distance := flank_distance * 0.5
        candidate_target = player_pos + flank_direction * reduced_distance
        if _flank_position_has_los_to_player(candidate_target, player_pos):
            _flank_target = candidate_target
        else:
            # Flank position is behind a wall - this will be caught by timeout
            _flank_target = candidate_target  # Use anyway, will timeout if stuck

func _flank_position_has_los_to_player(flank_pos: Vector2, player_pos: Vector2) -> bool:
    var space_state := get_world_2d().direct_space_state
    var query := PhysicsRayQueryParameters2D.create(flank_pos, player_pos)
    query.collision_mask = 0b100  # Walls only
    query.exclude = [self]
    return space_state.intersect_ray(query).is_empty()
```

### Additional Fix: Early Exit When Stuck at Wall

```gdscript
## In _process_flanking_state(), add navigation progress check
func _process_flanking_state(delta: float) -> void:
    # ... existing timeout check ...

    # Check if navigation path is making progress toward target
    var current_path_distance := _nav_agent.distance_to_target() if _nav_agent else INF
    var target_direction := (_flank_target - global_position).normalized()
    var move_direction := velocity.normalized() if velocity.length() > 0.1 else Vector2.ZERO

    # If we're moving perpendicular or away from target, we're stuck on a wall
    if move_direction != Vector2.ZERO:
        var alignment := target_direction.dot(move_direction)
        if alignment < 0.3:  # Moving mostly perpendicular or backwards
            _flank_wall_stuck_timer += delta
            if _flank_wall_stuck_timer >= 1.0:  # 1 second of non-progress
                _log_to_file("FLANKING: Stuck against wall, movement perpendicular to target")
                _flank_side_initialized = false
                _flank_fail_count += 1
                _flank_cooldown_timer = FLANK_COOLDOWN_DURATION
                _transition_to_combat()
                return
        else:
            _flank_wall_stuck_timer = 0.0
```

---

## Similar Issues in Game AI

### 1. Pathfinding "U-Turn" Problem
When an AI has a path that goes around an obstacle but the straight-line target is on the other side, the AI may attempt to move toward the target directly, hitting the wall repeatedly.

Reference: [Path Following Problems in Game AI](https://www.gamedeveloper.com/programming/the-total-beginner-s-guide-to-game-ai)

### 2. Local vs Global Navigation Conflict
The combination of global pathfinding (NavigationAgent2D) and local avoidance (wall avoidance) can create situations where:
- Global path says "go around the wall (north)"
- Local avoidance says "there's a wall east, steer south"
- Result: Agent oscillates or gets stuck

Reference: [Steering Behaviors - Obstacle Avoidance](https://www.red3d.com/cwr/steer/Obstacle.html)

### 3. "Magnetism to Walls" Problem
When wall avoidance is applied continuously, agents can get "stuck" sliding along walls instead of finding a path around them.

---

## Files to Modify

1. **scripts/objects/enemy.gd**
   - `_calculate_flank_position()` - Add LOS validation
   - `_process_flanking_state()` - Add wall-stuck early exit
   - Add new helper `_flank_position_has_los_to_player()`

---

## Test Cases

1. **Wall Between Enemy and Player:**
   - Place player behind a wall
   - Verify enemy doesn't try to flank to position behind wall
   - Verify enemy either flanks to valid position or stays in PURSUING

2. **Corner Trap:**
   - Create an L-shaped wall configuration
   - Place player at the inside of the L
   - Verify enemy doesn't get stuck oscillating at corner

3. **Open Area:**
   - Verify normal flanking behavior works in open areas
   - Verify enemies reach flank positions and engage

4. **Multiple Enemies:**
   - Verify multiple enemies don't all get stuck at same wall corner

---

---

## Part 2: PURSUING State Freeze Bug

### Problem Description

After fixing the FLANKING corner stuck issue, a new related issue was reported: enemies sometimes freeze in the PURSUING state. The symptoms were similar - enemies would get stuck in a corner while in PURSUING state, only producing "PURSUING corner check" log messages but no state transitions.

### Evidence from Log `game_log_20260125_080920.txt`

**Enemy1 freezes in PURSUING state:**

```
[08:13:02] [ENEMY] [Enemy1] FLANKING wall-stuck (alignment=-0.53), pos=(603.3171, 1048.066)
[08:13:02] [ENEMY] [Enemy1] State: FLANKING -> PURSUING
[08:13:02] [ENEMY] [Enemy1] PURSUING corner check: angle 110.3°
[08:13:04] [ENEMY] [Enemy1] PURSUING corner check: angle 76.4°
[08:13:06] [ENEMY] [Enemy1] PURSUING corner check: angle 78.9°
[08:13:08] [ENEMY] [Enemy1] PURSUING corner check: angle 109.4°
[08:13:08] [ENEMY] [Enemy1] PURSUING corner check: angle 99.1°
[08:13:10] [ENEMY] [Enemy1] PURSUING corner check: angle 94.5°
[08:13:12] [ENEMY] [Enemy1] PURSUING corner check: angle 113.2°
# No further state transitions until end of log
```

Enemy1 transitioned from FLANKING to PURSUING at 08:13:02 due to wall-stuck detection, then stayed in PURSUING with only corner check logs for 10+ seconds until the log ended.

### Root Cause

The FLANKING state had wall-stuck detection added to fix the original issue, but the PURSUING state lacked similar detection. When an enemy in PURSUING state hit a wall:

1. The enemy would call `_find_pursuit_cover_toward_player()` which returned no valid cover
2. The enemy would check for memory-based target via `_memory.has_target()`
3. If memory had a target, it would call `_move_to_target_nav(target_pos, ...)` and return early
4. The enemy would get stuck sliding along the wall (velocity perpendicular to target direction)
5. No timeout or stuck detection would trigger - the enemy would be frozen indefinitely

The key difference from FLANKING:
- FLANKING had `_flank_wall_stuck_timer` to detect perpendicular movement
- PURSUING had NO equivalent detection for any of its movement paths

### Code Analysis

The PURSUING state has four distinct movement paths:
1. **Vulnerability sound pursuit** (lines 2066-2076)
2. **Approach phase** (lines 2097-2117)
3. **Pursuit cover movement** (lines 2172-2177)
4. **Memory-based pursuit** (lines 2200-2209)

None of these paths had wall-stuck detection - they only had corner checking for visual purposes.

### Solution

Added wall-stuck detection to the PURSUING state similar to FLANKING:

1. **New variable:** `_pursuing_wall_stuck_timer: float = 0.0`
2. **New constant:** `PURSUING_WALL_STUCK_MAX_TIME: float = 2.0` (slightly longer than FLANKING's 1.0s)
3. **New helper function:** `_handle_pursuing_wall_stuck(delta, target_pos, context)` to reduce code duplication

The helper function:
- Checks if velocity is significant (length_squared > 1.0)
- Calculates alignment between movement direction and target direction
- If alignment < 0.3 (moving perpendicular/away from target), increments timer
- After 2 seconds of wall-stuck, transitions to:
  - FLANKING (if available)
  - SEARCHING (if has_left_idle)
  - COMBAT (as fallback)

### Fix Applied

Added wall-stuck detection to all four PURSUING movement paths:
- `vuln_sound` context: When pursuing reload/empty click sounds
- `approach` context: When directly approaching player
- `cover` context: When moving toward pursuit cover
- `memory` context: When pursuing memory-based suspected position

---

## References

- Game log 1: `docs/case-studies/issue-367/game_log_20260125_073543.txt` (FLANKING stuck)
- Game log 2: `docs/case-studies/issue-367/game_log_20260125_080920.txt` (PURSUING freeze)
- Related PR: #358 (corner checking implementation)
- Related Issue: #357 (enemies navigate corners without looking)
- [Godot NavigationAgent2D Documentation](https://docs.godotengine.org/en/stable/classes/class_navigationagent2d.html)
