# Case Study: Issue #468 - Uzi Muzzle Flash Size Reduction

## Overview

**Issue**: The Uzi (Mini UZI) muzzle flash should be 2x smaller than the M16's muzzle flash.
**Title** (Russian): "у узи должна быть вспышка в 2 раза меньше чем у m16"

## Timeline of Events

### Initial Implementation (2026-02-04)
- **Issue opened**: Request to reduce Uzi muzzle flash to 2x smaller than M16
- **First fix attempt**: Changed `effect_scale` in `caliber_9x19.tres` from `0.9` to `0.5`
- **Expected behavior**: 9x19mm caliber (used by Uzi and Silenced Pistol) would have 50% of M16's muzzle flash size

### User Feedback (2026-02-04 09:40)
User (Jhon-Crow) reported:
> "либо изменения не применились либо сделай ещё немного меньше" (either changes didn't apply or make it a bit smaller)

User attached game logs:
- `game_log_20260204_093651.txt` (52KB)
- `game_log_20260204_093709.txt` (800KB)

### Root Cause Analysis

#### The Problem: Caliber Data Not Passed to Muzzle Flash

The `effect_scale` change in `caliber_9x19.tres` was correct, but **the caliber data was never passed to the muzzle flash spawner**.

**Evidence from code analysis:**

1. **`spawn_muzzle_flash()` signature** (`scripts/autoload/impact_effects_manager.gd:334`):
   ```gdscript
   func spawn_muzzle_flash(position: Vector2, direction: Vector2, caliber_data: Resource = null) -> void:
   ```
   The `caliber_data` parameter is optional with default `null`.

2. **`SpawnMuzzleFlash()` in C# BaseWeapon** (`Scripts/AbstractClasses/BaseWeapon.cs:401-407`):
   ```csharp
   protected virtual void SpawnMuzzleFlash(Vector2 position, Vector2 direction)
   {
       var impactManager = GetNodeOrNull("/root/ImpactEffectsManager");
       if (impactManager != null && impactManager.HasMethod("spawn_muzzle_flash"))
       {
           impactManager.Call("spawn_muzzle_flash", position, direction);
           // ^^^ MISSING caliber parameter!
       }
   }
   ```
   The C# implementation only passed `position` and `direction`, but **NOT** the `caliber` data.

3. **`_get_effect_scale()` defaults to 1.0** (`scripts/autoload/impact_effects_manager.gd:368-374`):
   ```gdscript
   func _get_effect_scale(caliber_data: Resource) -> float:
       var effect_scale := DEFAULT_EFFECT_SCALE  # 1.0

       if caliber_data and "effect_scale" in caliber_data:
           effect_scale = caliber_data.effect_scale

       return clampf(effect_scale, MIN_EFFECT_SCALE, MAX_EFFECT_SCALE)
   ```
   Without caliber data, all weapons used `DEFAULT_EFFECT_SCALE = 1.0` regardless of their caliber's `effect_scale` setting.

4. **Casing ejection DID pass caliber data** (evidence it was possible):
   ```csharp
   // Line 393: Casing correctly uses caliber
   SpawnCasing(direction, WeaponData?.Caliber);
   ```
   The `SpawnCasing` method already receives and uses caliber data for appearance, proving the pattern was established but not applied to muzzle flash.

### Data Flow Diagram

```
Before Fix:
============
WeaponData.Caliber (9x19mm, effect_scale=0.5)
    |
    v
SpawnMuzzleFlash(position, direction)  <-- caliber NOT passed
    |
    v
spawn_muzzle_flash(pos, dir, null)
    |
    v
_get_effect_scale(null) -> 1.0 (DEFAULT)
    |
    v
Muzzle flash at full size (1.0x)


After Fix:
===========
WeaponData.Caliber (9x19mm, effect_scale=0.5)
    |
    v
SpawnMuzzleFlash(position, direction, WeaponData.Caliber)  <-- caliber PASSED
    |
    v
spawn_muzzle_flash(pos, dir, caliber_9x19)
    |
    v
_get_effect_scale(caliber_9x19) -> 0.5 (from effect_scale)
    |
    v
Muzzle flash at 50% size (0.5x) = 2x smaller than M16
```

## Solution

### Fix: Pass Caliber Data to Muzzle Flash

Modified `Scripts/AbstractClasses/BaseWeapon.cs`:

1. Updated `SpawnMuzzleFlash` method signature to accept caliber:
   ```csharp
   protected virtual void SpawnMuzzleFlash(Vector2 position, Vector2 direction, Resource? caliber)
   ```

2. Updated the method to pass caliber to GDScript:
   ```csharp
   impactManager.Call("spawn_muzzle_flash", position, direction, caliber);
   ```

3. Updated the call site in `SpawnBullet()`:
   ```csharp
   SpawnMuzzleFlash(spawnPosition, direction, WeaponData?.Caliber);
   ```

### Caliber Effect Scale Configuration

| Caliber | Weapon(s) | effect_scale | Result |
|---------|-----------|--------------|--------|
| 5.45x39mm | M16 (AssaultRifle) | 1.0 | Full size (reference) |
| 9x19mm | Mini UZI, Silenced Pistol | 0.5 | **2x smaller** than M16 |
| Buckshot | Shotgun | 1.2 | 20% larger than M16 |

## Files Modified

1. **`Scripts/AbstractClasses/BaseWeapon.cs`**
   - Added `caliber` parameter to `SpawnMuzzleFlash()` method
   - Pass `WeaponData?.Caliber` to `spawn_muzzle_flash()` call

2. **`resources/calibers/caliber_9x19.tres`** (already modified in first attempt)
   - `effect_scale = 0.5` (50% of M16's 1.0 = 2x smaller)

## Lessons Learned

1. **Always trace the data flow end-to-end**: The caliber's `effect_scale` was correctly set, but the data never reached the effect spawner. Tracing the call chain from weapon → spawner → effect revealed the disconnect.

2. **Check similar implementations for patterns**: The `SpawnCasing` method already used `caliber` correctly. This pattern should have been applied to `SpawnMuzzleFlash` as well.

3. **Optional parameters can hide bugs**: The `caliber_data` parameter defaulting to `null` made the code work without errors, but silently used wrong values. Consider logging when defaults are used.

4. **User testing is essential**: The user's feedback "changes didn't apply" was accurate. Without testing, the bug would have remained undetected since the code compiled and ran without errors.

## Related Issues

- **Issue #455**: Muzzle flash implementation (established the `effect_scale` system)
- This issue builds on #455's foundation by ensuring caliber-specific scaling is actually applied

## Game Logs Analysis

### Log 1: game_log_20260204_093651.txt
- User tested multiple weapons: M16, Shotgun, Silenced Pistol
- Scene reload when switching weapons via Armory menu
- No muzzle flash-specific logging (only sound propagation visible)

### Log 2: game_log_20260204_093709.txt
- User tested M16 vs Mini UZI specifically
- Line 253: `[GameManager] Weapon selected: mini_uzi`
- Line 397: `[Player] Detected weapon: Mini UZI (SMG pose)`
- Lines 399-464: Multiple `[SoundPropagation] Sound emitted: ... source=PLAYER (MiniUzi)` entries
- Confirms UZI was being used but muzzle flash appeared same size as M16

## References

- Original issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/468
- Related PR: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/474
- Case study #455 (muzzle flash implementation): `docs/case-studies/issue-455/case-study.md`
