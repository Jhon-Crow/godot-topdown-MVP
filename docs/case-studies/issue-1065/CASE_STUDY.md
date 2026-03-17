# Case Study: Extended Magazine — Bugs for Shotgun, Revolver, and PM/MiniUzi

**Issue:** #1065 — Add Extended Magazine passive item
**PR:** #1066
**Date:** 2026-03-17
**Reporter:** Jhon-Crow
**Analyst:** konard (AI)

---

## 1. Summary of the Bug Report

After the initial implementation of the Extended Magazine passive item (PR #1066 commit `33a8cce9`), the owner reported:

> «не работает для ПМ, дробовика, револьвера (так же должен расширяться визуал барабана)»
> ("doesn't work for PM [Makarov], shotgun, revolver — also the visual drum should expand")

Game log provided: `game_log_20260317_213029.txt`
Difficulty used: Power Fantasy (value 3)
Active item selected: Extended Magazine

---

## 2. Evidence from the Game Log

### 2.1 Active item confirmed loaded
```
[21:30:29] [ActiveItemManager] Active item changed from None to Extended Magazine
```

### 2.2 AKGL — WORKING (Extended Magazine applied correctly)
```
[21:30:29] [Player.Weapon] Equipped AKGL (ammo: 75/30)
```
- WeaponData.MagazineSize = 30, CurrentAmmo = 75 = 30 × 2.5 ✅

### 2.3 MakarovPM — WORKING (magazine scaled correctly)
```
[21:30:58] [Player] Ready! Ammo: 22/9, ...
```
Log format: `CurrentAmmo / WeaponData.MagazineSize`
- WeaponData.MagazineSize = 9 (original, unscaled — always)
- CurrentAmmo = 22 ≈ 9 × 2.5 = 22.5 → rounds to 22 ✅
*Note: the `/9` denominator is misleading — it always shows the raw WeaponData value, not the scaled one.*

### 2.4 MiniUzi — WORKING
```
[21:31:52] [Player.Weapon] Equipped MiniUzi (ammo: 80/32)
```
- 80 = 32 × 2.5 ✅

### 2.5 Shotgun — BUG: tube capacity NOT scaled
```
[21:31:38] [Player.Weapon] Equipped Shotgun (ammo: 0/8)
```
`CurrentAmmo = 0` is expected (tube-loaded weapon, not magazine).
`ShellsInTube` is initialized to `TubeMagazineCapacity = 8`.
**Expected after extended magazine: 8 × 2.5 = 20 shells in tube.**
No `[Shotgun] Extended Magazine:` log line was ever emitted — confirming the code path was not reached.

### 2.6 Revolver — BUG: CylinderCapacity not updated, visual shows wrong count
The revolver was not selected in this game session.
Code analysis shows `CylinderCapacity => CylinderSize` (the original export property, default = 5).
In `InitializeMagazinesWithDifficulty`, the scaled `cylinderSize` is computed but stored only in a **local variable** — it is never written back to `CylinderSize`.
After `InitializeMagazinesWithDifficulty` returns, all callers of `CylinderCapacity` (including `_Ready()` which sizes `_chamberOccupied[]`) still see 5.

---

## 3. Root Cause Analysis

### Root Cause 1: Shotgun override ignores Extended Magazine

**File:** `Scripts/Weapons/Shotgun.cs`
**Method:** `InitializeMagazinesWithDifficulty()` (line 329)

The Shotgun has a custom override for `InitializeMagazinesWithDifficulty()` because its ammo model differs from other weapons: it uses a *tube* (shells loaded one by one) rather than a detachable magazine. The override correctly scales the reserve ammo for Power Fantasy difficulty, but it **does not contain any logic for the Extended Magazine passive item**.

Specifically:
- `TubeMagazineCapacity` (set to 8 in the scene) is never multiplied.
- `ShellsInTube = TubeMagazineCapacity` is set at the end, keeping the original value.
- Reserve ammo (`MaxReserveAmmo`) is also not scaled by the extended magazine multiplier.

### Root Cause 2: Revolver stores scaled cylinder size only in a local variable

**File:** `Scripts/Weapons/Revolver.cs`
**Method:** `InitializeMagazinesWithDifficulty()` (line 367)
**Property:** `CylinderCapacity => CylinderSize` (line 1218)

In the Revolver override, the scaled `newCylinderSize` (e.g., 5 × 2.5 = 13) is computed and passed to `MagazineInventory.Initialize(magazineCount, cylinderSize)`.
However, `CylinderSize` (the exported property) **remains at its original value of 5**.

All subsequent code uses `CylinderCapacity` (which is `CylinderSize`):
- `_Ready()` at line 310: `_chamberOccupied = new bool[cylinderCapacity]` — always 5 slots
- `CylinderCapacity` used in `Fire()`, `StartReload()`, `CartridgeInserted`, comparisons
- `RevolverCylinderUI` renders based on `CylinderCapacity` → always 5 chambers shown visually

The fix is to write back the scaled value to `CylinderSize` **before** `MagazineInventory.Initialize` is called, so all code that reads `CylinderCapacity` sees the correct (scaled) value.

### Why MakarovPM and MiniUzi work:
Both `MakarovPM` and `MiniUzi` do **not** override `InitializeMagazinesWithDifficulty`, so they use the base class `BaseWeapon.InitializeMagazinesWithDifficulty()` which correctly applies the extended magazine logic. The owner may have been confused by the log format showing the original `WeaponData.MagazineSize` in the denominator.

---

## 4. Timeline of Events

1. Issue #1065 opened: owner requests Extended Magazine passive item.
2. PR #1066 created with initial implementation.
3. Base weapons (AKGL, AssaultRifle, MiniUzi, SilencedPistol, SniperRifle) — covered by `BaseWeapon.InitializeMagazinesWithDifficulty()`.
4. Revolver — has its own override that applies the multiplier locally but **forgets to write back** to `CylinderSize`.
5. Shotgun — has its own override that **entirely omits** the Extended Magazine logic.
6. Owner tests the build, notices shotgun and revolver visual don't show expanded capacity.

---

## 5. Proposed Fixes

### Fix 1: Shotgun — add Extended Magazine block to override

In `Shotgun.InitializeMagazinesWithDifficulty()`, after applying the Power Fantasy multiplier to `maxReserve`, add the same extended magazine scaling block used in `BaseWeapon`:
- Scale `TubeMagazineCapacity` by `get_magazine_size_multiplier()`.
- Scale `maxReserve` by `get_total_ammo_multiplier()` (applying the 5% total ammo reduction).
- Set `ShellsInTube = TubeMagazineCapacity` (already done, will now use scaled value).

### Fix 2: Revolver — write scaled value back to CylinderSize

In `Revolver.InitializeMagazinesWithDifficulty()`, after computing `newCylinderSize`, assign `CylinderSize = newCylinderSize` **before** calling `MagazineInventory.Initialize`. This ensures all reads of `CylinderCapacity` (including `_Ready()`'s `_chamberOccupied` sizing) see the extended value.

---

## 6. Files Affected

| File | Change |
|------|--------|
| `Scripts/Weapons/Shotgun.cs` | Add Extended Magazine scaling to `InitializeMagazinesWithDifficulty` |
| `Scripts/Weapons/Revolver.cs` | Persist scaled `CylinderSize` in `InitializeMagazinesWithDifficulty` |

---

## 7. Artifacts

- `game_log_20260317_213029.txt` — game log provided by owner showing shotgun not scaling
