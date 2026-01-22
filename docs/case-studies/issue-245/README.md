# Case Study: Issue #245 - Fix Enemy Shooting

## Overview

**Issue:** [#245 - fix стрельба врагов](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/245)
**Pull Request:** [#246](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/246)
**Date Created:** 2026-01-22
**Status:** Fix Implemented

## Problem Statement

The issue reports that in PR #221 (which added enemy models), enemies are shooting incorrectly:
- Bullets are not flying from the weapon
- Bullets should fly from the weapon in the correct direction
- Enemies should aim the same way as before (aiming logic should be preserved)

Translation of issue text:
> "в ветке https://github.com/Jhon-Crow/godot-topdown-MVP/pull/221 добавлены модельки врагов, но они стреляют не из оружия - пули должны лететь из оружия по правильному направлению, так же враги должны целиться как раньше (то есть нужно только прикрепить линию огня и прицеливания к оружию)."

Translation:
> "In PR #221, enemy models were added, but they don't shoot from the weapon - bullets should fly from the weapon in the correct direction, also enemies should aim like before (i.e., just need to attach the firing line and aiming to the weapon)."

## Root Cause Analysis

### The Problem

The current enemy shooting implementation spawns bullets from the **enemy center position** plus a directional offset:

```gdscript
# OLD CODE (enemy.gd, _shoot() function)
var direction := (target_position - global_position).normalized()
bullet.global_position = global_position + direction * bullet_spawn_offset
```

This has two issues:

1. **Bullet spawn position is incorrect**: Bullets spawn from the enemy's center (`global_position`) plus an offset in the direction of the target, NOT from the weapon's actual muzzle position.

2. **Visual disconnect**: The weapon sprite (`WeaponSprite`) is positioned and rotated to visually point at the target, but bullets don't actually originate from where the weapon's barrel appears to be.

### The Enemy Scene Structure

Current `Enemy.tscn`:
```
Enemy (CharacterBody2D)
├── Sprite2D (placeholder texture)
├── WeaponSprite (m16_rifle_topdown.png)
│   └── offset = Vector2(20, 0)
├── CollisionShape2D
├── RayCast2D
├── HitArea
└── NavigationAgent2D
```

The weapon sprite:
- Uses `m16_rifle_topdown.png` (64x16 pixels)
- Has an offset of `Vector2(20, 0)` - meaning it's rendered 20 pixels to the right of its node position
- Rotates to point at the target via `_update_weapon_sprite_rotation()`
- Flips vertically when aiming left (to avoid upside-down appearance)

### Expected Behavior

Bullets should spawn from the **weapon muzzle** (the end of the rifle barrel), not from the enemy's center. The muzzle position should be calculated based on:
1. The weapon sprite's global position
2. The weapon's rotation (which direction it's pointing)
3. The distance from the weapon node to the muzzle (right edge of the sprite)

## Solution

### 1. Added `_get_muzzle_position()` Helper Function

This function calculates the actual weapon muzzle position in world coordinates:

```gdscript
func _get_muzzle_position() -> Vector2:
    if not _weapon_sprite:
        # Fallback: return position in direction of aim
        if _player and is_instance_valid(_player):
            var direction := (_player.global_position - global_position).normalized()
            return global_position + direction * bullet_spawn_offset
        return global_position + Vector2.RIGHT * bullet_spawn_offset

    # Calculate weapon's forward direction from its global rotation
    var weapon_forward := Vector2.from_angle(_weapon_sprite.global_rotation)

    # The muzzle is 52px from the weapon sprite's position along its forward direction
    # (20px offset + 32px half-width of 64px sprite)
    var muzzle_offset := 52.0
    return _weapon_sprite.global_position + weapon_forward * muzzle_offset
```

**Key insight**: The muzzle offset is calculated as:
- Sprite offset: 20px (from scene file)
- Half sprite width: 32px (64px / 2)
- Total: 52px from the WeaponSprite node position to the muzzle

### 2. Updated Shooting Functions

All three shooting functions were updated to:
1. Get the muzzle position using `_get_muzzle_position()`
2. Calculate bullet direction from **muzzle to target** (not enemy center to target)
3. Spawn bullet at the muzzle position
4. Set `shooter_position` to the muzzle for accurate distance calculations

Updated functions:
- `_shoot()` - Main shooting function
- `_shoot_with_inaccuracy()` - Retreat mode shooting
- `_shoot_burst_shot()` - Burst fire mode

### 3. Updated Raycast Functions

Functions that check firing lines were updated to start raycasts from the muzzle position:

- `_is_bullet_spawn_clear()` - Checks if there's a wall blocking the shot
- `_is_firing_line_clear_of_friendlies()` - Checks for friendly fire
- `_is_shot_clear_of_cover()` - Checks if shot is blocked by cover

### 4. Updated Debug Visualization

The `_draw()` function was updated to show the actual muzzle position instead of the old bullet spawn point.

## Files Modified

### scripts/objects/enemy.gd

1. **Added `_get_muzzle_position()` function** (after `_update_weapon_sprite_rotation()`)
   - Calculates weapon muzzle position in world coordinates
   - Handles weapon rotation and sprite offset
   - Provides fallback for missing weapon sprite

2. **Updated `_shoot()`**
   - Now uses `_get_muzzle_position()` for bullet spawn position
   - Calculates direction from muzzle to target

3. **Updated `_shoot_with_inaccuracy()`**
   - Same changes as `_shoot()`

4. **Updated `_shoot_burst_shot()`**
   - Same changes as `_shoot()`

5. **Updated `_is_bullet_spawn_clear()`**
   - Checks from enemy center to muzzle
   - Checks from muzzle outward in firing direction

6. **Updated `_is_firing_line_clear_of_friendlies()`**
   - Starts raycast from muzzle position

7. **Updated `_is_shot_clear_of_cover()`**
   - Starts raycast from muzzle position

8. **Updated `_draw()` debug visualization**
   - Shows actual muzzle position

## Relationship to PR #221

PR #221 introduced modular enemy models with a more complex structure:
```
Enemy (CharacterBody2D)
├── EnemyModel (Node2D)
│   ├── Body, Head, Arms (Sprite2D)
│   └── WeaponMount (Node2D)
│       └── WeaponSprite (Sprite2D)
```

PR #221 also attempted to fix the bullet spawn issue but encountered challenges with:
- Coordinate system flipping when enemies aim left
- Using `global_transform.x` which gets mirrored with negative Y scale
- Execution order between model rotation and shooting

This fix (issue #245) takes a simpler approach that works with the current main branch's structure (without the EnemyModel hierarchy). The key insight is to use `Vector2.from_angle(_weapon_sprite.global_rotation)` to get the weapon's forward direction, which correctly handles all rotation cases.

## Lessons Learned

1. **Bullet spawn should match visual position**: Players expect bullets to come from where the weapon visually points. Using the enemy center + offset creates a disconnect between visual and gameplay.

2. **Use rotation angles, not transform axes**: When a sprite can be flipped (negative scale), using `global_transform.x` can give incorrect directions. Instead, use `Vector2.from_angle(rotation)` which always gives the intended direction.

3. **Calculate direction from spawn point to target**: When bullets spawn from a different position than the character center, the direction should be calculated from the spawn point to ensure bullets actually fly toward the target.

4. **Update all related systems**: When changing bullet spawn position, also update:
   - Raycast checks for walls
   - Friendly fire detection
   - Cover detection
   - Debug visualization

## Test Plan

- [ ] Verify bullets spawn from the weapon muzzle visually
- [ ] Verify bullets fly toward the player (not offset to the side)
- [ ] Verify enemies can still hit the player when aiming at them
- [ ] Verify enemies don't shoot through walls (spawn clear check works)
- [ ] Verify friendly fire avoidance still works
- [ ] Verify debug visualization shows correct muzzle position
