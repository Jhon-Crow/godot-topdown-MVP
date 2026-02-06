# Case Study: Issue #520 - ASVK Sniper Rifle Cannot Be Selected

## Summary

The ASVK sniper rifle was added to the game but could not be selected from the armory menu. When a player clicked on the ASVK in the armory, the game would restart with the previously equipped weapon (e.g., AssaultRifle) instead of the sniper rifle.

## Timeline of Events

1. **Issue #520 created**: Request to add ASVK (АСВК) anti-materiel sniper rifle
2. **Initial implementation**: SniperRifle.cs, SniperBullet.cs, weapon scenes, and armory menu entry were created
3. **Bug reported by @Jhon-Crow**: Selecting ASVK in armory does nothing; player keeps the same weapon

## Root Cause Analysis

### Primary Root Cause: Missing WEAPON_SCENES Entry in GameManager

**File**: `scripts/autoload/game_manager.gd`, lines 37-42

The `WEAPON_SCENES` dictionary serves as a whitelist of valid weapon IDs. The `set_selected_weapon()` method (line 172) validates the weapon ID against this dictionary:

```gdscript
func set_selected_weapon(weapon_id: String) -> void:
    if weapon_id in WEAPON_SCENES:
        selected_weapon = weapon_id
        weapon_selected.emit(weapon_id)
    else:
        push_warning("Unknown weapon ID: %s" % weapon_id)
```

The dictionary was missing the `"sniper"` entry:

```gdscript
const WEAPON_SCENES: Dictionary = {
    "m16": "res://scenes/weapons/csharp/AssaultRifle.tscn",
    "shotgun": "res://scenes/weapons/csharp/Shotgun.tscn",
    "mini_uzi": "res://scenes/weapons/csharp/MiniUzi.tscn",
    "silenced_pistol": "res://scenes/weapons/csharp/SilencedPistol.tscn"
    # "sniper" WAS MISSING HERE
}
```

When the armory called `GameManager.set_selected_weapon("sniper")`, it silently failed and the weapon selection remained unchanged.

### Secondary Issues: Incomplete Integration

1. **Level scripts missing SniperRifle detection**: The weapon signal connection chains in `building_level.gd`, `castle_level.gd`, and `tutorial_level.gd` did not include `SniperRifle` node lookups, which would cause ammo UI signals to not connect.

2. **Level scripts missing weapon swap logic**: Only `test_tier.gd` had the `elif selected_weapon_id == "sniper":` handler in `_setup_selected_weapon()`. The other three levels (building, castle, tutorial) would fall through to the default M16 path.

3. **Test mock outdated**: The `MockGameManager` in `test_game_manager.gd` only had `m16` and `shotgun` in its `WEAPON_SCENES`, not reflecting the actual GameManager's current state.

## Evidence from Game Log

From `game_log_20260206_201853.txt`:

- **Line 203**: `[PauseMenu] Armory button pressed` - User opens armory
- **Line 212**: Scene changes but...
- **Line 362**: `source=PLAYER (AssaultRifle)` - Player still has AssaultRifle after selection
- **Lines 390-398**: User opens armory again, selects ASVK again
- **Lines 544, 627**: Still shows `source=PLAYER (AssaultRifle)` - weapon never changed

No error about "Unknown weapon ID: sniper" appears in the log because `push_warning()` output depends on Godot's logging level configuration.

## Fix Applied

1. **GameManager**: Added `"sniper": "res://scenes/weapons/csharp/SniperRifle.tscn"` to `WEAPON_SCENES`
2. **All 4 level scripts**: Added SniperRifle to weapon detection chains and `_setup_selected_weapon()` handlers
3. **Test mock**: Updated to include all weapons including sniper
4. **Sprite**: Improved ASVK sprite to better match the reference image (scope, bipod, muzzle brake)

## Lessons Learned

- When adding a new weapon, all integration points must be updated: GameManager whitelist, all level scripts' weapon setup functions, all level scripts' weapon signal connection chains, and test mocks.
- The `WEAPON_SCENES` dictionary acts as a gatekeeper - if a weapon ID isn't in it, `set_selected_weapon()` silently ignores the selection (only emitting a warning). This silent failure made the bug hard to detect without checking logs.
- A checklist for adding weapons should include: GameManager.WEAPON_SCENES, all `_setup_selected_weapon()` functions, all weapon detection chains, armory_menu WEAPONS dictionary, player.gd arm pose detection, and tests.
