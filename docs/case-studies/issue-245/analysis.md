# Case Study: Issue #245 - Enemy Shooting Position Bug

## Problem Description

User report (translated from Russian): "Enemies shoot from the back, from the side, from the weapon - inconsistently."

The original issue: Enemy bullets should spawn from the weapon muzzle and fly in the correct direction, but they appear to come from incorrect positions relative to the weapon visual.

## Timeline

1. PR #221 added enemy models with modular sprites (body, head, arms, weapon)
2. PR #246 attempted to fix the muzzle shooting by:
   - Using `_weapon_sprite.global_position` as base
   - Adding offset in direction of `_enemy_model.rotation`
3. User testing revealed bullets still spawn from incorrect positions

## Technical Analysis

### Scene Structure
```
Enemy (CharacterBody2D)
  EnemyModel (Node2D) - rotation and scale applied here
    Body, Head, Arms (Sprite2D children)
    WeaponMount (Node2D) - position (0, 6)
      WeaponSprite (Sprite2D) - offset (20, 0), no individual rotation
```

### The Bug

In `_get_bullet_spawn_position()`:
```gdscript
var weapon_forward := Vector2.from_angle(_enemy_model.rotation)
var result := _weapon_sprite.global_position + weapon_forward * scaled_muzzle_offset
```

The issue: `Vector2.from_angle(_enemy_model.rotation)` only accounts for rotation, not scale.

When the enemy aims LEFT (angle > 90deg or < -90deg):
- `_enemy_model.rotation` is set to the target angle (e.g., PI for left)
- `_enemy_model.scale.y` is set to NEGATIVE (-1.3) for vertical flip to avoid upside-down weapon
- `Vector2.from_angle(_enemy_model.rotation)` gives (-1, 0) for angle PI
- BUT the actual weapon sprite's visual forward direction is affected by BOTH rotation AND scale

When `scale.y` is negative, the Y-axis is flipped. This affects how child nodes are positioned and oriented:
- The WeaponMount at local (0, 6) gets transformed differently
- The weapon sprite's visual "forward" (muzzle direction) is different from `Vector2.from_angle(rotation)`

### Root Cause

The code assumes the weapon's forward direction is purely based on rotation angle, but the actual visual direction is the result of the complete transform chain (rotation * scale).

The correct approach is to use `_weapon_sprite.global_transform.x.normalized()` which gives the actual world-space direction the weapon sprite's local +X axis points to, accounting for all parent transforms including scale flips.

## Solution

### Primary Fix: `_get_bullet_spawn_position()`

Replace:
```gdscript
var weapon_forward := Vector2.from_angle(_enemy_model.rotation)
```

With:
```gdscript
var weapon_forward := _weapon_sprite.global_transform.x.normalized()
```

This correctly handles:
1. Normal right-facing aim (no flip)
2. Left-facing aim with vertical flip
3. Any intermediate angles

### Secondary Fix: `_get_weapon_forward_direction()`

Updated to use `_weapon_sprite.global_transform.x.normalized()` instead of `Vector2.from_angle(_enemy_model.rotation)`.

### Tertiary Fixes: Raycast Functions

Updated `_is_firing_line_clear_of_friendlies()` and `_is_shot_clear_of_cover()` to use the actual muzzle position from `_get_bullet_spawn_position()` instead of a simple offset from enemy center.

## Data Files

- `game_log_20260122_151419.txt` - Game log showing bullet spawn positions

## Verification

After the fix, bullets should:
1. Always spawn from the visual muzzle position
2. Fly toward the target regardless of enemy facing direction
3. Work correctly when enemy is facing left (vertically flipped model)
