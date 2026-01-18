# Issue 101: Fix COMBAT AI - Case Study Analysis

## Problem Statement

Enemies in COMBAT state stand still and don't engage the player. They cycle rapidly between states without making meaningful progress:
- `COMBAT -> SEEKING_COVER -> IN_COVER -> COMBAT` (every 2-3 seconds)
- `FLANKING -> COMBAT -> PURSUING` (almost instantly)

The user requested that enemies should "exit cover in an arc (tactically) to examine the space beyond the cover at the maximum angle."

## Log Analysis

From `game_log_20260118_051445.txt`, the following patterns were observed:

### Pattern 1: Rapid State Cycling (2-3 second intervals)
```
[05:15:26] [ENEMY] [Enemy3] State: COMBAT -> SEEKING_COVER
[05:15:26] [ENEMY] [Enemy3] State: SEEKING_COVER -> IN_COVER
[05:15:26] [ENEMY] [Enemy3] State: IN_COVER -> COMBAT
```
This cycle repeats every 2-3 seconds, matching `_combat_shoot_duration`.

### Pattern 2: FLANKING Instant Exit
```
[05:15:05] [ENEMY] [Enemy10] State: PURSUING -> FLANKING
[05:15:05] [ENEMY] [Enemy10] State: FLANKING -> COMBAT
[05:15:05] [ENEMY] [Enemy10] State: COMBAT -> PURSUING
```
All transitions happen in the same second, indicating FLANKING immediately transitions to COMBAT.

## Root Cause Analysis

### Root Cause 1: Inconsistent Shot Clearance Checks

The code uses two different functions to check if the enemy can hit the player:

1. **`_is_shot_clear_of_cover()`** - Used in FLANKING/PURSUING
   - Checks from `bullet_spawn_offset` (30 pixels ahead) to player position
   - Only checks if the bullet PATH to player is clear
   - Does NOT check if there's a wall blocking the bullet spawn point

2. **`_is_bullet_spawn_clear()`** - Used in COMBAT
   - Checks from enemy CENTER to `bullet_spawn_offset + 5` (35 pixels ahead)
   - Checks if there's a wall immediately in front of the enemy

**Result**: FLANKING thinks "I can hit the player" → transitions to COMBAT → COMBAT realizes "wall blocking bullet spawn" → transitions back → rapid cycling.

### Root Cause 2: Inadequate Clear Shot Seeking Movement

When COMBAT detects bullet spawn is blocked, it tries to find a clear shot position:

1. `_calculate_clear_shot_exit_position()` only tries 2 positions (left/right perpendicular + forward blend)
2. `CLEAR_SHOT_EXIT_DISTANCE` is only 60 pixels
3. If the cover is larger than 60 pixels, the enemy can't escape
4. When enemy reaches target but still blocked, it recalculates and RETURNS immediately
5. Enemy effectively stands still until the 3-second timeout

**Result**: Enemy appears frozen in place during COMBAT state.

### Root Cause 3: Arc Movement Not Implemented

The user requested tactical arc movement to exit cover, but the current implementation:
- Only tries 2 discrete positions
- Doesn't progressively move along an arc
- Doesn't adapt based on cover geometry

## Proposed Solutions

### Fix 1: Unified Shot Check
Update `_can_hit_player_from_current_position()` to also check `_is_bullet_spawn_clear()`:

```gdscript
func _can_hit_player_from_current_position() -> bool:
    if _player == null:
        return false
    if not _can_see_player:
        return false
    # Check if bullet spawn is clear (no wall immediately in front)
    var direction_to_player := (_player.global_position - global_position).normalized()
    if not _is_bullet_spawn_clear(direction_to_player):
        return false
    # Check if the shot would be blocked by cover
    return _is_shot_clear_of_cover(_player.global_position)
```

### Fix 2: Arc Movement for Clear Shot Seeking
Replace the simple 2-position check with progressive arc movement:

1. Start from current position
2. Move in an arc around the cover edge (not just perpendicular)
3. Check for clear shot at each step
4. Continue until clear shot found or arc exhausted
5. Try the other direction if first direction fails

### Fix 3: Increased Movement Distance
- Increase `CLEAR_SHOT_EXIT_DISTANCE` from 60 to 80-100 pixels
- Allow progressive movement instead of recalculating at same position

## Implementation Plan

1. **Phase 1**: Fix the inconsistent shot check (Root Cause 1)
2. **Phase 2**: Implement arc movement system (Root Cause 2 & 3)
3. **Phase 3**: Add debug visualization for arc movement
4. **Phase 4**: Test with various cover geometries

## Files to Modify

- `scripts/objects/enemy.gd` - Main AI script

## Testing Strategy

1. Enable F7 debug mode
2. Observe enemies engaging from behind cover
3. Verify enemies move in an arc to find clear shots
4. Verify no rapid state cycling occurs
5. Verify enemies actually shoot when they should
