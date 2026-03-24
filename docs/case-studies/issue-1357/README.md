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

**Single minimal fix** in `scripts/objects/enemy.gd`, function `_move_to_target_nav()` (line ~4744):

### Nav Direction Guard
Preserve the original NavigationAgent2D direction before wall avoidance is applied. After wall avoidance, check the dot product between the original nav direction and the adjusted direction. If wall avoidance has steered >90° away (dot product < 0), blend back toward the nav direction (70% nav / 30% avoidance). This prevents wall avoidance from overriding the pathfinder in corridors and doorways — the primary cause of wall-sticking.

```gdscript
var nav_direction := direction
direction = _apply_wall_avoidance(direction)
if nav_direction.dot(direction) < 0.0:
    direction = (nav_direction * 0.7 + direction * 0.3).normalized()
```

**What this does NOT change:**
- Wall avoidance still works normally in open areas (dot product >= 0)
- Patrol point snapping logic is untouched
- No blank lines, comments, or formatting changes
- No changes to any other functions

### Known secondary issues (not fixed here)
- Patrol point snapping on empty navmesh (async bake) — can cause garbage snap positions
- Cross-wall patrol point snapping — no wall-check raycast between original and snapped point

These are deferred to avoid risk of breaking AI behavior.

## Previous Attempts

### PR #1358 (closed)
First attempt with three fixes (nav guard + navmesh polygon guard + wall-check raycast + unreachable point filtering). Owner reported AI was "completely broken."

### PR #1396 first commit
Second attempt with the same three fixes but less patrol filtering. Reverted to single minimal fix after owner feedback.

## Related Issues and Prior Work

- Issue #1107: Machete enemy corner escape (slide collision normals)
- Issue #1119: NavigationAgent2D routing for patrol (replaced direct direction)
- Issue #1216: Patrol point navmesh snapping with threshold
- Issue #1220: Patrol uses `_move_to_target_nav` for wall avoidance
- Issue #1289: Enlarged path_desired_distance during pursuit

## Files

- `game_log_20260323_140633.txt` — Original game log showing patrol point snap failure (1800+px distances)
- `game_log_20260324_062132.txt` — Game log from broken AI build (PR #1358)
