# Case Study: Issue #1289 — Fix Enemy Paths (Пути врагов)

## Issue Summary

**Title:** fix пути врагов (fix enemy paths)

**Requirements:**
1. Prohibit building paths that cross obstacles (`запрети строить пути, пересекающие препятствия`)
2. Calculate paths accounting for enemy collisions (`рассчитывай путь с учётом коллизии врагов`)
3. Increase step length when pursuing (`увеличь длину шага при pursuing`)

---

## Root Cause Analysis

### Problem 0 (Root Cause — Revisited): NavigationServer Not Updated After Bake

**Confirmed date:** 2026-03-22 — Owner feedback with screenshot showing paths through walls persisting even after the `parse_source_geometry_data` + `bake_from_source_geometry_data` fix from PR commit `18b3e5f7`.

**Location:** All 13 level scripts — `_setup_navigation()` function.

**Root cause:** `NavigationServer2D.bake_from_source_geometry_data(nav_poly, source_geometry)` updates the **`NavigationPolygon` resource object** in-place with the carved geometry, but it does **NOT** automatically push this update to the NavigationServer's live navigation map. The NavigationServer continues routing agents through the old (uncarved) navmesh until the region's polygon is explicitly re-registered.

The fix requires adding:
```gdscript
nav_region.navigation_polygon = nav_poly
```
after the bake call. This assignment triggers the node's internal setter, which calls `NavigationServer2D.region_set_navigation_polygon(region_rid, nav_poly)` — pushing the newly carved data to the live map so `NavigationAgent2D` queries use the correct walkable area.

**Timeline of events:**
1. Level `_ready()` → `_setup_navigation()` called
2. `parse_source_geometry_data()` collects wall geometry (working correctly)
3. `bake_from_source_geometry_data()` carves the `NavigationPolygon` resource (working correctly)
4. ❌ **Missing step:** `nav_region.navigation_polygon = nav_poly` NOT called → NavigationServer still has old uncarved map
5. Enemies spawn and `NavigationAgent2D.set_target_position()` is called using the stale uncarved map
6. Paths go through walls because the server believes those areas are walkable

