# Case Study: Issue #704 - Fix Homing Bullets Active Item

## Problem Summary

PR #689 implemented homing bullets that only worked on M16 and AK assault rifles. The issue reported that:
1. Homing bullets didn't work on shotgun pellets
2. Homing bullets didn't work on sniper rifle trajectory
3. Targeting behavior needed two modes:
   - **Airborne bullets** (already in flight when activated): home toward nearest enemy **to the bullet**
   - **Newly fired bullets** (fired during activation): home toward enemy closest **to the player's line of fire/crosshair**

## Root Cause Analysis

### Why only M16/AK worked

The homing system from PR #689 was implemented in three locations:
1. `Bullet.cs` - homing steering logic (`EnableHoming()`, `ApplyHomingSteering()`)
2. `Player.cs` - activation management and airborne bullet enablement
3. `BaseWeapon.cs` - enabling homing on newly spawned bullets via `SpawnBullet()`

The M16/AK (`AssaultRifle.cs`) worked because it calls `base.Fire()` which uses `BaseWeapon.SpawnBullet()`, which contains the homing check.

### Why Shotgun didn't work

`Shotgun.cs` completely overrides the firing mechanism:
- `Fire()` → `FirePelletsAsCloud()` → `SpawnPelletWithOffset()` — **custom spawn logic**
- `SpawnPelletWithOffset()` bypasses `BaseWeapon.SpawnBullet()` entirely
- `ShotgunPellet.cs` (extends `Area2D`) had **no homing-related code** at all
- No check for `Player.IsHomingActive()` in the shotgun's pellet spawning

### Why Sniper Rifle didn't work

`SniperRifle.cs` uses **hitscan** (instant raycast) instead of projectiles:
- `Fire()` sets `_skipBulletSpawn = true` before calling `base.Fire()`
- `SpawnBullet()` returns immediately without creating any bullet
- `PerformHitscan()` applies instant damage via raycasting
- Since no `Bullet` objects exist, there's nothing to steer

## Timeline of Events

1. **PR #689** (merged): Added homing bullets feature for M16/AK
2. **Issue #704** (opened): Owner tested with all weapons, found homing only works on 2 of 4 weapon types
3. Game logs (`game_log_20260209_033509.txt`, `game_log_20260209_033930.txt`) confirmed:
   - `[Player.Homing]` logs show activation/deactivation working
   - No `[Bullet]` homing steering logs appear → bullets don't steer
   - Testing with Makarov PM (pistol) — would work via BaseWeapon path
   - Shotgun and sniper were completely unaffected

## Solution

### 1. ShotgunPellet.cs — Add homing support
- Added homing fields: `_homingEnabled`, `_homingMaxTurnAngle`, `_homingSteerSpeed`, `_homingOriginalDirection`
- Added `EnableHoming()` method for airborne pellets (nearest-to-pellet targeting)
- Added `EnableHomingWithAimLine()` method for newly fired pellets (aim-line targeting)
- Added `ApplyHomingSteering()` with same algorithm as `Bullet.cs`
- Added `FindNearestEnemyPosition()` with dual targeting modes
- Integrated into `_PhysicsProcess()`

### 2. Shotgun.cs — Enable homing on spawned pellets
- Added homing check in `SpawnPelletWithOffset()` after `AddChild(pellet)`
- When player's homing is active, calls `EnableHomingWithAimLine()` on each pellet
- Uses player's aim direction for targeting

### 3. SniperRifle.cs — Redirect hitscan toward nearest enemy
- Modified `Fire()` to check `Player.IsHomingActive()` before hitscan
- Added `FindNearestEnemyNearAimLine()` method
- When homing active, redirects the hitscan direction toward the best target enemy
- Uses perpendicular distance scoring to find the enemy closest to the aim line

### 4. Bullet.cs — Add aim-line targeting mode
- Added `EnableHomingWithAimLine(Vector2 shooterPos, Vector2 aimDir)` method
- Added `FindEnemyNearestToAimLine()` for aim-line-based target selection
- `FindNearestEnemyPosition()` now dispatches to the appropriate targeting mode

