# Case Study: Issue #663 - Shotgun Doesn't Fire (except on Castle map)

## Summary

The shotgun weapon only fires on the Castle map. On all other maps (Building, Beach, Tutorial, TestTier), selecting and equipping the shotgun works correctly visually, but pressing the fire button does nothing.

## Timeline of Events

1. **Player selects shotgun** from the Armory menu during a level (e.g., Building Level).
2. **GameManager stores selection**: `[GameManager] Weapon selected: shotgun`
3. **Scene reloads** to apply weapon selection.
4. **C# Player._Ready()** runs `ApplySelectedWeaponFromGameManager()`:
   - Removes default MakarovPM
   - Instantiates Shotgun scene
   - Adds as child, sets `CurrentWeapon`
   - **Log: `Equipped Shotgun (ammo: 0/8)`** (ammo is 0!)
5. **GDScript level script** `_setup_selected_weapon()` runs:
   - Detects the shotgun is already equipped by C# Player
   - **Log: `Shotgun already equipped by C# Player - skipping GDScript weapon swap`**
   - Returns early without any ammo configuration
6. **Shotgun._Ready()** properly initializes `ShellsInTube = 8`
7. **Player tries to fire**: `CanFire` returns `false` because `CurrentAmmo == 0`
8. **Result**: Shotgun never fires.

### Why it works on Castle map

Castle level's `_setup_selected_weapon()` has special handling (line 1141):
```gdscript
# Still apply castle-specific ammo configuration
_configure_castle_weapon_ammo(existing_weapon)
```

This calls `ReinitializeMagazines(castle_magazines, true)` which fills the `MagazineInventory.CurrentMagazine` with ammo, making `CurrentAmmo > 0` and `CanFire` return `true`.

This is an **accidental fix** - the Castle level's 2x ammo bonus happens to fill the magazine inventory, which was the only thing making `CanFire` work.

## Root Cause Analysis

### The Architectural Mismatch

The Shotgun uses a **tube magazine system** (`ShellsInTube`), which is fundamentally different from the standard magazine system used by other weapons (pistols, rifles, SMGs).

**Standard weapons**: `CurrentAmmo` returns `MagazineInventory.CurrentMagazine.CurrentAmmo` - the actual number of rounds in the current magazine. This is the same value used for both display and firing logic.

**Shotgun**: The `MagazineInventory.CurrentMagazine` is repurposed as a **placeholder** (set to 0 at initialization in `Shotgun.cs:353`). The actual ammo is tracked in `ShellsInTube`. Reserve shells are stored in a spare magazine.

```
Standard weapon flow:
  CurrentAmmo (8/30) → CanFire (true) → Fire() → CurrentAmmo (7/30)

Shotgun flow:
  CurrentAmmo (always 0) → CanFire (FALSE) → Fire() never called!
  ShellsInTube (8/8) is the real ammo, but CanFire doesn't check it.
```

### The Code Path

1. `Player.cs:1181`: `shootInputActive = _semiAutoShootBuffered && CurrentWeapon.CanFire;`
2. `BaseWeapon.cs:80`: `CanFire => CurrentAmmo > 0 && !IsReloading && _fireTimer <= 0;`
3. `CurrentAmmo` returns 0 for Shotgun → `CanFire` returns `false`
4. `shootInputActive` is `false` → Player returns early, never calls `Shoot()` → `Fire()`

### Key Files Involved

| File | Role |
|------|------|
| `Scripts/AbstractClasses/BaseWeapon.cs:80` | Defines `CanFire` using `CurrentAmmo` |
| `Scripts/Weapons/Shotgun.cs:327-358` | `InitializeMagazinesWithDifficulty()` sets `CurrentMagazine.CurrentAmmo = 0` |
| `Scripts/Weapons/Shotgun.cs:408` | `ShellsInTube = TubeMagazineCapacity` (actual ammo) |
| `Scripts/Characters/Player.cs:1181` | Uses `CanFire` to gate firing input |
| `scripts/levels/castle_level.gd:1141` | Accidentally fixes by calling `_configure_castle_weapon_ammo` |
| `scripts/levels/building_level.gd:1362` | Returns early, no ammo config → bug manifests |

## Solution

### Fix Applied

1. **`BaseWeapon.cs`**: Made `CanFire` property `virtual` so subclasses can override it.
2. **`BaseWeapon.cs`**: Changed `_fireTimer` from `private` to `protected` so subclasses can access it.
3. **`Shotgun.cs`**: Added `override` of `CanFire` that checks `ShellsInTube > 0` along with shotgun-specific state (`ActionState`, `ReloadState`).

```csharp
// Shotgun.cs - new override
public override bool CanFire => ShellsInTube > 0 &&
                                 ActionState == ShotgunActionState.Ready &&
                                 ReloadState == ShotgunReloadState.NotReloading &&
                                 _fireTimer <= 0;
```

### Why This Fix is Correct

- Fixes the root cause rather than symptoms (no need to modify each level script)
- Works on all maps uniformly
- The shotgun's `Fire()` method already has its own checks for `ShellsInTube`, `ActionState`, and `ReloadState`, so the `CanFire` override mirrors those checks
- Does not affect other weapons (they still use the base `CanFire` implementation)
- The Castle level's `_configure_castle_weapon_ammo` continues to work as intended for its 2x ammo bonus

## Log Evidence

### Building Level (shotgun fails)
From `game_log_20260208_182826.txt`:
```
[18:28:30] [Player.Weapon] Equipped Shotgun (ammo: 0/8)
[18:28:30] [BuildingLevel] Shotgun already equipped by C# Player - skipping GDScript weapon swap
```

### Second session confirmation
From `game_log_20260208_181825.txt`:
```
[18:21:01] [Player.Weapon] Equipped Shotgun (ammo: 0/8)
[18:21:01] [BuildingLevel] Shotgun already equipped by C# Player - skipping GDScript weapon swap
```

Both logs confirm the shotgun is equipped with 0 ammo in CurrentAmmo (the MagazineInventory value), even though `ShellsInTube` is properly set to 8.
