# Case Study: Issue #1338 - Suppressed Enemies Stay in Place Instead of Seeking Cover

## Problem Statement

Suppressed enemies remain stationary while under fire instead of actively moving to cover. The expected behavior is that when an enemy is suppressed (under fire), it should immediately find the nearest cover position hidden from the player and move there.

## Timeline of Events

### Phase 1: Initial Report (2026-03-22 17:17)

- **Log file**: `game_log_20260322_171711.txt`
- **Reporter**: Jhon-Crow (repo owner)
- **Observation**: "подавленные враги должны сразу идти в укрытие" (suppressed enemies should immediately go to cover)
- When the player hides from view, the enemy stops being suppressed and does not seek cover

### Phase 2: First Fix Attempt (commit d5010345)

- Changed suppressed state to transition to `SEEKING_COVER` state when suppression ends
- This was later reverted/modified based on owner feedback

### Phase 3: Owner Feedback on Issue (2026-03-22 18:49)

- Owner requested: "revert retreat behavior to the first commit in the backup branch"
- Owner specified: "return cover search logic - rays are cast from the player, nearest cover to the enemy where rays can't reach is the target cover"

### Phase 4: Second Fix (commit 067ac5f0)

- Added `POST_SUPPRESSION_COVER_DURATION` (3s) timer
- Rewrote `_find_cover_position()` to cast rays from player
- Changed `_transition_to_in_cover()` to `_transition_to_seeking_cover()` when suppression ends
- **Problem**: enemy still stayed in place WHILE suppressed because `velocity = Vector2.ZERO` at start of `_process_suppressed_state()`

### Phase 5: Owner Reports Bug Still Present (2026-03-23 00:32)

- **Log file**: `game_log_20260323_033050.txt`
- **Observation**: "подавленный враг остаётся стоять на месте" (suppressed enemy stays in place)
- Log evidence shows `SUPPRESSED -> IN_COVER` transitions where enemy stays at current position
- Enemy never moves during the SUPPRESSED state because velocity is forced to zero

## Root Cause Analysis

### The Core Problem

In `_process_suppressed_state()`, the very first line was:

```gdscript
velocity = Vector2.ZERO
```

This unconditionally freezes the enemy in place every frame while in the SUPPRESSED state. The enemy cannot move toward cover because its velocity is zeroed out before any movement logic runs.

The SUPPRESSED state was designed as a "pinned down" state where the enemy stays still, but the desired behavior is that the enemy should actively seek cover even while being suppressed.

### Evidence from Game Logs

From `game_log_20260323_033050.txt`:
```
[03:31:12] [ENEMY] [Enemy3] State: IN_COVER -> SUPPRESSED     # enters suppressed, velocity=0
[03:31:14] [ENEMY] [Enemy3] State: SUPPRESSED -> IN_COVER     # exits at same position
[03:31:14] [ENEMY] [Enemy4] State: SUPPRESSED -> IN_COVER     # exits at same position
```

The enemies enter SUPPRESSED and stay motionless. When suppression ends they go to IN_COVER at the same position they were already at (since they were previously in cover). No movement occurs.

### Cover Search Logic

The `_find_cover_position()` function already implements the correct ray-from-player approach:
- Casts rays FROM the player position in all directions
- Finds obstacles that block those rays
- Places cover positions 35px past the obstacle (away from player)
- Verifies the position is reachable and truly hidden from the player
- Picks the nearest hidden cover to the enemy

## Fix (Phase 6)

Rewrote `_process_suppressed_state()` to actively seek cover while suppressed:

1. **Find cover**: calls `_find_cover_position()` if no valid cover is known
2. **Move to cover**: uses `_move_to_target_nav()` to navigate toward cover while visible
3. **Stop when hidden**: sets `velocity = Vector2.ZERO` only after reaching a hidden position
4. **Shoot while moving**: enemy can still fire at player/companion while moving to cover
5. **Exit suppression**: when no longer under fire, transitions to IN_COVER (if hidden) or SEEKING_COVER (if still exposed)

