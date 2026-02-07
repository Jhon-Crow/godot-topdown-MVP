# Case Study: Issue #610 - New First Level (Technical Labyrinth)

## Issue Summary

**Title:** Make a new first level
**Request:** Create a labyrinth-like level with technical rooms (enclosed spaces)
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

1. **Level size:** ~1600x1600px - smaller than BuildingLevel for a tighter labyrinth feel
2. **Room count:** 6 interconnected rooms with corridors
3. **Theme:** Technical/industrial rooms (server room, electrical, control room, etc.)
4. **Enemy count:** 4 (3 RIFLE + 1 SHOTGUN) - fewer enemies, lower HP = quick, tense level
5. **Placement:** The new level becomes the first level (simplest/easiest)

### Technical Rooms Layout

```
+--------+-----+--------+
| ELECTR |     | CTRL   |
| ROOM   | cor | ROOM   |
|  (E1)  |ridor|  (E2)  |
+---  ---+--  -+---  ---+
|        CORRIDOR        |
+---  ---+------+---  ---+
| SERVER |      | PUMP   |
| ROOM   | MAIN | ROOM   |
|  (E3)  | HALL |  (E4)  |
+--------+--  --+--------+
         |SPAWN |
         +------+
```

E1, E2, E3 = RIFLE enemies (1-2 HP)
E4 = SHOTGUN enemy (1-2 HP)

## References

- [Rooms and Mazes: A Procedural Dungeon Generator](https://journal.stuffwithstuff.com/2014/12/21/rooms-and-mazes/)
- [Level Design in Top-Down Shooters (MY.GAMES)](https://medium.com/my-games-company/level-design-in-top-down-shooters)
- [Designing Mazes as Game Levels](https://jahej.com/alt/2011_04_16_designing-mazes-as-game-levels.html)

## Implementation

See PR #613 for the complete implementation.
