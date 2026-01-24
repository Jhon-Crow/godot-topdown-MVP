# Case Study: Issue #66 - Enemy Field of View Limitation

## Issue Summary
Issue #66 requested adding a field of view (FOV) limitation for enemies so they can only see the player within a 100-degree vision cone, rather than having 360-degree vision.

## Timeline of Events

### January 21, 2026
1. **04:56:15** - Initial game testing session began
2. **04:56:15** - 10 enemies spawned with "player_found: yes" status immediately
3. **04:56:20** - First gunshot by player triggered enemy pursuit behavior
4. **04:56:28** - Enemies began engaging player and transitioning between states
5. **05:04:16** - Second testing session began (with debug mode enabled)
6. **05:04:23** - Enemy7 entered COMBAT state even though player wasn't in direct line of sight
7. **05:04:28** - Enemy10 also entered COMBAT and PURSUING states

## Root Cause Analysis

### Problem 1: Enemies Could See Through Walls
The logs reveal that enemies were entering COMBAT and PURSUING states without clear line of sight to the player. For example:
- `[05:04:23] [ENEMY] [Enemy7] State: IDLE -> COMBAT`
- `[05:04:28] [ENEMY] [Enemy10] State: IDLE -> COMBAT`

These state transitions happened without any corresponding gunshot sound events nearby, suggesting the enemies were detecting the player visually through walls.

**Root Cause**: The original raycast-based visibility check was not properly respecting wall collisions, allowing enemies to "see" players through obstacles.

**Solution**: The upstream repository introduced a multi-point visibility check system (issue #264 fix) that:
1. Checks visibility from 5 points on the player's body (center + 4 corners)
2. Uses direct space state queries with proper collision masks
3. Only marks player as visible if raycast reaches the point without hitting obstacles

### Problem 2: FOV Implementation Was Disabled by Default
The FOV functionality was implemented but moved to the Experimental settings menu and disabled by default. This was a design decision to allow players to opt-in to the new gameplay mechanic.

### Problem 3: Enemy Rotation Values Were Added but Caused Issues
Enemy rotation values were added to make enemies face room entrances, but the user reported that "rotated enemies still don't see the player." This was because:
1. FOV was disabled by default
2. When enabled, the FOV check combined with rotation made detection unreliable

**Solution**: Reverted all enemy rotation values to their default state (0 degrees), restoring original behavior.

## Technical Details

### Multi-Point Visibility Check (Merged from Upstream)
```gdscript
func _get_player_check_points(center: Vector2) -> Array[Vector2]:
    const PLAYER_RADIUS: float = 14.0
    var points: Array[Vector2] = []
    points.append(center)  # Center point
    var diagonal_offset := PLAYER_RADIUS * 0.707
    points.append(center + Vector2(diagonal_offset, diagonal_offset))
    points.append(center + Vector2(-diagonal_offset, diagonal_offset))
    points.append(center + Vector2(diagonal_offset, -diagonal_offset))
    points.append(center + Vector2(-diagonal_offset, -diagonal_offset))
    return points
```

### FOV Check Function
```gdscript
func _is_position_in_fov(target_position: Vector2) -> bool:
    # If FOV is disabled globally or for this enemy, position is always in FOV
    if not ExperimentalSettings.fov_enabled or not fov_enabled:
        return true
    # Calculate angle to target...
```

## Files Modified

| File | Changes |
|------|---------|
| `scripts/objects/enemy.gd` | Merged FOV check with multi-point visibility system |
| `scenes/levels/BuildingLevel.tscn` | Reverted enemy rotation values to 0 (default) |
| `scripts/ui/pause_menu.gd` | Resolved merge conflicts to include both Experimental and Armory menus |
| `project.godot` | Merged autoload registrations |

## Lessons Learned

1. **Wall collision detection is critical** - Visual detection systems must properly respect physics collision layers to prevent enemies from seeing through walls.

2. **Multi-point visibility is more robust** - Checking visibility from multiple points on a target prevents edge cases where the center point is blocked but parts of the target are still visible.

3. **Experimental features should be opt-in** - New gameplay mechanics like FOV limitation should be disabled by default to avoid breaking existing gameplay.

4. **Static rotation values may conflict with dynamic systems** - Setting initial rotation angles for enemies can interfere with AI systems that expect to control rotation themselves.

## Log Files

- `game_log_20260121_045615.txt` - First testing session showing enemy behavior
- `game_log_20260121_050416.txt` - Second session with debug mode enabled

## References

- Issue #66: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/66
- PR #156: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/156
- Issue #264 fix (multi-point visibility): Merged from upstream
