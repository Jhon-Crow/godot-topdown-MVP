# Case Study: Issue #1451 — Isaac-Style Level Generation Improvements

## Issue Summary

**Title:** fix уровни в рогалик
**Requirements:**
1. Level generation logic like The Binding of Isaac — exit should be in the farthest room
2. Room clearing mechanic — can only exit a room after clearing all enemies

## Background: The Binding of Isaac Level Generation

The Binding of Isaac (2011, Edmund McMillen) uses a procedural dungeon generation
system that has become a reference design for roguelike room-based games.

### Key Characteristics

1. **Grid-based map**: Rooms are placed on a 2D grid, forming a tree-like structure
2. **BFS expansion**: Rooms are added by expanding outward from a central start room
3. **Branching constraint**: New rooms can only be placed adjacent to cells with at most
   1 existing neighbor, preventing dense clusters and creating branching paths
4. **Boss room placement**: The boss room is placed at the dead-end with the **longest
   graph path** (BFS distance) from the start room — not Euclidean distance
5. **Door locking**: When the player enters a room with enemies, all doors physically
   close. They reopen only after all enemies are eliminated

### Boss Room Placement — Graph Distance vs Euclidean Distance

A critical detail in Isaac's algorithm: the boss room is placed using **graph distance**
(number of rooms the player must traverse), not **Euclidean distance** on the grid.

Example showing why this matters:
```
Grid layout:
  S - A - B
      |
      C - D - E (dead end)

Room E: Euclidean distance = sqrt(8) ≈ 2.83 grid units
Room B: Euclidean distance = 2 grid units

But BFS path distance:
Room E: 4 rooms from S (S→A→C→D→E)
Room B: 2 rooms from S (S→A→B)
```

The boss should be at E (longer path = more gameplay), not B.

## Existing Codebase Analysis

### What Was Already Implemented (Issue #1399)

The roguelike mode already had an Isaac-inspired branching map system:
- Grid-based BFS room expansion from center
- Branching constraint (max 1 existing neighbor)
- Dead-end detection for special room placement
- Door zones with colored indicators (ВЫХОД/EXIT for exit, СОКРОВ./TREASURE, etc.)
- Minimap showing room connections

### Identified Issues

#### 1. Exit Placement Used Euclidean Distance

```gdscript
# BEFORE (roguelike_level.gd, ~line 502):
dead_ends.sort_custom(func(a, b):
    var da: float = Vector2(rooms[a]["grid_pos"]).distance_to(Vector2(start_pos))
    var db: float = Vector2(rooms[b]["grid_pos"]).distance_to(Vector2(start_pos))
    return da > db
)
```

This sorted dead ends by straight-line distance on the grid, which can place the
exit at a room that's physically far but only 1-2 rooms away via the graph.

#### 2. No Physical Door Blocking During Combat

Door zones were hidden and disabled during combat, but the **doorway gaps in walls**
remained physically open. The player could walk into the gap area — nothing would
happen (the door zone transition wouldn't fire), but there was no collision barrier
preventing the player from standing in the doorway or partially leaving.

In Isaac, doors are sealed with physical barriers during combat.

## Implementation

### Fix 1: BFS Path Distance for Exit Placement

Added a `_bfs_distances()` static helper that performs BFS from the start room and
returns a dictionary mapping each room index to its shortest path distance.

```gdscript
static func _bfs_distances(rooms: Array, source: int) -> Dictionary:
    var dist: Dictionary = {source: 0}
    var queue: Array = [source]
    var head: int = 0
    while head < queue.size():
        var current: int = queue[head]
        head += 1
        for neighbor in rooms[current]["connections"]:
            if not dist.has(neighbor):
                dist[neighbor] = dist[current] + 1
                queue.append(neighbor)
    return dist
```

Dead ends are now sorted by BFS distance (descending), ensuring the exit is placed
at the room requiring the most traversal.

### Fix 2: Physical Door Barriers During Combat

Added Isaac-style door locking:

- **`_door_barriers`**: Array tracking `StaticBody2D` barrier nodes placed in doorway gaps
- **`_create_door_barriers()`**: Creates barriers in all doorway gaps when entering an
  uncleared combat room. Uses collision layer 4 (obstacles) and red-tinted visuals
- **`_remove_door_barriers()`**: Removes barriers with fade-out animation when all
  enemies are eliminated or become pacifist

Flow:
1. Player enters combat room → barriers created → doors physically sealed
2. Player clears all enemies → barriers removed → door zones activated → player can leave

Rooms that skip barriers:
- Start room (no enemies)
- Already-cleared rooms (revisiting)
- Treasure rooms (no enemies)

## References

- The Binding of Isaac Wiki — Floor Generation
- GDC 2014 — "Designing Procedural Levels for The Binding of Isaac" (Tommy Refenes)
- Existing Issue #1399 implementation (branching room map)
- Existing Issue #1061 implementation (roguelike mode foundation)