**Evidence:** Godot forum thread ["NavigationServer2D baking creates mesh, but agent can't find a path"](https://forum.godotengine.org/t/navigationserver2d-baking-creates-mesh-but-agent-cant-find-a-path/60755) and ["Navigation Baking creates the mesh, but agents don't work"](https://forum.godotengine.org/t/navigation-baking-creates-the-mesh-but-agents-dont-work/64422) both confirm this exact pattern.

**Fix applied (commit `f96f584e`):** Added `nav_region.navigation_polygon = nav_poly` after `bake_from_source_geometry_data()` in all 13 level scripts.

### Problem 0b (Root Cause — Final): Navmesh Bake Timing

**Confirmed date:** 2026-03-22 — Owner feedback with screenshot showing BuildingLevel paths still through walls after the `nav_region.navigation_polygon = nav_poly` fix.

**Location:** All 13 level scripts — `_setup_navigation()` called from `_ready()`.

**Root cause:** `parse_source_geometry_data()` is called in `_ready()` which runs before the PhysicsServer2D has registered the `CollisionShape2D` nodes from the scene tree. In Godot 4, physics shapes are only registered with the PhysicsServer after the node enters the tree AND the physics server processes the next frame. So calling `parse_source_geometry_data` in `_ready()` finds no collision bodies — the navmesh stays as an uncarved rectangle.

**Evidence from game log (`game_log_20260322_045330.txt`):**
- LabyrinthLevel (initial load): `poly_count=1 vertex_count=4 outline_count=1` — uncarved rectangle
- 11 seconds later (after user toggles navmesh overlay): `poly_count=61 vertex_count=96` — properly carved
- BuildingLevel (loaded via SceneLoader): `poly_count=1 vertex_count=4` — consistently uncarved across 3 separate loads

The LabyrinthLevel eventually shows carved navmesh because by the time the user manually toggles the overlay (11 seconds later), the physics server has caught up. But BuildingLevel never re-bakes, so it stays uncarved.

**Fix applied (commit `610745cf`):** Added `await get_tree().physics_frame` before `parse_source_geometry_data()` in all 13 level scripts. This defers the bake to after the physics server has registered all collision shapes.

---

### Problem 1: Paths Crossing Obstacles

**Location:** `scripts/objects/enemy.gd` — `_find_pursuit_cover_toward_player()` (line ~3134) and `_can_reach_position()` (line ~3242)

**Root cause:** The current `_can_reach_position()` performs a single straight-line raycast from the enemy to the candidate cover position. However, cover positions are calculated as `collision_point + collision_normal * 35.0` — they are offset slightly away from obstacle surfaces. This offset can place cover points in locations where:
- The point is technically not blocked by a direct line-of-sight raycast
- But the navmesh considers the point unreachable (too close to wall geometry, inside a wall corner, or across a thin wall)

The raycast uses `collision_mask = 4` (obstacles only) and only checks the direct line. No navmesh validation is performed, so the cover point may be selected even though NavigationAgent2D cannot actually route to it cleanly.

Additionally, in the `PursuingState` class (`scripts/ai/states/pursuing_state.gd`), the `_process_approach_phase` and `_process_cover_movement` methods apply only `_apply_wall_avoidance` (a simple raycast-based steering) rather than using the full `_move_to_target_nav()` with NavigationAgent2D routing. The pure wall avoidance can push enemies into walls or cause them to clip through thin obstacles.

**Fix:** Add navmesh proximity validation in `_find_pursuit_cover_toward_player` — reject any cover position whose closest navmesh point is more than `agent_radius * 2` away. This ensures all selected cover positions lie on navigable terrain.

### Problem 2: Paths Not Accounting for Enemy Collisions

**Location:** `scripts/objects/enemy.gd` — `_find_pursuit_cover_toward_player()` (line ~3134)

**Root cause:** The cover scoring function considers:
- Hidden-from-player bonus
- Progress toward player
- Distance penalty
- Same-obstacle penalty
- Flashlight penalty

But it does **not** consider whether another enemy is already occupying or heading to the same cover position. Multiple enemies converging on the same cover causes:
- Physical collision (they push each other)
- ORCA avoidance kicking in erratically
- Enemies clustering in the same spot, reducing tactical spread

The `NavigationAgent2D` already has `avoidance_enabled = true` (ORCA) which handles real-time velocity steering. However, the *cover selection* (which determines the *destination*) doesn't avoid already-occupied positions, leading to traffic jams at popular cover spots.

**Fix:** Add an "enemy-occupied penalty" to the cover scoring in `_find_pursuit_cover_toward_player`. Check nearby enemies (in the "enemies" group) and apply a penalty if their current `_pursuit_next_cover` or `global_position` is within a threshold distance of the candidate cover.

### Problem 3: Step Length Too Small During Pursuing

**Location:** `scenes/objects/Enemy.tscn` — NavigationAgent2D settings; `scripts/objects/enemy.gd` — pursuing state

**Root cause:** The `NavigationAgent2D` has `path_desired_distance = 40.0`. This is the distance from the current position to the next path waypoint before advancing to the next segment. A small value (40px) means the agent requests very short steps, resulting in:
- Many small intermediate targets
- The enemy making tiny micro-moves between waypoints
- Slow effective pursuit speed even at high `combat_move_speed`
- More frequent "reached waypoint" events, causing more frequent path recomputations

During PURSUING, a longer step length would allow smoother, more efficient movement through open areas.

**Fix:** Temporarily increase `_nav_agent.path_desired_distance` when entering PURSUING state and restore it on exit. This makes each path step cover more ground.

---

## Existing Code Context

### NavigationAgent2D Settings (Enemy.tscn)
```
path_desired_distance = 40.0
target_desired_distance = 10.0
avoidance_enabled = true
radius = 24.0
neighbor_distance = 100.0
max_neighbors = 10
time_horizon_agents = 0.8
time_horizon_obstacles = 1.0
max_speed = 320.0
```

### Key Constants
- `PURSUIT_APPROACH_MAX_TIME = 3.0` — max approach phase time
- `COVER_CHECK_DISTANCE = 300.0` — raycast distance for cover search
- `SEPARATION_RADIUS = 60.0` — ORCA separation radius

---

## Solutions Considered

### Fix 1: Navmesh Validation for Cover Positions

**Approach:** Use `NavigationServer2D.map_get_closest_point()` to validate each candidate cover position. If the closest navmesh point is more than `2 * agent_radius` away, the position is on or near non-navigable terrain — skip it.

The existing `_is_waypoint_navigable()` method (line ~2288) uses this pattern with a 50px threshold. We apply the same logic in `_find_pursuit_cover_toward_player`.

```gdscript
# After _can_reach_position() check, add navmesh validation:
if _nav_agent:
    var nav_map := _nav_agent.get_navigation_map()
    if nav_map.is_valid():
        var snapped := NavigationServer2D.map_get_closest_point(nav_map, cover_pos)
        if cover_pos.distance_to(snapped) > _nav_agent.radius * 2.0:
            continue  # Not on navmesh — skip
```

### Fix 2: Enemy-Occupied Penalty

**Approach:** In the cover scoring loop, check all enemies in the "enemies" group. If any other enemy's current pursuit cover target or position is within `SEPARATION_RADIUS * 2` of the candidate, apply a penalty.

```gdscript
const PURSUIT_ENEMY_OCCUPIED_PENALTY: float = 3.0
const PURSUIT_ENEMY_OCCUPIED_RADIUS: float = 80.0  # px

# In scoring loop:
var occupied_penalty: float = 0.0
for other_enemy in get_tree().get_nodes_in_group("enemies"):
    if other_enemy == self or not is_instance_valid(other_enemy):
        continue
    var other_cover: Vector2 = other_enemy.get("_pursuit_next_cover") if other_enemy.has_method("get") else Vector2.ZERO
    if other_cover != Vector2.ZERO and cover_pos.distance_to(other_cover) < PURSUIT_ENEMY_OCCUPIED_RADIUS:
        occupied_penalty += PURSUIT_ENEMY_OCCUPIED_PENALTY
        break
total_score -= occupied_penalty
```

### Fix 3: Increase Step Length During Pursuing

**Approach:** Modify `path_desired_distance` on the NavigationAgent2D when entering/exiting PURSUING state.

```gdscript
const PURSUIT_PATH_DESIRED_DISTANCE: float = 80.0  # doubled from 40.0

# In _enter_pursuing_state():
if _nav_agent:
    _nav_agent.path_desired_distance = PURSUIT_PATH_DESIRED_DISTANCE

# In _exit_pursuing_state() or on state transition:
if _nav_agent:
    _nav_agent.path_desired_distance = 40.0  # restore default
```

---

## Known Libraries and Approaches

### Godot 4 NavigationAgent2D
- `avoidance_enabled` + `velocity_computed` signal: already in use for ORCA
- `path_desired_distance`: controls when the agent considers a waypoint reached
- `NavigationServer2D.map_get_closest_point()`: validates if a position is on the navmesh

### ORCA (Optimal Reciprocal Collision Avoidance)
Already integrated via `NavigationAgent2D.avoidance_enabled = true`. Fix 2 (enemy-occupied penalty) complements ORCA by preventing enemies from targeting the same cover *destination* before ORCA even kicks in.

### References
- Godot 4 NavigationAgent2D docs: https://docs.godotengine.org/en/stable/classes/class_navigationagent2d.html
- ORCA algorithm paper: van den Berg et al., "Reciprocal n-Body Collision Avoidance" (2011)
- Godot NavigationServer2D.map_get_closest_point: used in existing `_is_waypoint_navigable()` at line 2288

---

## Implementation Plan

1. Add navmesh validation to `_find_pursuit_cover_toward_player` (Fix 1)
2. Add `PURSUIT_ENEMY_OCCUPIED_PENALTY` scoring to `_find_pursuit_cover_toward_player` (Fix 2)
3. Add `PURSUIT_PATH_DESIRED_DISTANCE` constant and modify `path_desired_distance` on PURSUING entry/exit (Fix 3)
4. Add unit tests for each fix

---

## Files to Modify

- `scripts/objects/enemy.gd` — main implementation
- `scenes/objects/Enemy.tscn` — (no change needed, handled in code)
- `tests/unit/test_pursuing_state.gd` — add tests for new behavior

---

## Additional Data Collected

### Game Log: `game_log_20260322_045330.txt`

Owner-provided game log from Windows export build running Godot 4.3-stable. Shows BuildingLevel navmesh remaining at `poly_count=1` (uncarved rectangle) across 3 consecutive level loads, confirming the physics frame timing root cause.

### Screenshots

- `screenshots/building-paths-through-walls.png` — BuildingLevel showing enemy paths (yellow lines) going straight through interior walls
- `screenshots/conflicting-paths.png` — Multiple enemies with overlapping/conflicting path lines through obstacles

### PR #1288 Integration

Per owner request, integrated TacticalGroupComponent from PR #1288 (Issue #1287). When 2+ enemies are within 500px of the player they form a tactical group and spread around the player using angular slot assignment. This complements the enemy-occupied penalty in PursuitComponent by providing macro-level coordination in addition to the micro-level cover position de-duplication.

---

## Root Cause 0c — C# LevelInitFallback Missing Navmesh Bake (Final Root Cause)

**Confirmed date:** 2026-03-22 — Owner feedback with screenshot showing BuildingLevel paths still going through walls after all prior fixes.

**Location:** `Scripts/Components/LevelInitFallback.cs` — `PerformFallbackInit()` method.

**Root cause:** BuildingLevel (and 5 other levels: CityLevel, DocksLevel, FactoryLevel, RevolverLevel, TestTier) have a C# `LevelInitFallback` node attached in their `.tscn` scenes. This component was added to work around the Godot 4.3 binary tokenization bug (`godotengine/godot#94150`) that can cause GDScript `_ready()` to silently fail to execute.

The race condition:
1. GDScript `_ready()` starts executing
2. `_setup_navigation()` is called, which contains `await get_tree().physics_frame` — this **suspends** `_ready()` execution
3. No further GDScript initialization runs (enemy tracking, etc.) because everything is after the await
4. C# `LevelInitFallback._Ready()` calls `CallDeferred(CheckAndInitialize)`
5. `CallDeferred` runs at the end of the current frame — BEFORE the physics frame await completes
6. `CheckAndInitialize` sees `_enemies` array is empty → concludes GDScript `_ready()` didn't run
7. C# fallback takes over ALL initialization — but **without navmesh baking**
8. When the physics frame finally fires, `_setup_navigation()` resumes and bakes the navmesh...
9. ...but the C# fallback already set `_initial_enemy_count` and `_enemies` in the GDScript properties
10. Result: the GDScript `_setup_navigation()` may actually complete successfully, but the bake arrives after enemies have already started pathfinding with the uncarved navmesh

**Evidence from game log (`game_log_20260322_052213.txt`):**
```
[05:23:07] [INFO] [LevelInitFallback] GDScript _ready() did NOT execute - performing C# fallback initialization
...
[05:23:08] [INFO] [NavMeshMonitor] refresh: region 'NavigationRegion2D' poly_count=1 vertex_count=4 outline_count=1
```
- No "Baking navigation mesh..." or "Navigation mesh baked successfully" print appears in the log for BuildingLevel
- NavMeshMonitor consistently shows `poly_count=1 vertex_count=4` (uncarved rectangle)
- The C# fallback's `PerformFallbackInit()` method has 11 initialization steps but does NOT include navmesh baking

**Fix applied:** Added `SetupNavigationDeferred()` as step 12 in `PerformFallbackInit()`. This async method:
1. Awaits `SceneTree.SignalName.PhysicsFrame` (mirrors GDScript `await get_tree().physics_frame`)
2. Validates the scene is still valid after the await (prevents crashes during scene transitions)
3. Calls `NavigationServer2D.ParseSourceGeometryData()` + `BakeFromSourceGeometryData()`
4. Pushes the baked navmesh to the live map with `navRegion.NavigationPolygon = navPoly`
5. Emits `bake_finished` signal to trigger NavMeshMonitor overlay refresh

This ensures navmesh baking happens even when GDScript `_ready()` silently fails due to the Godot binary tokenization bug.

### Game Log: `game_log_20260322_052213.txt`

Latest owner-provided game log confirming the C# fallback root cause. Key evidence:
- `LevelInitFallback] GDScript _ready() did NOT execute` appears for BuildingLevel
- NavMeshMonitor consistently shows `poly_count=1` (uncarved) for BuildingLevel across all loads
- LabyrinthLevel (which does NOT have LevelInitFallback) correctly shows `poly_count=61` after bake
