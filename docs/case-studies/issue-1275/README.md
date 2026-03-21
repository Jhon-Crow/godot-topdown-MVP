# Issue #1275 — Search Paths Don't Account for Walls

**Title (RU):** сейчас пути поиска построены не правильно
**Title (EN):** Search paths are currently built incorrectly — they must account for walls

**Status:** Fixed in PR #1276
**Screenshot:** See `screenshot.png` (from issue)

---

## Problem Description

When an enemy enters the `SEARCHING` state, it generates a spiral search pattern using
`_generate_search_waypoints()`. The generated waypoints are connected and navigated in order.

**The bug:** The path lines drawn between consecutive waypoints pass straight through walls.
This happens because the waypoint generator only checks whether the *destination point* is on
the navigation mesh — it does NOT check whether a navigable path exists *between* two points.

### Visual Evidence

The issue screenshot shows orange lines (debug visualization of the search path) crossing
directly through walls in the "OFFICE 2" room. Enemies would attempt to walk along these
impossible straight-line segments.

---

## Root Cause Analysis

### File: `scripts/objects/enemy.gd`

#### `_is_waypoint_navigable()` — line ~2277 (point-only check)
```gdscript
func _is_waypoint_navigable(pos: Vector2) -> bool:
    var nav_map := get_world_2d().navigation_map
    var closest := NavigationServer2D.map_get_closest_point(nav_map, pos)
    return pos.distance_to(closest) < 50.0
```

This only verifies that the **destination position** is on the nav mesh (≤ 50 px from the
closest nav-mesh point). It does NOT check whether the path from the *current spiral position*
to `pos` is navigable — i.e., whether there are walls in between.

#### `_generate_search_waypoints()` — line ~2246 (the spiral generator)
```gdscript
var next_pos := current_pos + offset  # offset = N/E/S/W step of leg_length px
if _is_waypoint_navigable(next_pos) and not _is_zone_visited(next_pos):
    _search_waypoints.append(next_pos)
```

The spiral adds `next_pos` to the waypoint list if the point itself is on the nav mesh.
However, `current_pos` advances to `next_pos` **even when `next_pos` is rejected** (wall/visited).
This means the spiral "teleports" through walls on the nav-mesh level: a later step may land
in a different room that is reachable on the mesh but unreachable from the enemy's actual position
without crossing a wall.

### Core Problem

**`_is_waypoint_navigable` is a point-presence check, not a path-connectivity check.**

A position can be on the nav mesh (navigable in isolation) while still being unreachable from
the enemy's current position because walls block the straight path between rooms.

The spiral's greedy step-advance pattern (`current_pos = next_pos` unconditionally) compounds
the issue: the "current position" in the spiral diverges from the enemy's actual position over
time, generating waypoints in unreachable rooms.

---

## Solution

### Approach: Add a path-connectivity check using `NavigationServer2D.map_get_path()`

Godot 4's `NavigationServer2D` exposes:
```gdscript
NavigationServer2D.map_get_path(
    map: RID,
    origin: Vector2,
    destination: Vector2,
    optimize: bool,
    navigation_layers: int = 1
) -> PackedVector2Array
```

If no path exists between `origin` and `destination`, it returns an **empty array**.

#### New helper: `_is_path_navigable(from_pos, to_pos)`

```gdscript
func _is_path_navigable(from_pos: Vector2, to_pos: Vector2) -> bool:
    var nav_map := get_world_2d().navigation_map
    var path := NavigationServer2D.map_get_path(nav_map, from_pos, to_pos, true)
    return path.size() >= 2
```

- `path.size() >= 2` means at least a start and an end point → a valid path exists.
- `path.size() == 0` means no path → blocked by walls or off-mesh.
- `path.size() == 1` means start == end (already there).

#### Fixed `_generate_search_waypoints()`

The waypoint is only added if:
1. The destination is on the nav mesh (`_is_waypoint_navigable`), AND
2. A navigable path exists from the **enemy's actual position** to the waypoint (`_is_path_navigable`).

The `current_pos` spiral-advance must only move forward when the step is to a position that is
on the nav mesh (so the spiral doesn't cross walls on the spiral-tracking level either).

---

## Alternative / Related Approaches

| Approach | Notes |
|----------|-------|
| `NavigationServer2D.map_get_path()` | **Chosen.** Returns empty if no path. O(N) per candidate waypoint. |
| `NavigationAgent2D.is_navigation_finished()` after setting target | Requires an existing NavigationAgent2D; introduces frame-delayed state mutation. Not suitable for bulk offline waypoint generation. |
| Raycast-based wall check (`_has_clear_path_to`) | Only checks line-of-sight, not nav-mesh connectivity. Fails for paths that go around corners (reachable via nav mesh but not via straight ray). |
| Pre-authored waypoints (`SearchPathWaypoints`, Issue #1225) | Already supported as an opt-in override. Solves the problem by design for levels that have them. Does not fix the procedural spiral for levels without them. |
| Passage waypoints (`_passage_waypoints`, Issue #1226) | Already used in pursuit/cover finding. Not connected to spiral waypoint generation. |

---

## Files Changed

- `scripts/objects/enemy.gd`:
  - Added `_is_path_navigable(from_pos, to_pos)` helper (beside `_is_waypoint_navigable`)
  - Modified `_generate_search_waypoints()` to validate path connectivity per waypoint
  - Ensured `current_pos` advance in spiral only moves to nav-mesh points

- `tests/unit/test_search_path_wall_awareness.gd`:
  - New unit tests for the stub logic of path-connectivity filtering

---

## References

- Godot 4 NavigationServer2D docs: `map_get_path` returns `PackedVector2Array`
- Issue #322: Original SEARCHING state implementation
- Issue #354: Stuck detection added to SEARCHING
- Issue #1225: Pre-authored SearchPathWaypoints for manual override
- Issue #1226: Passage waypoints for room-to-room navigation
