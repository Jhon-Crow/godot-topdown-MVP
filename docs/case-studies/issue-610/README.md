# Case Study: Issue #610 - New First Level (Technical Corridor)

## Issue Summary

**Title:** Make a new first level
**Request:** Create a level with a narrow long corridor layout, distinct from other levels
**Enemies:** 3 with PM (pistol/rifle) + 1 with shotgun, all unarmored (1-2 HP)

## Analysis

### Current Level Structure

The game has 5 levels in this order:
1. **BuildingLevel** (2400x2000px, 10 enemies) - Office building interior
2. **TestTier/Polygon** (4000x2960px, 10 enemies) - Training ground
3. **CastleLevel** (6000x2560px, 15 enemies) - Medieval fortress
4. **Tutorial** (1280x720px, 4 enemies) - Training level
5. **BeachLevel** (2400x2000px, 8 enemies) - Beach environment

### Level Architecture Pattern

All levels follow the same pattern:
- **Scene file** (`.tscn`) - Contains environment, walls, cover, enemies, player, UI
- **Script file** (`.gd`) - Contains game logic (enemy tracking, scoring, exit zones)
- **No TileMaps** - Uses `StaticBody2D` with `RectangleShape2D` for walls and collision
- **Navigation** - `NavigationRegion2D` with `NavigationPolygon` baked from collision layer 4
- **Visual style** - `ColorRect` nodes for walls, floors, and cover objects
- **Light occlusion** - `LightOccluder2D` on each wall/obstacle

### Enemy Configuration

Enemy weapon types available:
- `RIFLE` (0) - M16 style, 5.45x39mm caliber, semi-auto
- `SHOTGUN` (1) - Pump-action, 6-10 pellets, 15-degree spread
- `UZI` (2) - Mini UZI, 9mm, full-auto
- `MACHETE` (3) - Melee weapon

For this level:
- "PM" enemies will use `weapon_type = 0` (RIFLE) - closest to pistol behavior
- Shotgun enemy will use `weapon_type = 1` (SHOTGUN)
- All enemies: `min_health = 1`, `max_health = 2` (unarmored)

### Design Decisions

1. **Level size:** 4000x600px - narrow long corridor, unique shape among all levels
2. **Layout:** Single long corridor with 3 interior divider walls creating zigzag movement
3. **Theme:** Technical/industrial corridor with pipe and crate cover objects
4. **Enemy count:** 4 (3 RIFLE + 1 SHOTGUN) - spaced along the corridor length
5. **Placement:** The new level becomes the first level (simplest/easiest)

### Corridor Layout (v3)

```
4000px wide x 600px tall
Player spawns at left (200, 300), Exit at right (3850, 300)

+---------+-------+---------+-------+---------+-------+----------+
|         |D1     |         |       |         |D3     |          |
| [SPAWN] | |     |         |  D2   | [E3]    | |     | [E4]     |
| [E1]    | |     |         |  |    |         | |     |    [EXIT] |
|   [E2]  |       |         |  |    |         |       |          |
+---------+-------+---------+-------+---------+-------+----------+

D1, D2, D3 = Interior divider walls (partial height)
E1 = RIFLE enemy at (500, 300) - middle of starting room
E2 = RIFLE enemy at (800, 200) - right part of starting room, patrols
E3 = RIFLE enemy at (2600, 400)
E4 = SHOTGUN enemy at (3400, 250)
```

Cover objects: 3 crates (64x64) + 2 pipe sections (24x120)
- Crate1 at (350, 200) - provides cover between spawn and Enemy1

## Revision History

- **v1:** Square labyrinth layout (1600x1600px with 6 rooms). Feedback: "should be a narrow long corridor, not the same level as all the others"
- **v2:** Narrow corridor layout (4000x600px). Completely redesigned to be a unique elongated corridor shape. Feedback: "no exit from starting room, move 2 enemies to starting room"
- **v3:** Moved 2 enemies (Enemy1 and Enemy2) into the starting room (left of Divider1). Enemy1 at (500, 300) in the middle, Enemy2 at (800, 200) in the right part. Adjusted cover placement. Feedback: "nothing changed" - game log showed enemies not initializing
- **v4:** Fixed enemy initialization bug. Root cause analysis (see below) revealed that `_setup_enemy_tracking()` ran before child instance scripts were fully initialized during scene transitions. Fix: deferred the setup to the next frame using `call_deferred()`, added fallback signal detection for both GDScript ("died") and C# ("Died") naming conventions, and added group-based tracking as a last resort.

## Bug Analysis: v3 Enemy Initialization Failure

### Symptoms
- Game log showed `has_died_signal=false` for all 4 enemies in TechnicalLevel
- 0 enemies registered for tracking, scoring, and replay
- Enemies were visible in the scene tree (4 children found) with scripts attached
- The same Enemy.tscn worked correctly in BuildingLevel (10 enemies, all `has_died_signal=true`)

### Root Cause
The TechnicalLevel is loaded via `change_scene_to_file()` as a scene transition (not the initial project scene). During scene transitions in Godot 4.3, instanced child scenes (like Enemy.tscn) may not have their scripts fully resolved when the parent's `_ready()` runs. The `has_signal("died")` check returns `false` because the GDScript `signal died` declaration hasn't been processed yet.

BuildingLevel works because it's the default/main scene loaded at project startup, where all scene tree nodes are initialized before any `_ready()` callback.

### Key Evidence from Game Log
```
[BuildingLevel] Child 'Enemy1': script=true, has_died_signal=true   ← Works (initial scene)
[TechnicalLevel] Child 'Enemy1': script=true, has_died_signal=false  ← Broken (scene transition)
[TechnicalLevel] Enemy tracking complete: 0 enemies registered       ← No enemies tracked
```

### Fix Applied (v4)
1. **Deferred setup:** `call_deferred("_deferred_setup")` ensures all child instances have their scripts loaded before signal checking
2. **Signal fallback:** Check both `has_signal("died")` (GDScript) and `has_signal("Died")` (C# PascalCase)
3. **Group-based tracking:** As last resort, if enemy is in the "enemies" group, track it and connect signals when it becomes ready
4. **Enhanced diagnostics:** Log script path, node type, and tree status for easier debugging

### Game Log
See `game_log_v3_20260208.txt` in this directory.

## References

- [Rooms and Mazes: A Procedural Dungeon Generator](https://journal.stuffwithstuff.com/2014/12/21/rooms-and-mazes/)
- [Level Design in Top-Down Shooters (MY.GAMES)](https://medium.com/my-games-company/level-design-in-top-down-shooters)
- [Designing Mazes as Game Levels](https://jahej.com/alt/2011_04_16_designing-mazes-as-game-levels.html)

## Implementation

See PR #613 for the complete implementation.
