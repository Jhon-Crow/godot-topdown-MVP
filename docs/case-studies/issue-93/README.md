# Case Study: Issue #93 - AI Enemies Stuck in PURSUING State Behind Last Cover

## Executive Summary

This case study analyzes issue #93 where enemy AI in PURSUING state exhibits two problematic behaviors:
1. **Long cover stopping problem**: When moving along a long piece of cover, enemies stop too frequently behind the same cover piece
2. **Last cover stuck problem**: When reaching the final cover before the player, enemies either walk into walls or stand still instead of transitioning to COMBAT state

The PURSUING state was introduced in PR #89 to allow enemies to move cover-to-cover toward the player when they are far away and cannot hit the player from their current position. This case study documents the root causes, proposes solutions, and provides implementation guidance.

## Issue Overview

### Original Request

**Issue #93** (Created: 2026-01-18)
- **Title**: fix ai при PERSUING состоянии застревают за последним укрытием
- **Author**: Jhon-Crow (Repository Owner)

**Translated Requirements**:
1. When an enemy moves along one long cover, they should stop behind it less frequently
2. At the last cover before the player, enemies walk into walls or just stand still instead of switching to COMBAT state

**Additional Request**: Perform deep case study analysis with timeline reconstruction, root cause identification, and proposed solutions.

---

## Timeline of Events

### Phase 1: PURSUING State Implementation (2026-01-17)

1. **PR #89 merged** - "Add PURSUING and ASSAULT states for improved enemy AI combat behavior"
   - Added `PURSUING` state to `AIState` enum
   - Implemented `_process_pursuing_state()` function
   - Added `_find_pursuit_cover_toward_player()` for cover-to-cover movement
   - Fixed initial infinite loop bugs (visibility check, minimum distance)

### Phase 2: Issue Discovery (2026-01-18)

2. **Issue #93 created** - User reports:
   - Enemies stopping too often along long covers
   - Enemies getting stuck at last cover before player
   - Enemies walking into walls instead of engaging

---

## Root Cause Analysis

### Problem 1: Excessive Stopping Along Long Covers

**Code Path Analysis:**

In `_find_pursuit_cover_toward_player()` (lines 2254-2322):

```gdscript
# Cast rays in all directions to find obstacles
for i in range(COVER_CHECK_COUNT):
    var angle := (float(i) / COVER_CHECK_COUNT) * TAU
    var direction := Vector2.from_angle(angle)

    raycast.target_position = direction * COVER_CHECK_DISTANCE
    raycast.force_raycast_update()

    if raycast.is_colliding():
        var collision_point := raycast.get_collision_point()
        var collision_normal := raycast.get_collision_normal()

        # Cover position is offset from collision point along normal
        var cover_pos := collision_point + collision_normal * 35.0

        # Score calculation:
        # - Hidden from player (priority)
        # - Closer to player
        # - Not too far from current position
        var hidden_score: float = 5.0 if is_hidden else 0.0
        var approach_score: float = (my_distance_to_player - cover_distance_to_player) / CLOSE_COMBAT_DISTANCE
        var distance_penalty: float = cover_distance_from_me / COVER_CHECK_DISTANCE
```

**Bug**: The scoring system favors cover positions that are:
1. Hidden from player (weighted heavily with +5.0)
2. Closer to player than current position
3. Not too far from current position

However, when moving along a long wall, the algorithm continuously finds positions along the same wall that score well. Each position is only slightly closer to the player, causing the enemy to:
1. Stop at position A
2. Wait 1.5 seconds (PURSUIT_COVER_WAIT_DURATION)
3. Find position B (10-50 pixels closer on same wall)
4. Move to B
5. Wait 1.5 seconds
6. Repeat...

**Root Cause**: No differentiation between cover from the **same obstacle** vs cover from a **different obstacle**. The algorithm should prefer moving to a distinctly different cover position rather than shuffling along the same wall.

### Problem 2: Stuck at Last Cover Before Player

**Code Path Analysis:**

In `_process_pursuing_state()` (lines 1460-1549):

