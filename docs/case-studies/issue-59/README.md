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

## References

- [Cover System - Level Design Book](https://book.leveldesignbook.com/process/combat/cover)
- [Cover Strategies - AiGameDev.com](http://aigamedev.com/open/article/cover-strategies/)
- [Enemy AI Design - Tom Clancy's The Division](https://www.gamedeveloper.com/design/enemy-ai-design-in-tom-clancy-s-the-division)
- [Enemy AI Question - GameDev.net Forums](https://www.gamedev.net/forums/topic/709899-question-about-enemy-ai/)
- [Enemy NPC Design Patterns in Shooter Games](https://www.academia.edu/2806378/Enemy_NPC_Design_Patterns_in_Shooter_Games)
