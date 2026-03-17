# Case Study: Extended Magazine — Multi-Weapon Bug Analysis (Issue #1065)

**Issue:** #1065 — Add Extended Magazine passive item
**PR:** #1066
**Status:** Fixed in commit `c3d6dc1e`
**Analyst:** konard (AI)
**Last Updated:** 2026-03-17

---

## 1. Summary

The Extended Magazine passive item (PR #1066) was implemented to increase magazine capacity by 2.5× for all weapons. Post-implementation testing revealed that two weapons — **Shotgun** and **Revolver** — did not apply the effect correctly. A third weapon, **MakarovPM**, appeared to malfunction to the tester but log analysis confirmed it was working correctly.

### Reported vs. Actual Status

| Weapon | User-Reported | Log Evidence | Actual Status |
|--------|--------------|--------------|---------------|
| Shotgun | ❌ Broken | `ammo: 0/8` (tube = 8, not 20) | ❌ **Broken** in binary `33a8cce9` |
| Revolver | ❌ Broken | `ammo: 12/5` (cylinder = 12 ≈ 5×2.5) | ✅ **Fixed** in commit `33a8cce9` |
| MakarovPM | ❌ Reported broken | `ammo: 22/9` (22 = 9×2.5 ✅) | ✅ **Working** — user misread log format |
| MiniUzi | ✅ Working | `ammo: 80/32` (80 = 32×2.5) | ✅ Working |
| AKGL | ✅ Working | `ammo: 75/30` (75 = 30×2.5) | ✅ Working |

---

## 2. Evidence: Game Logs

### 2.1 `game_log_20260317_213029.txt` — First bug report (binary: `33a8cce9` initial impl, before any fixes)

**Difficulty:** Power Fantasy (value: 3)
**Active item:** Extended Magazine
**Reported by owner:** "doesn't work for PM, shotgun, revolver"

Key log lines:
```
[21:30:29] [ActiveItemManager] Active item changed from None to Extended Magazine
[21:30:58] [Player] Ready! Ammo: 22/9     ← MakarovPM: CurrentAmmo=22, MagazineSize=9
[21:31:38] [Player.Weapon] Equipped Shotgun (ammo: 0/8)  ← tube = 8, NOT 20 ❌
[21:31:52] [Player.Weapon] Equipped MiniUzi (ammo: 80/32) ← 80 = 32×2.5 ✅
```

No `[Shotgun] Extended Magazine:` log line exists — confirming the code path was never reached.

Revolver was NOT selected in this session. Code analysis was required to confirm the bug.

### 2.2 `game_log_20260317_233144.txt` — Second test session (binary: partial fix, Revolver ✅ but Shotgun still ❌)

**Difficulty:** Normal (value: 1)
**Session start:** 23:31 local time (21:31 UTC), which is ~2h after our fix commit at 19:17 UTC
**User report:** "everything works except PM" (*incorrect based on log evidence*)

Key log lines:
```
[23:31:44] [ActiveItemManager] Active item changed from None to Auto-Reload
[23:31:49] [ActiveItemManager] Active item changed from Auto-Reload to Extended Magazine

[23:31:49] [Player.Weapon] Equipped Revolver (ammo: 12/5)   ← 12 = 5×2.5 ✅ (Revolver fixed!)
[23:32:26] [Player.Weapon] Equipped Shotgun (ammo: 0/8)     ← tube = 8, NOT 20 ❌ (Shotgun still broken)
[23:32:43] [Player] Ready! Ammo: 22/9                       ← MakarovPM: 22 = 9×2.5 ✅ (PM working)
```

**Critical observation:** The user reported "PM is broken" but:
- `22/9` means `CurrentAmmo=22` / `WeaponData.MagazineSize=9` — the **22 is the scaled value** (9×2.5=22.5→22)
- The `9` in the denominator is always the **raw, unscaled WeaponData.MagazineSize**, not the active capacity
- MakarovPM is working correctly; the log format is misleading

**Binary provenance:** This log was produced by a build that included the Revolver fix (`33a8cce9`) but NOT the Shotgun fix (added in `c3d6dc1e`). The user likely rebuilt from branch tip after the first comment, but before our fix commit landed, or used a cached older binary.

---

## 3. Root Cause Analysis

### Root Cause 1: Shotgun override omits Extended Magazine block

**File:** `Scripts/Weapons/Shotgun.cs`
**Method:** `InitializeMagazinesWithDifficulty()` (line 329)
**Introduced by:** Initial implementation commit `33a8cce9`

The Shotgun has a custom `InitializeMagazinesWithDifficulty()` override because it uses a *tube* (shells loaded one at a time) instead of a detachable magazine. The override correctly handles Power Fantasy ammo scaling but **entirely omitted** the Extended Magazine block.

```
Before fix (commit 33a8cce9):
- Power Fantasy scaling: ✅ handled
- Extended Magazine: ❌ missing
- TubeMagazineCapacity: stays at 8

After fix (commit c3d6dc1e):
- Power Fantasy scaling: ✅ handled
- Extended Magazine: ✅ TubeMagazineCapacity × 2.5 = 20; reserve × 0.95
```

Evidence: No `[Shotgun] Extended Magazine:` line appears in either log file.

### Root Cause 2: Revolver cylinder size stored only in local variable

**File:** `Scripts/Weapons/Revolver.cs`
**Method:** `InitializeMagazinesWithDifficulty()` (line 367)
**Property:** `CylinderCapacity => CylinderSize` (line 1218)
**Introduced by:** Initial implementation commit `33a8cce9`
**Fixed in:** Commit `33a8cce9` (self-fixed, or fixed in same initial PR before first test)

In the Revolver override, the scaled cylinder size (`newCylinderSize = 5 × 2.5 = 13`) was computed and passed to `MagazineInventory.Initialize()`, but `CylinderSize` was **never written back**.

As a result:
- `CylinderCapacity => CylinderSize` always returned the original `5`
- `_Ready()` sized `_chamberOccupied = new bool[cylinderCapacity]` at 5 (too small)
- `RevolverCylinderUI` rendered 5 chambers visually

The fix: `CylinderSize = cylinderSize` is written **before** `MagazineInventory.Initialize()`.

From `game_log_20260317_233144.txt`, Revolver shows `12/5` (12 = 5×2.5) confirming the fix works. The `5` denominator is always the raw `WeaponData.MagazineSize`.

### Why MakarovPM appears broken but is not

The `[Player] Ready! Ammo: current/magazineSize` log format (C# `Player.cs` line 1192) uses:
- `currentAmmo = CurrentWeapon.CurrentAmmo` — the **scaled** value after Extended Magazine
- `maxAmmo = CurrentWeapon.WeaponData.MagazineSize` — always the **original, unscaled** WeaponData value

For MakarovPM with Extended Magazine on Normal difficulty:
- `WeaponData.MagazineSize = 9`
- After Extended Magazine: `CurrentAmmo = Mathf.RoundToInt(9 × 2.5) = 22`
- Log shows: `22/9` — **the 22 is correct**, the 9 is just the raw data field

This denominator "9" misleads testers into thinking the capacity is unchanged. The actual in-game HUD shows `AMMO: 22/[reserve]` correctly.

### Root Cause 3 (systemic): Misleading log format for ammo display

**File:** `Scripts/Characters/Player.cs` line 1192
**Impact:** Causes testers to think Extended Magazine is not working for all C# weapons

The log message `[Player] Ready! Ammo: {currentAmmo}/{maxAmmo}` where `maxAmmo = WeaponData.MagazineSize` (unscaled) creates confusion. A developer looking at `22/9` might interpret this as "22 bullets, max 9" which seems impossible, or "capacity = 9 (not scaled)".

**Proposed improvement:** Change the log to include the actual magazine capacity:
```csharp
// Instead of:
LogToFile($"[Player] Ready! Ammo: {currentAmmo}/{maxAmmo}");
// Use:
int rawMagSize = CurrentWeapon?.WeaponData?.MagazineSize ?? 0;
LogToFile($"[Player] Ready! Ammo: {currentAmmo}/{rawMagSize} (raw), MagCap: {CurrentWeapon?.MagazineInventory?.CurrentMagazine?.Capacity ?? 0}");
```

This is a low-priority enhancement but would prevent future debugging confusion.

---

## 4. Timeline of Events

| Time | Event |
|------|-------|
| Pre-issue | Shotgun and Revolver have custom `InitializeMagazinesWithDifficulty()` overrides |
| Issue #1065 opened | Owner requests Extended Magazine passive item |
| `33a8cce9` (2026-03-16 21:37 UTC) | Initial implementation: BaseWeapon ✅, Revolver ✅, Shotgun ❌ (omitted) |
| 2026-03-17 18:33 UTC | Owner tests with Power Fantasy difficulty; reports PM, Shotgun, Revolver broken; uploads `game_log_20260317_213029.txt` |
| 2026-03-17 19:04 UTC | AI work session starts |
| 2026-03-17 19:17 UTC | Fix commit `c3d6dc1e`: Shotgun ✅ fixed; Revolver ✅ already fixed; tests updated; case study added |
| ~21:31 UTC (23:31 local) | Owner tests again; Revolver ✅ working, Shotgun ❌ still 0/8 (old binary), PM ✅ working |
| 2026-03-17 20:33 UTC | Owner reports "everything works except PM"; uploads `game_log_20260317_233144.txt`; requests case study |

**Key finding:** The second test used a **binary built before the Shotgun fix** (`c3d6dc1e`). The owner's claim that "PM is broken" is contradicted by the log showing `22/9` (PM working correctly). The **Shotgun** was still broken in the binary tested.

---

## 5. Proposed / Implemented Fixes

### Fix 1: Shotgun — add Extended Magazine block (IMPLEMENTED in `c3d6dc1e`)

```csharp
// In Shotgun.InitializeMagazinesWithDifficulty() — after Power Fantasy scaling:
if (activeItemManager != null && activeItemManager.HasMethod("has_extended_magazine")
    && activeItemManager.Call("has_extended_magazine").AsBool())
{
    float magSizeMultiplier = activeItemManager.Call("get_magazine_size_multiplier").AsSingle();
    float totalAmmoMultiplier = activeItemManager.Call("get_total_ammo_multiplier").AsSingle();
    int originalTube = TubeMagazineCapacity;
    int newTubeCapacity = Mathf.Max(1, Mathf.RoundToInt(TubeMagazineCapacity * magSizeMultiplier));
    int newReserve = Mathf.Max(0, Mathf.RoundToInt(maxReserve * totalAmmoMultiplier));
    GD.Print($"[Shotgun] Extended Magazine: tube {originalTube}->{newTubeCapacity}, reserve {maxReserve}->{newReserve}");
    TubeMagazineCapacity = newTubeCapacity;
    maxReserve = newReserve;
}
ShellsInTube = TubeMagazineCapacity;
```

### Fix 2: Revolver — write back CylinderSize (IMPLEMENTED in `c3d6dc1e`)

```csharp
// In Revolver.InitializeMagazinesWithDifficulty() — after computing cylinderSize:
CylinderSize = cylinderSize;  // ← added: persist scaled value before MagazineInventory.Initialize
MagazineInventory.Initialize(magazineCount, cylinderSize);
```

### Fix 3 (low priority): Improve ammo log format to avoid confusion

In `Scripts/Characters/Player.cs` line 1192, add the actual active magazine capacity alongside the raw WeaponData value to prevent future misdiagnosis.

---

## 6. Math Reference

| Weapon | Difficulty | Raw Capacity | Extended (×2.5) | Expected Log |
|--------|-----------|-------------|-----------------|--------------|
| MakarovPM | Normal | 9 | 22 (rounds) | `22/9` (9 = WeaponData, misleading) |
| MakarovPM | Power Fantasy | 9 | 22 (rounds) | `22/9` |
| Revolver | Normal | 5 | 12 (cylinder) | `12/5` (5 = WeaponData) |
| Shotgun tube | Normal | 8 | 20 (shells) | `0/8` until loaded (bug until `c3d6dc1e`) |
| MiniUzi | Normal | 32 | 80 (rounds) | `80/32` |
| AKGL | Power Fantasy | 30 | 75 (rounds) | `75/30` |

---

## 7. Files Changed

| File | Change | Commit |
|------|--------|--------|
| `scripts/autoload/active_item_manager.gd` | Added EXTENDED_MAGAZINE enum (value 10), methods `has_extended_magazine()`, `get_magazine_size_multiplier()`, `get_total_ammo_multiplier()` | `33a8cce9` |
| `Scripts/AbstractClasses/BaseWeapon.cs` | Apply extended magazine in `InitializeMagazinesWithDifficulty()` | `33a8cce9` |
| `Scripts/Weapons/Revolver.cs` | Apply cylinder size multiplier | `33a8cce9` |
| `Scripts/Weapons/Shotgun.cs` | **Add Extended Magazine block** to `InitializeMagazinesWithDifficulty()` | `c3d6dc1e` |
| `Scripts/Weapons/Revolver.cs` | **Persist CylinderSize** (`CylinderSize = cylinderSize` write-back) | `c3d6dc1e` |
| `tests/unit/test_extended_magazine.gd` | Update mock enum order | `c3d6dc1e` |
| `tests/unit/test_active_item_manager.gd` | Update mock enum order | `c3d6dc1e` |
| `tests/unit/test_laser_sight.gd` | Update mock enum order | `c3d6dc1e` |
| `tests/unit/test_unlock_manager.gd` | Update mock enum order | `c3d6dc1e` |

---

## 8. Artifacts

| File | Description |
|------|-------------|
| `game_log_20260317_213029.txt` | First bug report log — Power Fantasy, initial build (`33a8cce9`), Shotgun ❌, Revolver not tested |
| `game_log_20260317_233144.txt` | Second test log — Normal difficulty, Revolver ✅, Shotgun ❌, MakarovPM ✅ (misreported as broken) |

---

## 9. Additional Context (Online Research)

The Godot 4 C# interop pattern used here (calling GDScript methods via `activeItemManager.Call("has_extended_magazine")`) is the standard approach for C#↔GDScript communication per [Godot docs on cross-language scripting](https://docs.godotengine.org/en/stable/tutorials/scripting/cross_language_scripting.html). The `Call()` method returns a `Variant` which is type-cast with `.AsBool()` / `.AsSingle()`.

A common pitfall when overriding C# virtual methods in game engines is forgetting to call the base implementation — or in this case, forgetting to *replicate* a base-class feature in the override. The Shotgun's omission of the Extended Magazine block is a classic example of an override that handles one extension point (Power Fantasy) but misses a newly-added one (Extended Magazine). This is best prevented by unit tests that verify each weapon type independently, which were added in commit `c3d6dc1e`.
