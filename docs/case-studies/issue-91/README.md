# Case Study: Issue #91 - Fix AI FLANKING State Wall Navigation

## Problem Description

**Issue**: When in FLANKING state, enemies can walk into walls instead of navigating through passages.

**Original Issue Text** (Russian):
> "при FLANKING состоянии враг может идти в стену, а должен идти через проходы"

**Translation**: "In FLANKING state, enemy can walk into wall, but should go through passages"

## Root Cause Analysis

### Current FLANKING Implementation

The FLANKING state in `scripts/objects/enemy.gd` (lines 989-1023) uses a simple navigation approach:

1. **Calculate flank position**: A target position is calculated at a fixed angle (60 degrees) and distance (200 pixels) from the player
2. **Direct linear movement**: The enemy moves directly toward this target using vector direction
3. **Simple wall avoidance**: Uses 3 raycasts (40 pixels range) to detect walls and blend avoidance into movement direction

```gdscript
# Current implementation (lines 1009-1022)
var direction := (_flank_target - global_position).normalized()
var avoidance := _check_wall_ahead(direction)
if avoidance != Vector2.ZERO:
    direction = (direction * 0.5 + avoidance * 0.5).normalized()
velocity = direction * combat_move_speed
```

### Why This Fails

The simple wall avoidance system has several limitations:

1. **Short detection range**: 40 pixels is insufficient for complex navigation
2. **Reactive, not proactive**: Only steers when about to hit a wall
3. **No path planning**: Cannot navigate around corners or through doorways
4. **Stuck in corners**: Can oscillate when walls on multiple sides

### Comparison with PURSUING State

The PURSUING state (lines 1278-1302) uses a more sophisticated approach:

1. **Cover-to-cover movement**: Finds intermediate cover positions toward the target
2. **Strategic positioning**: Chooses positions that are both closer to target AND hidden from player
3. **Wait periods**: Pauses at each cover, allowing recalculation of next move
4. **Multiple valid paths**: Can navigate complex layouts by hopping between covers

## Research Findings

### Godot Pathfinding Options

1. **NavigationAgent2D / NavigationRegion2D**: Built-in navigation mesh system
   - Requires setting up navigation polygons on the map
   - Automatic path calculation using A*
   - Good for complex environments
   - Documentation: https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_introduction_2d.html

2. **AStarGrid2D**: Grid-based pathfinding
   - Works well with tile-based maps
   - Manual obstacle marking required
   - Documentation: https://kidscancode.org/godot_recipes/4.x/2d/grid_pathfinding/index.html

3. **Raycast-based Navigation**: Current approach used in project
   - Cover detection using 16 raycasts
   - Wall avoidance using 3 raycasts
   - Custom scoring for cover positions

## Proposed Solution

Rather than implementing a full navigation mesh system (which would require map modifications), we can extend the existing cover-to-cover approach used in PURSUING state to the FLANKING state.

### Solution Approach: Cover-to-Cover Flanking

Modify FLANKING state to:

1. **Find intermediate covers toward flank target**: Instead of moving directly, find cover positions that are:
   - Closer to the flank target than current position
   - Reachable (can be checked via raycast)

2. **Use iterative cover movement**: Move between cover positions until reaching the flank target

3. **Fallback behavior**: If no cover is found, use existing direct movement with wall avoidance

### Implementation Changes

New function: `_find_flank_cover_toward_target()` - Similar to `_find_pursuit_cover_toward_player()` but targets the flank position instead of the player.

Modified `_process_flanking_state()`:
- Add cover-to-cover movement phases
- Track flank cover position separately from combat cover
- Add wait period at intermediate covers (optional, for tactical feel)

## Alternative Solutions Considered

1. **Full Navigation Mesh**: Would require adding NavigationRegion2D to all maps, significant architectural change
2. **Enhanced Wall Avoidance**: More raycasts, longer range - would help but still reactive, not proactive
3. **Pathfinding via AStarGrid2D**: Would require grid overlay system, complex setup

## Conclusion

The cover-to-cover approach is the best solution because:
- Consistent with existing codebase patterns (used in PURSUING state)
- No new dependencies or map modifications needed
- Provides tactical behavior that fits game style
- Reuses existing cover detection infrastructure

## References

- [Godot 2D Navigation Overview](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_introduction_2d.html)
- [Grid-based Pathfinding in Godot 4](https://kidscancode.org/godot_recipes/4.x/2d/grid_pathfinding/index.html)
- [RayCast2D in Godot 4](https://kidscancode.org/godot_recipes/4.x/kyn/raycast2d/index.html)
- [GDQuest Raycast Introduction](https://www.gdquest.com/library/raycast_introduction/)
- [NavigationServer2D Without Agents](https://medium.com/godot-dev-digest/pathfinding-in-godot-using-navigationserver2d-without-agents-b2018bb3ba41)
