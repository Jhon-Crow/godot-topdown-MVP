# Case Study: Issue #332 - Enemy FOV Logic Improvements

## Issue Summary

**Issue**: [fix логика врагов с полем зрения](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/332)

**Reporter**: Jhon-Crow

**Date**: 2026-01-25

## Problem Statement

The issue reported three distinct problems with enemy FOV (Field of View) behavior:

1. **Debug FOV visual doesn't match actual look direction** - When enemies stand still and turn their heads, the debug visualization (FOV cone) doesn't rotate to show the actual facing direction.

2. **Enemies don't react to being hit** - When hit by player bullets, enemies should turn toward the attacker but currently don't react.

3. **Enemies don't check corners when patrolling** - Patrol enemies walk past corners and doorways without checking them, allowing the player to hide in perpendicular passages.

## Root Cause Analysis

### Issue 1: FOV Cone Not Rotating

**Location**: `scripts/objects/enemy.gd:_draw_fov_cone()`

The `_draw_fov_cone()` function was drawing the FOV cone at a fixed angle (0 degrees, facing right) without accounting for `_enemy_model.global_rotation`.

The enemy's actual facing direction is stored in `_enemy_model.global_rotation`, but this wasn't being used in the drawing calculations.

### Issue 2: No Hit Reaction

**Location**: `scripts/objects/enemy.gd:on_hit_with_bullet_info()`

The hit handling function stored the hit direction for death animations but didn't use it to reorient the enemy model to face the attacker.

### Issue 3: No Corner Checking During Patrol

**Location**: `scripts/objects/enemy.gd:_process_patrol()`

Patrol enemies only looked in their movement direction. There was no logic to detect and check perpendicular openings (doorways, corridors) while walking.

## Solutions Implemented

### Fix 1: FOV Cone Rotation

Modified `_draw_fov_cone()` to use `_enemy_model.global_rotation` as the base angle for all cone calculations.

### Fix 2: Hit Reaction Rotation

Added rotation logic to `on_hit_with_bullet_info()` to turn the enemy toward the attacker using `-hit_direction` (opposite of bullet travel).

### Fix 3: Corner Checking for Patrol Enemies

Added a new function `_detect_perpendicular_opening()` and integrated it into `_process_patrol()`:

- Uses raycasts to detect openings perpendicular to movement direction
- When an opening is detected, briefly rotates to face it
- Uses a cooldown timer (`CORNER_CHECK_DURATION = 0.3s`) to avoid constant spinning

## Code Changes Summary

| File | Lines Changed | Description |
|------|---------------|-------------|
| `scripts/objects/enemy.gd` | +20/-35 | FOV fix, hit reaction, corner checking, removed deprecated function |

## Testing

Game logs collected from the user's testing session are stored in:
- `docs/case-studies/issue-332/logs/game-logs/`

## Architecture Notes

### Code Size Constraint

The `scripts/objects/enemy.gd` file has a CI-enforced limit of 5000 lines. To accommodate the new features:

1. Removed the deprecated `_calculate_aim_direction_from_weapon()` function
2. Condensed the `_is_player_distracted()` function
3. Final line count: 4995 lines (5 lines under limit)

## Future Improvements

1. **Tactical Sector Coverage** - Multiple enemies should coordinate to cover different directions
2. **Predictive Corner Checking** - Check corners ahead based on navigation path
3. **Variable Corner Check Duration** - Longer pauses at major intersections
