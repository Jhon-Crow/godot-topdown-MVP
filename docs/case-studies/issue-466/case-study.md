# Case Study: Issue #466 - Silenced Pistol Missing Muzzle Flash

## Issue Description

The silenced pistol should have a very small muzzle flash (approximately 100x100 pixels), but no flash was appearing at all when firing the weapon.

**Original issue:** "у пистолета с глушителем должна быть очень маленькая вспышка (где то 100x100)"
(Translation: "The silenced pistol should have a very small flash (about 100x100)")

## Timeline of Events

### Initial Implementation (Prior Commits)
1. The `spawn_muzzle_flash` function in `ImpactEffectsManager` was updated to accept a `scale_override` parameter (line 337)
2. `MIN_EFFECT_SCALE` was lowered from 0.3 to 0.2 (line 25) to allow very small flashes
3. `SilencedPistol.cs` added a `SilencedMuzzleFlashScale` constant of 0.2 (line 89)
4. `SilencedPistol.cs` overrode the `SpawnMuzzleFlash` method to pass the small scale factor (lines 728-737)

### Bug Discovery (2026-02-04)
User @Jhon-Crow reported that the muzzle flash was not appearing for the silenced pistol, providing game logs for analysis.

## Root Cause Analysis

The root cause was identified by comparing the code flow between the base class and the derived class:

### BaseWeapon.cs Flow (Working):
```csharp
protected virtual void SpawnBullet(Vector2 direction)
{
    // ... bullet spawning code ...

    // Line 390: Muzzle flash IS called
    SpawnMuzzleFlash(spawnPosition, direction);

    // Line 393: Casing is spawned
    SpawnCasing(direction, WeaponData?.Caliber);
}
```

### SilencedPistol.cs Flow (Bug):
```csharp
protected override void SpawnBullet(Vector2 direction)
{
    // ... custom bullet spawning code with stun effect ...

    // Line 718: Casing is spawned
    SpawnCasing(direction, WeaponData?.Caliber);

    // BUG: SpawnMuzzleFlash is NEVER called!
}
```

The `SilencedPistol.SpawnBullet` method was overridden to add the stun effect on bullets, but during that override, the call to `SpawnMuzzleFlash` was accidentally omitted.

## Evidence from Logs

Analysis of the game logs (`game_log_20260204_092446.txt` and `game_log_20260204_092506.txt`) confirmed:
- The silenced pistol was correctly selected: `[INFO] [GameManager] Weapon selected: silenced_pistol`
- No muzzle flash spawn entries appeared when firing with the silenced pistol
- Other weapons would show muzzle flash effects

## Fix

The fix is simple: add the `SpawnMuzzleFlash` call in `SilencedPistol.SpawnBullet` after spawning the bullet and before spawning the casing:

```csharp
// Spawn muzzle flash with small scale for silenced weapon
SpawnMuzzleFlash(spawnPosition, direction);

// Spawn casing if casing scene is set
SpawnCasing(direction, WeaponData?.Caliber);
```

Since `SilencedPistol` already has an overridden `SpawnMuzzleFlash` method that passes the correct small scale (0.2), the muzzle flash will now appear at the correct size.

## Lessons Learned

1. **Override completeness**: When overriding virtual methods that perform multiple operations, ensure all necessary operations from the base class are either called via `base.Method()` or replicated in the override.

2. **Test visual effects separately**: Visual effects like muzzle flash should be tested independently when making weapon changes, not just assumed to work.

3. **Code review patterns**: When reviewing overrides of virtual methods, compare the override against the base implementation to ensure no functionality is accidentally omitted.

## Files Changed

- `Scripts/Weapons/SilencedPistol.cs`: Added call to `SpawnMuzzleFlash` in `SpawnBullet` method

## Related Files (Reference)

- `Scripts/AbstractClasses/BaseWeapon.cs`: Base class with `SpawnBullet` method (lines 318-394)
- `scripts/autoload/impact_effects_manager.gd`: Contains `spawn_muzzle_flash` function (lines 330-369)
- `scripts/effects/muzzle_flash.gd`: Muzzle flash effect implementation
