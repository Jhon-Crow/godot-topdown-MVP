# Case Study: Issue #110 - FLANKING State AI Bug

## Issue Summary

**Issue**: Fix FLANKING AI - enemies rotate 90 degrees and freeze when in FLANKING state
**Reporter**: Jhon-Crow
**Date**: 2026-01-18

### Original Description (Russian)
> в состоянии FLENKING враги просто поворачиваются на 90 градусов и замирают
> (In FLANKING state enemies just rotate 90 degrees and freeze)
>
> исправь карту - чтоб в углах не было промежутков, сейчас в стыки между стенами видит ai и это добавляет проблем
> (fix the map - so there are no gaps in corners, currently AI sees through wall joints and this adds problems)

## Evidence Analysis

### Game Log Analysis

From `game_log_20260118_072943.txt`:

```
[07:29:55] [ENEMY] [Enemy10] State: PURSUING -> FLANKING
[07:29:57] [ENEMY] [Enemy2] State: PURSUING -> FLANKING
...
[07:30:09] [ENEMY] [Enemy10] State: PURSUING -> FLANKING
...
[07:30:30] [ENEMY] [Enemy3] State: PURSUING -> FLANKING
```

**Key observations**:
1. Enemies transition to FLANKING state but no subsequent state transitions are logged
2. The game log session ends at 07:30:44, leaving enemies stuck in FLANKING state
3. No transitions OUT of FLANKING state (like FLANKING -> COMBAT or FLANKING -> PURSUING)

### Timeline of Events

1. **07:29:43** - Game starts, 10 enemies spawn
2. **07:29:48-54** - Initial combat engagements
3. **07:29:55** - Enemy10 enters FLANKING state
4. **07:29:57** - Enemy2 enters FLANKING state
5. **07:30:00-02** - Game restarts (new spawn events)
6. **07:30:09** - Enemy10 enters FLANKING again
7. **07:30:30** - Enemy3 enters FLANKING
8. **07:30:44** - Log ends with enemies still in FLANKING

## Root Cause Analysis

### Primary Root Cause: No Timeout or Stuck Detection

The FLANKING state implementation in `enemy.gd` lacked:

1. **No overall state timeout**: Unlike COMBAT state which has `CLEAR_SHOT_MAX_TIME` (3 seconds) to prevent getting stuck, FLANKING had no timeout mechanism.

2. **No progress tracking**: The code didn't detect when an enemy was making no progress toward the flank target.

3. **Unreachable flank targets**: The flank target calculation could produce positions that are:
   - Inside walls
   - Outside the map boundaries
   - Blocked by obstacles from all directions

### Code Flow Analysis

When an enemy enters FLANKING state (`_transition_to_flanking()`):
1. Flank side chosen based on obstacle check
2. Flank target calculated at 60 degrees from player-enemy direction, 200 units from player
3. Enemy attempts to reach flank target

**Problem scenarios**:

**Scenario A: Direct path blocked**
```
if _has_clear_path_to(_flank_target):
    # Move directly - but wall avoidance may cause oscillation
    velocity = direction * combat_move_speed
    rotation = direction.angle()  # Enemy rotates toward target
```

When the enemy is near a wall corner:
- Direction to flank target points into the wall
- Wall avoidance (`_check_wall_ahead`) returns perpendicular vector
- Combined direction = 50% target + 50% avoidance
- This could result in ~90 degree rotation
- Enemy collides with wall and can't move

**Scenario B: Cover-to-cover movement fails**
```
_find_flank_cover_toward_target()
if not _has_flank_cover:
    # Fallback: direct movement with wall avoidance
    # Same oscillation problem as Scenario A
```

If no valid cover exists closer to the flank target, the fallback direct movement encounters the same wall collision issues.

### Secondary Issue: Wall Gaps

The map (`BuildingLevel.tscn`) had L-shaped wall corners where:
- Horizontal walls (24px height) meet vertical walls (24px width)
- At the corner points, small diagonal gaps could exist
- AI raycasts could pass through these gaps, incorrectly detecting player visibility

## Solution Implementation

### Fix 1: FLANKING State Timeout and Stuck Detection

