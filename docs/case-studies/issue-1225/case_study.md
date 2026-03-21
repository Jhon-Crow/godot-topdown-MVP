# Case Study: Issue #1225 — Optimizing Enemy Search Movement with Predefined Patrol Paths

## Problem Statement

The issue requests optimization of enemy search movement on 2D maps by pre-planning search paths.

**Original issue (Russian):** "на 2d карте вполне можно заранее запланировать пути поиска. то есть путь поиска изначально прописан на карте, он начинает проходиться врагами в зависимости от положения врага (с ближайшей точки пути) до предполагаемой позиции игрока (ближайшей точки к этой позиции) и так далее пока игрок не обнаружен. при этом путь поиска должен выглядеть как обход комнаты и всех препятствий в ней, а затем переход к другой комнате (например это можно сделать с помощью узловых точек на входах в комнату). реализуй это для карты Здание для теста."

**Translation:** "On a 2D map, search paths can be pre-planned. The search path is defined in the map from the start. Enemies traverse it starting from the nearest point to their current position, toward the expected player position (nearest path point to that position), and so on until the player is detected. The path should look like an orderly patrol of each room covering all obstacles, then a transition to the next room (e.g. via node-points at room entrances). Implement this for the Building test map."

## Current System Analysis

### Existing Search Behavior (`_process_searching_state`, enemy.gd:2287)

The current SEARCHING state uses a **dynamic expanding spiral** algorithm:
- Starts at last known player position
- Expands in a square spiral pattern (N, E, S, W directions)
- Generates waypoints dynamically at runtime
- No pre-defined knowledge of the map layout
- Radius expands from `SEARCH_INITIAL_RADIUS=100px` to `SEARCH_MAX_RADIUS=2000px`

**Problems with current approach:**
1. Generates random-looking movement that doesn't respect room boundaries
2. Enemies may search in walls or backtrack through areas already visited
3. Does not efficiently cover a building's rooms in logical order
4. High CPU cost: every search waypoint is validated against NavigationServer2D
5. No sense of building topology (rooms, corridors, doorways)
6. Enemies start from last known player position, not intelligently searching from current position along a logical path

### Existing Patrol System

Enemies already have a `PATROL` behavior mode (`enemy.gd:26-28`, `idle_state.gd:42`):
- Uses `patrol_offsets` (Array[Vector2]) relative to initial position
- Simple back-and-forth between 2+ patrol points
- `_setup_patrol_points()` converts offsets to absolute positions

### Building Level Layout (`BuildingLevel.tscn`)

The Building level (~2400×2000px) has these named areas:
- **OFFICE 1** (top-left, ~80,80 → 500,688): contains Desk1, Desk2
- **OFFICE 2** (left-center, ~524,712 → 912,1000): contains Table1
- **CONFERENCE ROOM** (top-right, ~1388,80 → 2448,600): contains Cabinet1, Cabinet2, Desk3, Desk4
- **BREAK ROOM** (right-center, ~1388,800 → 2448,1188): contains Table2
- **SERVER ROOM** (bottom-right, ~1700,1212 → 2448,2048): contains Table3, Cabinet3
- **STORAGE** (bottom-left, ~80,1612 → 500,2048): contains StorageCrate1, StorageCrate2
- **MAIN HALL** (center-bottom, ~912,1400 → 1488,2048): contains HallTable
- **Corridor** connecting OFFICE 1 and OFFICE 2 to CONFERENCE ROOM and BREAK ROOM (~924,700 → 1376,1012)

**Key doorway points (approx):**
- Office 1 ↔ Corridor: x≈512, y≈550 (gap between Room1_WallRight at y=200..600 and Room2_WallLeft at y=800..1000)
- Office 2 ↔ Corridor: x≈512, y≈900 (gap in wall)
- Corridor ↔ Conference Room: x≈1376, y≈300 (gap in Room3_WallLeft at y=200..600)
- Corridor ↔ Break Room: x≈1376, y≈950 (gap in Room4_WallLeft at y=800..1000)
- Main Hall ↔ Storage: x≈500, y≈1700 (below StorageRoom_WallRight at x=512)
- Main Hall → lower section: x≈1200, y≈1400 (above MainHall_WallTop)

## Proposed Solution

### Approach: Predefined `SearchPathWaypoints` Node in Scene

The most fitting approach for this codebase is to add a **`SearchPathWaypoints`** marker node to the Building level scene. This node contains a set of pre-placed `Marker2D` waypoints that form a logical patrol search path through all rooms.

When an enemy enters the SEARCHING state, instead of generating a spiral, it:
1. Looks for a `SearchPathWaypoints` node in the scene tree
2. Finds the nearest waypoint to its current position
3. Finds the nearest waypoint to the last known player position (search target)
4. Traverses waypoints from its nearest to the player-position nearest in path order
5. Continues cycling the path if player is not found

This integrates naturally with the existing:
- `NavigationAgent2D` for obstacle avoidance
- `_search_waypoints: Array[Vector2]` (already exists)
- `_process_searching_state()` (continues to work the same way)

### Implementation Plan

1. **Add export var** `search_path_waypoints_path: NodePath` to `enemy.gd`
2. **Populate `_search_waypoints`** from the referenced node if it exists (skip existing spiral)
3. **Add `SearchPathWaypoints` Node2D** containing `Marker2D` children to `BuildingLevel.tscn`
4. **Set the node path** on enemies in `BuildingLevel.tscn`

### Alternative Approaches Considered

| Approach | Pros | Cons |
|---|---|---|
| **Predefined waypoint path (chosen)** | Designer control, logical room coverage, zero runtime cost | Requires manual placement per level |
| Dynamic spiral (existing) | Works on any map, no placement needed | Doesn't respect rooms, looks random |
| NavMesh graph traversal | Automatic, topology-aware | Complex to implement in Godot 4 GDScript |
| Room-node graph + BFS | Very logical, room-aware order | Requires significant architectural change |

## References

- [Godot 4 NavigationAgent2D docs](https://docs.godotengine.org/en/stable/classes/class_navigationagent2d.html)
- [Patrol/Waypoint systems in Godot](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_introduction_2d.html)
- Existing issue #322 (SEARCHING state), #330 (never return to IDLE after combat)
- Existing issue #405 (search continues indefinitely for engaged enemies)
