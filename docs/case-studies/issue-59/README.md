# Case Study: Issue #59 - Enemy Cover-Edge Aiming Behavior

## Issue Description

**Original Issue (Russian):**
> когда игрок предположительно за укрытием (враг не может попасть) враг всё равно поворачивается в сторону движения игрока.
> должно быть так - когда игрок скрылся за укрытием, и это видит враг, это укрытие считается укрытием игрока, враги должны держать прицел чуть выше или чуть ниже этого укрытия (целится туда, от куда может появиться игрок).
> статус укрытия игрока сбрасывается когда враг видит игрока снова.

**Translation:**
When the player is presumably behind cover (enemy cannot hit them), the enemy still turns toward the player's movement direction.

**Expected behavior:**
- When the player hides behind cover (and the enemy sees this), this cover is considered the player's cover
- Enemies should aim slightly above or below this cover (aim where the player might emerge from)
- The cover status resets when the enemy sees the player again

## User Feedback After Initial Fix

The user reported: "enemies are still turning to follow the player's movements" (враги всё ещё поворачиваются вслед за движениями игрока)

## Root Cause Analysis

### Code Flow Analysis

1. **Visibility Detection** (`_check_player_visibility()` at line 1149-1206):
   - When player hides behind cover, `_can_see_player` is set to `false`
   - The variable `_is_player_behind_cover` is set to `true`
   - The cover position is recorded in `_player_cover_position`

2. **Combat State Processing** (`_process_combat_state()` at line 559-588):
   - **THE BUG**: At line 569-573, when `_can_see_player` becomes `false`:
   ```gdscript
   if not _can_see_player:
       if enable_flanking and _player:
           _transition_to_flanking()
       else:
           _transition_to_idle()
       return
   ```
   - The enemy **immediately transitions to FLANKING or IDLE state**
   - The `_aim_at_player()` function (which has cover-edge aiming logic) **is never called**

3. **State Behavior Analysis**:
   - **FLANKING state** (`_process_flanking_state()`): Sets rotation toward flank target (line 700)
   - **IDLE/GUARD state** (`_process_guard()`): Does not call `_aim_at_player()`
   - **IDLE/PATROL state** (`_process_patrol()`): Sets rotation toward movement direction (line 1440)

### The Problem

The cover-edge aiming logic in `_aim_at_player()` (lines 1247-1275) is **correctly implemented** but **never executed** because:

1. When player hides behind cover, `_can_see_player = false`
2. Combat state immediately transitions to another state before `_aim_at_player()` can be called
3. The new states (FLANKING, IDLE) have their own rotation logic that tracks different targets

## Industry Research

### Standard Approaches in Game AI

Based on research from game development resources:

1. **F.E.A.R. (2005)** - Used Goal Oriented Action Planning (GOAP) where enemies:
   - Track player's last known position
   - Flank and suppress simultaneously
   - Wait at cover edges for player to emerge

2. **Tom Clancy's The Division** - Enemy roles designed to:
   - Force players out of cover (throwers)
   - Maintain angles on cover (snipers)
   - Rush to break player's cover advantage

3. **Common "Last Known Position" Pattern**:
   - Enemy records player's last visible position and direction
   - When player breaks line of sight, enemy aims at last known position
   - Enemy may search or wait at predicted emergence points

### Key Design Principles

