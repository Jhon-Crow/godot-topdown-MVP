# Case Study: Issue #753 - Add New Large Map "Docks"

## Issue Summary

**Issue URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/753

**Request:** Create a new large map called "Docks" (Доки) with the following requirements:
1. Include empty spaces the size of 1 viewport (at least one such space between cover areas)
2. Place 20 enemies with varied weapons and tactical positioning
3. Create interesting tactical gameplay situations

## Technical Analysis

### Viewport Size
- Default viewport: **1280x720 pixels**
- Empty spaces requirement: At least 1280x720 px clear areas between cover zones

### Existing Map References

| Level | Size (px) | Enemies | Theme |
|-------|-----------|---------|-------|
| LabyrinthLevel | 1920x1080 | 5 | Technical rooms, corridors |
| BuildingLevel | 2400x2000 | 10 | Indoor, rooms, grenadier |
| TestTier | 1280x720 | 5 | Training ground |
| CastleLevel | 6000x2560 | 15 | Medieval fortress |
| CityLevel | 6000x5000 | 8 | Urban, buildings |
| BeachLevel | 2400x2000 | 8 | Outdoor, machete enemies |

### Weapon Types Available
From `enemy.gd`:
- `WeaponType.RIFLE` (0): M16 rifle - balanced ranged combat
- `WeaponType.SHOTGUN` (1): Slow but powerful, close range
- `WeaponType.UZI` (2): Fast SMG, high fire rate
- `WeaponType.MACHETE` (3): Melee weapon, requires close combat

### Enemy Behavior Modes
- `BehaviorMode.PATROL` (0): Moves between patrol points
- `BehaviorMode.GUARD` (1): Stationary guard

## Design Decision

### Map Concept: Industrial Docks
A large industrial docks area featuring:
- Water zones (boundaries)
- Shipping containers (cover)
- Warehouse structures
- Loading areas
- Crane platforms
- Open spaces between container yards (1280x720+ areas)

### Map Size: 5000x4000 pixels
Larger than Beach/Building but manageable, with clear zones for tactical gameplay.

### Zone Layout
```
+----------------------------------------------------------+
|                        WATER (boundary)                   |
+----------------------------------------------------------+
|  CRANE     |     OPEN AREA 1      |   CONTAINER YARD A   |
|  PLATFORM  |    (1280x720+)       |   (dense cover)      |
+------------+----------------------+----------------------+
|            |                      |                      |
| WAREHOUSE  |     OPEN AREA 2      |   LOADING DOCK       |
|    A       |    (1280x720+)       |   (mixed cover)      |
|            |                      |                      |
+------------+----------------------+----------------------+
|            |                      |                      |
| CONTAINER  |     OPEN AREA 3      |   WAREHOUSE B        |
|  YARD B    |    (1280x720+)       |   (indoor)           |
|            |                      |                      |
+----------------------------------------------------------+
|                    PLAYER START (bottom)                  |
+----------------------------------------------------------+
```

### Enemy Distribution (20 total)

| Zone | Count | Weapon Mix | Behavior |
|------|-------|------------|----------|
| Crane Platform | 2 | 1 Sniper (Rifle), 1 UZI | Guard |
| Container Yard A | 3 | 2 Rifle, 1 Shotgun | Patrol/Guard |
| Warehouse A | 3 | 1 Shotgun, 2 UZI | Guard |
| Loading Dock | 4 | 2 Rifle, 1 UZI, 1 Machete | Patrol |
| Container Yard B | 3 | 1 Rifle, 1 Shotgun, 1 Machete | Patrol |
| Warehouse B | 3 | 1 Rifle, 1 UZI, 1 Grenadier | Guard |
| Open Areas | 2 | 2 Patrol (Rifle) | Patrol |

### Tactical Situations Created
1. **Long-range engagement**: Open areas force player to use cover-to-cover movement
2. **CQB situations**: Warehouse interiors with shotgun/UZI enemies
3. **Flanking opportunities**: Container yards allow multiple approach angles
4. **Height advantage**: Crane platform with elevated enemies
5. **Melee ambush**: Machete enemies in tight spaces

## Implementation Timeline

1. Create `docks_level.gd` script (based on beach_level.gd template)
2. Create `DocksLevel.tscn` scene file with:
   - Environment structure (Background, Floor, Walls)
   - Cover objects (containers, warehouse walls, crates)
   - Zone labels
   - Navigation region
   - 20 enemies with tactical placement
3. Add level to `levels_menu.gd` LEVELS constant
4. Test and verify gameplay

## Files to Create/Modify

### New Files
- `scenes/levels/DocksLevel.tscn`
- `scripts/levels/docks_level.gd`

### Modified Files
- `scripts/ui/levels_menu.gd` (add LEVELS entry)
