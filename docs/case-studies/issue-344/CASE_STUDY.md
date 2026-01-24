# Case Study: Issue #344 - Enemies Don't Shoot at Close Range

## Summary

Enemies in COMBAT state would not shoot at the player when directly facing them at close range. The game logs showed "Player distracted - priority attack triggered" messages repeatedly without corresponding gunshot sounds, indicating the shooting code was being reached but shots were blocked.

## Timeline Reconstruction

### From game_log_20260125_023558.txt

1. **02:37:52** - Enemy7 and Enemy8 successfully shoot at player (gunshots heard)
2. **02:37:56 - 02:38:05** - Enemy6 logs "Player distracted - priority attack triggered" dozens of times
3. **No gunshots from Enemy6** - Despite priority attack being triggered, no bullets are fired

### Pattern Analysis

- Enemies that successfully shoot: Further from player, larger distance between center and player
- Enemies that fail to shoot: Close to player, small distance causing geometric mismatch

## Root Cause Analysis

### The Bug

In the `_shoot()` function (line 3914 of enemy.gd), an aim tolerance check compares two vectors:

1. **`weapon_forward`**: Direction from **enemy center** to player (calculated via `_get_weapon_forward_direction()`)
2. **`to_target`**: Direction from **bullet spawn position (muzzle)** to player

These vectors originate from different points:
- Enemy center position (`global_position`)
- Muzzle position (`bullet_spawn_pos`), which is ~52 pixels offset from center

### The Geometry Problem

```
     Enemy Center (E)
           |
           | ~52px offset
           v
        Muzzle (M) -----> weapon_forward direction
                  \
                   \---> to_target direction (different angle!)
                    \
                     Player (P)
```

When the player is **close** (e.g., 60 pixels away):
- The muzzle offset (~52px) is a significant fraction of the total distance
- The angle between `weapon_forward` and `to_target` can exceed 30 degrees
- The aim tolerance check (`AIM_TOLERANCE_DOT = 0.866 = cos(30deg)`) fails
- `_shoot()` returns early without firing

When the player is **far** (e.g., 500 pixels away):
- The muzzle offset is only ~10% of the distance
- The angular difference is small (~6 degrees)
- The aim tolerance check passes
- Shooting works correctly

### Mathematical Analysis

For a player at distance `d` from enemy center, with muzzle offset `m = 52px`:

| Distance | Offset % | Approx Angle Difference | Passes 30deg Check? |
|----------|----------|-------------------------|---------------------|
| 60px     | 87%      | ~40deg                  | NO                  |
| 100px    | 52%      | ~27deg                  | YES (marginal)      |
| 200px    | 26%      | ~14deg                  | YES                 |
| 500px    | 10%      | ~6deg                   | YES                 |

## The Fix

Changed the `to_target` calculation in three functions to use `global_position` (enemy center) instead of `bullet_spawn_pos` (muzzle):

### Before (buggy):
```gdscript
var to_target := (target_position - bullet_spawn_pos).normalized()
```

### After (fixed):
```gdscript
var to_target := (target_position - global_position).normalized()
```

### Why This Works

1. `weapon_forward` is calculated as direction from `global_position` to player
2. `to_target` is now also calculated from `global_position` to player
3. Both vectors use the same origin point
4. When enemy faces the player, both vectors are identical (dot product = 1.0)
5. The aim tolerance check passes consistently at any distance

### Functions Fixed

1. `_shoot()` (line 3948)
2. `_shoot_with_inaccuracy()` (line 2459)
3. `_shoot_burst_shot()` (line 2531)

## Historical Context

### Issue #254 - The Original Aim Tolerance

Issue #254 requested that enemy bullets fly realistically from the barrel, not at weird angles. The `AIM_TOLERANCE_DOT` check was added to block shots when the weapon isn't properly aimed.

### Issue #264 - Transform Delay Fix

Issue #264 identified that Godot 4's child node transforms don't update immediately when parent rotation changes. The fix was to calculate `weapon_forward` directly from positions when the player is visible, rather than reading from the (stale) transform.

### This Issue #344

The combination of these two fixes created a mismatch:
- `weapon_forward` uses `global_position` (from Issue #264 fix)
- `to_target` was using `bullet_spawn_pos` (muzzle position)
- At close range, these vectors diverge enough to fail the tolerance check

## Regression Test

Added test cases to `tests/unit/test_enemy.gd`:

1. `test_aim_check_uses_consistent_origin_issue_344()` - Verifies the fix prevents close-range failures
2. `test_aim_check_consistent_at_all_distances_issue_344()` - Verifies consistent behavior at all distances

## Files Changed

- `scripts/objects/enemy.gd` - Fixed aim check in three shooting functions (+10 lines of comments)
- `tests/unit/test_enemy.gd` - Added regression tests (+64 lines)

## Lessons Learned

1. **Geometric consistency**: When comparing vectors, ensure they originate from the same point
2. **Distance-dependent bugs**: Bugs that only manifest at certain distances are easy to miss in testing
3. **Cascading fixes**: Fixes for one issue can create subtle bugs elsewhere if not carefully integrated