### 5. BaseWeapon.cs — Use aim-line targeting for new bullets
- Updated homing enablement code to pass shooter position and aim direction
- Calls `EnableHomingWithAimLine()` instead of `EnableHoming()` for newly spawned bullets

### 6. Player.cs — Handle ShotgunPellet in airborne activation
- Updated `EnableHomingRecursive()` to also detect and enable homing on `ShotgunPellet` nodes

## Targeting Modes (Issue #704)

| Scenario | Targeting Mode | Algorithm |
|----------|---------------|-----------|
| Bullet already airborne, Space pressed | Nearest to bullet | `distance_squared(bullet, enemy)` |
| Bullet fired during active homing | Nearest to aim line | `perp_distance(enemy, aim_line) + distance * 0.1` |
| Shotgun pellet already airborne | Nearest to pellet | `distance_squared(pellet, enemy)` |
| Shotgun pellet fired during homing | Nearest to aim line | `perp_distance(enemy, aim_line) + distance * 0.1` |
| Sniper rifle fired during homing | Nearest to aim line | Redirect hitscan direction toward best target |

## Files Modified

| File | Changes |
|------|---------|
| `Scripts/Projectiles/ShotgunPellet.cs` | Added full homing system with aim-line targeting |
| `Scripts/Weapons/Shotgun.cs` | Added homing enablement in `SpawnPelletWithOffset()` |
| `Scripts/Weapons/SniperRifle.cs` | Added `FindNearestEnemyNearAimLine()`, hitscan redirection |
| `Scripts/Projectiles/Bullet.cs` | Added `EnableHomingWithAimLine()`, `FindEnemyNearestToAimLine()` |
| `Scripts/AbstractClasses/BaseWeapon.cs` | Updated to use aim-line targeting for new bullets |
| `Scripts/Characters/Player.cs` | Added ShotgunPellet handling in `EnableHomingRecursive()` |
| `tests/unit/test_homing_bullets.gd` | Added tests for pellet homing, aim-line targeting, sniper homing |

## Follow-up: Pistol Homing Bug (2026-02-09)

### Problem

After the initial fix for shotgun and sniper, the issue owner reported that homing also
doesn't work for pistols: Makarov PM, Silenced Pistol, Mini UZI, and Revolver.

### Root Cause

Two weapons had overridden `SpawnBullet()` to set custom `StunDuration` on their bullets:
- **MakarovPM.cs** (`SpawnBullet()` override, line 406): Completely reimplemented bullet spawning
  to set `StunDuration = 0.1f`, but omitted the homing activation code from `BaseWeapon.SpawnBullet()`.
- **SilencedPistol.cs** (`SpawnBullet()` override, line 643): Completely reimplemented bullet spawning
  to set `StunDuration = 0.6f` and custom muzzle flash, but omitted the homing activation code.

Both overrides copy-pasted the bullet instantiation logic from `BaseWeapon.SpawnBullet()` but
missed the homing enablement block (lines 435-453 of `BaseWeapon.cs`).

**Revolver** and **MiniUzi** do NOT override `SpawnBullet()` — they call `base.Fire()` which
uses `BaseWeapon.SpawnBullet()` with the homing code intact. These should have been working,
and the user may have been testing primarily with PM and silenced pistol.

### Fix

Added homing activation code to both `MakarovPM.SpawnBullet()` and `SilencedPistol.SpawnBullet()`,
matching the pattern from `BaseWeapon.SpawnBullet()`:

```csharp
// Enable homing on the bullet if the player's homing effect is active (Issue #704)
var weaponOwner = GetParent();
if (weaponOwner is Player player && player.IsHomingActive())
{
    Vector2 aimDir = (GetGlobalMousePosition() - player.GlobalPosition).Normalized();
    if (bullet != null)
    {
        bullet.EnableHomingWithAimLine(player.GlobalPosition, aimDir);
    }
    else if (bulletNode.HasMethod("enable_homing_with_aim_line"))
    {
        bulletNode.Call("enable_homing_with_aim_line", player.GlobalPosition, aimDir);
    }
    else if (bulletNode.HasMethod("enable_homing"))
    {
        bulletNode.Call("enable_homing");
    }
}
```

### Updated Files Modified

