# Case Study: Issue #357 - Enemies Navigate Corners Without Looking

## Issue Summary

**Original Title (Russian):** "fix враги обходят угол не глядя" (fix: enemies navigate corners without looking)

**Description:** Enemies navigate around corners behind which the player is hiding without ever turning to look in that direction - literally walking with their back to the player.

## Log Files Analyzed

The issue includes five log files from the user demonstrating the problem:
- `game_log_20260125_035127.txt` (908KB)
- `game_log_20260125_035837.txt` (105KB)
- `game_log_20260125_035940.txt` (357KB)
- `game_log_20260125_040455.txt` (141KB)
- `game_log_20260125_041941.txt` (278KB) - Added 2026-01-25 from PR #358 feedback

---

## Root Cause Analysis

### The Bug

When enemies are in PURSUING, FLANKING, or SEARCHING states and navigate around corners using the NavigationAgent2D pathfinding system, they do NOT look toward the corner where the player might be hiding. Instead, they:

1. Face the direction of their movement velocity
2. Only briefly check perpendicular directions when the corner check system activates
3. The corner check is designed for **peripheral vision detection** during patrol, NOT for **anticipatory tactical looking** when pursuing

### Code Analysis

#### 1. Model Rotation Priority System (`_update_enemy_model_rotation()` at line 1002-1037)

The enemy model rotation uses a priority system:
```gdscript
func _update_enemy_model_rotation() -> void:
    if _player != null and _can_see_player:
        target_angle = player_direction.angle()  # Priority 1: Look at player
    elif _corner_check_timer > 0:
        target_angle = _corner_check_angle       # Priority 2: Corner check angle
    elif velocity.length_squared() > 1.0:
        target_angle = velocity.normalized().angle()  # Priority 3: Movement direction
    elif _current_state == AIState.IDLE:
        target_angle = _idle_scan_targets[...]   # Priority 4: Idle scan
```

**Problem:** When pursuing but can't see the player, the enemy defaults to facing their movement direction (Priority 3). The corner check (Priority 2) only triggers when there's an opening perpendicular to movement, and it checks **perpendicular** angles (90° to movement), not angles toward the suspected player position.

#### 2. Navigation Movement (`_move_to_target_nav()` at line 4928-4940)

```gdscript
func _move_to_target_nav(target_pos: Vector2, speed: float) -> bool:
    var direction: Vector2 = _get_nav_direction_to(target_pos)
    # ...
    velocity = direction * speed
    rotation = direction.angle()  # Body rotation matches movement
    return true
```

**Problem:** The body rotation is set to match movement direction. The model rotation smoothly interpolates but defaults to velocity direction when not seeing the player.

#### 3. Corner Check System (`_process_corner_check()` at line 4103-4109)

```gdscript
func _process_corner_check(delta: float, move_dir: Vector2, state_name: String) -> void:
    if _corner_check_timer > 0:
        _corner_check_timer -= delta
    elif _detect_perpendicular_opening(move_dir):
        _corner_check_timer = CORNER_CHECK_DURATION  # 0.3 seconds
```

The corner check:
- Only triggers when there's an **opening perpendicular** to movement
- Looks perpendicular to movement (90° left or right)
- Duration is only 0.3 seconds
- Does NOT consider the target/suspected player position

### What Should Happen vs. What Actually Happens

**Expected Behavior (Tactical):**
When an enemy pursues a player around a corner:
1. Approach the corner
2. **Look toward the corner** (potential threat direction) before rounding it
3. Clear the corner, then continue pursuit

**Actual Behavior (Bug):**
1. Approach the corner
2. Face movement direction (back to the corner where player might be)
3. Briefly glance perpendicular (still wrong direction in many cases)
4. Continue with back exposed to potential ambush

---

## Evidence from Logs

From `game_log_20260125_035127.txt`:
```
[03:51:36] [ENEMY] [Enemy1] PURSUING corner check: angle -131.6°
[03:51:36] [ENEMY] [Enemy2] PURSUING corner check: angle 153.7°
[03:51:36] [ENEMY] [Enemy1] PURSUING corner check: angle -75.7°
[03:51:37] [ENEMY] [Enemy1] PURSUING corner check: angle -74.1°
```

