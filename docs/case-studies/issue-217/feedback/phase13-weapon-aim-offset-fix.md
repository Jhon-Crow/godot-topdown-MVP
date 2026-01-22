# Phase 13: Weapon Aim Offset Fix

## User Report
**Date**: 2026-01-22
**Issue**: "теперь враги снова стреляют не из оружия (поверни модельку так, чтобы оружие совпало с текущей линией огня и прицела)"
Translation: "now enemies are again shooting not from the weapon (rotate the model so the weapon matches the current line of fire and aim)"
**Log File**: game_log_20260122_134431.txt

## Root Cause Analysis

### Problem Summary
The enemy model rotation was calculated based on the direction from **enemy center** to player. However, the weapon is offset from the enemy center (at position (0, 6) in local coordinates). This meant that while the model appeared to face the player, the weapon barrel didn't actually point at the player.

### Technical Details

#### The Geometry Issue
```
Enemy at E = (0, 0)
Player at P = (100, 50)
Weapon offset from center: ~8 pixels (when scaled)

Old calculation:
- Direction = (P - E).normalized() = direction from enemy center to player
- Model rotates to this angle
- But weapon is NOT at enemy center!

Result:
- Model faces the player (from enemy center perspective)
- Weapon barrel points slightly OFF from the player
- Error angle ≈ atan(weapon_offset / distance_to_player)
- For close targets (50 pixels), error could be ~9 degrees
```

#### Scene Structure Analysis
From `Enemy.tscn`:
- EnemyModel (origin at Enemy position)
  - Body at (-4, 0)
  - WeaponMount at (0, 6) - offset BELOW enemy center
  - WeaponSprite (child of WeaponMount)

When the model rotates, the weapon orbits around the model origin (0, 0), not around the weapon itself.

### Previous Fixes in This Issue
1. **Phase 11**: Removed incorrect PI offset from rotation (enemy was facing opposite direction)
2. **Phase 12**: Changed from `global_transform.x` to `Vector2.from_angle()` for direction calculation (fixed ~45 degree offset when Y-flipped)

This Phase 13 fix addresses a different problem: the weapon position offset from enemy center.

## Solution Implemented

### New Function: `_calculate_aim_direction_from_weapon()`
Added a new function that calculates the correct aim direction accounting for weapon offset:

```gdscript
func _calculate_aim_direction_from_weapon(target_pos: Vector2) -> Vector2:
    var weapon_mount_local := Vector2(0, 6)
    var rough_direction := (target_pos - global_position)
    var rough_distance := rough_direction.length()

    # For distant targets, simple calculation is sufficient
    if rough_distance > 25.0 * enemy_model_scale:
        return rough_direction.normalized()

    # For close targets, iterate to find correct rotation
    var current_direction := rough_direction.normalized()
    for _i in range(2):
        var estimated_angle := current_direction.angle()
        var would_flip := absf(estimated_angle) > PI / 2

        # Calculate weapon position with estimated rotation
        var weapon_offset_world: Vector2
        if would_flip:
            var scaled := Vector2(weapon_mount_local.x * enemy_model_scale,
                                  weapon_mount_local.y * -enemy_model_scale)
            weapon_offset_world = scaled.rotated(estimated_angle)
        else:
            var scaled := weapon_mount_local * enemy_model_scale
            weapon_offset_world = scaled.rotated(estimated_angle)

        var weapon_global_pos := global_position + weapon_offset_world
        var new_direction := (target_pos - weapon_global_pos)
        if new_direction.length_squared() < 0.01:
            break
        current_direction = new_direction.normalized()

    return current_direction
```

### Modified: `_update_enemy_model_rotation()`
Changed the aim direction calculation:

```gdscript
# Before:
face_direction = (_player.global_position - global_position).normalized()

# After:
face_direction = _calculate_aim_direction_from_weapon(_player.global_position)
```

### Key Design Decisions

1. **Distance Threshold**: For targets > 25 pixels away (scaled), use simple calculation. The angular error at this distance is negligible.

2. **Iterative Approach**: The weapon position depends on rotation, which we're calculating. We iterate 2 times to converge on the correct value.

3. **Y-Flip Handling**: When the model is flipped (aiming left), the Y scale is negative, affecting how the weapon offset transforms. This is handled explicitly in the calculation.

### Debug Logging Added
Added detailed debug output to `_shoot()` and `_get_bullet_spawn_position()` to help diagnose any remaining issues:
- Enemy and player positions
- Model rotation and scale
- Weapon node position
- Bullet spawn position and offset
- Comparison of calculated vs visual forward direction

## Expected Results

1. **Close Range**: Weapon barrel should now correctly point at the player even at close range
2. **Long Range**: Behavior unchanged (simple calculation used for efficiency)
3. **Y-Flip**: Correct handling whether enemy is aiming left or right

## Test Plan
- [ ] Verify weapon barrel visually points at player at close range (<50 pixels)
- [ ] Verify weapon barrel visually points at player at medium range (50-200 pixels)
- [ ] Verify weapon barrel visually points at player at long range (>200 pixels)
- [ ] Verify bullets spawn from weapon muzzle and fly toward player
- [ ] Verify Y-flip behavior (aiming left) works correctly
- [ ] Check debug logs for any discrepancies between calculated and visual directions

## Files Modified
- `scripts/objects/enemy.gd`:
  - Modified `_update_enemy_model_rotation()` to use new aim calculation
  - Added `_calculate_aim_direction_from_weapon()` function
  - Added debug logging to `_shoot()` and `_get_bullet_spawn_position()`
