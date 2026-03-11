# Case Study: Issue #950 - Revolver Shows 30 Bullets After Weapon Switch

## Problem Statement

**Title (Russian):** fix при переключении оружия не изменилось количество патронов
**Translation:** fix: when switching weapons from m16 to revolver, the ammo count did not change (revolver loaded with 30 bullets)

**Reporter:** Jhon-Crow
**Severity:** High (incorrect gameplay — player thinks they have full M16 ammo when they actually have a revolver with 5-round cylinder)

---

## Timeline / Sequence of Events

Based on game log `game_log_20260302_185913.txt` (captured 2026-03-02 18:59:13, release build):

| Time     | Event |
|----------|-------|
| 18:59:13 | Game starts, LabyrinthLevel loads with M16 (AssaultRifle) selected |
| 18:59:13 | `[Player.Weapon] Equipped AssaultRifle (ammo: 30/30)` — correct |
| 18:59:13 | PersistManager navigates to BuildingLevel (last played level) |
| 18:59:14 | BuildingLevel loads with M16 — `Equipped AssaultRifle (ammo: 30/30)` — correct |
| 18:59:16 | Player opens Armory (pause menu) |
| 18:59:18 | `[GameManager] Weapon selected: revolver` — player switches weapon |
| 18:59:18 | BuildingLevel reloads with Revolver |
| 18:59:18 | **BUG:** `[Player.Weapon] Equipped Revolver (ammo: 30/30)` — should be 5/15 |
| 18:59:18 | `[Player] Ready! Ammo: 30/30` — C# Player confirms wrong value |
| 18:59:18 | `[ReplayManager] Detected player weapon: Assault Rifle (default)` — secondary bug |
| 18:59:19 | `[Player] Detected weapon: RSh-12 Revolver (Pistol pose)` — weapon correctly identified later |
| 18:59:22 | Scene reloads again with Revolver — bug repeats: `30/30` |

---

## Root Cause Analysis

### Primary Bug: Wrong Magazine Size During Initialization

The revolver is initialized with `CurrentAmmo = 30` and `WeaponData.MagazineSize = 30` instead of the correct values (`CurrentAmmo = 5`, `WeaponData.MagazineSize = 5`).

**Initialization Chain:**
1. `Player.ApplySelectedWeaponFromGameManager()` (Player.cs:2608)
   - Calls `GD.Load<PackedScene>("res://scenes/weapons/csharp/Revolver.tscn")`
   - Calls `weaponScene.Instantiate<BaseWeapon>()`
   - Calls `AddChild(weapon)` → triggers `Revolver._Ready()` synchronously
2. `Revolver._Ready()` calls `base._Ready()` (BaseWeapon.cs:150)
3. `BaseWeapon._Ready()` calls `InitializeMagazinesWithDifficulty()` (BaseWeapon.cs:179)
4. `InitializeMagazinesWithDifficulty()` calls `MagazineInventory.Initialize(4, WeaponData.MagazineSize)` (BaseWeapon.cs:220)
5. If `WeaponData.MagazineSize = 30` (wrong), the revolver gets 30-bullet "magazines" instead of 5-round cylinders

**Expected vs Actual:**
- `RevolverData.tres`: `MagazineSize = 5`
- `WeaponData.cs` default: `MagazineSize = 30`
- Actual runtime value: **30** (using C# class default, not .tres value)

**Why is WeaponData.MagazineSize = 30 for the Revolver?**

The most likely cause is a **Godot 4.3 C# `[GlobalClass]` resource deserialization issue in release builds**. When `GD.Load<PackedScene>()` loads the weapon scene and `Instantiate()` creates the weapon instance, the `WeaponData` resource (RevolverData.tres) may not have its C# properties properly set from the .tres file in the compiled release binary. Instead, the C# class default values are used (MagazineSize=30 from WeaponData.cs line 34).

Evidence:
- AssaultRifle also shows 30/30, but this is COINCIDENTALLY CORRECT because AssaultRifleData.tres also has `MagazineSize = 30` (same as C# default)
- If resource deserialization were working correctly for AssaultRifle, it could also be working correctly and we can't distinguish - but for Revolver the bug is visible since expected MagazineSize=5 differs from default 30

**Contributing Factor - WeaponData.cs Default:**
```csharp
// WeaponData.cs line 34
public int MagazineSize { get; set; } = 30;  // Default equals AssaultRifle size
```
The default value of 30 was chosen because the AssaultRifle was the first weapon. This made the bug invisible for AssaultRifle but visible for all other weapons.

### Secondary Bug: ReplayManager Doesn't Detect Revolver

`ReplayManager.DetectPlayerWeapon()` (ReplayManager.cs:1420) checks for MiniUzi, Shotgun, SniperRifle, SilencedPistol, then falls through to "Assault Rifle (default)" for everything else — including Revolver, AKGL, and MakarovPM.

Log evidence (line 506): `[ReplayManager] Detected player weapon: Assault Rifle (default)` when Revolver was equipped.

### Tertiary Issue: GDScript `.get()` on Non-Exported C# Properties

In `building_level.gd:573`:
```gdscript
if weapon.get("CurrentAmmo") != null and weapon.get("ReserveAmmo") != null:
    _update_ammo_label_magazine(weapon.CurrentAmmo, weapon.ReserveAmmo)
```

`CurrentAmmo` and `ReserveAmmo` in `BaseWeapon.cs` are public properties but NOT `[Export]`-annotated. In Godot 4, `Node.get("PropertyName")` only works for `[Export]`-annotated properties (or built-in engine properties). Without `[Export]`, `.get()` returns null.

If this check fails, `_update_ammo_label_magazine` is never called for the initial display, and the ammo label shows empty text (or stale value if the label persists somehow).

However, since the Player.cs log shows `CurrentAmmo = 30` at the time of logging (which happens AFTER `_Ready()`), the primary bug is the wrong initialization, not just a display issue.

---

## Fix Strategy

### Fix 1 (Primary): Override Revolver Cylinder Initialization

Add a dedicated `[Export] public int CylinderSize` property to `Revolver.cs` that:
1. Is explicitly set in `Revolver.tscn` (so it uses Godot's property system directly)
2. Overrides `InitializeMagazinesWithDifficulty()` to use `CylinderSize` instead of `WeaponData.MagazineSize`

This bypasses the WeaponData resource loading issue entirely for the cylinder capacity.

### Fix 2 (Secondary): Add [Export] to CurrentAmmo/ReserveAmmo in BaseWeapon

Add `[Export]` annotation to `CurrentAmmo` and `ReserveAmmo` properties so that GDScript `.get()` calls work correctly for the ammo display initialization.

Note: These properties have `protected set`, so `[Export]` would make them read-only exposed properties.

### Fix 3 (Tertiary): Fix ReplayManager Weapon Detection

Add detection cases for Revolver, AKGL, and MakarovPM in `ReplayManager.DetectPlayerWeapon()`.

---

## Files Affected

- `Scripts/Weapons/Revolver.cs` — override `InitializeMagazinesWithDifficulty()`, add `CylinderSize` property
- `scenes/weapons/csharp/Revolver.tscn` — set `CylinderSize = 5`
- `Scripts/AbstractClasses/BaseWeapon.cs` — add `[Export]` to `CurrentAmmo` and `ReserveAmmo`
- `Scripts/Autoload/ReplayManager.cs` — add Revolver/AKGL/MakarovPM detection

---

## Related Issues / PRs

- Issue #865: Missing Revolver ammo counter lookup (fixed in PR via commit 039cfc99)
- Issue #716: Empty drum fix for Revolver
- Issue #619: Original Revolver implementation (PR #620)
