# Issue #949: Fix Ammunition Counts

## Summary
Fix ammunition counts for M16/AK on Building map (Hard difficulty) and silenced pistol on City map.

## Issue Description
1. **M16/AK on Building map (Hard difficulty)**: Currently 30+90 ammo, should be 30+30
2. **Silenced pistol on City map**: Currently 13+39 (52 total), should match enemy count on all maps

## Root Cause Analysis

### Issue 1: AK+GL on Building Map
**File**: `scripts/levels/building_level.gd`
**Location**: `_setup_selected_weapon()` function around line 1545-1567

**Problem**: The M16 weapon code includes `ReinitializeMagazines(2, true)` to reduce ammo from 4 magazines (30+90) to 2 magazines (30+30), but the AK+GL weapon setup code was missing this initialization.

**Evidence**:
- M16 code (lines 1529-1540): Has `base_magazines = 2` and calls `ReinitializeMagazines()`
- AK+GL code (lines 1545-1567): Only adds the weapon and equips it, no magazine reinitialization

**Fix**: Added similar magazine reinitialization code for AK+GL that:
- Sets `base_magazines = 2`
- Checks for Power Fantasy mode multiplier
- Calls `ReinitializeMagazines(base_magazines, true)`

### Issue 2: Silenced Pistol on City Map
**File**: `scripts/levels/city_level.gd`
**Location**: `_setup_player_tracking()` function around line 280-294

**Problem**: The city level script was missing the `_configure_silenced_pistol_ammo()` function entirely, while other levels (building_level.gd, beach_level.gd, docks_level.gd, etc.) have it.

**Evidence**:
- Grep search for `_configure_silenced_pistol_ammo` found 6 level files with the function, but city_level.gd was NOT among them
- The SilencedPistol.cs has `ConfigureAmmoForEnemyCount()` method that configures ammo to match enemy count
- City level has 8 enemies, so silenced pistol should have 8 bullets total (not 52)

**Fix**: Added:
1. Call to `_configure_silenced_pistol_ammo(weapon)` in `_setup_player_tracking()`
2. The `_configure_silenced_pistol_ammo()` function itself (copied from building_level.gd pattern)

## Technical Details

### Weapon Ammo System
- Weapons use `StartingMagazineCount = 4` by default (in BaseWeapon.cs)
- For rifles with 30-round magazines: 4 magazines = 30 current + 90 reserve = 120 total
- Building level should have 2 magazines = 30 current + 30 reserve = 60 total
- `ReinitializeMagazines(count, fillAll)` allows level scripts to override the default

### SilencedPistol Ammo Configuration
- Magazine size: 13 rounds
- `ConfigureAmmoForEnemyCount(enemyCount)` distributes exactly enough bullets for the given enemy count
- Example: 8 enemies = 8 bullets (less than one full magazine)
- Example: 26 enemies = 13 + 13 (one full magazine + one spare)

## Files Changed

1. `scripts/levels/building_level.gd`
   - Added magazine reinitialization for AK+GL weapon (same as M16)

2. `scripts/levels/city_level.gd`
   - Added call to `_configure_silenced_pistol_ammo()` in `_setup_player_tracking()`
   - Added `_configure_silenced_pistol_ammo()` function

## Testing

### Manual Testing Checklist
- [ ] Building map, Hard difficulty, AK+GL weapon: Should show 30+30 ammo
- [ ] Building map, Hard difficulty, M16 weapon: Should show 30+30 ammo (unchanged)
- [ ] Building map, Power Fantasy mode, AK+GL: Should show increased ammo (multiplier applied)
- [ ] City map, Silenced pistol: Should show 8 bullets (matching 8 enemies)

### Regression Testing
- [ ] Other weapons on Building map still work correctly
- [ ] Other levels still work correctly
- [ ] Power Fantasy ammo multiplier still works

## Related Code

### Building Level - M16 (reference implementation)
```gdscript
# Reduce M16 ammunition by half for Building level (issue #413)
var base_magazines: int = 2
var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
if difficulty_manager:
    var ammo_multiplier: int = difficulty_manager.get_ammo_multiplier()
    if ammo_multiplier > 1:
        base_magazines *= ammo_multiplier
if m16.has_method("ReinitializeMagazines"):
    m16.ReinitializeMagazines(base_magazines, true)
```

### SilencedPistol.cs - ConfigureAmmoForEnemyCount
```csharp
public void ConfigureAmmoForEnemyCount(int enemyCount)
{
    int magazineCapacity = WeaponData.MagazineSize; // 13 for silenced pistol
    int fullMagazines = enemyCount / magazineCapacity;
    int remainingBullets = enemyCount % magazineCapacity;
    // ... distributes ammo to match enemy count exactly
}
```

## Enemy Counts by Map (for reference)
- Building: 10 enemies
- City: 8 enemies
- Castle: 13 enemies
- Beach: 8 enemies
- Docks: 20 enemies
- Labyrinth: 5 enemies
- TestTier: 10 enemies
- Revolver: 12 enemies