Added new variables to track FLANKING state progress:

```gdscript
## Timer for total time spent in FLANKING state (for timeout detection).
var _flank_state_timer: float = 0.0

## Maximum time to spend in FLANKING state before giving up (seconds).
const FLANK_STATE_MAX_TIME: float = 5.0

## Last recorded position for progress tracking during flanking.
var _flank_last_position: Vector2 = Vector2.ZERO

## Timer for checking if stuck (no progress toward flank target).
var _flank_stuck_timer: float = 0.0

## Maximum time without progress before considering stuck (seconds).
const FLANK_STUCK_MAX_TIME: float = 2.0

## Minimum distance that counts as progress toward flank target.
const FLANK_PROGRESS_THRESHOLD: float = 10.0
```

Added timeout and stuck detection at the start of `_process_flanking_state()`:

```gdscript
# Update state timer
_flank_state_timer += delta

# Check for overall FLANKING state timeout
if _flank_state_timer >= FLANK_STATE_MAX_TIME:
    # Give up and transition to COMBAT or PURSUING

# Check for stuck detection - not making progress
var distance_moved := global_position.distance_to(_flank_last_position)
if distance_moved < FLANK_PROGRESS_THRESHOLD:
    _flank_stuck_timer += delta
    if _flank_stuck_timer >= FLANK_STUCK_MAX_TIME:
        # Stuck - transition to COMBAT or PURSUING
```

### Fix 2: Enhanced Logging

Added file logging for FLANKING state events to help diagnose future issues:

```gdscript
# On FLANKING start
_log_to_file("FLANKING started: target=%s, side=%s, pos=%s" % [_flank_target, side, global_position])

# On timeout
_log_to_file("FLANKING timeout (%.1fs), target=%s, pos=%s" % [timer, target, pos])

# On stuck detection
_log_to_file("FLANKING stuck (%.1fs no progress), target=%s, pos=%s" % [timer, target, pos])
```

### Fix 3: Map Corner Fills

Added 24x24 pixel corner fill pieces at L-shaped wall junctions:

- Room2_CornerBL at (512, 1000)
- Room2_CornerBR at (912, 1000)
- Corridor_CornerTR at (1364, 700)
- Corridor_CornerBR at (1364, 1012)
- MainHall_CornerTL at (1000, 1388)
- MainHall_CornerTR at (1400, 1388)
- StorageRoom_CornerTR at (500, 1600)

These prevent raycasts from passing through diagonal gaps at wall corners.

## Files Modified

1. `scripts/objects/enemy.gd`
   - Added timeout and progress tracking variables
   - Modified `_process_flanking_state()` with timeout/stuck detection
   - Modified `_transition_to_flanking()` to initialize new variables
   - Modified `_reset()` to reset new variables
   - Added detailed logging for diagnostics

2. `scenes/levels/BuildingLevel.tscn`
   - Added `RectangleShape2D_corner_fill` sub-resource (24x24)
   - Added `CornerFills` node with 7 corner fill pieces

## Testing Recommendations

1. **Timeout test**: Place enemy in position where flank target is completely blocked
   - Expected: Enemy should exit FLANKING state within 5 seconds

2. **Stuck detection test**: Place enemy against wall with flank target on other side
   - Expected: Enemy should exit FLANKING state within 2 seconds of no movement

3. **Corner visibility test**: Position player and enemy on opposite sides of a wall corner
   - Expected: AI should not detect player through corner gap

4. **Log verification**: Enable debug logging and check for FLANKING state messages
   - Expected: Logs should show state entry, timeout/stuck events, and state exit

## Lessons Learned

1. **All timed states need escape mechanisms**: Any AI state that involves movement toward a target should have:
   - Overall timeout
   - Stuck/no-progress detection
   - Fallback state transitions

2. **Logging is essential for AI debugging**: The existing state change logging was helpful, but more detailed logging within states helps identify stuck scenarios.

3. **Map geometry affects AI behavior**: Small gaps in wall collision shapes can cause unexpected AI behavior when raycasts pass through.

## References

- Issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/110
- Original game log: `game_log_20260118_072943.txt` (in this directory)
