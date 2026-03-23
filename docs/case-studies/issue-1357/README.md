# Case Study: Issue #1357 — Enemy Cannot Follow Planned Patrol Path (Stuck at Wall)

## Summary

Enemies with patrol behavior get stuck at walls and cannot follow their planned navigation path. The screenshot in the issue shows an enemy pressed against a wall with its computed patrol path (yellow line with waypoint dots) routing through or along a wall, unable to make progress.

## Root Cause Analysis

Three interrelated problems cause the enemy to get stuck:

### 1. Cross-Wall Patrol Point Snapping (Primary Cause)

**File:** `scripts/objects/enemy.gd`, `_process_patrol()` (line ~3997)

Patrol points are snapped to the nearest point on the navigation mesh during the first physics frame. The snap threshold is `path_desired_distance * 2 = 80px`. However, the code only checks **distance** — it does NOT verify there is no wall between the original point and the snapped point.

**Before fix:**
```gdscript
var snapped := NavigationServer2D.map_get_closest_point(nav_map, _patrol_points[i])
if _patrol_points[i].distance_to(snapped) <= snap_thr: _patrol_points[i] = snapped
```

A patrol point that is 50px from a wall can be snapped to a navmesh region on the OTHER side of that wall, making the resulting path physically impossible to follow.

### 2. Wall Avoidance Fighting NavigationAgent2D Direction

**File:** `scripts/objects/enemy.gd`, `_move_to_target_nav()` (line ~4678)

After the NavigationAgent2D computes the optimal direction (which already accounts for walls via the navmesh), `_apply_wall_avoidance()` is applied. The wall avoidance uses 8 raycasts and applies weights of 0.3–0.7 to steer away from walls. When the valid navigation path necessarily runs close to a wall (e.g., through a corridor or around a corner), the wall avoidance can apply up to 70% weight AGAINST the nav direction, effectively overriding the pathfinder and causing the enemy to oscillate or get stuck.

### 3. Stuck Detection Only Advances One Point

**File:** `scripts/objects/enemy.gd`, `_process_patrol()` (line ~4024)

When stuck detection triggers (enemy moves less than 20px in 1.5 seconds), it advances to the next patrol point. However, if the next point is ALSO unreachable (e.g., also snapped across a wall), the enemy gets stuck again immediately and cycles through unreachable points indefinitely.

## Solution

### Fix 1: Raycast Wall Check During Patrol Point Snapping

Added a physics raycast between the original patrol point position and the snapped position. If a wall (collision layer 3) is detected between them, the snap is rejected and the original position is kept.

Also added a post-snap filter that removes patrol points that are too far from the navmesh (>10px), keeping only reachable points.

### Fix 2: Limit Wall Avoidance Override of Navigation Direction

When `_apply_wall_avoidance()` steers the enemy more than 90° away from the NavigationAgent2D's computed direction (dot product < 0), the influence is reduced: 70% nav direction, 30% wall avoidance. This prevents the wall avoidance from completely overriding the pathfinder while still providing collision prevention.

### Fix 3: Skip Consecutive Unreachable Points in Stuck Detection

When stuck detection triggers, the enemy now checks whether the next patrol point is actually reachable (via `_has_nav_path_to()`), and skips consecutive unreachable points until a reachable one is found (bounded by the total patrol point count to prevent infinite loops).

## Update — 2026-03-23: Root Cause Found via Game Log Analysis

### Game Log Evidence (`game_log_20260323_140633.txt`)

The owner provided a game log that revealed the actual bug. Log lines:

```
[Enemy7] Patrol point 0 at (1700, 870) unreachable (dist to navmesh: 1909.7), removed (Issue #1357)
[Enemy7] Patrol point 1 at (1800, 870) unreachable (dist to navmesh: 1999.2), removed (Issue #1357)
[Enemy7] Patrol point 2 at (1600, 870) unreachable (dist to navmesh: 1821.2), removed (Issue #1357)
[Enemy7] Patrol points snapped to navmesh (Issue #1216, #1357: 3 points)
```

All three patrol points were reported as "unreachable" with distances of **1800–2000 pixels** to the nearest navmesh point. This is physically impossible — patrol points are placed within the level area. The diagnosis: **the navmesh had not yet baked when the snap ran**.

### Root Cause: Race Between Navmesh Bake and Enemy Spawn

Level scripts (e.g. `building_level.gd`) call `_setup_navigation()` which uses `await get_tree().physics_frame` before calling `bake_from_source_geometry_data()`. However `_setup_enemy_tracking()` is called immediately after without awaiting the bake. Enemies spawn and start running `_process_patrol()` in the same frame as `_setup_navigation()` is still awaiting.

The previous fix added `Engine.get_physics_frames() > _spawn_physics_frame` (1 frame delay), but baking takes multiple frames. When `map_get_closest_point()` is called on an empty (0-polygon) map, it returns a default/garbage position thousands of pixels away from any patrol point. All patrol points are flagged as unreachable and removed. The enemies then have no valid patrol path and spin/stand still.

### Fix 4: Navmesh Polygon Count Guard

Added a check for `NavigationServer2D.map_get_polygon_count(nav_map) == 0` before running the patrol point snap. If the navmesh has no polygons yet, the snap is deferred to the next frame (returns early without setting `_patrol_points_snapped = true`). Once the navmesh bake completes and polygons are available, the snap runs correctly on the next frame.

**File:** `scripts/objects/enemy.gd`, `_process_patrol()` — added guard in the snap block.

## Files Changed

- `scripts/objects/enemy.gd` — Four targeted fixes in `_process_patrol()` and `_move_to_target_nav()`
- `docs/case-studies/issue-1357/game_log_20260323_140633.txt` — Game log provided by owner showing the bug in action

## Related Issues and Prior Work

- Issue #1119: Original NavigationAgent2D routing implementation (replaced direct direction movement)
- Issue #1216: Patrol point navmesh snapping (introduced the snap logic with distance-only check)
- Issue #1220: Unified patrol movement to use `_move_to_target_nav()` (introduced wall avoidance in patrol)
- Issue #1107: Corner escape mechanism (slide collision normal blending)
- Issue #1146: ORCA avoidance between enemies

## Similar Problems in Game Development

Enemy pathfinding getting stuck at walls is a well-known problem in game AI. Common causes include:

1. **Navmesh-physics misalignment** — The navigation mesh doesn't perfectly match the collision geometry, allowing the pathfinder to route through areas that are physically blocked.
2. **Steering behavior conflicts** — Multiple steering behaviors (pathfinding, wall avoidance, separation, etc.) can produce contradictory forces that cancel out, leaving the agent stationary.
3. **Waypoint validation** — Waypoints placed in the editor may be valid at design time but become unreachable after navmesh baking or level changes.

### Relevant Godot Resources

- [Godot Navigation Server documentation](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationservers.html)
- [NavigationAgent2D avoidance](https://docs.godotengine.org/en/stable/classes/class_navigationagent2d.html)
- `NavigationServer2D.map_get_closest_point()` — Returns nearest point on navmesh but does not consider wall occlusion
