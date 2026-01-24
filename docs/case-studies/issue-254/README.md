# Case Study: Issue #254 - Enemy Bullets Fly in Wrong Direction

## Overview

**Issue:** [#254 - fix пули врагов летят из ствола под любым углом](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/254)
**Pull Request:** [#255](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/255)
**Date Created:** 2026-01-22
**Status:** In Progress

## Problem Statement

Translation of issue text:
> "в https://github.com/Jhon-Crow/godot-topdown-MVP/pull/246 осталась проблема
> пули вылетают с конца оружия врагов в любом направлении, а должны только реалистично, по направлению ствола.
> это не должно сказаться на опасности врагов, они должны быстрее поворачиваться перед стрельбой."

Translation:
> "In PR #246, there's still a problem. Bullets fly from the end of enemy weapons in any direction, but they should only fly realistically, in the direction of the barrel. This should not affect the danger level of enemies; they should turn faster before shooting."

## Background - Previous Fixes

### Issue #245 and PR #246

PR #246 fixed THREE related bugs:

1. **Bug #1: Muzzle Position** - Bullets were spawning from inconsistent positions. Fixed by using `_weapon_sprite.global_transform.x.normalized()` to get the actual visual forward direction.

2. **Bug #2: Model Facing Direction (Flip Compensation)** - When the model is flipped vertically, the rotation angle's visual effect is inverted. Fixed by negating the rotation angle when applying the vertical flip.

3. **Bug #3: Model Facing Direction (Dual Rotation Conflict)** - The EnemyModel used local `rotation`, but the Enemy CharacterBody2D also had its own rotation set in various places. Fixed by using `global_rotation` instead of local `rotation`.

## Timeline of Events

### Phase 1: Initial Issue Creation (2026-01-22)

User @Jhon-Crow created issue #254 noting that despite the fixes in PR #246, bullets still fly in any direction from the weapon muzzle instead of realistically following the barrel direction.

## Root Cause Analysis

### Current Implementation

Looking at `scripts/objects/enemy.gd`, line 3656-3659:

```gdscript
# Calculate bullet direction FROM MUZZLE TO TARGET
# This ensures bullets actually fly toward the target, not just in the model's facing direction
# The model faces the player (center-to-center), and bullets fly from muzzle to target
var direction := (target_position - bullet_spawn_pos).normalized()
```

**The Design Decision**: The previous PR intentionally made bullets fly FROM muzzle TO target (player), not in the direction the barrel is pointing. This was a deliberate choice to ensure bullets always fly toward the player.

**The Problem**: This creates an unrealistic situation:
1. Enemy model rotates gradually (at `rotation_speed: float = 15.0` rad/sec)
2. While rotating, the barrel might point in a different direction than the player
3. But bullets still fly toward the player, creating a visual disconnect

**Example Scenario**:
- Enemy is facing right (angle 0°)
- Player is to the upper-left (angle -135°)
- Enemy starts rotating toward player
- At angle -45° (halfway rotated), enemy shoots
- Bullet spawns from muzzle (which is pointing toward -45°)
- But bullet flies toward -135° (directly to player)
- Visual: Barrel points one way, bullet goes another way

### User's Requirement

The user wants:
1. **Realistic bullet direction**: Bullets should fly in the direction the barrel is pointing
2. **Maintain danger level**: Enemies should still be effective in combat
3. **Faster rotation**: Enemies should rotate faster before shooting to compensate

## Proposed Solution

### Change 1: Bullet Direction

Modify the `_shoot()` function to use the weapon's visual forward direction instead of muzzle-to-target direction:

```gdscript
# BEFORE (unrealistic - bullets always fly to target):
var direction := (target_position - bullet_spawn_pos).normalized()

# AFTER (realistic - bullets fly in barrel direction):
var direction := _get_weapon_forward_direction()
```

### Change 2: Shoot Only When Aimed

Add a check to only shoot when the weapon is properly aimed at the target (within a small tolerance):

```gdscript
# Only shoot if weapon is roughly aimed at target
var weapon_forward := _get_weapon_forward_direction()
var to_target := (target_position - bullet_spawn_pos).normalized()
var aim_dot := weapon_forward.dot(to_target)
if aim_dot < 0.95:  # ~18° tolerance
    return  # Don't shoot until properly aimed
```

### Change 3: Increase Rotation Speed

Increase the default rotation speed to compensate:

```gdscript
# BEFORE:
@export var rotation_speed: float = 15.0

# AFTER (faster rotation, approximately 1.5x):
@export var rotation_speed: float = 25.0
```

## Technical Details

### Aim Tolerance Calculation

The dot product of two unit vectors equals `cos(angle_between_them)`:
- `cos(0°) = 1.0` (perfectly aligned)
- `cos(10°) ≈ 0.985`
- `cos(18°) ≈ 0.95`
- `cos(30°) ≈ 0.866`

Using `aim_dot < 0.95` means bullets only fire when within ~18° of target. This is realistic while still allowing for combat effectiveness.

### Rotation Speed Calculation

With `rotation_speed = 25.0 rad/sec`:
- 90° rotation takes: `(π/2) / 25 ≈ 0.063 sec` (63ms)
- 180° rotation takes: `π / 25 ≈ 0.126 sec` (126ms)

This is fast enough to maintain combat danger while allowing for realistic aim-before-shoot behavior.

## Files to Modify

### scripts/objects/enemy.gd

1. Increase `rotation_speed` from 15.0 to 25.0
2. Add aim tolerance check before shooting
3. Change bullet direction to use weapon forward direction
4. Apply same changes to `_shoot_with_inaccuracy()` and `_shoot_burst_shot()`

## Test Plan

- [ ] Verify bullets fly in the direction the barrel is pointing
- [ ] Verify enemies can still hit the player effectively
- [ ] Verify enemies rotate to face the player before shooting
- [ ] Verify rotation speed is noticeably faster
- [ ] Verify enemies remain challenging in combat

## References

- Issue #245: Previous shooting direction bugs
- PR #246: Previous fixes for muzzle position and facing direction
- `docs/case-studies/issue-245/`: Previous case study with detailed analysis