```gdscript
# If can see player and can hit them from current position, engage
if _can_see_player and _player:
    var can_hit := _can_hit_player_from_current_position()
    if can_hit:
        _log_debug("Can see and hit player from pursuit, transitioning to COMBAT")
        _has_pursuit_cover = false
        _transition_to_combat()
        return

# Check if we're waiting at cover
if _has_valid_cover and not _has_pursuit_cover:
    _pursuit_cover_wait_timer += delta
    velocity = Vector2.ZERO

    if _pursuit_cover_wait_timer >= PURSUIT_COVER_WAIT_DURATION:
        _find_pursuit_cover_toward_player()
        if _has_pursuit_cover:
            _log_debug("Found pursuit cover at %s" % _pursuit_next_cover)
        else:
            # No pursuit cover found - fallback behavior
            if _can_see_player:
                _transition_to_combat()
                return
            # Try flanking
            if enable_flanking and _player:
                _transition_to_flanking()
                return
            # Last resort: move directly toward player
            _transition_to_combat()
            return
```

**Bug Scenario**: When the enemy is at the last cover before the player:

1. `_can_see_player` is true (player is visible)
2. `_can_hit_player_from_current_position()` returns false (cover blocks shot)
3. Enemy waits at cover (timer counting)
4. Timer expires, calls `_find_pursuit_cover_toward_player()`
5. No cover found closer to player (we're at the closest one)
6. `_has_pursuit_cover = false`
7. Fallback: checks `if _can_see_player` again
8. **Critical**: At this exact moment, visibility may fluctuate (player moving, cover edge occlusion)
9. If visibility check fails, tries flanking (may also fail)
10. If flanking disabled or fails, loop continues

**Additional Bug**: Even if the enemy transitions to COMBAT, the COMBAT state's `_process_combat_state()` has its own logic that may immediately transition back to PURSUING if the enemy can't hit the player:

```gdscript
# In _process_combat_state():
if _can_see_player:
    if player_close:
        # Engage
    else:
        if can_hit:
            # Continue combat
        else:
            # Can't hit from here - need to pursue
            _transition_to_pursuing()  # BACK TO PURSUING!
```

This creates a ping-pong effect where the enemy oscillates between PURSUING and COMBAT without ever actually approaching the player.

**Root Cause**: The PURSUING state's fallback behavior doesn't account for the "can see but can't hit" scenario at the last cover. The enemy should either:
1. Move out of cover toward the player (approach phase)
2. Sidestep to get a clear shot
3. Use the COMBAT state's approach phase properly

### Problem 3: Walking Into Walls

**Code Path Analysis:**

In `_process_pursuing_state()` when moving toward pursuit cover:

```gdscript
if _has_pursuit_cover:
    var direction := (_pursuit_next_cover - global_position).normalized()
    var distance := global_position.distance_to(_pursuit_next_cover)

    # Apply wall avoidance
    var avoidance := _check_wall_ahead(direction)
    if avoidance != Vector2.ZERO:
        direction = (direction * 0.5 + avoidance * 0.5).normalized()

    velocity = direction * combat_move_speed
```

**Bug**: The wall avoidance blending (50/50 with original direction) may not be sufficient when the target cover position is:
1. On the opposite side of a wall from the enemy
2. Calculated based on raycast collision normal that doesn't account for pathfinding

When `_find_pursuit_cover_toward_player()` finds a cover position, it uses:
```gdscript
var cover_pos := collision_point + collision_normal * 35.0
```

This offset of 35 pixels from the collision point may place the cover position in an unreachable location if there's a wall between the enemy and that position.

**Root Cause**: The cover position calculation assumes the enemy can reach the position directly, but doesn't verify the path is clear.

---

## Technical Deep Dive

### PURSUING State Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                      PURSUING STATE                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Entry: _transition_to_pursuing()                         │   │
│  │  - Reset pursuit timer                                   │   │
│  │  - Clear pursuit cover flag                              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Check: Under fire?                                       │   │
│  │  YES → RETREATING                                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                           │ NO                                  │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Check: Multiple enemies in combat?                       │   │
│  │  YES → ASSAULT                                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                           │ NO                                  │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Check: Can see AND hit player?                           │   │
│  │  YES → COMBAT                                            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                           │ NO                                  │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Check: At valid cover, no pursuit target?                │   │
│  │  YES → Wait (timer += delta)                             │   │
│  │        Timer done? → Find next cover                     │   │
│  │          Found? → Set pursuit target                     │   │
│  │          Not found? → Fallback (COMBAT/FLANKING)         │◄─┐│
│  └─────────────────────────────────────────────────────────┘   ││
│                           │                                     ││
│                           ▼                                     ││
│  ┌─────────────────────────────────────────────────────────┐   ││
│  │ Check: Has pursuit cover target?                         │   ││
│  │  YES → Move toward target                                │   ││
│  │        Reached? → Mark as current cover, reset  ─────────┼───┘│
│  └─────────────────────────────────────────────────────────┘   │
│                           │ NO                                  │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Find initial pursuit cover                               │   │
│  │  Found? → Continue                                       │   │
│  │  Not found? → FLANKING or COMBAT                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Cover Finding Algorithm

The `_find_pursuit_cover_toward_player()` function:

1. Casts rays in 16 directions (COVER_CHECK_COUNT)
2. For each ray that hits an obstacle:
   - Calculate cover position (collision point + normal * 35)
   - Skip if not closer to player
   - Skip if too close to current position (< 30 pixels)
   - Check if hidden from player
   - Calculate score based on: hidden (+5), approach distance, distance penalty
3. Select best-scoring cover

**Current Scoring Formula:**
```
total_score = hidden_score + approach_score * 2.0 - distance_penalty
where:
  hidden_score = 5.0 if hidden, else 0.0
  approach_score = (my_distance_to_player - cover_distance_to_player) / CLOSE_COMBAT_DISTANCE
  distance_penalty = cover_distance_from_me / COVER_CHECK_DISTANCE
```

---

## Industry Best Practices Research

### Cover-Based AI in Commercial Games

According to research on game AI systems:

1. **F.E.A.R. (2005)** - Pioneered dynamic cover-based AI using GOAP
   - Enemies evaluate cover quality based on protection level and firing angles
   - Use "tactical positions" rather than arbitrary wall positions
   - [Source: Building the AI of F.E.A.R.](https://www.gamedeveloper.com/design/building-the-ai-of-f-e-a-r-with-goal-oriented-action-planning)

2. **The Last of Us Part II** - Uses "awareness states" with priority-based cover selection
   - Enemies remember where player was last seen
   - Cover positions are pre-calculated at level design time
   - [Source: AI in Gaming](https://www.lizard.global/en/blog/ai-in-gaming-how-ai-is-used-to-create-intelligent-game-characters-opponents)

3. **Metal Gear Solid Series** - Cover-to-cover movement with "investigation" behavior
   - Enemies take cover to call for backup
   - Blind fire and grenade throwing from cover
   - [Source: Wikipedia - Cover System](https://en.wikipedia.org/wiki/Cover_system)

### Recommended Patterns

1. **Pre-placed Cover Points**: Instead of runtime raycast detection, define cover positions at level design time
   - Faster evaluation
   - Guaranteed reachability
   - Can be tagged with metadata (facing direction, protection level)

2. **Cover Graph**: Connect cover points in a navigation graph
   - Enables pathfinding between covers
   - Prevents selection of unreachable covers
   - Allows "leapfrog" movement patterns

3. **Tactical Position Evaluation**: Score covers based on:
   - Line of sight to player
   - Line of fire (can hit player from this position?)
   - Exposure (how much of enemy is visible to player)
   - Distance factors
   - **Same-obstacle penalty** (don't pick another spot on same wall)

4. **Approach Behavior**: When no better cover exists:
   - Use suppression fire while moving
   - Move to intermediate "assault positions"
   - Coordinate with other enemies for covering fire

---

## Proposed Solutions

### Solution 1: Add Same-Obstacle Detection (Recommended)

Modify `_find_pursuit_cover_toward_player()` to track which obstacle each cover belongs to and penalize covers on the same obstacle:

```gdscript
func _find_pursuit_cover_toward_player() -> void:
    if _player == null:
        _has_pursuit_cover = false
        return

    var player_pos := _player.global_position
    var best_cover: Vector2 = Vector2.ZERO
    var best_score: float = -INF
    var found_valid_cover: bool = false
    var current_obstacle: Object = null

    # Track current cover's obstacle
    if _has_valid_cover:
        # Cast ray to current cover to find its obstacle
        var to_current := (_cover_position - global_position).normalized()
        for i in range(COVER_CHECK_COUNT):
            var raycast := _cover_raycasts[i]
            raycast.force_raycast_update()
            if raycast.is_colliding():
                var dist := global_position.distance_to(raycast.get_collision_point())
                if dist < 50.0:  # Close to current cover
                    current_obstacle = raycast.get_collider()
                    break

    for i in range(COVER_CHECK_COUNT):
        var angle := (float(i) / COVER_CHECK_COUNT) * TAU
        var direction := Vector2.from_angle(angle)

        var raycast := _cover_raycasts[i]
        raycast.target_position = direction * COVER_CHECK_DISTANCE
        raycast.force_raycast_update()

        if raycast.is_colliding():
            var collision_point := raycast.get_collision_point()
            var collision_normal := raycast.get_collision_normal()
            var collider := raycast.get_collider()

            var cover_pos := collision_point + collision_normal * 35.0

            # ... existing distance checks ...

            # Penalize same obstacle
            var same_obstacle_penalty: float = 0.0
            if current_obstacle != null and collider == current_obstacle:
                same_obstacle_penalty = 3.0  # Significant penalty

            var total_score: float = hidden_score + approach_score * 2.0 - distance_penalty - same_obstacle_penalty
```

### Solution 2: Add Approach Phase When No Cover Found

When at the last cover and no better cover exists, add an "approach" sub-state within PURSUING:

```gdscript
## Whether the enemy is in approach phase (moving toward player without cover)
var _pursuit_approaching: bool = false

## Timer for approach phase
var _pursuit_approach_timer: float = 0.0

## Maximum time to approach before giving up
const PURSUIT_APPROACH_MAX_TIME: float = 3.0

func _process_pursuing_state(delta: float) -> void:
    # ... existing checks ...

    # If in approach phase, move toward player
    if _pursuit_approaching:
        if _player:
            var direction := (_player.global_position - global_position).normalized()
            var can_hit := _can_hit_player_from_current_position()

            _pursuit_approach_timer += delta

            # If we can now hit the player, transition to combat
            if can_hit:
                _log_debug("Can now hit player after approach, transitioning to COMBAT")
                _pursuit_approaching = false
                _transition_to_combat()
                return

            # If approach timer expired, give up and find new cover or engage
            if _pursuit_approach_timer >= PURSUIT_APPROACH_MAX_TIME:
                _log_debug("Approach timer expired, transitioning to COMBAT")
                _pursuit_approaching = false
                _transition_to_combat()
                return

            # Apply wall avoidance and move
            var avoidance := _check_wall_ahead(direction)
            if avoidance != Vector2.ZERO:
                direction = (direction * 0.5 + avoidance * 0.5).normalized()

            velocity = direction * combat_move_speed
            rotation = direction.angle()
        return

    # ... existing cover waiting logic ...

    # When no cover found, start approach phase instead of immediate transition
    if _pursuit_cover_wait_timer >= PURSUIT_COVER_WAIT_DURATION:
        _find_pursuit_cover_toward_player()
        if _has_pursuit_cover:
            _log_debug("Found pursuit cover at %s" % _pursuit_next_cover)
        else:
            # No pursuit cover found - start approach phase
            if _can_see_player:
                _log_debug("No cover found but can see player, starting approach phase")
                _pursuit_approaching = true
                _pursuit_approach_timer = 0.0
                return
            # ... rest of fallback logic ...
```

### Solution 3: Add Minimum Progress Requirement

Require that each new cover position makes significant progress toward the player:

```gdscript
## Minimum distance progress required for a valid pursuit cover (percentage of current distance)
const PURSUIT_MIN_PROGRESS_PERCENT: float = 0.15  # Must be at least 15% closer

func _find_pursuit_cover_toward_player() -> void:
    # ...
    var my_distance_to_player := global_position.distance_to(player_pos)
    var min_required_progress := my_distance_to_player * PURSUIT_MIN_PROGRESS_PERCENT

    # ...

    for i in range(COVER_CHECK_COUNT):
        # ...
        if raycast.is_colliding():
            # ...
            var cover_distance_to_player := cover_pos.distance_to(player_pos)
            var progress := my_distance_to_player - cover_distance_to_player

            # Skip covers that don't make enough progress
            if progress < min_required_progress:
                continue

            # ... rest of scoring ...
```

### Solution 4: Verify Path to Cover Position

Add pathfinding validation to ensure the enemy can reach the selected cover:

```gdscript
## Check if there's a clear path to a position (no walls blocking)
func _can_reach_position(target: Vector2) -> bool:
    var space_state := get_world_2d().direct_space_state
    var query := PhysicsRayQueryParameters2D.new()
    query.from = global_position
    query.to = target
    query.collision_mask = 4  # Obstacles only
    query.exclude = [get_rid()]

    var result := space_state.intersect_ray(query)
    if result.is_empty():
        return true

    # Check if obstacle is beyond the target
    var hit_distance := global_position.distance_to(result["position"])
    var target_distance := global_position.distance_to(target)
    return hit_distance >= target_distance - 10.0

func _find_pursuit_cover_toward_player() -> void:
    # ...
    for i in range(COVER_CHECK_COUNT):
        if raycast.is_colliding():
            # ...
            var cover_pos := collision_point + collision_normal * 35.0

            # Verify we can reach this position
            if not _can_reach_position(cover_pos):
                continue

            # ... rest of scoring ...
```

---

## Implementation Recommendations

### Priority Order

1. **Solution 1 + 3** (Combined): Add same-obstacle detection AND minimum progress requirement
   - Directly addresses the "long cover stopping" problem
   - Low risk of breaking existing functionality
   - Easy to test and verify

2. **Solution 2**: Add approach phase
   - Addresses the "stuck at last cover" problem
   - Provides graceful fallback when no cover exists
   - Requires more careful testing

3. **Solution 4**: Path verification
   - Addresses the "walking into walls" problem
   - May have performance implications (additional raycasts)
   - Should be implemented with caching if performance is a concern

### Testing Checklist

1. **Long Cover Test**:
   - [ ] Place enemy behind a long wall (100+ pixels)
   - [ ] Player visible but far away
   - [ ] Enemy should NOT stop multiple times along same wall
   - [ ] Enemy should skip to the end of the wall or find different cover

2. **Last Cover Test**:
   - [ ] Place enemy at cover position closest to player
   - [ ] Player visible but shot blocked by cover edge
   - [ ] Enemy should approach player (not stand still)
   - [ ] Enemy should eventually engage in COMBAT

3. **Path Obstruction Test**:
   - [ ] Create scenario where calculated cover is behind a wall
   - [ ] Enemy should NOT walk into the wall
   - [ ] Enemy should find alternative cover or engage

4. **Regression Tests**:
   - [ ] Normal cover-to-cover pursuit still works
   - [ ] ASSAULT state coordination still works
   - [ ] COMBAT state cycling still works
   - [ ] RETREATING under fire still works

---

## Data Files

This case study includes the following data files:

| File | Description |
|------|-------------|
| `issue-93-details.json` | Full issue data from GitHub API |
| `issue-88-details.json` | Related issue #88 (original PURSUING bugs) |
| `pr-89-details.json` | PR that introduced PURSUING state |
| `pr-89-diff.txt` | Code changes in PR #89 |
| `pr-89-review-comments.json` | PR #89 review comments |
| `pr-89-conversation-comments.json` | PR #89 conversation comments |

---

## References

### Primary Sources
- [Issue #93](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/93) - Current issue
- [Issue #88](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/88) - Original PURSUING state bugs
- [PR #89](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/89) - PURSUING state implementation

### Research Sources
- [Building the AI of F.E.A.R.](https://www.gamedeveloper.com/design/building-the-ai-of-f-e-a-r-with-goal-oriented-action-planning)
- [Designing a Simple Game AI Using FSMs](https://www.gamedeveloper.com/programming/designing-a-simple-game-ai-using-finite-state-machines)
- [Finite State Machines: Theory and Implementation](https://code.tutsplus.com/finite-state-machines-theory-and-implementation--gamedev-11867t)
- [Game Programming Patterns - State](https://gameprogrammingpatterns.com/state.html)
- [AI in Gaming](https://www.lizard.global/en/blog/ai-in-gaming-how-ai-is-used-to-create-intelligent-game-characters-opponents)
- [Wikipedia - Cover System](https://en.wikipedia.org/wiki/Cover_system)

### Godot Resources
- [GDQuest - Finite State Machine in Godot 4](https://www.gdquest.com/tutorial/godot/design-patterns/finite-state-machine/)
- [GameDev Academy - Godot State Machine Tutorial](https://gamedevacademy.org/godot-state-machine-tutorial/)
- [Godot Forum - State Machines and Enemy AI](https://forum.godotengine.org/t/state-machines-and-enemy-ai/111974)

---

## Conclusion

Issue #93 stems from two distinct problems in the PURSUING state implementation:

1. **Excessive stopping along long covers**: The cover-finding algorithm doesn't distinguish between different obstacles, leading to repeated small movements along the same wall.

2. **Getting stuck at last cover**: When no better cover exists, the fallback logic doesn't properly handle the "can see but can't hit" scenario, leading to state oscillation or inaction.

The recommended approach is to implement:
1. Same-obstacle detection with scoring penalty
2. Minimum progress requirement for cover selection
3. Approach phase when no cover is available
4. Path verification before selecting a cover

These changes will create more natural enemy movement that doesn't stop unnecessarily and can gracefully handle edge cases.

---

## Addendum: Second Analysis (2026-01-18)

### New User Feedback

The repository owner provided additional feedback with game logs:

> "враг должен обходить последнее укрытие. сейчас утыкается в него в том месте, за которым игрок."
> (Translation: "Enemy should go around the last cover. Currently runs into it at the spot behind which the player is.")
>
> "возможно проблема так же в COMBAT или FLANKING состоянии."
> (Translation: "Possibly the problem is also in the COMBAT or FLANKING state.")

### New Game Logs Analysis

Two new game logs were provided:
- `logs/game_log_20260118_064145.txt`
- `logs/game_log_20260118_065215.txt`

**Key Observations from Log 1:**
- Enemy10 shows `PURSUING -> FLANKING -> COMBAT -> PURSUING` rapid cycling (lines 33-44)
- Enemy3 shows `PURSUING -> COMBAT -> PURSUING` rapid cycling (lines 107-122)
- Enemy3 goes `PURSUING -> FLANKING -> COMBAT -> PURSUING` (lines 111-113, 118-120)

**Key Observations from Log 2:**
- Enemy10 shows rapid `SUPPRESSED -> SEEKING_COVER -> IN_COVER -> SUPPRESSED` cycling (lines 54-92) - this is a separate bug
- Enemy7 shows repeated `PURSUING -> FLANKING -> COMBAT -> PURSUING` rapid cycles (lines 140-195)
- Many FLANKING state transitions that immediately go back to COMBAT → PURSUING

### Root Cause: FLANKING State Premature Transition

**Critical Bug Found**: In `_process_flanking_state()` (line 1194-1196):

```gdscript
# If can see player, engage in combat
if _can_see_player:
    _transition_to_combat()
    return
```

This causes the FLANKING state to immediately exit if the enemy can see the player, even if the enemy **cannot actually hit** the player due to a wall blocking the shot.

**Bug Sequence:**
1. Enemy at last cover, player visible but wall blocks shot
2. Enemy in PURSUING can't find better cover
3. Transitions to FLANKING to get around obstacle
4. FLANKING checks `_can_see_player` → true → immediately goes to COMBAT
5. COMBAT checks if can hit → can't → goes to seeking clear shot → times out → FLANKING
6. Loop repeats every few seconds without enemy actually moving around the obstacle

### Additional Bug: Random Flank Side Each Frame

In `_calculate_flank_position()` (line 2590):

```gdscript
var flank_side := 1.0 if randf() > 0.5 else -1.0
```

This is called every frame in FLANKING state, causing the flank direction to randomly switch. The enemy never commits to going around one side of the obstacle.

### Fix Implemented

**Fix 1**: Changed FLANKING state to check `_can_hit_player_from_current_position()` instead of just `_can_see_player`:

```gdscript
# Only transition to combat if we can ACTUALLY HIT the player, not just see them.
if _can_see_player and _can_hit_player_from_current_position():
    _log_debug("Can see AND hit player from flanking position, engaging")
    _transition_to_combat()
    return
```

**Fix 2**: Added `_flank_side` variable that is set once when entering FLANKING state, and `_choose_best_flank_side()` function to intelligently select the side with fewer obstacles:

```gdscript
## The side to flank on (1.0 = right, -1.0 = left). Set once when entering FLANKING state.
var _flank_side: float = 1.0

## Whether flank side has been initialized for this flanking maneuver.
var _flank_side_initialized: bool = false

func _transition_to_flanking() -> void:
    _current_state = AIState.FLANKING
    # Initialize flank side only once per flanking maneuver
    _flank_side = _choose_best_flank_side()
    _flank_side_initialized = true
    # ...
```

**Fix 3**: Updated debug label to show flank direction (L/R) for easier debugging.

### Testing Recommendations

1. **Last Cover Flanking Test:**
   - Enemy at cover, player behind same cover on other side
   - Enemy should enter FLANKING and consistently move in one direction
   - Should NOT rapidly cycle between states
   - Should eventually reach a position with clear shot

2. **Blocked Shot Continuation Test:**
   - Enemy can see player but wall blocks shot
   - FLANKING should continue until clear shot is available
   - Should NOT immediately transition to COMBAT just because player is visible

---

*Case Study Updated: 2026-01-18*
*Author: AI Issue Solver (Claude)*
