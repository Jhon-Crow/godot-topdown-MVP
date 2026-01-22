# Case Study: Issue #245 - Enemy Shooting Position and Facing Direction Bug

## Problem Description

### Initial Report (2026-01-22 ~15:14)
User report (translated from Russian): "Enemies shoot from the back, from the side, from the weapon - inconsistently."

The original issue: Enemy bullets should spawn from the weapon muzzle and fly in the correct direction, but they appear to come from incorrect positions relative to the weapon visual.

### Second Report (2026-01-22 ~15:28)
After initial fix for muzzle position: "Bullets fly from the barrels, but enemies turn their backs to me."

The muzzle position fix worked (bullets now spawn from weapon), but the enemy MODEL is visually facing the wrong direction.

### Third Report (2026-01-22 ~16:37)
After rotation negation fix: "Enemies move and attack with their backs facing forward"

Despite applying the rotation negation fix, the issue persisted. This led to a deeper investigation.

## Timeline

1. PR #221 added enemy models with modular sprites (body, head, arms, weapon)
2. PR #246 attempted to fix the muzzle shooting by:
   - Using `_weapon_sprite.global_position` as base
   - Adding offset in direction of `_enemy_model.rotation`
3. User testing revealed bullets still spawn from incorrect positions
4. Second fix applied: Using `_weapon_sprite.global_transform.x.normalized()` for visual direction
5. User testing revealed enemies now turn their backs to player
6. Rotation negation fix applied: Negate rotation when flipping vertically
7. User testing revealed enemies still face backwards
8. **True root cause identified**: Dual rotation system conflict - both Enemy node and EnemyModel have rotation applied

## Technical Analysis

### Scene Structure
```
Enemy (CharacterBody2D)
  EnemyModel (Node2D) - rotation and scale applied here
    Body, Head, Arms (Sprite2D children)
    WeaponMount (Node2D) - position (0, 6)
      WeaponSprite (Sprite2D) - offset (20, 0), no individual rotation
```

### Bug #1: Muzzle Position (Fixed)

In `_get_bullet_spawn_position()`:
```gdscript
var weapon_forward := Vector2.from_angle(_enemy_model.rotation)
var result := _weapon_sprite.global_position + weapon_forward * scaled_muzzle_offset
```

The issue: `Vector2.from_angle(_enemy_model.rotation)` only accounts for rotation, not scale.

**Solution**: Use `_weapon_sprite.global_transform.x.normalized()` which gives the actual visual forward direction including scale effects.

### Bug #2: Model Facing Wrong Direction (The Real Issue)

In `_update_enemy_model_rotation()`:
```gdscript
var target_angle := face_direction.angle()
_enemy_model.rotation = target_angle

if aiming_left:
    _enemy_model.scale = Vector2(enemy_model_scale, -enemy_model_scale)
```

**The Problem**: When we apply a negative Y scale (vertical flip) to avoid an upside-down sprite, the visual effect of rotation is INVERTED. A rotation angle that would normally point left now visually points right.

**Mathematical Explanation**:

When a 2D transform has negative scale on one axis, it creates a mirror effect. Consider:
- Sprite faces right at angle 0°
- To face up-left (angle -153°), we rotate by -153°
- If we ALSO flip vertically (scale.y = -1), the visual result is mirrored

The issue is that negative scale.y mirrors the Y axis, which effectively inverts the rotation direction visually. The combination of:
- `rotation = -153°` (intending to face up-left)
- `scale.y = -1.3` (vertical flip)

Results in the sprite visually facing up-RIGHT instead of up-LEFT, because the flip mirrors the rotation effect.

**Solution**: When applying vertical flip, negate the rotation angle:
```gdscript
if aiming_left:
    _enemy_model.rotation = -target_angle  # Negate to compensate for flip
    _enemy_model.scale = Vector2(enemy_model_scale, -enemy_model_scale)
else:
    _enemy_model.rotation = target_angle
    _enemy_model.scale = Vector2(enemy_model_scale, enemy_model_scale)
```

This ensures the visual result is correct:
- Without flip: rotation = target_angle, scale.y positive -> faces target_angle ✓
- With flip: rotation = -target_angle, scale.y negative -> faces target_angle ✓ (the two inversions cancel out)

### Bug #3: Dual Rotation System Conflict (The TRUE Root Cause)

The previous fix (negating rotation when flipping) was mathematically correct, but the issue persisted because of a deeper architectural problem.

