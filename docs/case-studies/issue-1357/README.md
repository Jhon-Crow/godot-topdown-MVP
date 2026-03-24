# Case Study: Issue #1357 — Enemy Cannot Follow Planned Path (Stuck at Wall)

## Summary

Enemies with path-following behavior get stuck at walls and cannot traverse their planned navigation path. The issue affects all movement states (PURSUING, FLANKING, PATROL) — not just patrolling. The screenshot shows an enemy pressed against a wall with its computed path routing along the wall, unable to make progress.

## Root Cause Analysis

Two interrelated problems cause the enemy to get stuck:

### 1. Wall Avoidance Overrides NavigationAgent2D Direction (Primary Cause)

**File:** `scripts/objects/enemy.gd`, `_move_to_target_nav()`

After NavigationAgent2D computes an optimal direction (which already accounts for walls via the navmesh), `_apply_wall_avoidance()` is applied with 8 raycasts. The avoidance weight ranges from 0.3 (far from wall) to 0.7 (close to wall).

When the valid navigation path runs close to a wall (corridors, doorways, corners), wall avoidance applies up to **70% weight against** the nav direction. This effectively overrides the pathfinder, causing oscillation or sticking.

**Before fix (in `_move_to_target_nav`):**
```gdscript
direction = _apply_wall_avoidance(direction)
# Wall avoidance can steer direction >90° away from nav path in tight spaces
```

**After fix:**
```gdscript
var nav_direction := direction
direction = _apply_wall_avoidance(direction)
# If wall avoidance steers >90° from nav path, reduce its influence
if nav_direction.dot(direction) < 0.0:
    direction = (nav_direction * 0.7 + direction * 0.3).normalized()
```

### 2. Patrol Point Snapping on Empty Navmesh

**File:** `scripts/objects/enemy.gd`, `_process_patrol()`

Level scripts bake the navmesh asynchronously (`await get_tree().physics_frame` + `bake_from_source_geometry_data`), but enemies spawn before the bake completes. When `NavigationServer2D.map_get_closest_point()` is called on a navmesh with 0 polygons, it returns garbage positions (1800–2000px away), causing all patrol points to be flagged as unreachable or snapped to wrong locations.

**Evidence from game log (`game_log_20260323_140633.txt`):**
```
[Enemy7] Patrol point 0 at (1700, 870) unreachable (dist to navmesh: 1909.7)
[Enemy7] Patrol point 1 at (1800, 870) unreachable (dist to navmesh: 1999.2)
[Enemy7] Patrol point 2 at (1600, 870) unreachable (dist to navmesh: 1821.2)
```

### 3. Cross-Wall Patrol Point Snapping

The patrol snap code checks distance only — it does NOT verify there is no wall between the original point and the snapped point. A patrol point that is 50px from a wall can be snapped to a navmesh region on the OTHER side of that wall.

## Solution

Three targeted fixes, all in `scripts/objects/enemy.gd`:

### Fix 1: Nav Direction Guard (`_move_to_target_nav`)
Preserve the original NavigationAgent2D direction before wall avoidance. If wall avoidance steers >90° away (dot product < 0), blend back toward the nav direction (70% nav, 30% avoidance). This prevents wall avoidance from overriding the pathfinder in corridors.

### Fix 2: Navmesh Polygon Count Guard (`_process_patrol`)
Before snapping patrol points, check `NavigationServer2D.map_get_polygon_count(nav_map) == 0`. If the navmesh has no polygons yet (bake not complete), return early and retry next frame.

### Fix 3: Wall-Check Raycast for Snap (`_process_patrol`)
Before accepting a snapped patrol point, cast a physics ray between the original and snapped positions on the obstacle layer (mask `0b100`). If the ray hits a wall, keep the original position.

## Previous Attempt (PR #1358)

PR #1358 attempted the same fixes but was rejected because the AI was "completely broken". Analysis of the game log (`game_log_20260324_062132.txt`) from that build shows:
- Level: LabyrinthLevel (5 enemies)
- `has_died_signal=false` for all enemies — enemy script failed to initialize properly
- Game session lasted only 3 seconds before ending

The current fix applies the same logical changes more conservatively, with careful attention to not breaking existing AI behavior.

## Related Issues and Prior Work

- Issue #1107: Machete enemy corner escape (slide collision normals)
- Issue #1119: NavigationAgent2D routing for patrol (replaced direct direction)
- Issue #1216: Patrol point navmesh snapping with threshold
- Issue #1220: Patrol uses `_move_to_target_nav` for wall avoidance
- Issue #1289: Enlarged path_desired_distance during pursuit

## Files

- `game_log_20260323_140633.txt` — Original game log showing patrol point snap failure (1800+px distances)
- `game_log_20260324_062132.txt` — Game log from broken AI build (PR #1358)