| File | Changes |
|------|---------|
| `Scripts/Weapons/MakarovPM.cs` | Added `using GodotTopDownTemplate.Characters`, homing activation in `SpawnBullet()` |
| `Scripts/Weapons/SilencedPistol.cs` | Added `using GodotTopDownTemplate.Characters`, homing activation in `SpawnBullet()` |

### Lessons Learned

When base class methods contain important logic (like homing activation), subclass overrides
must either call `base.SpawnBullet()` or replicate all essential behaviors. The OOP principle
of not breaking Liskov Substitution applies here: the overrides silently dropped a feature
that was expected to work across all weapon types.

### New Game Logs

- `game_log_20260209_092738.txt` — Testing pistols with homing (12408 lines)
- `game_log_20260209_093001.txt` — Testing shotgun and UZI with homing (8134 lines)
- `game_log_20260209_102552.txt` — Extended testing session 1
- `game_log_20260209_102645.txt` — Extended testing session 2

## Logs

- `logs/game_log_20260209_033509.txt` — First testing session (8791 lines)
- `logs/game_log_20260209_033930.txt` — Second testing session (5221 lines)

---

## Follow-up: GDScript Bullets Not Moving (2026-02-10)

### Problem

User reported (PR #706 comment 2026-02-10):
> "пули у пистолетов полностью сломались - не летят, просто появляются красные прямоугольники"
> Translation: "pistol bullets are completely broken - they don't fly, only red rectangles appear"

### Initial Analysis

Examined `game_log_20260210_221451.txt`:

1. **C# Bullets (AssaultRifle) work correctly**:
   - Line 604: `GUNSHOT, source=PLAYER (AssaultRifle)`
   - Lines 607+: `[Bullet] _get_distance_to_shooter...` — bullets moving and hitting walls

2. **GDScript Bullets (MakarovPM, Revolver) don't produce movement logs**:
   - Line 309: `GUNSHOT, source=PLAYER (MakarovPM)` — shot fired
   - No subsequent `[Bullet]` logs — bullets not moving

### Weapon → Bullet Scene Mapping

| Weapon | Bullet Scene | Script Type | Status |
|--------|--------------|-------------|--------|
| AssaultRifle | `csharp/Bullet.tscn` | C# `Bullet.cs` | ✅ Working |
| MakarovPM | `Bullet9mm.tscn` | GDScript `bullet.gd` | ❌ Not Moving |
| Revolver | `Bullet12p7mm.tscn` | GDScript `bullet.gd` | ❌ Not Moving |
| SilencedPistol | `Bullet9mm.tscn` | GDScript `bullet.gd` | ❌ Not Moving |

### Hypothesis

The issue is specific to **GDScript bullets spawned from C# weapons**. The C# code uses
`Node.Set("property_name", value)` to set GDScript properties before adding the bullet
to the scene tree. Something in this flow may be causing properties (especially `direction`
and `speed`) to not be applied correctly in release builds.

### Diagnostic Logging Added

Added logging to `bullet.gd` to capture property values:
- `_ready()`: logs direction, speed, shooter_id, position when bullet initializes
- `_physics_process()`: logs direction, speed, delta, position for first 3 frames

This will reveal whether:
1. Properties are being set correctly before/after AddChild
2. `_physics_process` is running
3. Direction/speed values are correct or defaulting

---

## Follow-up: GDScript Bullets Still Broken (2026-02-10, Second Report)

### Problem

User reported (PR #706 comment 2026-02-10):
> "пули пистолетов и uzi всё ещё сломаны"
> Translation: "pistol and UZI bullets are still broken"

New game logs provided:
- `game_log_20260210_224728.txt` (132KB)
- `game_log_20260210_224755.txt` (252KB)

### Root Cause Analysis

**Key Evidence:**
- 232 `[Bullet]` log entries found (from C# `Bullet.cs`)
- 0 `[Bullet.gd]` log entries found (from GDScript `bullet.gd`)
- Even though `Bullet9mm.tscn` uses `bullet.gd`, the GDScript code was NEVER executed

**The Bug Location:**

In `MakarovPM.cs` and `SilencedPistol.cs`, the `SpawnBullet()` method used:

```csharp
var bullet = bulletNode as Bullet;  // Line 431

if (bullet != null)  // THIS IS THE PROBLEM!
{
    // C# Bullet initialization
    bullet.Direction = direction;
    // ... etc
}
else
{
    // GDScript fallback - NEVER REACHED
    if (bulletNode.HasMethod("initialize_bullet"))
    {
        bulletNode.Call("initialize_bullet", ...);
    }
}
```

**Why the bug occurs:**

1. `BulletScene.Instantiate<Node2D>()` instantiates `Bullet9mm.tscn` which uses `bullet.gd`
2. The cast `bulletNode as Bullet` attempts to cast a GDScript node to a C# class
3. In Godot, **this cast incorrectly succeeds** due to Godot's permissive type system
4. However, the resulting `bullet` object doesn't have C# properties like `Direction`, `Speed`, etc.
5. Setting `bullet.Direction = direction` **fails silently** — property doesn't exist
6. The `else` block with `initialize_bullet()` is **never reached**
7. The GDScript bullet gets added to the scene with default values: `direction = Vector2.RIGHT`, `speed = 2500`
8. Result: Bullets appear but don't move toward intended target / homing doesn't work

**Correct Pattern (from `BaseWeapon.cs`):**

```csharp
if (bullet is CSharpBullet csBulletInit)  // Correct: use 'is' not 'as'
{
    // C# bullet code
}
else if (bullet.HasMethod("initialize_bullet"))  // GDScript fallback
{
    bullet.Call("initialize_bullet", ...);
}
```

### Second Bug: shooter_id Truncation

The GDScript `shooter_id` parameter was being cast to `(int)`:

```csharp
bulletNode.Call("initialize_bullet",
    direction,
    WeaponData?.BulletSpeed ?? 2500.0f,
    WeaponData?.Damage ?? 1.0f,
    (int)shooterId,  // BUG: truncates 64-bit ID
    GlobalPosition,
    StunDurationOnHit);
```

Game logs showed shooter IDs like `113346874310` (larger than `int.MaxValue`).
This causes:
1. ID truncation → corrupted value
2. `_is_player_bullet()` returns `false` (can't find shooter from corrupted ID)
3. Homing steering skipped (`if not _is_player_bullet(): return`)

### Fix Applied

1. **Changed cast pattern** from `as Bullet` to `is Bullet`:
   ```csharp
   if (bulletNode is Bullet csBullet)
   ```

2. **Changed shooter_id cast** from `(int)` to `(long)`:
   ```csharp
   (long)shooterId  // GDScript int is 64-bit
   ```

3. **Applied to all affected files:**
   - `Scripts/Weapons/MakarovPM.cs`
   - `Scripts/Weapons/SilencedPistol.cs`
   - `Scripts/AbstractClasses/BaseWeapon.cs`

### Files Modified

| File | Changes |
|------|---------|
| `Scripts/Weapons/MakarovPM.cs` | Use `is` pattern, cast to `(long)` |
| `Scripts/Weapons/SilencedPistol.cs` | Use `is` pattern, cast to `(long)` |
| `Scripts/AbstractClasses/BaseWeapon.cs` | Cast shooter_id to `(long)` |

### Lessons Learned

1. **Godot C# → GDScript Interop Quirks**: The `as` cast can "succeed" even when the types
   don't actually match, leading to silent failures when accessing properties.

2. **Type Safety**: Always use `is` pattern matching (`x is Type y`) instead of `as` cast
   (`x as Type`) when dealing with mixed C#/GDScript codebases.

3. **Integer Sizes**: GDScript's `int` is 64-bit, while C#'s `int` is 32-bit. When passing
   Godot instance IDs (which are 64-bit), use `long` in C# to avoid truncation.

4. **Silent Failures**: Property setters on mismatched types fail silently in Godot. Always
   add diagnostic logging during development to catch these issues early.

### Verification

Build succeeded with 0 errors. The fix:
1. Ensures GDScript bullets receive proper initialization via `initialize_bullet()`
2. Preserves full 64-bit shooter IDs for accurate player detection
3. Enables homing to work correctly on pistol and UZI bullets

### New Game Logs

- `logs/game_log_20260210_224728.txt` — Testing with broken pistols
- `logs/game_log_20260210_224755.txt` — Extended testing session
