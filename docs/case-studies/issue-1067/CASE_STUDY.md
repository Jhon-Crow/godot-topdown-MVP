# Case Study: Issue #1067 — Auto-Reload Passive Item Bugs

## Overview

Issue #1067 requested a passive item "auto-reload" (автоперезарядка) with these mechanics:
- Magazine capacity is reduced 2.1×
- On each enemy kill, the current magazine is refilled from reserve ammo

After the initial implementation (PR #1068), the repository owner (Jhon-Crow) reported two rounds of bugs via game logs. This case study analyzes the root causes and documents the fixes.

---

## Timeline / Sequence of Events

| Date | Event |
|------|-------|
| 2026-03-16 | PR #1068 opened: initial implementation |
| 2026-03-17 08:07 | Owner reports 4 bugs (comment 4073091505) |
| 2026-03-17 08:12 | AI work session started, second attempt begins |
| 2026-03-17 08:51 | Owner reports 4 more bugs (comment 4073311634) with 2 game logs |
| 2026-03-17 ~09:00 | Third AI work session begins (current) |

---

## Bug Reports

### Round 1 (comment 4073091505) + attached log: `game_log_20260317_110315.txt`

1. Item consumes ammo when triggered — should be a pure transfer
2. After first trigger, magazine size becomes normal size
3. Item doesn't work for revolver — should reduce cylinder and refill on kill
4. Should work so that killing every shot means no manual reload needed

### Round 2 (comment 4073311634) + logs: `game_log_20260317_114944.txt`, `game_log_20260317_115432.txt`

1. Cylinder display conflicts: shows charge display instead of 2-slot cylinder
2. Cylinder not reloading despite counter showing 2 charges available
3. Total ammo count is reduced (becomes unpassable) — should be the same total
4. Item has no effect on m16, uzi, AK, shotgun, PM

---

## Root Cause Analysis

### Root Cause A: Level GDScript Overwrites `ReinitializeMagazines` Call

**Symptoms**: Bug #4 from round 2 (item has no effect on most weapons), Bug #2 round 1 (magazine becomes normal size)

**Evidence from `game_log_20260317_115432.txt`**:
```
[11:54:44] [Player.AutoReload] Reducing magazine size: 30 -> 14
[11:54:44] [Player] Ready! Ammo: 14/30         ← CORRECT after Player._Ready()
[11:54:44] [BuildingLevel] AssaultRifle equipped - applying building-level ammo config
                                                ← BuildingLevel._Ready() runs AFTER
[11:54:47] [Player.AutoReload] Kill — magazine already full  ← 30 rounds = "full"!
```

**Root cause**: In Godot 4, `_Ready()` runs children before parents. Execution order:
1. `Player._Ready()` → `InitAutoReload()` → `ReduceMagazineSizeForAutoReload()` → reduced to 14
2. Level GDScript `_Ready()` runs AFTER → `_apply_building_ammo_config()` → `ReinitializeMagazines(2, true)` → resets to full 30×2

The `ReinitializeMagazines(count)` overload (no size parameter) uses `WeaponData.MagazineSize` which is the **original unreduced** size (30). This undoes the reduction.

**Affected weapons**: All weapons on BuildingLevel and LabyrinthLevel (m16, AK+GL, UZI, MakarovPM).
**Revolver was working** because LabyrinthLevel doesn't call `ReinitializeMagazines` for the revolver.

**Fix**: Add `ApplyAutoReloadAfterLevelAmmoConfig()` public method to `Player.cs`. Call it from all level scripts after each `ReinitializeMagazines` call. This re-runs the reduction with the correct new magazine count.

---

### Root Cause B: Total Ammo Reduced (Gameplay Becomes Unpassable)

**Symptoms**: Bug #3 round 2 (total ammo count is less with the item than without)

**Evidence**: With M16, original: 4 magazines × 30 = 120 bullets. After reduction: 4 magazines × 14 = 56 bullets. Player lost 64 bullets (53% of their ammo).

**Root cause**: `ReinitializeMagazines(StartingMagazineCount, reducedSize)` kept the **same number of magazines** (4) but made each magazine smaller. This dramatically reduced total ammo.

**Intended mechanic**: The magazine holds fewer bullets, but the player should have the same total bullet count — just spread across more magazines.

**Fix**: Calculate the new magazine count to preserve total bullets:
```csharp
int totalBullets = currentMagazineCount * originalSize;
int newMagazineCount = Math.Max(1, (int)Math.Ceiling((double)totalBullets / reducedSize));
```
Example: M16 → `ceil(120 / 14) = 9` magazines of 14 = 126 bullets (≥ 120 ✓)

---

### Root Cause C: Revolver `_chamberOccupied` Not Rebuilt After Size Change

**Symptoms**: Bug #1 round 2 (cylinder shows wrong number of slots), Bug #2 round 2 (cylinder not loading)

**Evidence**: Setting `CurrentWeapon.Set("CylinderSize", reducedSize)` only changes the property value. The `_chamberOccupied` array (initialized in `_Ready()` with `new bool[cylinderCapacity]`) was still `bool[5]`. All cylinder UI logic reads `_chamberOccupied.Length` which remained 5.

**Root cause**: `CylinderSize` is an `[Export]` property. Setting it via `Set()` updates the field but does NOT call `_Ready()` again or rebuild `_chamberOccupied`. The array mismatch caused:
- Cylinder HUD showing 5 slots (old size) but ammo counter showing 2 (reduced)
- On cylinder open, `_chamberOccupied.Length != cylinderCapacity` check at line 1259 was false (both were 5 before fix) — wait, both are 5 initially, but after CylinderSize=2 the check `_chamberOccupied.Length != CylinderCapacity` correctly triggers... but CylinderCapacity returns CylinderSize=2 while array is 5.

Actually the check AT LINE 1259 (`if (_chamberOccupied.Length != cylinderCapacity)`) would catch this — but only when the cylinder is **opened**. Before opening, the cylinder HUD reads `GetChamberStates()` which returns the stale 5-element array.

**Fix**: Add `ReinitializeCylinder()` public method to `Revolver.cs` that rebuilds `_chamberOccupied` with `new bool[CylinderSize]`, marks first `CurrentAmmo` chambers as occupied, and emits `CylinderStateChanged`.

---

### Root Cause D: `CurrentAmmo` Setter Doesn't Update Revolver `_chamberOccupied`

**Symptoms**: Bug #2 round 2 (cylinder not reloading on kill despite counter showing it should)

**Root cause**: In `OnEnemyKilledForAutoReload()`:
```csharp
CurrentWeapon.CurrentAmmo = currentAmmo + toAdd;  // sets MagazineInventory.CurrentMagazine.CurrentAmmo
```
For a regular weapon this is sufficient. But for the revolver, `_chamberOccupied[]` tracks per-chamber state and is the source of truth for the cylinder HUD (via `GetChamberStates()`). Setting `CurrentAmmo` only updates the magazine data, not the chamber tracking array.

Result: `CurrentAmmo` = 2 but `_chamberOccupied = [false, false]` — cylinder HUD shows empty.

**Fix**: After setting `CurrentAmmo`, call `ReinitializeCylinder()` which rebuilds `_chamberOccupied` from the current `CurrentAmmo` value, then emit `CylinderStateChanged`.

---

## Summary of Fixes

| Bug | File | Fix |
|-----|------|-----|
| Item has no effect on m16/uzi/AK/shotgun/PM | `Player.cs`, all level `.gd` files | Add `ApplyAutoReloadAfterLevelAmmoConfig()`, call from level scripts |
| Total ammo is reduced | `Player.cs` | Calculate `newMagazineCount = ceil(totalBullets / reducedSize)` |
| Cylinder shows wrong slot count | `Revolver.cs` | Add `ReinitializeCylinder()`, call after `CylinderSize` change |
| Cylinder not reloading on kill | `Player.cs` | Call `ReinitializeCylinder()` in `OnEnemyKilledForAutoReload` |

---

## Files Modified

- `Scripts/Characters/Player.cs` — main fix: `ApplyAutoReloadAfterLevelAmmoConfig()`, ammo preservation formula, `ReinitializeCylinder` calls
- `Scripts/Weapons/Revolver.cs` — added `ReinitializeCylinder()` method
- `scripts/levels/building_level.gd` — call `ApplyAutoReloadAfterLevelAmmoConfig()` after ammo config
- `scripts/levels/labyrinth_level.gd` — same
- `scripts/levels/docks_level.gd` — same
- `scripts/levels/beach_level.gd` — same
- `scripts/levels/castle_level.gd` — same
- `scripts/levels/decadence_level.gd` — same
- `scripts/levels/test_tier.gd` — same
- `tests/unit/test_auto_reload.gd` — new tests for total ammo preservation and kill-per-shot mechanic

---

## Verification

The core mechanic is verified by `test_kill_per_shot_means_no_manual_reload`:
- Magazine size = 2 (revolver, reduced from 5)
- Reserve = 8 bullets (10 total)
- Player fires 1 shot, kills 1 enemy, magazine refills to 2
- After 10 such cycles: 0 manual reloads needed ✓

Game logs (after fix) should show:
```
[Player.AutoReload] Reducing magazine size: 30 -> 14, magazines: 4 -> 9 (total bullets: 120)
[Player.AutoReload] Re-applying magazine size reduction after level ammo config
```
