# Issue #949: Fix Ammunition Counts - Deep Case Study Analysis

## Summary
Fix ammunition counts for M16/AK on Building map (Hard difficulty) and silenced pistol on City map.

## Issue Description
1. **M16/AK on Building map (Hard difficulty)**: Currently 30+90 ammo, should be 30+30
2. **Silenced pistol on City map**: Currently 13+39 (52 total), should match enemy count on all maps

## Timeline of Events

### Initial Investigation (First Attempt)
1. **Problem Identification**: The issue reported M16 and AK showing 30+90 ammo instead of 30+30 on Building map
2. **Initial Analysis**: Found that M16 had `ReinitializeMagazines(2, true)` call but AK+GL was missing it
3. **First Fix Attempt** (Commit b9631ee2):
   - Added `ReinitializeMagazines(2, true)` call for AK+GL in `_setup_selected_weapon()`
   - Added `_configure_silenced_pistol_ammo()` function to city_level.gd
4. **Result**: Fix appeared to be correct but user reported the issue persisted

### Deep Investigation (Second Attempt)
5. **User Feedback**: "у АК и m16 всё ещё 30+90 на карте здание" (AK and M16 still have 30+90 on Building map)
6. **Root Cause Discovery**: The fix was bypassed due to early return in the code

## Root Cause Analysis

### The Real Problem: Race Condition Between C# and GDScript

The Godot game has TWO weapon initialization paths that compete:

1. **C# Path** (`Scripts/Characters/Player.cs`):
   - In `_Ready()` (line 1007), calls `ApplySelectedWeaponFromGameManager()`
   - This method loads and equips the weapon with **default 4 magazines** (30+90)
   - Sets `CurrentWeapon = weapon` immediately
   - **Does NOT call `ReinitializeMagazines()`**

2. **GDScript Path** (`scripts/levels/building_level.gd`):
   - In `_setup_selected_weapon()` (line 1400-1402):
   ```gdscript
   if existing_weapon != null and _player.get("CurrentWeapon") == existing_weapon:
       _log_to_file("%s already equipped by C# Player - skipping GDScript weapon swap" % expected_name)
       return  # <-- EARLY RETURN! Skips ReinitializeMagazines!
   ```

### The Bug Flow

```
1. Player._Ready() executes in C#
   ↓
2. ApplySelectedWeaponFromGameManager() called
   ↓
3. Weapon loaded with default 4 magazines (30+90)
   ↓
4. CurrentWeapon set to the new weapon
   ↓
5. building_level.gd _setup_selected_weapon() runs
   ↓
6. Checks: existing_weapon != null && CurrentWeapon == existing_weapon
   ↓
7. Condition TRUE → EARLY RETURN
   ↓
8. ReinitializeMagazines(2, true) NEVER CALLED
   ↓
9. Weapon stays at 30+90 instead of 30+30
```

### Why the First Fix Failed

The first fix added `ReinitializeMagazines` calls AFTER the weapon equip code:

```gdscript
elif selected_weapon_id == "ak_gl":
    # ... load and equip weapon ...
    akgl.ReinitializeMagazines(base_magazines, true)  # This was added
```

But because the C# code already equipped the weapon, the code path hit the early return at line 1402, and **never reached** the `elif selected_weapon_id == "ak_gl":` block.

## The Fix

### Solution: Apply Ammo Config Before Early Return

Changed the early return to instead apply building-level ammo configuration:

**Before:**
```gdscript
if existing_weapon != null and _player.get("CurrentWeapon") == existing_weapon:
    _log_to_file("%s already equipped by C# Player - skipping GDScript weapon swap" % expected_name)
    return  # Just returns, skipping ammo config
```

**After:**
```gdscript
if existing_weapon != null and _player.get("CurrentWeapon") == existing_weapon:
    _log_to_file("%s already equipped by C# Player - applying building-level ammo config" % expected_name)
    # Apply building-level ammo configuration to already-equipped weapon (Issue #949)
    _apply_building_ammo_config(existing_weapon, selected_weapon_id)
    return
```