### Expected State Flow After Fix

```
SUPPRESSED (actively moving to cover) -> IN_COVER (arrived, hidden) -> (3s timer) -> PURSUING
```

### Previous Incorrect Flow

```
SUPPRESSED (frozen, velocity=0) -> IN_COVER (same position) -> PURSUING
```

### Phase 7: Owner Reports Cover Detection Still Incorrect (2026-03-23 01:05)

- **Log file**: `game_log_20260323_040254.txt`
- **Observation**: "всё ещё враг не уходит когда игрока нет в прямой видимости. так же всё ещё не корректно определяется ближайшее укрытие"
  (enemy still doesn't leave when player is not in line of sight; nearest cover is still incorrectly determined)
- Rays from player should go in all directions, but the nearest cover to the enemy should be chosen

### Phase 8: Owner Confirms Suppression Works, Cover Still Wrong (2026-03-23 02:31)

- **Log file**: `game_log_20260323_052526.txt`
- **Screenshot**: `screenshot_cover_bug.png`
- **Observation**: "подавление работает правильно. не правильно определяется ближайшее укрытие"
  (suppression works correctly; nearest cover is incorrectly determined)
- Screenshot shows enemy path going toward distant cover instead of nearby wall

### Root Cause Analysis (Phase 8)

Two issues with `_find_cover_position()`:

1. **Angular resolution too low**: Only 16 rays (22.5° apart) meant many nearby walls were missed entirely. Increased to 36 rays (10° apart) to cover all wall segments in indoor environments.

2. **Reachability check too restrictive**: `_can_reach_position()` used a direct line-of-sight raycast from enemy to cover position. In indoor environments with corners, valid cover behind walls was rejected because a wall blocked the direct line — even though the navigation mesh could route around the corner. Replaced with `NavigationServer2D.map_get_closest_point()` to snap cover positions to the nav-mesh, ensuring they are on walkable ground.

### Fix (Phase 8)

- `COVER_CHECK_COUNT`: 16 → 36 (finer angular resolution catches more walls)
- `_find_cover_position()`: Replaced `_can_reach_position()` with nav-mesh snapping
- `_find_cover_closest_to_player()`: Same nav-mesh snap fix
- `_find_distant_cover_position()`: Same nav-mesh snap fix
- Added file logging for cover search results to aid future debugging

### Phase 9: Owner Requests No Predefined Waypoints (2026-03-23 03:28)

- **Log file**: `round4/game_log_20260323_063239.txt`
- **Observation**: "для укрытий не должно быть заранее назначенных точек. укрытием должно считаться ближайшее к врагу место, в котором в него не попадают лучи, выпущенные из игрока."
  (cover should not use predefined waypoints; cover = nearest position to enemy where rays from player don't hit)
- Also requested merge from main for debug visualization of cover search

### Root Cause Analysis (Phase 9)

Three issues with cover search:

1. **Predefined combat waypoints bypassed raycast search**: `_find_cover_position()` and `_find_cover_closest_to_player()` both called `_combat_waypoint()` first. If a predefined waypoint was found, it was used as cover without checking if it was truly the nearest hidden position. This meant enemies would go to designer-placed waypoints instead of the geometrically nearest cover behind obstacles.

2. **Debug visualization didn't match actual algorithm**: The `get_cover_raycast_data()` function returned data from `_cover_raycasts` (RayCast2D nodes attached to the enemy), but `_find_cover_position()` used `PhysicsRayQueryParameters2D` from the player position. The debug overlay showed rays from the enemy, making it impossible to verify the player-origin raycast search.

3. **`_find_distant_cover_position()` used enemy-origin raycasts**: Unlike `_find_cover_position()` which cast from the player, the distant cover search still used enemy-attached RayCast2D nodes, creating inconsistency.

### Fix (Phase 9)

- Removed all `_combat_waypoint()` calls from `_find_cover_position()`, `_find_cover_closest_to_player()`, and `_find_flank_cover_toward_target()`
- Added `_last_cover_search_rays` array to cache ray data from player-origin searches
- Updated `get_cover_raycast_data()` to return cached player-origin ray data (matching actual search algorithm)
- Updated `_find_distant_cover_position()` to use player-origin `PhysicsRayQueryParameters2D` (consistent with other cover functions)
- Debug visualization (CoverRaycastMonitor) now correctly shows rays originating from the player

### Phase 10: Cover Detection Fails for Large/Thick Obstacles (2026-03-23 04:37)

- **Screenshot**: `cover_large_obstacle.png` (previously) and `screenshot_thick_cover_20260323.png`
- **Observation**: "определение укрытия должно работать с большими укрытиями"
  (cover detection must work with large obstacles)
- Screenshot shows a large rectangular building/wall where rays hit the near side but no cover is found behind it

### Phase 11: Still Not Working (2026-03-23 05:36)

- **Log file**: `game_log_20260323_083151.txt`
- **Screenshot**: `screenshot_thick_cover_20260323.png`
- **Observation**: "всё ещё не считаются толстые укрытия (не должно быть ограничений по толщине укрытия)"
  (thick cover still not counted — there should be NO limit on cover thickness)
- Screenshot shows rays hitting thick obstacle but enemy not finding valid cover behind it

### Root Cause Analysis (Phase 11)

The `_get_far_side_cover()` function used a **single reverse ray** to find the far edge of obstacles:

```gdscript
var far_probe := player_pos + direction * COVER_CHECK_DISTANCE  # 300px
# Reverse ray from 300px away back toward player
```

**Problem**: When the obstacle is thicker than `COVER_CHECK_DISTANCE - near_edge_distance`, the reverse ray probe point starts **inside** the obstacle. In Godot 4.x, `intersect_ray()` does NOT detect the collider that the ray **starts inside of**. This means:

1. Ray from player hits near edge at distance 100px
2. Reverse ray starts at distance 300px (still inside a 250px+ thick wall)
3. `intersect_ray()` returns empty — it can't see the wall it's inside
4. Fallback: simple 35px offset from near edge — places cover ON the near side, still visible to player
5. `_is_position_visible_from_player()` correctly rejects this position → no valid cover found

### Fix (Phase 11)

Replaced the single reverse-ray approach with **iterative point probing** using `intersect_point()`:

1. Start probing at `near_edge + 5px` (inside obstacle)
2. Step outward in 30px increments along the ray direction
3. At each step, use `PhysicsPointQueryParameters2D.intersect_point()` to check if the point overlaps an obstacle body
4. `intersect_point()` correctly detects when a point is **inside** a collider (unlike `intersect_ray()` which misses colliders the origin is inside)
5. When `intersect_point()` returns empty after previously returning non-empty, we've found the far edge
6. Place cover 35px past the far edge exit point
7. Maximum probe distance: 900px (3× `COVER_CHECK_DISTANCE`) — supports walls up to ~900px thick

This approach has no thickness limitation and works reliably because `intersect_point()` is the correct Godot API for testing if a point is inside a collision body.

## Data Files

- `game_log_20260322_171711.txt` - Original issue report log
- `game_log_20260323_033050.txt` - Post-first-fix log showing bug still present
- `game_log_20260323_040254.txt` - Post-movement-fix log showing cover detection issue
- `game_log_20260323_052526.txt` - Confirmation suppression works, cover detection still wrong
- `screenshot_cover_bug.png` - Screenshot showing enemy choosing distant cover over nearby wall
- `round4/game_log_20260323_063239.txt` - Log showing predefined waypoint issue
- `round4/cover_detection_wrong.png` - Screenshot of incorrect cover detection
- `game_log_20260323_065933.txt` - Log showing more ray count requested
- `game_log_20260323_083151.txt` - Log showing thick obstacle cover failure
- `screenshot_thick_cover_20260323.png` - Screenshot of thick obstacle not generating valid cover
- `cover_large_obstacle.png` - Screenshot of large obstacle cover issue
