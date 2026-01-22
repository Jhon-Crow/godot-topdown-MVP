# Case Study: Issue #245 - Enemy Shooting Position and Facing Direction Bug

## Problem Description

### Initial Report (2026-01-22 ~15:14)
User report (translated from Russian): "Enemies shoot from the back, from the side, from the weapon - inconsistently."

The original issue: Enemy bullets should spawn from the weapon muzzle and fly in the correct direction, but they appear to come from incorrect positions relative to the weapon visual.

### Second Report (2026-01-22 ~15:28)
After initial fix for muzzle position: "Bullets fly from the barrels, but enemies turn their backs to me."

The muzzle position fix worked (bullets now spawn from weapon), but the enemy MODEL is visually facing the wrong direction.

## Timeline

1. PR #221 added enemy models with modular sprites (body, head, arms, weapon)
2. PR #246 attempted to fix the muzzle shooting by:
   - Using `_weapon_sprite.global_position` as base
   - Adding offset in direction of `_enemy_model.rotation`
3. User testing revealed bullets still spawn from incorrect positions
4. Second fix applied: Using `_weapon_sprite.global_transform.x.normalized()` for visual direction
5. User testing revealed enemies now turn their backs to player
6. **Root cause identified**: Rotation angle not negated when vertical flip is applied

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

### Root Cause

The code assumed that rotation angle alone determines facing direction, but when vertical flipping is applied, the rotation must be negated to maintain the correct visual direction.

This is a known Godot behavior documented in [GitHub issue #21020](https://github.com/godotengine/godot/issues/21020) and discussed in various [Godot forum posts](https://forum.godotengine.org/t/flipping-node-sprite-scale-x-1-flipping-every-frame/67514).

## Solution

### Primary Fix: `_update_enemy_model_rotation()`

Negate rotation angle when applying vertical flip:
```gdscript
if aiming_left:
    _enemy_model.rotation = -target_angle
    _enemy_model.scale = Vector2(enemy_model_scale, -enemy_model_scale)
else:
    _enemy_model.rotation = target_angle
    _enemy_model.scale = Vector2(enemy_model_scale, enemy_model_scale)
```

### Secondary Fix: Player Model (Same Pattern)

Applied the same fix to `_update_player_model_rotation()` in player.gd to ensure consistent behavior.

### Tertiary Fix: Muzzle Position (Previous Fix)

Using `_weapon_sprite.global_transform.x.normalized()` for weapon forward direction, which correctly accounts for all transforms.

## Data Files

- `game_log_20260122_151419.txt` - Initial game log showing bullet spawn positions
- `game_log_20260122_152844.txt` - Second game log showing model facing issue

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
