# Case Study: Issue #1226 — Fix AI Transitions Between Rooms

## Problem Statement

Enemies in the Building map failed to reliably navigate to the player when the player was in a different room. The `_find_pursuit_cover_toward_player()` function uses raycasting to find nearby obstacles as cover positions, scoring them by straight-line distance progress toward the player. When the player is behind a wall in another room, this cover-finding heuristic stalls: every candidate cover position found via local raycasts reduces the *straight-line* distance to the player, but the enemy cannot cross walls, so it oscillates between covers in its own room and never commits to going through a doorway.

## Root Cause Analysis

### Navigation Architecture
The building level uses Godot 4's `NavigationAgent2D` + `NavigationRegion2D` for actual pathfinding. The navigation mesh is baked from physics collision geometry (layer 4 = walls), producing a correct walkable mesh that includes all doorways and corridors.

However, **the pursuit AI does NOT use NavigationAgent2D to find cover positions**. Instead, `_find_pursuit_cover_toward_player()` (enemy.gd:3110) works as follows:
1. Casts 16 rays in all directions from the enemy position.
2. For each collision, proposes `collision_point + collision_normal * 35.0` as a cover position.
3. Filters/scores these by: (a) does it bring the enemy closer to player (straight line)? (b) is it reachable by line-of-sight raycast?

The problem with step (b) is that `_can_reach_position()` (enemy.gd:3214) casts a **single ray** from the enemy to the candidate cover to check for walls. This is a local, direct check — it cannot verify that a doorway route exists.

When an enemy is in Office 1 (top-left) and the player is in the Main Hall (bottom), all candidate covers found via local raycasting are within Office 1. They all pass the straight-line distance filter (they do bring the enemy a tiny bit closer to the target), but the enemy never approaches the actual doorway because:
- There are no obstacles near the doorway to cast behind.
- The minimum progress fraction (`PURSUIT_MIN_PROGRESS_FRACTION = 0.10`) may filter out small advances.
- Once the enemy exhausts local covers, it enters the approach phase, but then uses wall-avoidance movement that can get stuck near the doorway if there is no visible cover to commit to.

### Why Explicit Passage Waypoints Solve This

Explicit `Marker2D` passage waypoints at every doorway act as guaranteed routing anchors:
- When the enemy cannot find a valid cover closer to the player, it checks passage waypoints.
- The nearest passage waypoint that brings the enemy closer to the player is selected as an intermediate target.
- The enemy navigates to the passage waypoint using the nav mesh (`NavigationAgent2D`), which guarantees a valid cross-room path.
- Once through the doorway, the enemy re-runs `_find_pursuit_cover_toward_player()` in the new room.

This is the same pattern used in commercial games (e.g., Halo's nav-hint nodes, FEAR's tactical action points) and recommended in Godot navigation documentation.

## Building Layout

```
+----+--------+-----+------------------+
| O1 |        | COR |    CONFERENCE    |
|    |  OPEN  |     |    ROOM (R3)     |
+----+        +--+--+                  |
             R2  |  +------------------+
     OFFICE 2    |  |   BREAK ROOM(R4) |
                 |  |                  |
                 |  +------+--+--------+
     [LOBBY]     |         |  | SERVER |
  LobD  LobD     |         |R5| ROOM   |
+-[200]-[200]-+--+-------+ |  |        |
|  STORAGE    |  MAIN     +--+--------+
|             |  HALL                  |
+-------------+------------------------+
```

### Doorway Positions (passage waypoints)

| ID | Description | Position |
|----|-------------|----------|
| P1 | Office1 → Corridor (top gap) | (512, 650) |
| P2 | Office2 right → Corridor | (950, 700) |
| P3 | Corridor → Conference Room (Room3) | (1376, 500) |
| P4 | Corridor → Break Room (Room4) | (1376, 900) |
| P5 | Break Room → Server Room | (1688, 1194) |
| P6 | Left passage → Lobby | (140, 1400) |
| P7 | Mid-left passage → Lobby | (450, 1400) |
| P8 | Mid-right passage → Lobby | (750, 1400) |
| P9 | Corridor → Main Hall | (950, 1400) |
| P10 | Storage Room entrance (left) | (200, 1600) |
| P11 | Storage Room entrance (right) | (550, 1750) |
| P12 | Server Room lower left | (1700, 1750) |

## Solution Design

### 1. Scene Changes: `BuildingLevel.tscn`
Add a `PassageWaypoints` `Node2D` container as a child of `Environment`, with `Marker2D` children at each doorway position. These are purely logical — no collision, no visual.

### 2. Level Script: `building_level.gd`
In `_setup_navigation()` (or a new `_setup_passage_waypoints()`), collect all `Marker2D` children of `PassageWaypoints` and pass their global positions to each enemy via `set_passage_waypoints()`.

### 3. Enemy AI: `enemy.gd`
Add:
- `var _passage_waypoints: Array[Vector2] = []` — list of passage positions provided by the level.
- `func set_passage_waypoints(waypoints: Array[Vector2]) -> void` — called by the level to register waypoints.
- Modify `_find_pursuit_cover_toward_player()`: if no valid cover is found, find the closest passage waypoint that brings the enemy closer to the player. Set `_pursuit_next_cover` to that waypoint.

This minimal change preserves all existing cover logic and only falls back to passage waypoints when the cover search fails.

## Known Art / Prior Work

- **Halo series**: Uses "pathing hints" (nav nodes at doorways, cover points, flanking positions) that the HKBT AI reads to build routes through complex geometry.
- **FEAR**: Tactical Action Points (TAPs) are placed by level designers at every cover/navigation decision point.
- **Unreal Engine's EQS**: Environment Query System allows AI to query for nav-mesh reachable points at runtime; explicit hint nodes reduce query cost.
- **Godot 4 documentation**: Recommends using `NavigationLink2D` or explicit waypoints for multi-zone navigation where pathfinding quality may degrade.
- **Issue #93 in this repo**: Previous fix for pursuit stalling along long walls (minimum progress fraction) — this issue is the room-crossing variant of the same problem.

## Test Plan
1. Place player in Main Hall (y≈1250) and have enemies from Office1 (y≈300) pursue — they must reach the player.
2. Place player in Conference Room (x≈1800, y≈300) and have enemies from Storage Room pursue — they must traverse the full building.
3. Verify enemies still find cover correctly within the same room (regression check).
