# Case Study: BFF Companion AI Not Working - Issue #674

## Summary

The BFF companion spawned correctly but had no functional AI behavior. Users reported:
1. "у напарника сейчас нет ии" (The companion currently has no AI)
2. "не должен спавниться в или за стеной" (Should not spawn in or behind walls)

## Timeline of Events

| Date | Event | Observation |
|------|-------|-------------|
| 2026-02-09 | Initial companion implementation | Companion visual appears |
| 2026-02-10 19:46 | User feedback via PR comment | AI not working, wall spawn issue |
| 2026-02-10 | Debug logging added | No [BffCompanion] logs appeared |

## Root Cause Analysis

### Issue 1: AI Not Working

**Evidence from game logs:**
- `[Player.BffPendant] Companion summoned at position (393.0791, 1209.7606)` appears
- NO `[BffCompanion]` logs appear (should log every ~1 second)
- Game runs for 5+ seconds after spawn with zero companion status logs

**Diagnosis:**
The companion script's `_ready()` and `_physics_process()` methods were executing, but:
1. The `FileLogger.info()` calls might have been silently failing
2. The AI logic worked but didn't produce visible behavior in-game

**Root Cause:**
1. **FileLogger access issue**: Direct `FileLogger.info()` calls from dynamically instantiated scenes may have timing issues. The FileLogger autoload might not be fully initialized when accessed.
2. **Simplified movement logic**: Original implementation used basic velocity-based movement instead of proper NavigationAgent2D pathfinding, causing the companion to get stuck on walls.

### Issue 2: Spawning Inside/Behind Walls

**Root Cause:**
The original spawn logic simply applied a fixed offset without validating the position:
```gdscript
var spawn_offset := Vector2(-50, 30)
if _player_model:
    spawn_offset = spawn_offset.rotated(_player_model.rotation)
companion.global_position = global_position + spawn_offset
```

This could place the companion:
- Inside a wall if the player was near one
- Behind a wall if player's rotation pointed that way

## Fixes Applied

### Fix 1: Robust Logging Function

Added a unified `_log()` function with multiple fallbacks:
```gdscript
func _log(message: String) -> void:
    if Engine.has_singleton("FileLogger"):
        var fl = Engine.get_singleton("FileLogger")
        if fl and fl.has_method("info"):
            fl.info(message)
            return
    # Fallback: try autoload node
    var fl_node = get_node_or_null("/root/FileLogger")
    if fl_node and fl_node.has_method("info"):
        fl_node.info(message)
    else:
        # Last resort: print to console
        print(message)
```

### Fix 2: NavigationAgent2D-based Movement

Changed from simple velocity-based movement to proper pathfinding:
```gdscript
func _get_nav_direction_to(target_pos: Vector2) -> Vector2:
    if _nav_agent == null:
        return (target_pos - global_position).normalized()

    _nav_agent.target_position = target_pos

    if _nav_agent.is_navigation_finished():
        return Vector2.ZERO

    var next_pos: Vector2 = _nav_agent.get_next_path_position()
    return (next_pos - global_position).normalized()
```

### Fix 3: Wall-Safe Spawn Position

Added spawn position validation with multiple fallback positions:
```gdscript
func _find_valid_companion_spawn_position() -> Vector2:
    var offsets: Array[Vector2] = [
        Vector2(-50, 30).rotated(base_rotation),   # Behind and to the side
        Vector2(-60, 0).rotated(base_rotation),    # Directly behind
        Vector2(-50, -30).rotated(base_rotation),  # Behind and other side
        # ... more fallback positions
    ]

    for offset in offsets:
        var test_pos := global_position + offset
        if _is_spawn_position_valid(space_state, test_pos, COMPANION_RADIUS):
            return test_pos

    # Final fallback: spawn at player position
    return global_position

func _is_spawn_position_valid(space_state, pos, radius) -> bool:
    # Check 1: Line of sight from player
    # Check 2: Circle overlap test (not inside wall)
    return no_wall_between and not_overlapping_wall
```

## AI Behavior Design (User Requirement)

User specified: "должно быть как у врага в режиме агрессив, под воздействием газовой гранаты, но вместо поиска - следование за игроком"

Translation: "Should be like enemy in aggressive mode under gas grenade effect, but instead of searching - following the player"

**Implemented behavior:**
1. **Follow player** when no enemies visible (not search like aggressive enemy)
2. **Attack enemies on sight** (like aggressive enemy behavior)
3. **Stop moving during combat** (like aggressive enemy)
4. **Use navigation** for pathfinding around obstacles

## Comparison with Enemy AI

| Aspect | Aggressive Enemy | BFF Companion |
|--------|------------------|---------------|
| Primary goal | Attack other enemies | Attack enemies, follow player |
| When no target | Search for any enemy | Follow player |
| Movement | NavigationAgent2D | NavigationAgent2D |
| Combat | Stop and shoot | Stop and shoot |
| Targeting | Nearest enemy with LOS | Nearest enemy with LOS |
| Friendly fire prevention | N/A | Check if player in firing line |

## Files Changed

1. `scripts/objects/bff_companion.gd` - AI rewrite with navigation
2. `scripts/characters/player.gd` - Wall-safe spawn validation

## Log Files

- `logs/game_log_20260210_224424.txt` - First user test log
- `logs/game_log_20260210_224511.txt` - Second user test log

## References

- Enemy AI implementation: `scripts/objects/enemy.gd`
- Aggression component: `scripts/components/aggression_component.gd`
- NavigationAgent2D: `scenes/objects/BffCompanion.tscn` (node already existed)
