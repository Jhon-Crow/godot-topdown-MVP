# Issue #610: Create New First Level (Labyrinth of Technical Rooms)

## Issue Summary

**Request:** Create a new first level that resembles a labyrinth of technical rooms (enclosed spaces).

**Requirements:**
- Height: 1080px
- Layout: Labyrinth-like technical rooms (enclosed spaces, corridors)
- 3 enemies with PM (default ranged weapon) - unarmored (1-2 HP)
- 1 enemy with shotgun - unarmored (1-2 HP)
- 1 enemy with M16 (RIFLE) - armored (2-4 HP)
- Total: 5 enemies

## Codebase Analysis

### Existing Level Architecture
Each level consists of:
1. **Scene file (.tscn)** - Defines the visual layout, walls, enemies, player spawn, UI
2. **Script file (.gd)** - Handles game logic (enemy tracking, scoring, exit zone, etc.)
3. **Registration** - Level added to `levels_menu.gd` LEVELS array

### Level Pattern (from BuildingLevel.tscn)
- Background ColorRect (full area)
- Floor ColorRect (playable area)
- Outer Walls (StaticBody2D with CollisionShape2D + ColorRect + LightOccluder2D)
- Interior Walls (same structure, collision_layer = 4, collision_mask = 0)
- Cover objects (desks, tables, cabinets - collision_layer = 4)
- Enemies (instances of Enemy.tscn with exported property overrides)
- Navigation (NavigationRegion2D with NavigationPolygon)
- Player spawn
- UI (CanvasLayer with labels)
- PauseMenu

### Enemy Configuration
- `weapon_type = 0` = RIFLE (M16) - default
- `weapon_type = 1` = SHOTGUN
- `weapon_type = 2` = UZI
- `weapon_type = 3` = MACHETE
- `min_health` / `max_health` control HP range
- `behavior_mode = 0` = PATROL, `1` = GUARD
- `destroy_on_death = true` for cleanup
- `enable_flanking = true` / `enable_cover = true` for AI behaviors

### Design Decisions

**Level Size:** 1920x1080px (width x height as specified). This is smaller than BuildingLevel (2464x2064) making it more compact and labyrinth-like.

**Layout:** Technical rooms connected by narrow corridors, creating a maze-like feel. Rooms will be named after typical technical spaces (Server Room, Generator Room, Control Room, Storage, etc.).

**Enemy Placement:**
1. Enemy1-3: Default weapon (RIFLE type 0 as PM equivalent), min_health=1, max_health=2
2. Enemy4: Shotgun (weapon_type=1), min_health=1, max_health=2
3. Enemy5: RIFLE/M16 (weapon_type=0), min_health=2, max_health=4, armored

**Color Scheme:** Dark industrial/technical room palette:
- Background: Very dark (0.03, 0.03, 0.05) - darker than building
- Floor: Dark concrete grey (0.15, 0.14, 0.13)
- Walls: Industrial grey-green (0.25, 0.25, 0.22)
- Interior walls: Slightly lighter (0.3, 0.28, 0.25)
- Cover: Metal grey tones

## Implementation Plan

1. Create `scenes/levels/LabyrinthLevel.tscn` - New level scene
2. Create `scripts/levels/labyrinth_level.gd` - Level script (based on building_level.gd)
3. Update `scripts/ui/levels_menu.gd` - Register as first level in LEVELS array
4. Update `project.godot` - Set as main/default scene (first level)
