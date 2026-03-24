# Issue #1399: Branching Room Map for Roguelike Mode

## Problem Statement

The roguelike mode currently uses a strictly linear room progression (room 1 → room 2 → ... → treasure → next level). The issue requests an Isaac-style branching room map where:

1. Rooms connect to form a navigable map (like The Binding of Isaac)
2. Players can move between rooms freely and skip optional rooms
3. Passage colors indicate room type:
   - **Grey** — normal combat room
   - **Gold** — treasure room
   - **Red** — next level exit

## Research: The Binding of Isaac Map Generation

Reference: [Dungeon Generation in Binding of Isaac — BorisTheBrave.Com](https://www.boristhebrave.com/2020/09/12/dungeon-generation-in-binding-of-isaac/)

Key points:
- Isaac uses a **grid-based layout** (9×8 grid) where rooms occupy grid cells
- Generation starts from a central room and expands outward using **BFS**
- Rooms connect to adjacent grid cells (up/down/left/right)
- **No loops**: a room is not placed if it would have 2+ existing neighbors (creates branching corridors)
- Boss rooms are placed at the farthest distance from start
- Special rooms (treasure, shop, etc.) are placed after the main path

## Adapted Design for This Project

### Grid Layout
- Use a smaller grid (e.g., 7×7) since levels have 3–5 rooms
- Start room at center of grid
- BFS expansion with branching constraint

### Room Types on Map
- **Normal rooms** (combat) — grey connections
- **Treasure room** — gold connection, placed on a dead-end branch
- **Next level exit** — red connection, placed at farthest point from start

### Map Data Structure
```gdscript
# Stored in GameManager to survive scene reloads
var roguelike_room_map: Array = []  # Array of {grid_pos, type, connections, cleared}
var roguelike_current_map_room: int = 0  # Index into room_map
```

### Minimap UI
- Small grid overlay in corner of screen
- Current room highlighted
- Visited rooms shown, unvisited rooms as outlines
- Colored connections between rooms

### Door System
- Multiple exit doors per room (up to 4: N/S/E/W)
- Each door colored based on destination room type
- Doors appear after room is cleared
- Player walks into a door to navigate to that connected room

## Files Modified
- `scripts/autoload/game_manager.gd` — room map state
- `scripts/levels/roguelike_level.gd` — map generation, multi-door system, minimap UI
- `scripts/components/exit_zone.gd` — door color support