From [The Level Design Book](https://book.leveldesignbook.com/process/combat/cover):
> Cover depends on angles -- the combatants' sightlines as they rotate around corners.

From [AiGameDev.com](http://aigamedev.com/open/article/cover-strategies/):
> Raycasting to trace lines from the player to potential cover geometry, determining if obstacles block enemy line-of-sight.

From [GameDev.net](https://www.gamedev.net/forums/topic/709899-question-about-enemy-ai/):
> The AI casts a ray to the player to verify the player is still visible. It also continuously records the player's last visible position, and records the player's last visible velocity (direction).

## Proposed Solutions

### Solution 1: Stay in Combat State While Tracking Cover (Recommended)

**Approach**: Modify `_process_combat_state()` to NOT transition to flanking/idle when player is behind cover.

**Changes**:
```gdscript
func _process_combat_state(delta: float) -> void:
    velocity = Vector2.ZERO

    # Check for suppression - high priority
    if _under_fire and enable_cover:
        _transition_to_seeking_cover()
        return

    # If player is behind cover, stay in combat and aim at cover edges
    # Don't transition to flanking or idle - keep watching the cover
    if _is_player_behind_cover:
        if _player:
            _aim_at_player()  # This will use cover-edge aiming
        return

    # If can't see player AND not tracking cover, try flanking or return to idle
    if not _can_see_player:
        if enable_flanking and _player:
            _transition_to_flanking()
        else:
            _transition_to_idle()
        return

    # ... rest of combat logic ...
```

**Pros**:
- Minimal code changes
- Uses existing cover-edge aiming logic
- Clear behavioral distinction: player behind cover vs player gone

**Cons**:
- Enemy stays stationary while waiting at cover

### Solution 2: Add New AI State for Cover Watching

**Approach**: Create a new `AIState.WATCHING_COVER` state specifically for this behavior.

**Pros**:
- Clean separation of concerns
- Can add more complex behaviors (e.g., timer before flanking)
- Better for debugging and state visualization

**Cons**:
- More code to maintain
- Need to handle all state transitions

### Solution 3: Hybrid Approach with Timer

**Approach**: Stay in combat briefly, then flank after a delay.

**Pros**:
- More dynamic behavior
- Prevents enemies from permanently staring at cover
- Feels more intelligent

**Cons**:
- More complex implementation
- Need to tune timing parameters

## Recommended Implementation

**Solution 1** is recommended for the following reasons:

1. **Simplest fix** - Only need to add a condition check
2. **Uses existing code** - The cover-edge aiming logic is already implemented and correct
3. **Matches user expectation** - Enemy should aim at cover edges where player might emerge
4. **Easy to verify** - Clear success criteria

## Success Criteria

1. When player hides behind cover, enemy stops tracking player movement
2. Enemy aims at the edge of cover where player disappeared
3. When player becomes visible again, normal tracking resumes
4. The fix should be verifiable by enabling `debug_logging` and observing log messages

## Follow-up Issue: Enemies Getting Stuck During Movement

### User Feedback (January 2026)

After the initial fix was deployed, the user reported:
> "debug_logging включить не могу, потому что в собранном exe нет такой функции. враги пытаются двигаться, но застревают."
>
> Translation: "I can't enable debug_logging because the compiled exe doesn't have that function. Enemies are trying to move but get stuck."

### Root Cause Analysis

The enemies were getting stuck due to several issues in the movement and pathfinding logic:

#### 1. Ineffective Wall Avoidance

**Original implementation** (`_check_wall_ahead()`):
- Used only 3 raycasts at narrow angles (-28°, 0°, +28°)
- `WALL_CHECK_DISTANCE` was only 40 pixels (enemy radius is 24 pixels)
- Random direction choice for center raycast hits caused jittering
- 50/50 blend between movement direction and avoidance was too weak

**Problem**: The narrow angle spread and short detection distance made it easy for enemies to get trapped in corners or against walls.

#### 2. No Stuck Detection

The original code had no mechanism to detect when an enemy was stuck (not making progress toward target). Once stuck, an enemy would keep trying the same approach indefinitely.

#### 3. Invalid Flank Positions

**Original `_calculate_flank_position()`**:
- Calculated a random position without validating if it was actually reachable
- The target could be inside a wall or obstacle
- No fallback positions if the initial position was blocked

### Industry Research on Movement Issues

Based on research from Godot community forums and game development resources:

1. **CharacterBody2D Common Issues** ([Godot Forums](https://forum.godotengine.org/t/movement-stuck-in-2-walls/72424)):
   - Characters can get stuck in corners with standard `move_and_slide()`
   - Wall avoidance raycasts need wider angles to detect obstacles early

2. **Pathfinding Without NavigationAgent** ([abitawake.com](https://abitawake.com/news/articles/enemy-ai-chasing-a-player-without-navigation2d-or-a-star-pathfinding)):
   - Direct path movement works for simple scenarios
   - Need stuck detection and recovery for complex environments
   - Alternative positions should be validated before movement

3. **Enemy Stuck Detection Patterns** ([Godot Forum](https://forum.godotengine.org/t/enemy-gets-stuck/67304)):
   - Track position over time to detect lack of progress
   - Implement retry logic with alternative positions
   - Give up gracefully if movement is impossible

### Solution Implementation

#### Fix 1: Improved Wall Avoidance

```gdscript
## Distance to check for walls ahead.
const WALL_CHECK_DISTANCE: float = 60.0  # Was 40.0

## Number of raycasts for wall detection.
const WALL_CHECK_COUNT: int = 5  # Was 3

# Use 5 raycasts spread from -60° to +60° (every 30 degrees)
# Weight avoidance inversely by distance (closer walls = stronger avoidance)
# Use deterministic direction for center raycast to avoid jitter
```

**Key changes**:
- Increased `WALL_CHECK_DISTANCE` from 40 to 60 pixels
- Increased `WALL_CHECK_COUNT` from 3 to 5
- Widened angle spread from ±28° to ±60°
- Added distance-weighted avoidance (closer walls have more influence)
- Changed avoidance blend from 50/50 to 30/70 (favor avoidance)
- Made center raycast direction deterministic to prevent jitter

#### Fix 2: Stuck Detection System

```gdscript
## Time threshold to consider the enemy "stuck" (in seconds).
const STUCK_DETECTION_TIME: float = 1.0

## Minimum distance the enemy should move in STUCK_DETECTION_TIME to not be considered stuck.
const STUCK_DETECTION_DISTANCE: float = 20.0

## Maximum number of flank position retries before giving up.
const MAX_FLANK_RETRIES: int = 3
```

**New functions**:
- `_check_if_stuck(delta)`: Tracks position over time and detects when enemy hasn't moved enough
- `_reset_stuck_detection()`: Resets tracking when changing states or reaching destination

#### Fix 3: Validated Flank Positions

```gdscript
func _calculate_flank_position() -> void:
    # Try different flank angles if the first one is blocked
    var sides := [initial_side, -initial_side]
    var distance_multipliers := [1.0, 0.7, 0.5, 1.3]

    for distance_mult in distance_multipliers:
        for side in sides:
            var test_position := player_pos + flank_direction * (flank_distance * distance_mult)
            if _is_position_valid(test_position):
                _flank_target = test_position
                return

    # All positions blocked - fall back to moving toward player
    _flank_target = player_pos + player_to_enemy * (flank_distance * 0.5)

func _is_position_valid(pos: Vector2) -> bool:
    # Use physics space state to check if position overlaps with obstacles
    var query := PhysicsPointQueryParameters2D.new()
    query.position = pos
    query.collision_mask = 4  # Only check obstacles (layer 3)
    return space_state.intersect_point(query, 1).is_empty()
```

**Key changes**:
- Validate flank position is not inside an obstacle before using it
- Try alternative positions (other side, closer/farther distances)
- Fall back to moving directly toward player if all positions blocked

### Recovery Behavior

When stuck is detected:
1. **In FLANKING state**: Increment retry counter, try new flank position
2. **After MAX_FLANK_RETRIES (3)**: Give up flanking, return to COMBAT state
3. **In SEEKING_COVER state**: Invalidate cover position, find new cover
4. **State transitions**: Reset stuck detection when changing states

### Testing Recommendations

1. Test in environments with many obstacles and corners
2. Verify enemies can reach flank positions around buildings
3. Check that enemies don't get stuck on cover objects
4. Observe that stuck enemies recover and try alternative approaches

## References

- [Cover System - Level Design Book](https://book.leveldesignbook.com/process/combat/cover)
- [Cover Strategies - AiGameDev.com](http://aigamedev.com/open/article/cover-strategies/)
- [Enemy AI Design - Tom Clancy's The Division](https://www.gamedeveloper.com/design/enemy-ai-design-in-tom-clancy-s-the-division)
- [Enemy AI Question - GameDev.net Forums](https://www.gamedev.net/forums/topic/709899-question-about-enemy-ai/)
- [Enemy NPC Design Patterns in Shooter Games](https://www.academia.edu/2806378/Enemy_NPC_Design_Patterns_in_Shooter_Games)
- [Movement Stuck in Walls - Godot Forum](https://forum.godotengine.org/t/movement-stuck-in-2-walls/72424)
- [Enemy Gets Stuck - Godot Forum](https://forum.godotengine.org/t/enemy-gets-stuck/67304)
- [Enemy AI: Chasing a Player Without Navigation2D](https://abitawake.com/news/articles/enemy-ai-chasing-a-player-without-navigation2d-or-a-star-pathfinding)