**Discovery**: The enemy.gd code sets rotation in TWO places:
1. `_enemy_model.rotation` in `_update_enemy_model_rotation()` - for visual facing direction
2. `rotation` (the Enemy CharacterBody2D node itself) in multiple places like `_aim_at_player()`, state processing, etc.

**The Problem**: In Godot's scene tree, the EnemyModel is a child of the Enemy node:
```
Enemy (CharacterBody2D) <- has its own rotation
  └── EnemyModel (Node2D) <- also has rotation
```

When you set `_enemy_model.rotation`, it's in LOCAL coordinates. The final VISUAL rotation is:
```
visual_rotation = parent_rotation + local_rotation
```

So if:
- Enemy node: `rotation = 30°` (from `_aim_at_player()`)
- EnemyModel: `rotation = -30°` (from `_update_enemy_model_rotation()`)
- Visual result: `30° + (-30°) = 0°` - facing wrong direction!

The fix with rotation negation was correct for the flip compensation, but it was being "undone" by the parent's rotation.

**Code locations where Enemy node rotation is set:**
- Line 1353: `rotation = direction_to_player.angle()` (distracted attack)
- Line 1410: `rotation = direction_to_player.angle()` (vulnerable attack)
- Line 1569: `rotation = direction_to_player.angle()` (sidestepping)
- Line 1621: `rotation = direction_to_player.angle()` (seeking clear shot)
- Line 1674: `rotation = direction_to_player.angle()` (exposed positioning)
- Line 2116: `rotation = target_angle` (patrol walking)
- Line 3621: `rotation = target_angle` (gradual aiming)
- Plus several more...

### Root Cause Summary

Two separate issues combined:
1. **Flip compensation**: When vertically flipping (scale.y < 0), rotation must be negated ✓ (correctly fixed)
2. **Parent-child rotation**: Using local `rotation` for EnemyModel while parent Enemy node also rotates causes unwanted rotation composition ✗

This is a Godot transform hierarchy issue documented in various places:
- [Godot Issue #21020](https://github.com/godotengine/godot/issues/21020)
- [Godot Forum discussions](https://forum.godotengine.org/t/flipping-node-sprite-scale-x-1-flipping-every-frame/67514)

## Solution

### Primary Fix: Use `global_rotation` Instead of `rotation`

The solution is to use `global_rotation` for setting the EnemyModel's facing direction. This ensures the visual direction is set in world coordinates, independent of any parent rotation:

```gdscript
if aiming_left:
    _enemy_model.global_rotation = -target_angle  # Use GLOBAL rotation
    _enemy_model.scale = Vector2(enemy_model_scale, -enemy_model_scale)
else:
    _enemy_model.global_rotation = target_angle   # Use GLOBAL rotation
    _enemy_model.scale = Vector2(enemy_model_scale, enemy_model_scale)
```

With `global_rotation`:
- The EnemyModel's facing direction is set directly in world space
- Parent rotation (Enemy node) doesn't affect the visual direction
- The flip compensation (rotation negation) works correctly

### Secondary Fix: Player Model (Same Pattern)

Applied the same fix to `_update_player_model_rotation()` in player.gd for consistency, since the player's CharacterBody2D also has rotation applied during grenade throws.

### Tertiary Fix: Muzzle Position (Previous Fix)

Using `_weapon_sprite.global_transform.x.normalized()` for weapon forward direction, which correctly accounts for all transforms including the global rotation and scale.

## Data Files

- `game_log_20260122_151419.txt` - Initial game log showing bullet spawn positions
- `game_log_20260122_152844.txt` - Second game log showing model facing issue after muzzle fix
- `game_log_20260122_163542.txt` - Third game log showing model still facing backwards after rotation negation fix

## Verification

After the fix, enemies should:
1. Always visually face the player when shooting
2. Spawn bullets from the visual muzzle position
3. Bullets fly toward the target
4. Work correctly when enemy is facing left (vertically flipped model)

## References

- [Godot Issue #21020 - Global rotation can return opposite sign of expected](https://github.com/godotengine/godot/issues/21020)
- [Godot Forum - Flipping Node/Sprite](https://forum.godotengine.org/t/flipping-node-sprite-scale-x-1-flipping-every-frame/67514)
- [KidsCanCode - Top-down movement](https://kidscancode.org/godot_recipes/4.x/2d/topdown_movement/index.html)
