# Case Study: Issue #457 - Weapon Shooting Incorrectly on Castle Map

## Issue Summary

**Title**: fix оружие стреляет не правильно на карте Замок (Weapons shoot incorrectly on Castle map)

**Reported Problems**:
1. Enemy shotgun periodically shoots single pellets instead of multiple pellets
2. M16 shoots not in the barrel direction

## Timeline Analysis

### Initial Report
- **Date**: 2026-02-04
- **Reporter**: Jhon-Crow
- **Map Affected**: CastleLevel

### Evidence Gathered
- Game log file: `game_log_20260204_010437.txt` (~1.7MB, 18,703 lines)
- Log shows CastleLevel has 13 enemies including:
  - 3 shotgun enemies (ShotgunEnemy1, ShotgunEnemy2, ShotgunEnemyRight1)
  - 8 UZI enemies
  - 2 rifle enemies (LowerEnemy1, LowerEnemy2)

## Root Cause Analysis

### Problem 1: M16 Shoots Not in Barrel Direction

**Root Cause Identified**: Visual rotation mismatch with travel direction

The enemy's `_spawn_projectile()` function set the `Direction` property directly:
```gdscript
if p.get("Direction") != null: p.Direction = direction
```

However, C# projectiles (Bullet.cs, ShotgunPellet.cs) have a `SetDirection()` method that:
1. Sets the `Direction` property
2. Calls `UpdateRotation()` to sync visual rotation with travel direction

When setting the property directly without calling `SetDirection()`, the projectile travels correctly but its **visual sprite rotation doesn't match** the travel direction, making it appear to fly sideways.

**Evidence**: The player's Shotgun.cs correctly uses:
```csharp
if (pellet.HasMethod("SetDirection"))
    pellet.Call("SetDirection", direction);
else
    pellet.Set("Direction", direction);
```

### Problem 2: Shotgun Shooting Single Pellets

**Investigation Status**: Pending verification with additional logging

Potential causes considered:
1. Weapon type not being set to SHOTGUN (weapon_type=1)
2. `_is_shotgun_weapon` flag not being set correctly
3. `_pellet_count_min/max` values not being loaded from config
4. Random number generation issues

**Verification**: CastleLevel.tscn correctly sets `weapon_type = 1` for shotgun enemies:
```
[node name="ShotgunEnemy1" parent="Environment/Enemies" instance=ExtResource("4_enemy")]
weapon_type = 1
```

WeaponConfigComponent correctly defines shotgun config:
```gdscript
1: {  # SHOTGUN
    "is_shotgun": true,
    "pellet_count_min": 6,
    "pellet_count_max": 10,
    "spread_angle": 15.0
}
```

## Solution Implemented

### Fix 1: Use SetDirection() Method for C# Projectiles

**File**: `scripts/objects/enemy.gd`

**Change**: Modified `_spawn_projectile()` to prefer `SetDirection()` method:

```gdscript
# Issue #457 Fix: Prefer SetDirection() method for C# projectiles
if p.has_method("SetDirection"):
    p.SetDirection(direction)
elif p.get("direction") != null:
    p.direction = direction
elif p.get("Direction") != null:
    p.Direction = direction
```

This ensures `UpdateRotation()` is called to sync the visual rotation with the actual travel direction.

### Fix 2: Enhanced Logging for Shotgun Debugging

Added debug logging to:
1. Weapon configuration (`_configure_weapon_type()`)
2. Shotgun firing (`_shoot_shotgun_pellets()`)

This will help verify if the shotgun is configured correctly and firing the expected number of pellets.

## Testing Recommendations

1. **Visual Direction Test**:
   - Spawn rifle enemies on Castle map
   - Observe bullet trails - they should now align with barrel direction

2. **Shotgun Pellet Count Test**:
   - Enable `debug_logging` on shotgun enemies
   - Verify log output shows correct pellet counts (6-10)
   - Visually confirm multiple pellets per shot

3. **Regression Testing**:
   - Test on other levels (BuildingLevel) to ensure no regression
   - Verify player weapons still work correctly

## Files Modified

1. `scripts/objects/enemy.gd`:
   - `_spawn_projectile()` - Added SetDirection() method call for C# projectiles
   - `_configure_weapon_type()` - Enhanced logging for shotgun configuration
   - `_shoot_shotgun_pellets()` - Added debug logging for pellet count

## Lessons Learned

1. **GDScript/C# Interop**: When calling C# methods from GDScript, prefer using explicit method calls (e.g., `SetDirection()`) over property assignment when the method performs additional logic beyond simple assignment.

2. **Visual vs Functional Behavior**: A projectile can travel correctly while appearing to go in the wrong direction if rotation isn't synchronized with velocity. Always ensure visual state matches functional state.

3. **Defensive Programming**: Use `has_method()` checks before calling methods to support multiple projectile implementations (GDScript and C#).

## Related Issues

- Issue #254: Aim-before-shoot behavior
- Issue #264: Transform delay issues
- Issue #344: Close-range shooting issues
- Issue #417: Player-like weapons for enemies