### New Function: `_apply_building_ammo_config()`

```gdscript
func _apply_building_ammo_config(weapon: Node, weapon_id: String) -> void:
    if weapon == null:
        return

    # M16 and AK+GL should have 2 magazines (30+30) on Building level (Issue #949)
    if weapon_id == "m16" or weapon_id == "ak_gl":
        var base_magazines: int = 2
        var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
        if difficulty_manager:
            var ammo_multiplier: int = difficulty_manager.get_ammo_multiplier()
            if ammo_multiplier > 1:
                base_magazines *= ammo_multiplier
        if weapon.has_method("ReinitializeMagazines"):
            weapon.ReinitializeMagazines(base_magazines, true)
        # ... update ammo display ...
```

## Technical Details

### Weapon Ammo System
- Weapons use `StartingMagazineCount = 4` by default (in BaseWeapon.cs)
- For rifles with 30-round magazines: 4 magazines = 30 current + 90 reserve = 120 total
- Building level should have 2 magazines = 30 current + 30 reserve = 60 total
- `ReinitializeMagazines(count, fillAll)` allows level scripts to override the default

### C# Player.ApplySelectedWeaponFromGameManager()
Located at `Scripts/Characters/Player.cs:2554-2638`:
- Reads weapon selection from GameManager autoload
- Loads weapon scene and instantiates it
- Sets CurrentWeapon property
- Does NOT apply level-specific ammo limits

### GDScript building_level.gd _setup_selected_weapon()
Located at `scripts/levels/building_level.gd:1374-1620`:
- Checks if weapon already equipped by C# (to avoid double-equip)
- If not equipped, loads and equips weapon with building-level ammo config
- **Bug**: If already equipped, returns early without ammo config

## Files Changed

1. `scripts/levels/building_level.gd`
   - Modified early return to call `_apply_building_ammo_config()` before returning
   - Added `_apply_building_ammo_config()` function that applies level-specific ammo limits

2. `scripts/levels/city_level.gd`
   - Added `_configure_silenced_pistol_ammo()` function
   - Added call in `_setup_player_tracking()`

## Testing

### Manual Testing Checklist
- [ ] Building map, Hard difficulty, AK+GL weapon: Should show 30+30 ammo
- [ ] Building map, Hard difficulty, M16 weapon: Should show 30+30 ammo
- [ ] Building map, Power Fantasy mode, AK+GL: Should show increased ammo (multiplier applied)
- [ ] City map, Silenced pistol: Should show 8 bullets (matching 8 enemies)

### Regression Testing
- [ ] Other weapons on Building map still work correctly
- [ ] Other levels still work correctly
- [ ] Power Fantasy ammo multiplier still works

## Lessons Learned

1. **Dual Initialization Paths**: When both C# and GDScript can initialize the same object, ensure all initialization logic runs in both paths
2. **Early Returns**: Early returns can bypass important logic - consider what should happen before returning
3. **Root Cause vs Symptoms**: The first fix addressed where the ammo config code should be, but missed that the code path was bypassed entirely
4. **Comments Don't Match Reality**: The comment said "skipping GDScript weapon swap" but it was actually "skipping all weapon configuration including ammo limits"

## Related Issues
- Issue #413: Original M16 ammo reduction for Building level
- Issue #501: Power Fantasy mode ammo multiplier
- Issue #636: Makarov PM 2.5x ammo configuration

## Enemy Counts by Map (for reference)
- Building: 10 enemies
- City: 8 enemies
- Castle: 13 enemies
- Beach: 8 enemies
- Docks: 20 enemies
- Labyrinth: 5 enemies
- TestTier: 10 enemies
- Revolver: 12 enemies

## Logs and Data
- Solution draft log: `./logs/solution-draft-log.txt`
- Issue comments: `./logs/issue-comments.json`
- PR comments: `./logs/pr-comments.json`
