# Issue #241: Player Takes Self-Damage When Shooting Upward

## Bug Summary
Player takes damage when shooting upward with the assault rifle (M16), dying from self-inflicted bullet damage.

## Root Cause Analysis

### Investigation
The game log (`logs/game_log_20260122_131619.txt`) clearly shows the issue at timestamps 13:16:44:
- Player fires AssaultRifle at position (450, 1256)
- Immediately, `[PenultimateHit] Player damaged: 1.0 damage` occurs
- This happens repeatedly until the player dies

### Root Cause
**Property name case mismatch between C# and GDScript conventions.**

In `Scripts/AbstractClasses/BaseWeapon.cs`, the code was setting bullet properties using snake_case:
```csharp
bullet.Set("shooter_id", owner.GetInstanceId());
bullet.Set("shooter_position", GlobalPosition);
```

However, the C# Bullet class (`Scripts/Projectiles/Bullet.cs`) uses PascalCase property names:
```csharp
public ulong ShooterId { get; set; } = 0;
public Vector2 ShooterPosition { get; set; } = Vector2.Zero;
```

Because of this mismatch, the `ShooterId` was never properly set on C# bullets spawned by the AssaultRifle. The bullet's self-damage prevention check failed because `ShooterId == 0`:

```csharp
// In Bullet.cs OnAreaEntered():
if (parent != null && ShooterId == parent.GetInstanceId() && !_hasRicocheted)
{
    return; // Don't hit the shooter with direct shots
}
```

With `ShooterId = 0` and `parent.GetInstanceId()` returning a valid ID, the check `0 == validId` always failed, so bullets hit the player.

### Evidence from Other Weapons
Other weapons in the codebase correctly use PascalCase:
- `Scripts/Weapons/Shotgun.cs:1147`: `pellet.Set("ShooterId", ...)`
- `Scripts/Characters/Player.cs:1428`: `bullet.Set("ShooterId", ...)`

Only `BaseWeapon.cs` used the wrong case.

## Fix Applied

Updated `Scripts/AbstractClasses/BaseWeapon.cs` to set properties using both PascalCase (C#) and snake_case (GDScript) for compatibility:

```csharp
// Set shooter ID to prevent self-damage
var owner = GetParent();
if (owner != null)
{
    // Try both cases for compatibility with C# and GDScript bullets
    bullet.Set("ShooterId", owner.GetInstanceId());
    bullet.Set("shooter_id", owner.GetInstanceId());
}

// Set shooter position for distance-based penetration calculations
bullet.Set("ShooterPosition", GlobalPosition);
bullet.Set("shooter_position", GlobalPosition);
```

This ensures the property is set regardless of whether the bullet is a C# or GDScript implementation.

## Files Changed
- `Scripts/AbstractClasses/BaseWeapon.cs`

## Lessons Learned
1. Property names in Godot's `Set()` method are case-sensitive
2. C# properties export with their original PascalCase names
3. GDScript properties use snake_case by convention
4. When supporting both C# and GDScript variants, consider setting both property name cases
