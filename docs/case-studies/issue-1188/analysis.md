# Issue #1188: Enemy Pathfinding Optimization – Case Study

## Problem Statement
> Enemies should not walk into walls and should have cached "tactical" paths, all of this must be optimized.
>
> (Original: враги должны ходить не врезаясь в стены и должны быть закэшированный "такитческие" пути, всё это должно быть оптимизировано.)

---

## Current Architecture (as of branch tip)

### NavigationAgent2D Presence
Every `Enemy.tscn` scene includes a `NavigationAgent2D` node with:
- `path_desired_distance = 40.0`
- `target_desired_distance = 10.0`
- `avoidance_enabled = false`
- `max_speed = 320.0`

### All Levels Have Navigation Regions
`NavigationRegion2D` + `NavigationPolygon` are present in all 13 levels. Source geometry is baked from objects in the `"navigation_source"` group.

### Where NavigationAgent2D IS Used
| Code path | Function | Nav used? |
|-----------|----------|-----------|
| PATROL movement (after PR #1119) | `_process_patrol()` | ✅ Yes |
| SEEKING_COVER | `_move_to_target_nav(_cover_position)` | ✅ Yes |
| RETREATING (most branches) | `_move_to_target_nav(_cover_position)` | ✅ Yes |
| PURSUING (cover-to-cover) | `_move_to_target_nav(_pursuit_next_cover)` | ✅ Yes |
| SEARCHING (spiral waypoints) | direct `_nav_agent.target_position =` | ✅ Yes |
| EVADING_GRENADE | direct `_nav_agent.target_position =` | ✅ Yes |
| Vulnerability sound pursuit | `_move_to_target_nav(_last_known_player_position)` | ✅ Yes |

### Where NavigationAgent2D IS NOT Used (Root Cause)
| Code path | Lines | Issue |
|-----------|-------|-------|
| COMBAT approach phase | ~1571-1577 | `_apply_wall_avoidance(direction_to_player)` only — no navmesh |
| COMBAT clear shot movement | ~1516-1520 | `_apply_wall_avoidance()` only — no navmesh |
| PACIFIST pursuit attacker | ~2434 | `_apply_wall_avoidance()` only — no navmesh |
| `_can_reach_position()` validity check | ~3223-3245 | Single raycast — fails around corners |

### Wall Avoidance Mechanism
`_apply_wall_avoidance()` uses 8 `RayCast2D` nodes (`_wall_raycasts`) to steer away from nearby walls. This is a local reactive approach (works well near walls) but:
- Cannot route around large obstacles or around corners
- Does not know about the NavMesh topology
- When the enemy needs to reach a target around a 90° corner, wall avoidance steers the enemy *along* the wall but never commits to turning the corner

### Cover Search Raycasts
`_find_pursuit_cover_toward_player()` casts 16 raycasts synchronously every time it is called (can be called multiple times per frame during PURSUING state). Already partially throttled with `COVER_SEARCH_COOLDOWN = 0.3s`.

`_can_reach_position()` uses a single physics raycast. This only works for straight-line paths and will incorrectly reject cover positions that require navigating around a corner.

---

## Root Cause Analysis

### Primary Bug: COMBAT Approach Uses No NavMesh
When an enemy transitions to COMBAT and approaches the player (lines ~1563-1583), movement direction is:
```gdscript
var move_direction := direction_to_player  # Direct line to player
move_direction = _apply_wall_avoidance(move_direction)  # Only local steering
velocity = move_direction * combat_move_speed
```
If the player is behind a wall or around a corner, the enemy walks into the wall and stays stuck until `GLOBAL_STUCK_MAX_TIME` (4 seconds) triggers a global stuck recovery.

### Secondary Bug: _can_reach_position Uses Raycast Not NavMesh
`_can_reach_position()` checks if there is a direct line-of-sight to cover using a physics raycast. This incorrectly *rejects* cover around corners (the raycast hits the corner wall), causing `_find_pursuit_cover_toward_player()` to find no valid cover and fall through to the "approach directly" path — which loops back to the primary bug.

### Performance Issue: Redundant _nav_agent Target Reassignment
`_get_nav_direction_to()` sets `_nav_agent.target_position = target_pos` every physics frame (60 fps). NavigationAgent2D internally only recalculates when the target changes (Godot 4 uses async path requests), so most reassignments are no-ops. However, the pattern of calling `_move_to_target_nav` combined with `_apply_wall_avoidance` on top of the navmesh direction is partially redundant — the navmesh already steers around walls.

---

## Solution Implemented

### Fix 1: Use NavMesh in COMBAT Approach Phase
Replace direct-direction + wall-avoidance in COMBAT approach with `_move_to_target_nav(_player.global_position)`. This ensures enemies navigate around corners to reach the player.

The enemy still aims at the player while following the nav path (rotation is set separately after velocity is set).

### Fix 2: Use NavMesh in COMBAT Clear Shot Movement
Replace wall-avoidance-only movement in clear shot seeking with `_move_to_target_nav(_clear_shot_target)`.

### Fix 3: Use NavMesh for PACIFIST Pursuing
Replace wall-avoidance-only movement in pacifist state with `_move_to_target_nav`.

### Fix 4: Use NavigationServer2D for _can_reach_position
Replace single raycast with a NavigationServer2D closest-point check. If the nav mesh has a point near the target, it's reachable. This allows cover-around-corners to be correctly accepted.

---

## Known Alternatives Considered

| Approach | Pros | Cons |
|----------|------|------|
| Godot NavigationAgent2D (current partial, extending) | Built-in, async, navmesh-based, wall-aware | Requires navmesh in every scene (already present) |
| A* grid pathfinding (custom) | Full control | Very expensive to bake for tile-free levels; re-implementing what NavigationAgent already does |
| Steering Behaviors (pure) | Simple | Cannot navigate complex winding corridors reliably |
| Avoidance only (current) | Zero setup | Gets stuck in concave obstacles and at corners |

NavigationAgent2D is the correct choice as the project already uses it and all levels already have NavigationRegion2D baked.

---

## Files Modified
- `scripts/objects/enemy.gd` — COMBAT approach, clear shot, pacifist state, `_can_reach_position`

---

## Session 3 Update: NavMesh Still Not Carving Walls (2026-03-20)

### New Evidence

Owner confirmed (with screenshot) that even after Session 2 fix, the navmesh still appears as a solid rectangle with no wall cutouts. Screenshot `navmesh_no_wall_carving_screenshot.png` shows the BuildingLevel with nav mesh debug overlay enabled — the entire level is one blue rectangle with room walls NOT carved out.

Game log `game_log_20260320_084058.txt` shows BuildingLevel being tested, with PATROL STUCK events still occurring.

### Deeper Root Cause: Timing of `bake_navigation_polygon()` in `_ready()`

The Session 2 fix replaced the async `NavigationServer2D.parse_source_geometry_data()` approach with `nav_region.bake_navigation_polygon(false)`. However, calling `bake_navigation_polygon(false)` **directly** in `_ready()` is **still unreliable**.

#### Why `_ready()` Is Too Early for NavMesh Baking

Godot 4's navigation server runs on a **separate thread** from the main game logic. It synchronizes with the physics server only at **physics frame boundaries**. When `_ready()` runs:

1. All nodes have entered the scene tree ✅
2. All `StaticBody2D` nodes have called `add_child()` ✅
3. **BUT**: The `PhysicsServer2D` may not have fully processed the registration of all collision shapes yet ⚠️
4. **AND**: The navigation server's geometry parser queries `PhysicsServer2D` — if it hasn't synced, it finds no obstacles

This is a confirmed behavior documented by Godot navigation system core contributor **smix8** (godotengine/godot#57022):

> "Any change like registering a map, a region or an agent, changing their transform … takes time to sync as the NavigationServer runs on a different thread. Don't expect changes to be in effect immediately or a path to return on the same frame you setup all the regions and maps. You need to wait at least 1 physics tick for the NavigationServer sync and queue flush before changes can take place."

The official Godot documentation on navigation mesh baking (navigation_using_navigationmeshes.rst) also states:

> "Some mega-nodes like TileMap are often not ready on the first frame. Also the parsing needs to happen on the main thread. So do a deferred call to avoid common parsing issues."

#### Evidence: Why Beach/Docks Appeared to Work

The beach and docks levels use the same `bake_navigation_polygon(false)` approach. They may have appeared to work due to:
- Different scene loading order where physics bodies happened to be registered before the nav region bake ran
- Or the pre-baked polygon data in the `.tscn` file was not being overwritten (the beach level doesn't call `nav_poly.clear()`)

With the building/labyrinth levels, `nav_poly.clear()` is called before baking, which removes the pre-baked polygon data, so there's no fallback if the bake produces no geometry.

### Correct Fix: `call_deferred()`

The solution is to use `call_deferred()` to defer the bake until after all `_ready()` callbacks have completed and all physics bodies are fully registered:

```gdscript
# INCORRECT — may run before physics bodies are registered:
nav_region.bake_navigation_polygon(false)

# CORRECT — deferred, runs after entire scene is fully ready:
nav_region.bake_navigation_polygon.call_deferred(false)
```

`call_deferred()` schedules the call to the **end of the current frame**, after:
1. All `_ready()` callbacks on all nodes have completed
2. All deferred `add_child()` calls have executed
3. All physics bodies have fully registered their collision shapes

This guarantees that when the geometry parser runs, all `StaticBody2D` obstacles with `collision_layer = 4` are present and queryable, and the navmesh will correctly carve them out.

### References

- [godotengine/godot#57022 — NavigationServer sync requires 1 physics tick](https://github.com/godotengine/godot/issues/57022)
- [godotengine/godot#92003 — Runtime-baked navmesh not recognized by agents](https://github.com/godotengine/godot/issues/92003)
- [Godot Forum #127936 — NavigationRegion2D not baking at runtime (deferred timing issue)](https://forum.godotengine.org/t/navigationregion2d-not-baking-at-runtime/127936)
- [Godot Docs — Using NavigationServer](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationservers.html)

### Files Updated (Session 3)

All 13 level scripts updated to use `call_deferred()`:
- `scripts/levels/building_level.gd`
- `scripts/levels/labyrinth_level.gd`
- `scripts/levels/labyrinth2_level.gd`
- `scripts/levels/arena_level.gd`
- `scripts/levels/castle_level.gd`
- `scripts/levels/city_level.gd`
- `scripts/levels/revolver_level.gd`
- `scripts/levels/test_tier.gd`
- `scripts/levels/roguelike_level.gd`
- `scripts/levels/beach_level.gd` (preventive)
- `scripts/levels/docks_level.gd` (preventive)
- `scripts/levels/factory_level.gd` (preventive)
- `scripts/levels/decadence_level.gd` (preventive)

---

## Session 4 — Further Investigation and Fixes (2026-03-20)

### Owner Feedback (after Session 3)

> "1. теперь навмеш не отображается при включённом отображении"
> "2. враги всё так же идут в стену"
> (1. navmesh no longer shows when display is enabled. 2. enemies still walk into walls.)

Screenshot: navmesh overlay shows **nothing at all** (not even a flat rectangle).

Game log saved: `docs/case-studies/issue-1188/game_log_20260320_090955.txt`

### Root Causes Identified (Session 4)

#### Display Bug — `nav_mesh_monitor.gd` reads wrong data

The overlay's `refresh()` function was reading `nav_poly.get_outline_count()` (the pre-bake input outlines) instead of the baked polygon data (`get_polygon_count()` + `get_polygon()` + `get_vertices()`).

After `bake_navigation_polygon()`, Godot updates the **triangulated polygon data** (vertices + polygons), not the input outlines. The outlines remain as the original floor boundary. So the overlay was either showing a flat rectangle (the floor outline) or nothing (if the outlines had been cleared).

The `call_deferred` bake timing also meant the overlay refreshed BEFORE the bake completed, seeing empty polygon data.

#### Level Scripts — Unnecessary `nav_poly.clear()` + `add_outline()` calls

Level scripts `arena_level.gd`, `building_level.gd`, `castle_level.gd`, `city_level.gd`, `labyrinth_level.gd`, `revolver_level.gd`, `test_tier.gd` were calling:
1. `nav_poly.clear()` — removes ALL data including outlines
2. `nav_poly.add_outline(floor_outline)` — re-adds the floor boundary

This was unnecessary since all these level `.tscn` files already have the correct outlines pre-set. The `clear()` call actually caused the overlay to see empty data (the outline was cleared by `clear()`, then the deferred bake hadn't run yet, so `get_outline_count() == 0` and `get_polygon_count() == 0`).

### Session 4 Fixes

#### Fix 1: `nav_mesh_monitor.gd` — Read baked polygon data

Changed `refresh()` to read triangulated baked polygon data (`get_polygon_count()` / `get_polygon()` / `get_vertices()`) which reflects the actual carved navmesh, falling back to outlines only if no baked data exists.

Added timing fix: use `NavigationRegion2D.bake_finished` signal + a 0.2s timer fallback to ensure overlay refreshes AFTER the bake completes.

#### Fix 2: Level scripts — Remove `clear()` + `add_outline()`

For all levels that already have outlines in their `.tscn` files, removed the redundant `nav_poly.clear()` + `nav_poly.add_outline()` calls. These levels now use the same simple pattern as `beach_level.gd`:

```gdscript
func _setup_navigation() -> void:
    var nav_region: NavigationRegion2D = get_node_or_null("NavigationRegion2D")
    if nav_region == null:
        push_warning("...")
        return
    # Bake navmesh with walls (collision layer 4) carved out — Issue #1188
    # call_deferred ensures StaticBody2D nodes are fully registered before baking
    nav_region.bake_navigation_polygon.call_deferred(false)
```

`roguelike_level.gd` retains `clear()` + `add_outline()` since its `.tscn` has no pre-baked outline.

### Files Updated (Session 4)

- `scripts/autoload/nav_mesh_monitor.gd` — fixed display and timing
- `scripts/levels/arena_level.gd` — removed clear()+add_outline()
- `scripts/levels/building_level.gd` — removed clear()+add_outline()
- `scripts/levels/castle_level.gd` — removed clear()+add_outline()
- `scripts/levels/city_level.gd` — removed clear()+add_outline()
- `scripts/levels/labyrinth_level.gd` — removed clear()+add_outline()
- `scripts/levels/revolver_level.gd` — removed clear()+add_outline()
- `scripts/levels/test_tier.gd` — removed clear()+add_outline()
- `docs/case-studies/issue-1188/game_log_20260320_090955.txt` — owner's session 4 game log

---

## Session 5 — Physics Frame Timing Fix (2026-03-20)

### Owner Feedback (after Session 4)

> "1. навмеш всё ещё не отображается (сверься с main)"
> "2. противники всё ещё идут в стену"
> (1. navmesh still not displaying. 2. enemies still walk into walls.)

Screenshot: navmesh overlay shows **nothing** (not even a flat rectangle — unlike main).
Game log saved: `docs/case-studies/issue-1188/logs/game_log_20260320_095119.txt`

Key evidence from game log:
- `PATROL STUCK: pos=(1200, 1601.992) for 1.5s` — Enemy10 stuck against a wall
- `PATROL STUCK: pos=(1611.34, 898.8737) for 1.5s` — Enemy7 stuck against a wall
- Repeated corner-check events at 89.9° — enemy hitting right-angle wall repeatedly

### Root Cause: `call_deferred` Does NOT Guarantee Physics Registration

Session 4's assumption was wrong. `call_deferred` schedules work at **idle time** — the end of the current frame's idle processing. However, in Godot 4's engine architecture:

- `StaticBody2D` nodes register their collision shapes with `PhysicsServer2D` during `_enter_tree()` ✅
- But `PhysicsServer2D` only **processes** these registrations (making them queryable) at **physics frame boundaries** (60Hz, every 16.7ms) ⚠️
- `call_deferred` runs in the SAME frame as `_ready()` — the first idle period — BEFORE the first physics frame processes ⚠️
- So `bake_navigation_polygon` runs, queries `PhysicsServer2D`, finds NO registered geometry, and produces 0 polygons

After baking 0 polygons, `bake_navigation_polygon` clears the polygon AND the outlines (via an internal `clear()` call). This means:
- `get_polygon_count()` = 0 → baked data unavailable
- `get_outline_count()` = 0 → fallback also unavailable
- Overlay shows **nothing** (compared to main's approach of showing the flat rectangle from the original outlines that were NOT cleared)

### Fix: `await get_tree().physics_frame`

Replaced `call_deferred` with an async function that waits for one physics frame:

```gdscript
## Bake navigation polygon after one physics frame to ensure all StaticBody2D
## collision shapes are fully registered — Issue #1188.
func _bake_navmesh_after_physics_frame(nav_region: NavigationRegion2D) -> void:
    await get_tree().physics_frame
    if is_instance_valid(nav_region):
        nav_region.bake_navigation_polygon(false)
```

`get_tree().physics_frame` is a signal that fires **after each physics step completes**. Awaiting it guarantees:
1. All `_ready()` callbacks have run
2. One full physics step has completed
3. All `StaticBody2D` collision shapes are fully registered and queryable by `PhysicsServer2D`
4. The navmesh bake correctly finds and carves all wall shapes

### Files Updated (Session 5)

All 13 level scripts updated to use `_bake_navmesh_after_physics_frame()` instead of `call_deferred`:
- `scripts/levels/arena_level.gd`
- `scripts/levels/beach_level.gd`
- `scripts/levels/building_level.gd`
- `scripts/levels/castle_level.gd`
- `scripts/levels/city_level.gd`
- `scripts/levels/decadence_level.gd`
- `scripts/levels/docks_level.gd`
- `scripts/levels/factory_level.gd`
- `scripts/levels/labyrinth2_level.gd`
- `scripts/levels/labyrinth_level.gd`
- `scripts/levels/revolver_level.gd`
- `scripts/levels/roguelike_level.gd`
- `scripts/levels/test_tier.gd`
- `scripts/autoload/nav_mesh_monitor.gd` — timer extended from 0.2s to 0.5s
- `docs/case-studies/issue-1188/logs/game_log_20260320_095119.txt` — owner's session 5 game log
- `docs/case-studies/issue-1188/screenshots/navmesh_session5.png` — owner's session 5 screenshot

---

## Session 6 (2026-03-20) — Root Cause Identified: Single Physics Frame Not Sufficient

### Owner Report (Session 6)
Owner tested the Session 5 fix and reported:
1. Navmesh display still not visible
2. Enemies still walk into walls

Game log: `docs/case-studies/issue-1188/game_log_20260320_102819.txt`

Key log entry confirming issue:
```
[10:29:00] [ENEMY] [Enemy10] PATROL STUCK: pos=(1200, 1601.992) for 1.5s, skipping
[10:29:02] [ENEMY] [Enemy7] PATROL STUCK: pos=(1611.34, 898.8737) for 1.5s, skipping
```

### Root Cause Analysis (Session 6)

The Session 5 fix (`await get_tree().physics_frame`) was correct in principle but **insufficient**. Research confirmed:

**Issue 1: NavigationServer2D needs its own sync step**

When `bake_navigation_polygon(false)` completes, it:
1. Updates the `NavigationPolygon` resource data (vertices, polygons)
2. Notifies the NavigationServer2D about the region update

But NavigationServer2D runs on a **separate thread** and syncs with the main thread at specific points. After calling `bake_navigation_polygon()`, one additional physics frame is needed for NavigationServer2D to process the update and make the new navmesh data available to NavigationAgent2D queries.

**Issue 2: No logging to confirm bake was running**

Previous code had no log output from the bake function. This made it impossible to diagnose from game logs whether the bake was:
- Running at all
- Producing polygons (walls carved)
- Producing 0 polygons (flat rectangle, no walls carved)

**Timeline confirmed from game log:**
- `10:28:57` — BuildingLevel loaded, enemies spawned
- No "Baking navmesh" log entry at any point
- `10:29:00` — Enemy PATROL STUCK (only 3 seconds after spawn)

The lack of any navmesh log confirms the bake output was not being logged, which masked whether the bake succeeded or failed.

### Fix (Session 6): Two Physics Frames + Diagnostic Logging

Updated `_bake_navmesh_after_physics_frame` in all 13 level scripts:

```gdscript
## Bake navigation polygon after two physics frames to ensure all StaticBody2D
## collision shapes are fully registered and NavigationServer2D has synced — Issue #1188.
func _bake_navmesh_after_physics_frame(nav_region: NavigationRegion2D) -> void:
    await get_tree().physics_frame  # Wait for StaticBody2D shapes to register with PhysicsServer2D
    await get_tree().physics_frame  # Wait for NavigationServer2D to sync the map state
    if not is_instance_valid(nav_region):
        return
    _log_to_file("Baking navmesh (Issue #1188): carving walls from collision layer 4")
    nav_region.bake_navigation_polygon(false)
    var poly_count: int = nav_region.navigation_polygon.get_polygon_count() if nav_region.navigation_polygon else 0
    _log_to_file("Navmesh bake complete: %d polygons (>1 means walls were carved)" % poly_count)
```

**Two-frame sequence:**
- Frame 1: All `_ready()` callbacks run; `CollisionShape2D` shapes are registered via `NOTIFICATION_ENTER_TREE`. `bake_navigation_polygon` queries PhysicsServer2D for static colliders — but NavigationServer2D may not have synced yet.
- Frame 2: NavigationServer2D processes the baked polygon data and makes it available to NavigationAgent2D path queries.

**Diagnostic value:** The `poly_count` log will show:
- `poly_count = 0` or `= 1`: bake failed, flat rectangle only, walls not carved
- `poly_count > 10` (typically 50–200): bake succeeded, walls properly carved into walkable mesh

### Files Updated (Session 6)

All 13 level scripts + nav_mesh_monitor.gd:
- `scripts/levels/arena_level.gd`
- `scripts/levels/beach_level.gd`
- `scripts/levels/building_level.gd`
- `scripts/levels/castle_level.gd`
- `scripts/levels/city_level.gd`
- `scripts/levels/decadence_level.gd`
- `scripts/levels/docks_level.gd`
- `scripts/levels/factory_level.gd`
- `scripts/levels/labyrinth2_level.gd`
- `scripts/levels/labyrinth_level.gd`
- `scripts/levels/revolver_level.gd`
- `scripts/levels/roguelike_level.gd`
- `scripts/levels/test_tier.gd`
- `scripts/autoload/nav_mesh_monitor.gd` — updated comment (timer 0.5s still sufficient for 2 frames)
- `docs/case-studies/issue-1188/game_log_20260320_102819.txt` — owner's session 6 game log

---

## Session 7 (2026-03-20) — CONFIRMED ROOT CAUSE: Wrong Source Geometry Scan Root

### Owner Report (Session 7)
Owner tested the Session 6 fix and reported:
1. Enemies in PURSUING state still walk into walls
2. Navmesh display still not working — "restore display as in main"

Game logs: `docs/case-studies/issue-1188/game-logs/game_log_20260320_102819.txt` and `game_log_20260320_111647.txt`

### Definitive Diagnostic Evidence (Session 7)

Game log from Session 6 build contained the bake diagnostic log for the FIRST TIME:
```
[LabyrinthLevel] Baking navmesh (Issue #1188): carving walls from collision layer 4
[LabyrinthLevel] Navmesh bake complete: 1 polygons (>1 means walls were carved)
[BuildingLevel] Baking navmesh (Issue #1188): carving walls from collision layer 4
[BuildingLevel] Navmesh bake complete: 1 polygons (>1 means walls were carved)
```

**1 polygon = bake ran but walls were NOT carved.** The bake produced only the floor outline as a single untrimmed polygon.

All previous sessions (2–6) were fixing **timing issues** — but the timing was never the actual root cause. The bake was finding NO wall geometry because of a fundamentally wrong scene scanning scope.

### THE Actual Root Cause: `source_geometry_mode = 0` Only Scans NavigationRegion2D Children

**Godot 4.3 `NavigationPolygon.source_geometry_mode` values:**

| Value | Name | What it scans |
|-------|------|--------------|
| 0 | `SOURCE_GEOMETRY_ROOT_NODE_CHILDREN` | Children of the **NavigationRegion2D** node itself |
| 1 | `SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN` | All nodes in the named group + their children |
| 2 | `SOURCE_GEOMETRY_GROUPS_EXPLICIT` | Only nodes explicitly in the named group |

**Critical finding from Godot 4.3 source code** (`scene/2d/navigation_region_2d.cpp`):
```cpp
NavigationServer2D::get_singleton()->parse_source_geometry_data(
    navigation_polygon, source_geometry_data, this);  // 'this' = NavigationRegion2D
```

When calling `bake_navigation_polygon()`, Godot passes **the NavigationRegion2D itself** as the root node. With `source_geometry_mode = 0`, the geometry parser scans `this` (NavigationRegion2D) and ALL its **descendants** — NOT the scene root or siblings.

**Scene hierarchy in all affected levels:**
```
LevelName (Node2D — scene root)
├── Environment (Node2D)
│   ├── Walls (Node2D)
│   │   ├── WallTop (StaticBody2D, collision_layer=4)   ← WALL
│   │   ├── WallBottom (StaticBody2D, collision_layer=4) ← WALL
│   │   └── ...
│   └── InteriorWalls (Node2D)
│       └── ... (StaticBody2D, collision_layer=4)       ← WALL
└── NavigationRegion2D  ← scan starts HERE with mode=0
    └── (NO children)  ← nothing to scan!
```

The walls are **siblings** of NavigationRegion2D (children of the scene root), not children of NavigationRegion2D. So `bake_navigation_polygon()` scanned zero nodes, found zero obstacles, and produced 1 polygon (the untrimmed floor outline).

**This bug was present through all 6 sessions.** The timing fixes (Sessions 3–6) were necessary for other reasons but never addressed the actual geometry scanning problem.

### Fix (Session 7): Use `NavigationServer2D.parse_source_geometry_data` with scene root

Instead of `nav_region.bake_navigation_polygon(false)`, use the NavigationServer2D API directly with `self` (the level node = actual scene root) as the scan root:

```gdscript
## BEFORE (wrong — only scans NavigationRegion2D's own children):
nav_region.bake_navigation_polygon(false)

## AFTER (correct — scans ALL children of the scene root including walls):
var nav_poly: NavigationPolygon = nav_region.navigation_polygon
var source_geometry := NavigationMeshSourceGeometryData2D.new()
NavigationServer2D.parse_source_geometry_data(nav_poly, source_geometry, self)
NavigationServer2D.bake_from_source_geometry_data(nav_poly, source_geometry)
```

`self` is the level's GDScript class (e.g., `LabyrinthLevel`), which is the actual scene root node. Passing it to `parse_source_geometry_data` makes the parser scan ALL of LabyrinthLevel's children — including `Environment/Walls/WallTop` etc. — respecting `parsed_geometry_type` and `parsed_collision_mask` settings from the NavigationPolygon.

### NavMesh Overlay Fix (Session 7)

Restored `nav_mesh_monitor.gd` to the main branch version (reading `outlines` from the NavigationPolygon, not baked polygon triangles). The main branch approach works because:
- Outlines are set in `.tscn` files and always available immediately
- No timing coordination needed (no need to wait for bake)
- Shows the walkable boundary rectangle — helpful for confirming navmesh extent

### Expected Results After Session 7 Fix

Game log should show:
```
[LabyrinthLevel] Baking navmesh (Issue #1188): scanning scene root for wall colliders on layer 4
[LabyrinthLevel] Navmesh bake complete: N polygons (>1 means walls were carved)
```

Where `N >> 1` (typically 50–200 per level). This confirms walls were carved and NavigationAgent2D paths will route around them correctly.

### Files Updated (Session 7)

All 13 level scripts — same list as Session 6, same function `_bake_navmesh_after_physics_frame` updated to use `NavigationServer2D.parse_source_geometry_data(nav_poly, source_geometry, self)` instead of `nav_region.bake_navigation_polygon(false)`.

- `scripts/autoload/nav_mesh_monitor.gd` — restored to main branch version
- `docs/case-studies/issue-1188/game-logs/game_log_20260320_111647.txt` — owner's Session 7 log
