# Case Study: Issue #312 - Add Silenced Pistol

## Issue Summary
**Issue**: [#312](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/312)
**Title**: добавить пистолет с глушителем (Add silenced pistol)
**Status**: Fixed - weapon now appears in armory

## Bug Report: Weapon Not Appearing in Armory

### Problem Description
After initial implementation, the silenced pistol was not appearing in the game's armory menu. The user reported: "пистолет не добавился в armory (возможно проблема с C#)" (pistol was not added to armory, possibly a C# problem).

### Root Cause Analysis

**Root Cause**: The silenced pistol weapon class and scene files were created, but the weapon was **not registered** in the game's weapon registry systems.

In this project, weapons require registration in **two separate GDScript files**:

1. **`scripts/ui/armory_menu.gd`** - Contains `WEAPONS` dictionary for UI display
2. **`scripts/autoload/game_manager.gd`** - Contains `WEAPON_SCENES` dictionary for scene loading

The C# weapon code (`SilencedPistol.cs`) was correctly implemented, but the integration with the GDScript-based armory system was missed.

### Timeline of Events

| Time | Event |
|------|-------|
| 2026-01-24 ~16:27 | Initial PR #315 created with silenced pistol implementation |
| 2026-01-24 19:44:48 | User tested the game build |
| 2026-01-24 19:44:49 | User opened armory menu - no silenced pistol visible |
| 2026-01-24 19:45:05 | User ended game session, filed bug report |
| 2026-01-24 ~16:46 | User reported issue with game log attached |

### Evidence from Logs

Game log (`game_log_20260124_194448.txt`) shows:
```
[19:44:49] [INFO] [PauseMenu] Armory button pressed
[19:44:49] [INFO] [PauseMenu] armory_menu_scene resource path: res://scenes/ui/ArmoryMenu.tscn
[19:44:49] [INFO] [PauseMenu] _populate_weapon_grid method exists
```

The armory menu loaded successfully, but since `silenced_pistol` was not in the `WEAPONS` dictionary, it was never displayed.

### Fix Applied

Added silenced pistol registration to both files:

**`scripts/ui/armory_menu.gd`:**
```gdscript
"silenced_pistol": {
    "name": "Silenced Pistol",
    "icon_path": "res://assets/sprites/weapons/silenced_pistol_topdown.png",
    "unlocked": true,
    "description": "Beretta M9 with suppressor - semi-auto, 9mm, 13 rounds, silent shots (enemies don't hear), 2x recoil, smooth aiming. Press LMB to fire.",
    "is_grenade": false
}
```

**`scripts/autoload/game_manager.gd`:**
```gdscript
"silenced_pistol": "res://scenes/weapons/csharp/SilencedPistol.tscn"
```

### Lessons Learned

1. **Cross-language integration**: When adding C# components to a GDScript-based system, ensure all registration points are updated
2. **Checklist needed**: A weapon addition checklist would prevent similar issues:
   - [ ] Create weapon script (C# or GDScript)
   - [ ] Create weapon data resource (.tres)
   - [ ] Create weapon scene (.tscn)
   - [ ] Add sprite/icon asset
   - [ ] Register in `armory_menu.gd` WEAPONS dictionary
   - [ ] Register in `game_manager.gd` WEAPON_SCENES dictionary
   - [ ] Test weapon appears in armory
   - [ ] Test weapon is selectable and functional

---

## Requirements Analysis

### Original Requirements (translated from Russian):
1. **Caliber**: 9mm
2. **Fire mode**: Semi-automatic (shoots one bullet per trigger pull)
3. **Magazine capacity**: 13 rounds
4. **Sound**: Shots and reload sounds are inaudible to enemies (silenced)
5. **Spread**: Same as M16 (2.0 degrees)
6. **Recoil**: 2x more than M16 per single shot, stays at maximum position for a period (simulates time for human to control recoil)
7. **Bullets**: Ricochet like all 9mm (same as Uzi), do not penetrate walls
8. **Bullet speed**: Slightly higher than other 9mm (due to suppressor effect)
9. **Scope**: No scope/laser sight
10. **Aiming sensitivity**: Lower than all existing weapons (very smooth aiming)
11. **Reload**: Same as M16

### Reference Model
- Beretta M9 with suppressor (as shown in reference images)

## Implementation Details

### Files Created

1. **`Scripts/Weapons/SilencedPistol.cs`** - Main weapon script
   - Inherits from `BaseWeapon`
   - Semi-automatic fire mode
   - Extended recoil recovery delay (0.35s vs 0.08-0.1s for other weapons)
   - 2x recoil offset compared to M16 (±10 degrees vs ±5 degrees)
   - No sound propagation (enemies don't hear shots)

2. **`resources/weapons/SilencedPistolData.tres`** - Weapon configuration
   - Uses existing 9x19mm caliber for bullet properties
   - Magazine: 13 rounds
   - Fire rate: 5.0 shots/sec (semi-auto limited by player click speed)
   - Spread: 2.0 degrees (same as M16)
   - Bullet speed: 1350 px/s (higher than standard 9mm's 1200 px/s)
   - Sensitivity: 2.0 (lower than M16's 4.0 and Uzi's 8.0)
   - Loudness: 0.0 (silent)
   - Screen shake intensity: 10.0 (2x M16's 5.0)

3. **`scenes/weapons/csharp/SilencedPistol.tscn`** - Scene file
   - Uses 9mm bullet scene (same as Uzi)
   - Uses standard casing scene
   - Bullet spawn offset: 22px (accounts for suppressor length)

4. **`assets/sprites/weapons/silenced_pistol_topdown.png`** - Placeholder sprite
   - 44x12 pixels (longer than standard pistol due to suppressor)
   - Grayscale placeholder (to be replaced with proper art)

### Files Modified

1. **`scripts/autoload/audio_manager.gd`**
   - Added `SILENCED_SHOT` constant with placeholder sound
   - Added `VOLUME_SILENCED_SHOT` constant (-18.0 dB, very quiet)
   - Added `play_silenced_shot()` function
   - Added silenced shot to preload list

## Weapon Stats Comparison

| Property | Silenced Pistol | M16 | Mini Uzi |
|----------|-----------------|-----|----------|
| Damage | 1.0 | 1.0 | 0.5 |
| Fire Rate | 5.0 | 10.0 | 25.0 |
| Magazine | 13 | 30 | 32 |
| Bullet Speed | 1350 | 2500 | 1200 |
| Spread | 2.0° | 2.0° | 6.0° |
| Sensitivity | 2.0 | 4.0 | 8.0 |
| Screen Shake | 10.0 | 5.0 | 15.0 |
| Loudness | 0.0 | 1469.0 | 1469.0 |
| Automatic | No | Yes | Yes |
| Recoil Recovery | 0.35s | 0.1s | 0.08s |
| Max Recoil | ±10° | ±5° | ±8° |

## Key Implementation Decisions

### 1. Recoil System
The silenced pistol implements a distinctive "heavy recoil with slow recovery" system:
- Each shot applies 2x the recoil of M16 per bullet
- Recovery is delayed by 0.35s (vs 0.08-0.1s for automatic weapons)
- This simulates the real-world experience of controlling pistol recoil

### 2. Silent Sound Propagation
- `Loudness` set to 0.0 prevents `SoundPropagation.emit_sound()` from alerting enemies
- Local audio still plays for player feedback (at very low volume)

### 3. Aiming Sensitivity
- Sensitivity of 2.0 (lowest of all weapons) creates smooth, deliberate aim
- Matches the tactical nature of a suppressed weapon

### 4. Bullet Properties
- Uses existing 9x19mm caliber (same as Uzi)
- Can ricochet up to 1 time at shallow angles (≤20°)
- Cannot penetrate walls
- Slightly higher bullet speed (1350 vs 1200) due to suppressor gas containment

## Future Improvements

1. **Proper Sprite Art**: The current placeholder should be replaced with a proper Beretta M9 with suppressor sprite matching the reference images
2. **Dedicated Sound**: Add proper suppressed shot sound effect (current uses pistol bolt sound as placeholder)
3. **Silenced Reload Sound**: Consider adding a quieter reload animation/sound specific to the silenced pistol
4. **Magazine Drop Animation**: The standard casing effect works, but a visible magazine drop during reload would add polish

## Testing Recommendations

1. Verify semi-automatic fire works (no automatic fire on hold)
2. Test recoil feels heavier than other weapons
3. Confirm enemies don't react to shots (no sound propagation)
4. Test ricochet behavior matches Uzi (9mm rules)
5. Verify bullet speed is slightly higher than Uzi
6. Check smooth aiming (low sensitivity)
7. Confirm 13-round magazine capacity
