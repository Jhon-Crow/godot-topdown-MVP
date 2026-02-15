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

## Regression: Bullets Not Flying (2026-02-15)

### Symptom

After the initial fix, user reported:
> "пистолетные пули полностью сломались - при стрельбе появляются красные прямоугольники, но не летят"
> (Pistol bullets completely broken - when shooting, red rectangles appear but don't fly)

### Root Cause: Missing @export Annotations

**Critical finding:** In Godot 4.x, `Node.Set()` called from C# can only set **exported** (`@export`) properties on GDScript nodes. Non-exported variables are silently ignored.

The `bullet.gd` had several variables that were set from C# weapons but were NOT exported:

```gdscript
# BEFORE (broken):
var direction: Vector2 = Vector2.RIGHT       # ❌ Not exported
var shooter_id: int = -1                     # ❌ Not exported
var shooter_position: Vector2 = Vector2.ZERO # ❌ Not exported
var stun_duration: float = 0.0               # ❌ Not exported
var is_breaker_bullet: bool = false          # ❌ Not exported
```

When C# called `bulletNode.Set("direction", direction)`, it **silently failed**, leaving `direction = Vector2.RIGHT` (default value pointing right). The bullet would spawn but:
1. Direction wasn't set → bullet always moved right
2. If spawn position was behind a wall facing right → bullet immediately destroyed
3. Visual "red rectangle" appeared briefly before destruction

### Fix

Added `@export` annotation to all variables set from C#:

```gdscript
# AFTER (fixed):
@export var direction: Vector2 = Vector2.RIGHT       # ✅ Exported
@export var shooter_id: int = -1                     # ✅ Exported
@export var shooter_position: Vector2 = Vector2.ZERO # ✅ Exported
@export var stun_duration: float = 0.0               # ✅ Exported
@export var is_breaker_bullet: bool = false          # ✅ Exported
@export var homing_enabled: bool = false             # ✅ Exported
@export var damage_multiplier: float = 1.0           # ✅ Exported
```

### Lesson Learned

**When using C#/GDScript interop in Godot 4.x:**
- `Node.Set("property", value)` only works on `@export` properties
- Non-exported variables are silently ignored (no error, no warning)
- Always use `@export` for any GDScript variable that C# needs to set
- Alternatively, use `Call("method_name", args)` to call setter methods

## Files Modified

- `scripts/projectiles/bullet.gd` - Added aim-line targeting implementation + @export annotations
- `tests/unit/test_homing_bullets.gd` - Added unit tests

## Second Regression: Bullets Still Not Flying (2026-02-15 18:11 UTC)

### Symptom

After the @export fix was pushed, user reported:
> "пули всё ещё сломаны, проверь С#"
> (bullets still broken, check C#)

### Analysis

1. **Log Analysis:** The new log (`game_log_20260215_211028.txt`) shows:
   - Player fires Makarov PM (lines 326, 330, 338, etc.)
   - **NO `[Bullet]` debug messages appear**
   - This indicates either outdated build or different issue

2. **Timeline Mismatch:**
   - User's log timestamp: 18:11 UTC
   - Fix commit timestamp: 17:42 UTC
   - User likely used old exported build without @export fix

3. **Additional Investigation:**
   - Added diagnostic logging to `MakarovPM.cs` and `BaseWeapon.cs`
   - Log now shows `[MakarovPM] GDScript bullet detected` and actual direction after Set()
   - Simplified property setting: only use snake_case (GDScript convention)
   - Removed redundant PascalCase attempts that don't work with GDScript

### Changes Made (2026-02-15 18:30+ UTC)

1. **MakarovPM.cs:**
   - Simplified GDScript bullet property setting
   - Added diagnostic logging to verify direction is set correctly
   - Use only snake_case property names: `direction`, `speed`, `shooter_id`, etc.

2. **BaseWeapon.cs:**
   - Restructured SpawnBullet to clearly separate C# vs GDScript paths
   - Added verification that direction was actually set
   - Added `[BaseWeapon]` logging for debugging

### Key Insight: C# to GDScript Property Interop

When calling `Node.Set()` from C# to set a GDScript `@export` property:
- Use the **exact snake_case name** as defined in GDScript: `Set("direction", value)`
- PascalCase names like `Set("Direction", value)` don't work
- The property MUST be `@export` decorated in GDScript

## Test Data

- `logs/game_log_20260215_154849.txt` - Original game log from issue report
- `logs/game_log_20260215_164144.txt` - Regression log (bullets not flying, first report)
- `logs/game_log_20260215_211028.txt` - Second regression log (still not flying)

## References

- Issue #781: Original bug report
- Issue #709: Wall-awareness for homing (integrated)
- Issue #737: Max turn angle for aim-line targeting
- Godot 4.x C#/GDScript interop: https://docs.godotengine.org/en/stable/tutorials/scripting/cross_language_scripting.html
