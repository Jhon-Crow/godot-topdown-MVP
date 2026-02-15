# Case Study: Issue #781 - Homing Bullets Not Working for Pistol Weapons

## Issue Summary

**Issue:** `homing bullets не работает для пистолетных патронов` (Homing bullets don't work for pistol-type weapons)

**Affected weapons:**
- Makarov PM (ПМ)
- Uzi
- Silenced Pistol (пистолет с глушителем)
- Revolver (револьвер)

## Timeline of Events

| Time | Event |
|------|-------|
| 15:48:49 | Game session started with Makarov PM weapon |
| 15:48:54 | Player switched to Breaker Bullets active item |
| 15:49:16 | Player switched to Homing Bullets |
| 15:49:19 | First homing activation - 1 second duration |
| 15:49:28 | Second homing activation |
| 15:49:39 | Third homing activation |
| 15:49:49 | Fourth homing activation |

## Root Cause Analysis

### Problem

Pistol weapons use **GDScript bullets** (`bullet.gd`) while other weapons use **C# bullets** (`Bullet.cs`).

The `BaseWeapon.SpawnBullet()` method tries to call `enable_homing_with_aim_line()` first, then falls back to `enable_homing()`:

```csharp
if (bullet.HasMethod("enable_homing_with_aim_line"))
{
    bullet.Call("enable_homing_with_aim_line", player.GlobalPosition, aimDir);
}
else if (bullet.HasMethod("enable_homing"))
{
    bullet.Call("enable_homing");
}
```

**The GDScript `bullet.gd` was missing the `enable_homing_with_aim_line()` method**, so it fell back to the basic `enable_homing()` which:
1. Doesn't receive the player's aim direction
2. Targets nearest enemy to bullet instead of crosshair direction
3. Uses smaller turn angles and slower steering

### Evidence from Log

The game log shows:
- Homing was activated 4+ times during the session
- Player was using Makarov PM (Pistol weapon)
- No specific homing steering logs (debug mode was off)

## Solution

Added `enable_homing_with_aim_line(shooter_pos, aim_dir)` to `bullet.gd`:

1. **New variables:**
   - `_use_aim_line_targeting: bool` - enables aim-line targeting mode
   - `_shooter_origin: Vector2` - player position at firing time
   - `_shooter_aim_direction: Vector2` - player aim direction at firing time

2. **New method:**
   - `enable_homing_with_aim_line(shooter_pos, aim_dir)` - matches C# implementation
   - Increases `homing_max_turn_angle` to 170° for wider targeting
   - Increases `homing_steer_speed` to 50.0 for sharper turns

3. **Helper functions:**
   - `_find_enemy_nearest_to_aim_line(enemies)` - finds enemy closest to crosshair
   - `_has_line_of_sight_to_target(target_pos)` - wall-awareness (Issue #709)

## Files Modified

- `scripts/projectiles/bullet.gd` - Added aim-line targeting implementation
- `tests/unit/test_homing_bullets.gd` - Added unit tests

## Test Data

- `game_log_20260215_154849.txt` - Original game log from issue report

## References

- Issue #781: Original bug report
- Issue #709: Wall-awareness for homing (integrated)
- Issue #737: Max turn angle for aim-line targeting
