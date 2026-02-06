# Case Study: Issue #516 — Enemy Weapon Spread + Bullet Direction Bug

## Timeline

1. **Issue #516 reported**: Enemies have no weapon spread. UZI should have rapidly increasing spread (same as player).
2. **PR #517 created**: Added progressive weapon spread to enemies matching player's system.
3. **User feedback on PR**: "M16 bullets start flying exactly to the right (not in barrel direction)."
4. **Investigation**: Downloaded game log, analyzed bullet trajectories, identified root cause.

## Original Issue: No Enemy Weapon Spread

### Problem
Enemy single-bullet weapons (rifle, UZI) fired with **zero spread**, making them unrealistically accurate. The player's weapons all have progressive spread systems.

### Fix
Added progressive spread parameters to `weapon_config_component.gd` and spread calculation to `_shoot_single_bullet()` in `enemy.gd`. The spread mirrors the player's system:
- **Rifle**: threshold=3, initial=0.5°, increment=0.6°/shot, max=4.0°
- **UZI**: threshold=0, initial=6.0°, increment=5.4°/shot, max=60.0° after 10 shots
- **Shotgun**: no progressive spread (uses existing pellet spread system)

## Discovered Bug: Bullets Flying Right (Vector2.RIGHT)

### Evidence from Game Log

File: `game_log_20260206_212633.txt` (8738 lines)

Key observations:
- Bullets with valid `shooter_id` (e.g., `49358571115`) travel toward the player correctly.
- Bullets with `shooter_id=0` and `shooter_position=(0, 0)` travel horizontally right.
- Example: `bullet_pos=(920.12, 688.86)` with `shooter_position=(0, 0)` — the bullet's y=688.86 matches Enemy3's y position, but it moves purely along the X axis.

### Root Cause Analysis

The enemy `_spawn_projectile()` function had two issues:

1. **Property setting before `add_child()`**: The C# Bullet node was having its properties set via GDScript interop *before* being added to the scene tree. While `SetDirection()` likely works in most cases, the `shooter_id` and `shooter_position` properties were being set through generic property access (`p.shooter_id = value`) rather than dedicated setter methods, which may fail silently in cross-language (GDScript → C#) interop.

2. **Missing setter method calls**: The C# Bullet class provides dedicated methods `SetShooterId()` and `SetShooterPosition()` (lines 411, 421 in `Bullet.cs`), but `_spawn_projectile()` only used `SetDirection()` as a method call and tried to set other properties via direct assignment.

### Fix Applied

Updated `_spawn_projectile()` to:
1. Call `add_child(p)` first so C# `_Ready()` initializes the node
2. Then set direction via `SetDirection()` (which also calls `UpdateRotation()`)
3. Use `SetShooterId()` and `SetShooterPosition()` setter methods when available
4. Fall back to property assignment for GDScript bullets

This matches the pattern used by `BaseWeapon.cs` (the player's C# weapon base class).

### Comparison with BaseWeapon.cs

The player's C# weapon (`BaseWeapon.cs`) spawns bullets differently:
```csharp
// BaseWeapon.cs pattern:
bullet.Call("SetDirection", direction);
bullet.Set("ShooterId", owner.GetInstanceId());
bullet.Set("ShooterPosition", GlobalPosition);
GetTree().CurrentScene.AddChild(bullet);
```

Our fix aligns the enemy's GDScript approach with this pattern by using setter methods.

## Files Changed

- `scripts/objects/enemy.gd` — Progressive spread + `_spawn_projectile` interop fix
- `scripts/components/weapon_config_component.gd` — Spread parameters per weapon type
- `tests/unit/test_enemy.gd` — 8 regression tests for spread system

## Key Lessons

1. **Cross-language interop**: When calling C# methods/properties from GDScript, prefer dedicated setter methods over direct property assignment.
2. **Node lifecycle**: Setting properties on C# nodes after `add_child()` ensures `_Ready()` has run and the node is fully initialized.
3. **Default values matter**: C# Bullet defaults `Direction = Vector2.Right` and `ShooterId = 0`. If property setting fails silently, bullets fly right with no shooter attribution.
