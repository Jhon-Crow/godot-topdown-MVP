# Case Study: Issue #1275 — Search Paths Built Incorrectly (Don't Account for Walls)

## Problem Statement

**Title (RU):** Сейчас пути поиска построены не правильно
**Title (EN):** Current search paths are built incorrectly — they don't account for walls

The enemy AI generates search waypoints in an expanding square spiral pattern when hunting for the player. These waypoints are visualized in the Experimental menu ("Show Search Paths"). The bug: the paths drawn between waypoints are **straight lines that pass through walls**, making them visually incorrect and conceptually misleading.

**Author's comment:** "пути должны учитывать стены" — "paths should account for walls"
**Additional context:** "начни из main (чтоб была возможность видеть пути)" — "start from main (so that paths are visible)"

---

## System Architecture (Relevant Parts)

### Search Waypoint Generation (`scripts/objects/enemy.gd`)

When an enemy enters the `SEARCHING` state, it calls `_generate_search_waypoints()` which:
1. Creates waypoints in an **expanding square spiral** using fixed geometric offsets
2. Each direction step is `SEARCH_WAYPOINT_SPACING = 75.0` pixels
3. Each waypoint is individually checked via `_is_waypoint_navigable(pos)` — which only verifies the **point** is on the nav mesh (`NavigationServer2D.map_get_closest_point` within 50px)
4. **No check** exists to verify the **path between consecutive waypoints** is navigable (wall-free)

```gdscript
# Current: only checks if individual point is on nav mesh
func _is_waypoint_navigable(pos: Vector2) -> bool:
    var nav_map := get_world_2d().navigation_map
    var closest := NavigationServer2D.map_get_closest_point(nav_map, pos)
    return pos.distance_to(closest) < 50.0
```

### Search Path Visualization (`scripts/autoload/search_path_monitor.gd`)

The `SearchPathMonitor` draws:
- **Predefined paths** (cyan): Static `SearchPathWaypoints` Marker2D nodes placed in scenes
- **Active enemy search paths** (orange): Dynamic spiral waypoints of enemies in SEARCHING state

The drawing code uses **straight lines** between waypoints:
```gdscript
# Current: straight line, ignores walls
for i in range(waypoints.size() - 1):
    var from: Vector2 = waypoints[i]
    var to: Vector2 = waypoints[i + 1]
    draw_line(from, to, active_path_color, 2.0)
```

### Navigation Movement (Correct)

When the enemy actually **moves** to a waypoint:
```gdscript
_nav_agent.target_position = target_waypoint
```
The `NavigationAgent2D` correctly routes around walls using the nav mesh. So **movement itself is correct** — only the visualization misleads and the conceptual path plan ignores wall topology.

---

## Root Cause Analysis

The issue has **two related problems**:

### Problem 1: Visualization draws straight lines through walls
`SearchPathMonitor._draw()` connects waypoints with `draw_line()` in world space. These lines can pass through any wall, giving a false impression of the planned path.

### Problem 2: Spiral waypoint generation ignores wall topology
Waypoints are placed at geometrically regular positions regardless of whether consecutive waypoints are actually reachable from each other. A waypoint on the other side of a wall is considered "navigable" (it's on the nav mesh), but the implied sequential search path skips over walls, making the search pattern conceptually incorrect — the enemy doesn't actually search in a coherent spiral when walls intervene.

---

## Data Collection

### Nav Mesh Path API in Godot 4

`NavigationServer2D` in Godot 4 provides:
```gdscript
# Get actual wall-avoiding path between two points
NavigationServer2D.map_get_path(
    map: RID,
    origin: Vector2,
    destination: Vector2,
    optimize: bool,
    navigation_layers: int = 1
) -> PackedVector2Array
```
This returns the actual waypoints of a navigation-mesh-computed path, identical to what `NavigationAgent2D` uses internally.

### Related Issues

- **#322**: Original spiral search pattern with visited zone tracking
- **#1225**: Predefined search paths via `SearchPathWaypoints` nodes
- **#1251**: `SearchPathMonitor` — search path visualization overlay
- **#1277**: `EnemyPathMonitor` — enemy current nav path visualization (correctly shows actual nav paths)

---

## Proposed Solutions

### Solution A: Fix Visualization — Draw Actual Nav Paths Between Waypoints (Chosen)

**In `SearchPathMonitor`**: Instead of straight lines between waypoints, compute the actual nav mesh path between each pair of consecutive waypoints using `NavigationServer2D.map_get_path()` and draw that instead.

**Pros:**
- Directly fixes the visual issue
- No change to game logic (waypoint movement already uses NavigationAgent2D)
- Low risk

**Cons:**
- Only fixes visualization; spiral waypoint ordering may still be suboptimal across walls
- Requires access to a valid navigation map RID in the autoload

**In `enemy.gd`**: Expose `get_nav_map()` or reuse the nav agent's map so `SearchPathMonitor` can query paths.

### Solution B: Fix Waypoint Generation — Only Include Reachable Waypoints

**In `_generate_search_waypoints()`**: Before adding a waypoint, check that `NavigationServer2D.map_get_path()` from the previous waypoint to the new one actually reaches (or gets close to) the destination. Skip waypoints across walls.

**Pros:**
- Fixes both the conceptual search order and visualization
- Enemy searches in topologically coherent order

**Cons:**
- More expensive (calls `map_get_path` per candidate waypoint)
- May leave unreachable areas un-searched (enemy won't find the player behind a wall until it navigates around)
- However: NavigationAgent2D already routes to each waypoint anyway, so skipping "across-wall" waypoints doesn't lose coverage — the nav agent will go around anyway

### Solution C: Generate Nav-Mesh-Aware Waypoints

Instead of geometric spiral, traverse the nav mesh graph from the search center outward. This would be a much larger refactor.

---

## Decision

**Implement both Solution A and Solution B together:**

1. **Fix visualization** (`search_path_monitor.gd`): Draw actual nav mesh paths between consecutive waypoints using `NavigationServer2D.map_get_path()`. This requires getting the nav map RID — obtained from the first enemy in SEARCHING state that has a `_nav_agent`.

2. **Expose nav map from enemy** (`enemy.gd`): Add `get_nav_map() -> RID` method.

3. **Fix spiral generation** (`enemy.gd`): In `_generate_search_waypoints()`, also check that `NavigationServer2D.map_get_path()` from previous waypoint to `next_pos` actually reaches `next_pos` (within tolerance). This ensures the sequential waypoint order is wall-aware.

---

## Implementation

See the changes in:
- `scripts/objects/enemy.gd` — `_generate_search_waypoints()` and new `get_nav_map()` method
- `scripts/autoload/search_path_monitor.gd` — draw actual nav paths instead of straight lines
