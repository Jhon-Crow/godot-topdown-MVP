# Case Study: BFF Companion AI Not Working - Issue #674

## Summary

The BFF companion spawned correctly but had no functional AI behavior. Users reported:
1. "у напарника сейчас нет ии" (The companion currently has no AI)
2. "не должен спавниться в или за стеной" (Should not spawn in or behind walls)
3. "не работает. можешь просто копировать ии врага, но чтоб он был в состоянии agressive" (Doesn't work. Just copy the enemy AI in aggressive state)

## Timeline of Events

| Date | Event | Observation |
|------|-------|-------------|
| 2026-02-09 | Initial companion implementation | Companion visual appears |
| 2026-02-10 19:46 | User feedback via PR comment | AI not working, wall spawn issue |
| 2026-02-10 | Debug logging added | No [BffCompanion] logs appeared |
| 2026-02-10 20:26 | User feedback | "не работает" - still not working, request to copy aggressive enemy AI |
| 2026-02-15 | AI rewrite | Complete rewrite to mirror AggressionComponent exactly |

## Root Cause Analysis

### Issue 1: AI Not Working (Original - Feb 10)

**Evidence from game logs:**
- `[Player.BffPendant] Companion summoned at position (393.0791, 1209.7606)` appears
- NO `[BffCompanion]` logs appear (should log every ~1 second)
- Game runs for 5+ seconds after spawn with zero companion status logs

**Original diagnosis:** FileLogger timing issues and simplified movement logic.

### Issue 2: AI Still Not Working (Feb 10 - Second Report)

**User feedback:** "не работает" (doesn't work)

**User solution request:** "можешь просто копировать ии врага, но чтоб он был в состоянии agressive и не считал игрока врагом" (just copy the enemy AI in aggressive state but don't consider player as enemy)

**Root Cause:**
The custom AI implementation deviated significantly from the enemy AI patterns:
1. **Different rotation logic**: Used lerp_angle instead of enemy's wrapf-based rotation
2. **Different aim tolerance**: Used 0.95 instead of enemy's 0.866 (cos 30°)
3. **Different cooldown values**: Custom values instead of enemy defaults
4. **Different combat flow**: Separate functions for different states instead of unified process_combat pattern

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

### Fix 1 (Feb 10): Robust Logging Function
Added fallback logging to ensure debug messages appear.

### Fix 2 (Feb 10): NavigationAgent2D-based Movement
Changed from simple velocity to proper pathfinding.

### Fix 3 (Feb 10): Wall-Safe Spawn Position
Added spawn position validation with fallback positions.

### Fix 4 (Feb 15): Complete AI Rewrite - Mirror AggressionComponent

**Key change:** Rewrote `_process_combat_ai()` to EXACTLY mirror `AggressionComponent.process_combat()`:

```gdscript
func _process_combat_ai(delta: float) -> void:
    # Step 1: Find enemy target with LOS (like _find_nearest_enemy_target_with_los)
    if _current_target == null or not is_instance_valid(_current_target) or _current_target.get("_is_alive") == false:
        _current_target = _find_enemy_with_los()

    # Step 2: If we have LOS to target, engage in combat
    if _current_target != null and _has_los_to(_current_target):
        var dir := (_current_target.global_position - global_position).normalized()

        # Rotate toward target (SAME logic as AggressionComponent)
        var angle_diff := wrapf(dir.angle() - rotation, -PI, PI)
        if abs(angle_diff) <= rotation_speed * delta:
            rotation = dir.angle()
        elif angle_diff > 0:
            rotation += rotation_speed * delta
        else:
            rotation -= rotation_speed * delta

        if _model:
            _model.rotation = rotation

        # Check aim and shoot (SAME as AggressionComponent)
        var weapon_forward := Vector2.RIGHT.rotated(rotation)
        if weapon_forward.dot(dir) >= AIM_TOLERANCE_DOT and _can_shoot() and _shoot_timer >= shoot_cooldown:
            _shoot(weapon_forward)
            _shoot_timer = 0.0

        velocity = Vector2.ZERO  # Stop moving during combat

    elif _current_target != null:
        _move_to_target_nav(_current_target.global_position, combat_move_speed)

    else:
        _nav_target = _find_any_enemy()
        if _nav_target != null:
            _move_to_target_nav(_nav_target.global_position, combat_move_speed)
        else:
            _process_follow_player(delta)  # Only difference: follow player instead of search
```

**Parameters matched to enemy:**
- `rotation_speed = 25.0` (same as enemy)
- `shoot_cooldown = 0.1` (same as enemy)
- `AIM_TOLERANCE_DOT = 0.866` (cos 30°, same as enemy)
- `combat_move_speed = 320.0` (same as enemy)

## AI Behavior Design (User Requirement)

User specified: "должно быть как у врага в режиме агрессив, под воздействием газовой гранаты, но вместо поиска - следование за игроком"

Translation: "Should be like enemy in aggressive mode under gas grenade effect, but instead of searching - following the player"

## Comparison with AggressionComponent (Issue #675)

| Aspect | AggressionComponent | BFF Companion (New) |
|--------|---------------------|---------------------|
| Target group | "enemies" (other enemies) | "enemies" (hostile NPCs) |
| Rotation logic | `wrapf(angle_diff)` + delta | **SAME** |
| Aim tolerance | `0.866` (cos 30°) | **SAME** |
| Shoot check | `weapon_forward.dot(dir) >= AIM_TOLERANCE_DOT` | **SAME** |
| Combat velocity | `Vector2.ZERO` (stop) | **SAME** |
| When no LOS | `_move_to_target_nav()` | **SAME** |
| When no target | `_find_nearest_enemy_any()` | Follow player instead |
| Rotation speed | 25.0 rad/s | **SAME** |
| Shoot cooldown | 0.1s | **SAME** |

The ONLY behavioral difference is: when no enemies exist, the companion follows the player instead of searching/wandering.

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
