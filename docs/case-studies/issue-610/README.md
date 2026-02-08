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

### Corridor Layout

```
4000px wide x 600px tall
Player spawns at left (200, 300), Exit at right (3850, 300)

+---------+-------+---------+-------+---------+-------+----------+
|         |D1     |         |       |         |D3     |          |
| [SPAWN] | |     | [E2]    |  D2   | [E3]    | |     | [E4]     |
|         | |     |         |  |    |         | |     |    [EXIT] |
| [E1]    |       |         |  |    |         |       |          |
+---------+-------+---------+-------+---------+-------+----------+

D1, D2, D3 = Interior divider walls (partial height)
E1 = RIFLE enemy at (900, 350)
E2 = RIFLE enemy at (1800, 200) - patrols
E3 = RIFLE enemy at (2600, 400)
E4 = SHOTGUN enemy at (3400, 250)
```

Cover objects: 3 crates (64x64) + 2 pipe sections (24x120)

## Revision History

- **v1:** Square labyrinth layout (1600x1600px with 6 rooms). Feedback: "should be a narrow long corridor, not the same level as all the others"
- **v2:** Narrow corridor layout (4000x600px). Completely redesigned to be a unique elongated corridor shape.

## References

- [Rooms and Mazes: A Procedural Dungeon Generator](https://journal.stuffwithstuff.com/2014/12/21/rooms-and-mazes/)
- [Level Design in Top-Down Shooters (MY.GAMES)](https://medium.com/my-games-company/level-design-in-top-down-shooters)
- [Designing Mazes as Game Levels](https://jahej.com/alt/2011_04_16_designing-mazes-as-game-levels.html)

## Implementation

See PR #613 for the complete implementation.
