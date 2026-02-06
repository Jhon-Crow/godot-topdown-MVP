# Case Study: Issue #526 - Weapon Selection Table UI

## Problem Description

The current armory menu (`armory_menu.gd`) has several UX problems:
1. **Mixed categories**: Weapons and grenades are displayed in a single flat grid with no visual separation
2. **No stats display**: Only tooltip descriptions are shown — no structured weapon parameters
3. **No "currently equipped" panel**: Players cannot easily see what they have selected and compare stats
4. **Limited extensibility**: Adding new weapon categories requires modifying the flat grid layout

## Technical Details

### Current Architecture
- `armory_menu.gd` uses a single `WEAPONS` dictionary containing both weapons and grenades
- Items are distinguished by `is_grenade: bool` flag
- A `GridContainer` with 3 columns renders all items in a flat grid
- Selection is highlighted with a green border
- Weapon data (stats) exists in `.tres` resource files but is NOT loaded in the armory menu

### Available Data Sources for Stats Panel
1. **WeaponData (.tres resources)**: Damage, FireRate, MagazineSize, MaxReserveAmmo, ReloadTime, BulletSpeed, Range, SpreadAngle, BulletsPerShot, IsAutomatic, Loudness, Sensitivity
2. **CaliberData (.tres resources)**: caliber_name, can_ricochet, can_penetrate, max_penetration_distance
3. **GrenadeManager.GRENADE_DATA**: name, description per grenade type
4. **Descriptions in armory_menu.gd**: Special features text per weapon

### Weapon-to-Resource Mapping
| Weapon ID | Resource Path |
|-----------|--------------|
| m16 | `res://resources/weapons/AssaultRifleData.tres` |
| shotgun | `res://resources/weapons/ShotgunData.tres` |
| mini_uzi | `res://resources/weapons/MiniUziData.tres` |
| silenced_pistol | `res://resources/weapons/SilencedPistolData.tres` |
| sniper | `res://resources/weapons/SniperRifleData.tres` |

## Proposed Solution

### UI Layout (new design)
```
+---------------------------------------------------------------------+
|                         ARMORY                                       |
+---------------------------------------------------------------------+
|                                                                       |
|  WEAPONS (Firearms)                                                  |
|  +--------+  +--------+  +--------+  +--------+  +--------+         |
|  | [M16]  |  |[Shotgn]|  |[MUzi]  |  |[Pistol]|  |[ASVK]  |        |
|  | M16    |  |Shotgun |  |MiniUZI |  |Silenced|  | ASVK   |        |
|  +--------+  +--------+  +--------+  +--------+  +--------+         |
|  +--------+  +--------+  +--------+                                  |
|  |  ???   |  |  ???   |  |  ???   |                                  |
|  +--------+  +--------+  +--------+                                  |
|                                                                       |
|  GRENADES                                                            |
|  +--------+  +--------+  +--------+                                  |
|  |[Flash] |  | [Frag] |  | [F-1]  |                                  |
|  |Flashbng|  |  Frag  |  |F-1 Gren|                                  |
|  +--------+  +--------+  +--------+                                  |
|                                                                       |
|  CURRENT LOADOUT                                                     |
|  +---------------------------------------+                            |
|  | Weapon: M16 (Assault Rifle)           |                            |
|  | Caliber: 5.45x39mm | Auto | 30 rnd   |                            |
|  | Damage: 1.0  | Fire Rate: 10/s        |                            |
|  | Range: 1500px | Spread: 2.0°          |                            |
|  | Ricochet: Yes | Penetration: Yes      |                            |
|  +---------------------------------------+                            |
|  | Grenade: Flashbang                    |                            |
|  | Blinds enemies for 12s, stuns for 6s  |                            |
|  +---------------------------------------+                            |
|                                                                       |
|                    [ Back ]                                           |
+---------------------------------------------------------------------+
```

### Implementation Approach
1. Separate `WEAPONS` dictionary into two: `FIREARMS` and keep grenades from `GrenadeManager`
2. Add `WEAPON_RESOURCE_PATHS` mapping to load `.tres` files for stats
3. Create category headers (Labels) for "Weapons" and "Grenades" sections
4. Add a "Current Loadout" panel below showing selected weapon/grenade stats
5. Load weapon resource data dynamically to display parameters
6. Keep the existing selection logic (GameManager/GrenadeManager integration)

### Extensibility
- New weapon categories can be added as new sections with headers
- Weapon stats automatically loaded from `.tres` resources
- Grenade data pulled from GrenadeManager singleton
- Layout uses VBoxContainer with separate GridContainers per category

## References

- Existing armory_menu.gd: `scripts/ui/armory_menu.gd`
- WeaponData resource: `Scripts/Data/WeaponData.cs`
- CaliberData resource: `scripts/data/caliber_data.gd`
- GameManager: `scripts/autoload/game_manager.gd`
- GrenadeManager: `scripts/autoload/grenade_manager.gd`
