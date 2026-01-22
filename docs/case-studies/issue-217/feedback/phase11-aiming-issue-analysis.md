# Phase 11: Enemy Aiming Issue Analysis

## User Report
**Date**: 2026-01-22
**Issue**: "враги стреляют мимо меня (целятся не оружием)" - Enemies shoot past me (not aiming with weapon)
**Log File**: game_log_20260122_131801.txt

## Root Cause Analysis

### Problem Summary
Enemies were shooting in the **opposite direction** from where their weapon was visually pointing. The bullets were being fired 180 degrees away from the intended target (player).

### Technical Details

#### The Bug Location
File: `scripts/objects/enemy.gd`
Function: `_update_enemy_model_rotation()` (lines 1057-1095)

#### Incorrect Code
```gdscript
func _update_enemy_model_rotation() -> void:
    # ...
    var target_angle := face_direction.angle() + PI  # <-- BUG: Adding PI
    _enemy_model.rotation = target_angle
```

#### Why This Was Wrong

1. **Sprite Orientation**: Enemy sprites face RIGHT (+X direction) in local space, just like player sprites
2. **PI Offset Misunderstanding**: The comment claimed "Enemy sprites face LEFT (PI radians offset from player sprites which face RIGHT)" - this was incorrect
3. **Effect on Weapon Direction**:
   - `_get_weapon_forward_direction()` uses `_weapon_sprite.global_transform.x.normalized()`
   - When `_enemy_model.rotation = face_direction.angle() + PI`, the weapon's +X axis points AWAY from the player
   - Bullets used this direction, so they flew in the opposite direction

#### Comparison with Player Code
Player's `_update_player_model_rotation()` (lines 350-377):
```gdscript
var target_angle := aim_direction.angle()  # No PI offset
_player_model.rotation = target_angle
```

The player code correctly sets rotation without adding PI, and the weapon points toward the target.

### Evidence from Logs

Looking at bullet spawn positions in the game log, we can see patterns like:
```
[INFO] [Bullet] _get_distance_to_shooter: shooter_position=(476.8153, 810.0131), shooter_id=41188066843, bullet_pos=(261.6806, 1396.82)
```

The bullet traveling from (476, 810) to (261, 1396) shows a direction of approximately (-0.32, 0.95) - going down-left. If the enemy was at (507, 749) aiming at the player, this direction is roughly 180 degrees off from where the player would be.

## Fix Applied

Remove the `+ PI` from the rotation calculation and update the flip logic accordingly:

```gdscript
func _update_enemy_model_rotation() -> void:
    # ...
    # Calculate target rotation angle
    # Enemy sprites face RIGHT (same as player sprites, 0 radians)
    var target_angle := face_direction.angle()  # Removed + PI

    # Apply rotation to the enemy model
    _enemy_model.rotation = target_angle

    # Handle sprite flipping for left/right aim
    # When aiming left (angle > 90 or < -90), flip vertically
    var aiming_left := absf(target_angle) > PI / 2

    # Flip the enemy model vertically when aiming left
    if aiming_left:
        _enemy_model.scale = Vector2(enemy_model_scale, -enemy_model_scale)
    else:
        _enemy_model.scale = Vector2(enemy_model_scale, enemy_model_scale)
```

## Impact

- Enemies now correctly aim their weapons at the player
- Bullets spawn from weapon muzzle and travel toward the target
- Visual alignment matches actual bullet trajectory

## Lesson Learned

When copying/adapting code between similar entities (player/enemy), verify sprite orientation assumptions rather than assuming they need different handling. Both player and enemy use RIGHT-facing sprites, so their rotation logic should be identical.