The corner check angles are perpendicular to movement (±90° offset), not toward the target position. When an enemy is going around a corner to chase a player, looking perpendicular means looking at the WALL, not around the corner.

---

## Industry Standards and Best Practices

### 1. Anticipation and Look-Ahead (Steering Behaviors)

According to Craig Reynolds' foundational work on [Steering Behaviors](https://www.red3d.com/cwr/steer/gdc99/):
> "The typical velocity of a character is large relative to its maximum turning acceleration. As a result, the steering behaviors must anticipate the future, and take into account eventual consequences of current actions."

### 2. Tactical AI in Stealth Games

From research on [Stealth Game AI](https://www.wayline.io/blog/predictable-problem-stealth-game-ai-overhaul):
> "Detection isn't as trivial as setting enemies to an alerted state when the player enters their vision. Immediate, unexpected detection from a guard walking around the corner feels random and frustrating."
> "Planning is a core component of a stealth experience. The game needs to communicate the detection system to the player so they're able to change the plan and respond accordingly."

### 3. Path Following with Look-Ahead

From [Path Following in AI](https://gamedevelopment.tutsplus.com/tutorials/understanding-steering-behaviors-path-following--gamedev-8769):
> "For complex paths with sudden changes of direction the predictive behavior can appear smoother than the non-predictive one."

---

## Proposed Solutions

### Solution 1: Target-Aware Corner Checking (Recommended)

**Concept:** When in PURSUING/FLANKING/SEARCHING states, the corner check should look toward the target position, not just perpendicular to movement.

**Implementation:**
```gdscript
func _detect_tactical_opening(move_dir: Vector2, target_pos: Vector2) -> bool:
    # Check if target is around a corner ahead
    var dir_to_target := (target_pos - global_position).normalized()
    var angle_to_target := dir_to_target.angle()
    var move_angle := move_dir.angle()

    # If target direction differs significantly from movement, look toward target
    var angle_diff := abs(wrapf(angle_to_target - move_angle, -PI, PI))
    if angle_diff > deg_to_rad(45.0):  # Target is significantly off movement path
        # Raycast toward target to see if there's an opening
        var space_state := get_world_2d().direct_space_state
        var query := PhysicsRayQueryParameters2D.create(
            global_position,
            global_position + dir_to_target * CORNER_CHECK_DISTANCE
        )
        query.collision_mask = 0b100
        query.exclude = [self]

        if space_state.intersect_ray(query).is_empty():
            _corner_check_angle = angle_to_target  # Look toward target
            return true

    # Fall back to perpendicular check
    return _detect_perpendicular_opening(move_dir)
```

**Pros:**
- Enemies look where they expect the player to be
- More realistic tactical behavior
- Maintains existing perpendicular check as fallback

**Cons:**
- Requires passing target position through the call chain
- May need tuning for different states

### Solution 2: Navigation Path Look-Ahead

**Concept:** Look at the next navigation path point instead of current velocity direction.

**Implementation:**
```gdscript
func _get_path_look_ahead_angle() -> float:
    if _nav_agent == null or _nav_agent.is_navigation_finished():
        return velocity.normalized().angle()

    # Get the next few path points
    var path := _nav_agent.get_current_navigation_path()
    var current_idx := _nav_agent.get_current_navigation_path_index()

    # Look 2-3 points ahead on the path
    var look_ahead_idx := mini(current_idx + 2, path.size() - 1)
    var look_ahead_pos := path[look_ahead_idx]

    return (look_ahead_pos - global_position).normalized().angle()
```

**Pros:**
- Simple to implement
- Anticipates turns naturally
- Works with existing navigation system

**Cons:**
- Doesn't specifically look at corners
- May cut corners too much in navigation

### Solution 3: Memory-Based Looking

**Concept:** Use the enemy memory system to determine where to look when pursuing.

**Implementation:**
```gdscript
func _get_tactical_look_angle() -> float:
    if _memory and _memory.has_target():
        # Look toward last known/suspected player position
        var dir_to_suspected := (_memory.suspected_position - global_position).normalized()
        return dir_to_suspected.angle()
    return velocity.normalized().angle()
```

**Pros:**
- Uses existing memory system
- Contextually appropriate (looks where player was last seen)
- Integrates with other AI systems

**Cons:**
- Requires active memory
- May look at outdated positions

### Solution 4: Hybrid Approach (Most Complete)

**Concept:** Combine path look-ahead with target-aware corner checking.

**Priority:**
1. If can see player → look at player (existing)
2. If at corner AND have target memory → look toward target
3. If navigating → look ahead on path
4. If moving → look in movement direction
5. If idle → idle scan (existing)

---

## Existing Libraries/Components That Could Help

### 1. GDX-AI Steering Behaviors (LibGDX)
- [GitHub - libgdx/gdx-ai](https://github.com/libgdx/gdx-ai/wiki/Steering-Behaviors)
- Implements obstacle avoidance with ray casting look-ahead
- Could be ported/adapted for Godot

### 2. Surfacer (Godot 3)
- [GitHub - SnoringCatGames/surfacer](https://github.com/SnoringCatGames/surfacer)
- AI and pathfinding for 2D platformers
- Uses character-behavior system with states like "follow", "wander"

### 3. Context Steering (Game AI Pro 2)
- [Game AI Pro 2 - Chapter 18](http://www.gameaipro.com/GameAIPro2/GameAIPro2_Chapter18_Context_Steering_Behavior-Driven_Steering_at_the_Macro_Scale.pdf)
- Context-based steering at macro scale
- Can combine multiple behaviors naturally

### 4. NavigationAgent2D Enhancements
- Godot's NavigationAgent2D already provides `get_current_navigation_path()`
- Can be extended with path-aware rotation

---

## Recommended Implementation

Based on the analysis, **Solution 4 (Hybrid Approach)** is recommended because:

1. It maintains backward compatibility
2. It uses existing systems (memory, navigation)
3. It provides the most realistic tactical behavior
4. It can be implemented incrementally

### Priority Implementation Order:

1. **Phase 1:** Add target-aware corner checking in `_process_corner_check()`
2. **Phase 2:** Add path look-ahead rotation in `_update_enemy_model_rotation()`
3. **Phase 3:** Integrate with memory system for smarter look direction
4. **Phase 4:** Tune parameters and test edge cases

---

## Test Cases

1. **Corner Approach Test:**
   - Enemy pursues player around a corner
   - Expected: Enemy looks around corner before rounding it

2. **Multiple Corners Test:**
   - Enemy navigates through corridor with multiple turns
   - Expected: Enemy anticipates each turn direction

3. **Back-to-Wall Test:**
   - Player hides behind obstacle
   - Enemy approaches
   - Expected: Enemy doesn't expose back to potential ambush position

4. **Memory Decay Test:**
   - Player moves while enemy can't see
   - Enemy should look toward last known position
   - After memory decay, should scan more broadly

---

## References

- [Steering Behaviors For Autonomous Characters - Craig Reynolds](https://www.red3d.com/cwr/steer/gdc99/)
- [Introduction to Steering Behaviours - Game Developer](https://www.gamedeveloper.com/design/introduction-to-steering-behaviours)
- [Understanding Steering Behaviors: Path Following - Envato Tuts+](https://gamedevelopment.tutsplus.com/tutorials/understanding-steering-behaviors-path-following--gamedev-8769)
- [The Predictable Problem: Why Stealth Game AI Needs an Overhaul - Wayline](https://www.wayline.io/blog/predictable-problem-stealth-game-ai-overhaul)
- [Context Steering - Game AI Pro 2](http://www.gameaipro.com/GameAIPro2/GameAIPro2_Chapter18_Context_Steering_Behavior-Driven_Steering_at_the_Macro_Scale.pdf)
- [Godot NavigationAgent2D Documentation](https://docs.godotengine.org/en/stable/classes/class_navigationagent2d.html)

---

## User Feedback Log

### 2026-01-25: Feedback from PR #358

**User comment (translated from Russian):**
> "The problem remains. The enemy should check each new corner angle (at least look at each unexplored corner for a second)."

**New log file added:** `game_log_20260125_041941.txt`

**Analysis of new log:**
- Log shows PURSUING and FLANKING corner checks still using perpendicular angles
- Example from log:
  ```
  [04:20:14] [ENEMY] [Enemy4] PURSUING corner check: angle -174.2°
  [04:20:14] [ENEMY] [Enemy3] PURSUING corner check: angle -128.3°
  [04:20:14] [ENEMY] [Enemy2] FLANKING corner check: angle 83.1°
  ```
- The corner check angles are perpendicular to movement, NOT toward the suspected target position
- Corner check duration is only 0.3 seconds (user requests at least 1 second)

**Action Required:**
1. Implement target-aware corner checking - when in tactical states (PURSUING, FLANKING, SEARCHING), look toward the suspected player position instead of perpendicular to movement
2. Increase corner check duration from 0.3s to 1.0s per user feedback

---

### 2026-01-25: Second Feedback from PR #358

**User comment (translated from Russian):**
> "Enemy quickly turns away when player enters their field of view.
> Return corner check to 0.3s, but the enemy should check all corners with line of fire (center of FOV) as soon as there's an opportunity (can turn and corner becomes visible)."

**New log file added:** `game_log_20260125_050557.txt`

**Analysis of issue:**
The user identified TWO separate problems:

1. **Enemy turns away too quickly after seeing player:**
   - When player enters enemy FOV, enemy looks at player (correct)
   - When player exits FOV, enemy immediately turns toward movement direction (bug)
   - Expected: Enemy should continue looking toward where player was for a moment

2. **Corner check duration too long at 1.0s:**
   - User prefers quick 0.3s glances at corners
   - But wants MORE corners to be checked, not longer checks

**Root Cause:**
In `_update_enemy_model_rotation()`:
- Priority 1: Player visible → look at player
- Priority 2: Corner check timer active → look at corner
- Priority 3: Moving → look in movement direction

When player exits FOV, if corner check timer has already expired, enemy immediately goes to Priority 3 (movement direction), causing the "turn away" behavior.

**Fix Implementation:**

1. **Reverted CORNER_CHECK_DURATION to 0.3s** (per user request)

2. **Added "hold aim" on visibility loss:**
   In `_check_player_visibility()`, when enemy loses sight in tactical states (COMBAT, PURSUING, FLANKING, SEARCHING):
   - Set `_corner_check_angle` toward player's last position
   - Set `_corner_check_timer = CORNER_CHECK_DURATION`
   - This keeps enemy looking toward the threat for 0.3s after losing sight

3. **Enhanced tactical corner scanning:**
   In `_detect_tactical_opening()`:
   - Now scans multiple angles, not just perpendicular
   - Priority order:
     1. Direction to suspected target (if differs from movement/facing)
     2. Flanking angles (45° offset from target)
     3. Perpendicular angles (standard corner check)
   - Only triggers for angles the enemy isn't already facing

**Code Changes:**

```gdscript
# In _check_player_visibility() - hold aim when losing sight
if was_visible and _player and _current_state in [AIState.COMBAT, AIState.PURSUING, AIState.FLANKING, AIState.SEARCHING]:
    var dir_to_player := (_player.global_position - global_position).normalized()
    _corner_check_angle = dir_to_player.angle()
    _corner_check_timer = CORNER_CHECK_DURATION
    _log_to_file("Lost sight in %s: holding aim toward (%.1f°)" % [AIState.keys()[_current_state], rad_to_deg(_corner_check_angle)])

# In _detect_tactical_opening() - scan multiple angles with priorities
# 1. Check target direction first (priority)
# 2. Check flanking angles (45° offset each side)
# 3. Fall back to perpendicular check
```

**Expected Behavior After Fix:**
1. Enemy sees player → looks at player
2. Player exits FOV → enemy holds aim toward player for 0.3s
3. During movement, enemy proactively scans toward suspected target and flanking angles
4. Quick 0.3s glances at each corner/angle

---
