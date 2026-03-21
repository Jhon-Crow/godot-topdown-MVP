# Case Study: Issue #1216 — Navmesh Does Not Account for Walls

**Issue:** [#1216](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1216) — "fix нав меш"
**PR:** [#1217](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1217)
**Status:** Partially fixed (root causes 1, 2 & 3 resolved; root causes 4 & 5 being addressed)
**Date:** 2026-03-21
**Engine:** Godot 4.3-stable

---

## 1. Problem Statement

**Original report (translated from Russian):**
> "The navmesh doesn't account for walls, so enemies try to pass through walls to reach the player. Fix it. Don't break the navmesh display when the experimental option is enabled."

**Follow-up report (2026-03-21):**
> "Already better, check if it's the navmesh or the enemy pathfinding logic (they still periodically walk into walls)"
> — with game log `game_log_20260321_002214.txt` attached

---

## 2. Data Sources

| File | Description |
|------|-------------|
| `game_log_20260321_002214.txt` | Full game log from session on BuildingLevel (after Labyrinth tutorial) |
| `scenes/levels/BuildingLevel.tscn` | BuildingLevel scene with wall/enemy positions |
| `scripts/levels/building_level.gd` | BuildingLevel script with navmesh setup |
| `scripts/objects/enemy.gd` | Enemy AI including patrol and stuck detection |
| `scripts/levels/labyrinth2_level.gd` | Affected level (root cause #1) |
| `scripts/levels/roguelike_level.gd` | Affected level (root cause #2) |

---

## 3. Timeline / Sequence of Events

### Pre-fix State

```
Before PR #1217:
  labyrinth2_level.gd::_setup_navigation():
    NavigationServer2D.bake_from_source_geometry_data(nav_poly, NavigationMeshSourceGeometryData2D.new())
    # ↑ EMPTY geometry → walls never subtracted
    nav_region.bake_navigation_polygon()
    # ↑ async (threaded by default) → race condition with above

  roguelike_level.gd::_setup_navigation():
    # Created NavigationRegion2D with correct settings, but
    # NEVER called parse + bake → navmesh stayed empty
```

### Fix Applied (commit 8f6b9f6b)

Both files now use the canonical pattern from `arena_level.gd`, `building_level.gd`, etc.:

```gdscript
var source_geometry := NavigationMeshSourceGeometryData2D.new()
NavigationServer2D.parse_source_geometry_data(nav_poly, source_geometry, self)
NavigationServer2D.bake_from_source_geometry_data(nav_poly, source_geometry)
```

### Remaining Issue (from 2026-03-21 game log)

After the fix, the user observed that enemies **still periodically walk into walls**. The game log for `BuildingLevel` reveals two distinct symptoms:

1. **PATROL STUCK** — Enemy7 (pos: 1600,900) and Enemy10 (pos: 1200,1550) repeatedly trigger the stuck detection and skip to next patrol point.
2. **Corner check oscillation** — Enemy7's velocity alternates direction every 0.3s while barely moving.

---

## 4. Root Cause Analysis

### Root Cause #1 — Empty geometry bake (FIXED)

`labyrinth2_level.gd` passed a freshly constructed, empty `NavigationMeshSourceGeometryData2D` to `bake_from_source_geometry_data`. Since no wall collision shapes were in the geometry data, walls were never subtracted from the walkable polygon. Enemies could path straight through them.

**Why:** The programmer incorrectly assumed the bake call would auto-parse the scene. The `NavigationMeshSourceGeometryData2D` must be explicitly populated via `parse_source_geometry_data(nav_poly, data, root_node)` first.

### Root Cause #2 — Missing bake call (FIXED)

`roguelike_level.gd` created a `NavigationRegion2D` with correct settings (`parsed_geometry_type = STATIC_COLLIDERS`, `parsed_collision_mask = 4`) but never invoked `parse_source_geometry_data` or `bake_from_source_geometry_data`. The polygon remained as its empty default. Enemy `NavigationAgent2D` instances had no valid map data, effectively falling back to direct (wall-ignoring) movement.

### Root Cause #3 — Enemy spawn positions inside navmesh obstacle erosion zones (OPEN)

Godot 4's `NavigationPolygon` erodes all obstacles by `agent_radius` (set to **24 px** in BuildingLevel) before baking the walkable polygon. This erosion prevents agents from being routed closer to walls than their radius.

**Enemy7** spawns at **(1600, 900)**. The nearest obstacle is `Table2` at (1550, 950) with a 80×80 collision shape — actual extents: x ∈ [1510, 1590], y ∈ [910, 990]. After 24px erosion: x ∈ [**1486, 1614**], y ∈ [886, 1014].

Enemy7's spawn at x=1600 is **inside the eroded exclusion zone** (1600 < 1614). The NavigationServer2D snaps the agent's position to the nearest valid navmesh point (≈ x=1614), which is ~14px from spawn. When the agent requests paths from this snapped position, it generates routes that briefly traverse non-navigable geometry from the agent's **actual** physical position (1600,900), causing it to appear to walk through or into the table.

Additionally, the snapped position is at the erosion boundary — any small perturbation (ORCA avoidance, physics jitter) can push the agent back inside the exclusion zone, causing repeated re-snapping and the oscillating velocity pattern seen in the log (`target: 166°→89.9°→89.6°...`).

**Enemy10** spawns at **(1200, 1550)** near the `MainHall_WallTop` at (1200,1388). Patrol target **(1200,1700)** requires navigating south through a hallway bounded by `MainHall_WallLeft` (900,1600) and `MainHall_WallRight` (1500,1600). The stuck pattern (stuck at y≈1602) suggests Enemy10 is also placed near the boundary of an eroded wall section.

### Root Cause #4 — NavigationServer2D map propagation delay (SUSPECTED)

In Godot 4.3, `NavigationServer2D.bake_from_source_geometry_data()` without a callback runs **synchronously on the calling thread** and modifies the `NavigationPolygon` resource. However, the NavigationServer2D's internal map update (which propagates the new polygon to the physics server's navigation map) happens during the **next physics synchronization step** — not immediately.

If `_setup_navigation()` is called in `_ready()` and enemies also initialize in `_ready()` (child nodes' `_ready` runs before parent), there is a window of **one physics frame** where enemy `NavigationAgent2D` instances query a stale navigation map. During this first frame, paths are computed on the old/empty navmesh, potentially crossing walls.

This explains the "periodically" qualifier — it affects the first path query after level load, not every movement.

**Evidence from Godot 4.3 docs / source:**
> `NavigationServer2D.bake_from_source_geometry_data()` — "When baking is done without a callback the baking is synchronous but the navigation mesh will not be updated until the next physics frame."
> — Godot 4 Navigation documentation

---

## 5. Why `building_level.gd` Was Not Listed as Affected (But Exhibits Root Cause #3)

The original fix focused on `labyrinth2_level.gd` and `roguelike_level.gd` because they had broken baking. `building_level.gd` already had correct `parse + bake` code. However, its **scene file** has Enemy7 placed inside Table2's eroded exclusion zone — a scene design issue separate from the baking logic.

The levels listed as "NOT affected" in PR #1217 (`beach`, `decadence`, `docks`, `factory`) use `bake_navigation_polygon(false)` which is synchronous and reads geometry from the `.tscn`'s pre-configured `NavigationPolygon`. These do not share root cause #1 or #2.

---

## 6. Proposed Solutions

### Solution A: Fix Enemy7 spawn position in BuildingLevel.tscn (addresses Root Cause #3)

Move Enemy7 from (1600,900) to a clear open area in Room 4. The room spans x:1376–1776, y:800–1012. A safe center position away from Table2 (1550,950, eroded to 1486–1614 × 886–1014) would be approximately **(1700, 870)** or **(1680, 850)**.

Similarly review Enemy10 at (1200,1550) relative to MainHall walls.

**Pros:** Minimal code change. Directly fixes the snapping/oscillation symptom.
**Cons:** Requires visual map review; other levels may have similar placement issues.

### Solution B: Add one-frame delay before enemies start patrolling (addresses Root Cause #4)

In `building_level.gd::_ready()`, defer enemy activation by one physics frame after baking:

```gdscript
func _ready() -> void:
    _setup_navigation()
    # Wait one physics frame for NavigationServer2D to propagate the new map
    await get_tree().physics_frame
    _setup_enemy_tracking()
    ...
```

**Pros:** Ensures all enemies use the freshly-baked map on first path query.
**Cons:** Adds a single-frame delay to level startup (imperceptible). Should be applied to all affected levels.

### Solution C: Use `NavigationServer2D.map_changed` signal (addresses Root Cause #4)

Connect to `NavigationServer2D.map_changed` and activate enemies only after the signal fires:

```gdscript
func _ready() -> void:
    _setup_navigation()
    NavigationServer2D.map_changed.connect(_on_nav_map_changed, CONNECT_ONE_SHOT)

func _on_nav_map_changed(_map: RID) -> void:
    _setup_enemy_tracking()
```

**Pros:** Precise — no hardcoded delay.
**Cons:** `map_changed` fires for any map change; need to filter by the correct map RID. More complex.

### Solution D: Use existing `bake_navigation_polygon(false)` pattern (addresses Root Cause #4)

Migrate affected levels to the synchronous `nav_region.bake_navigation_polygon(false)` pattern (already working in `beach`, `docks`, `factory` levels) instead of the manual `parse + bake`. According to Godot 4.3 docs, `bake_navigation_polygon(false)` is "baking on main thread" and updates the server map in the same frame.

**Pros:** Consistent with existing working pattern; guaranteed same-frame map update.
**Cons:** Requires `NavigationPolygon` resource to already have `parsed_geometry_type` and `parsed_collision_mask` set in the scene file (not set programmatically at runtime).

### Solution E: Validate and clamp patrol points to nearest navmesh position (addresses Root Cause #3)

In `_setup_patrol_points()` in `enemy.gd`, validate each patrol point against the navmesh and snap it to the nearest valid position:

```gdscript
func _setup_patrol_points() -> void:
    _patrol_points.clear()
    _patrol_points.append(_get_valid_nav_point(_initial_position))
    for offset in patrol_offsets:
        _patrol_points.append(_get_valid_nav_point(_initial_position + offset))

func _get_valid_nav_point(pos: Vector2) -> Vector2:
    if _nav_agent == null: return pos
    return NavigationServer2D.map_get_closest_point(_nav_agent.get_navigation_map(), pos)
```

**Pros:** Fixes patrol stuck for any enemy placed near wall edges. Robust against future scene design mistakes.
**Cons:** Requires `_nav_agent` to be valid and map to be ready at setup time (timing dependency).

---

## 7. Recommended Action Plan

1. **Implement Solution B** (one-frame physics delay) in all levels that call `NavigationServer2D.parse_source_geometry_data + bake_from_source_geometry_data` in `_ready()`: `building_level.gd`, `labyrinth_level.gd`, `labyrinth2_level.gd`, `roguelike_level.gd`, `arena_level.gd`, `revolver_level.gd`, `castle_level.gd`, `city_level.gd`, `test_tier.gd`.

2. **Move Enemy7 in BuildingLevel.tscn** from (1600,900) to ≥(1640,900) or another clear position, keeping it inside Room 4.

3. **Implement Solution E** as a general defensive measure in `enemy.gd::_setup_patrol_points()` using `call_deferred` to ensure it runs after the navigation map is ready.

---

## 8. Key Metrics from Game Log

| Metric | Value |
|--------|-------|
| Session level | BuildingLevel (after LabyrinthLevel tutorial) |
| Enemies exhibiting stuck | Enemy7, Enemy10 |
| Enemy7 stuck position | (1611, 899) — 11 px from spawn (1600, 900) |
| Enemy10 stuck position | (1200, 1602) — 52 px from spawn (1200, 1550) |
| PATROL STUCK threshold | 20 px in 1.5 s |
| Table2 eroded boundary (x) | 1486–1614 (agent_radius=24) |
| Enemy7 spawn x | 1600 (inside eroded zone: < 1614) |
| Stuck events observed | 3 (Enemy7×2, Enemy10×1 in first 16 s of BuildingLevel) |

---

## 9. Follow-up Findings (2026-03-21 session 2)

### Root Cause #5 — IDLE enemies walk directly to player via ally intel (regression)

**Symptom:** Enemies in IDLE state (patrol/guard, never having engaged the player) were
sometimes walking directly toward the player. Reported: "sometimes enemies in idle state walk
directly toward the player."

**Root Cause:** In `_process_idle_state()`, the memory system check (Issue #297) triggered
`_transition_to_pursuing()` for ANY enemy with memory confidence >= 0.5, including:
- Enemies that received intel from an ally who saw the player (confidence 1.0 × 0.9 = 0.9)
- Enemies that heard gunshots from the player (confidence 0.7)

Since `_memory.is_medium_confidence()` fires at >= 0.5, a pure patrol enemy receiving
one ally intel broadcast would immediately start pursuing the player — regardless of whether
the enemy itself had ever seen the player.

**Fix (committed 2026-03-21):** Gate the memory→pursuing transition on `_has_left_idle`:

```gdscript
# Before (bug):
if _memory and _memory.has_target():
    if _memory.is_high_confidence(): _transition_to_pursuing(); return
    elif _memory.is_medium_confidence(): _transition_to_pursuing(); return

# After (fix):
if _has_left_idle and _memory and _memory.has_target():
    if _memory.is_high_confidence(): _transition_to_pursuing(); return
    elif _memory.is_medium_confidence(): _transition_to_pursuing(); return
```

`_has_left_idle` is set to `true` the first time an enemy transitions out of IDLE state
(i.e., it has previously engaged). Pure patrol enemies (never engaged) will only react to
direct visual detection of the player.

### Root Cause #4 Confirmed — Navmesh snap runs on stale map (Enemy10 stuck)

**Symptom:** Enemy10 at (1200, 1550) is consistently snapped to (1200, 1424) by the patrol
point snap code introduced in fix for Root Cause #3. The snap moves the enemy 126px north
into the wrong area of the corridor, causing repeated PATROL STUCK at (1200, 1424).

**Root Cause Confirmed:** `bake_from_source_geometry_data()` is synchronous for polygon
computation but the NavigationServer2D's internal map update happens on the NEXT physics
frame. The patrol snap code runs on physics frame 1 (via `_physics_process`), which is the
SAME frame as `_ready()` completes. At this point the NavServer map is stale (shows
pre-bake or empty data), so `map_get_closest_point(1200, 1550)` returns (1200, 1424) — the
nearest edge of the pre-baked flat rectangle cut off at y=1424 by wall geometry already
present in the pre-baked resource.

**Evidence from logs:**
- `game_log_20260321_065153.txt` line 704: snap fires at 06:52:20 (frame 3 from ReplayManager)
- Line 705: immediately triggers `PATROL corner check: angle 180.0°` — enemy moving NORTH
- Line 739: `PATROL STUCK: pos=(1200, 1424.01)` — enemy never moved past the snapped position

**Fix (committed 2026-03-21):** Record `_spawn_physics_frame = Engine.get_physics_frames()`
in `_ready()` and add `Engine.get_physics_frames() > _spawn_physics_frame` as a guard before
the snap. This ensures the snap runs in physics frame 2+, after the NavServer has had one
full physics step to propagate the freshly-baked navmesh:

```gdscript
# Before (bug):
if not _patrol_points_snapped and _nav_agent != null:

# After (fix):
if not _patrol_points_snapped and _nav_agent != null and Engine.get_physics_frames() > _spawn_physics_frame:
```

---

## Session 4 (2026-03-21): Main Hall Isolated + CASING_KICK Idle Pursuit

### New Logs
- `logs/game_log_20260321_065153.txt` — Lab+Building session: Enemy1 IDLE→PURSUING via memory (confidence 0.62)
- `logs/game_log_20260321_065417.txt` — Building: Enemy10 cycling stuck at y=1424
- `logs/game_log_20260321_072808.txt` — Lab+Building: Enemy10 wall-patrol cycle, corner checks near ±180°
- `screenshot_office2_stuck.png` — user screenshot of stuck enemy in lower-left office 2

### Root Cause 4: Main Hall Corridor Completely Isolated

After the snap fix, Enemy10's patrol points `(1000,1550)`, `(1200,1550)`, `(1400,1550)` all
mapped to y=1424 (wall boundary). The reason: entrance gaps on both sides of `MainHall_WallTop`
are only 40 px wide, below the minimum passable width of `2 × agent_radius = 48 px`.

```
Gap left:  [936, 976] = 40 px  → IMPASSABLE (agent diameter = 48 px)
Gap right: [1424, 1464] = 40 px → IMPASSABLE
```

The main hall is a completely isolated navmesh island; `map_get_closest_point` returns the
globally nearest point on the CONNECTED navmesh, which is the wall boundary at y=1424.

**Fix applied:** Shorten `MainHall_WallTop` from 400×24 to 200×24 (use
`RectangleShape2D_interior_wall_short_h`), move `MainHall_CornerTL` from (1000,1388) to
(1100,1388), `MainHall_CornerTR` from (1400,1388) to (1300,1388). Entrance gaps now 140 px.

Also added snap distance guard in `_process_patrol`: only snap if closest navmesh point is
within `path_desired_distance × 2` of original, preventing cross-wall snaps.

### Root Cause 5: PATROL STUCK Does Not Advance Index Immediately

When stuck, the handler set `_is_waiting_at_patrol_point = true` which eventually advances
the index after `patrol_wait_time` seconds. But if the wait timer was reset, the index
wasn't advanced, and the enemy could retry the stuck point.

**Fix applied:** Explicitly increment `_current_patrol_index` at stuck-detection time:
```gdscript
_current_patrol_index = (_current_patrol_index + 1) % _patrol_points.size()
```

### Root Cause 6: CASING_KICK Sound Sets `_has_left_idle` on Pure IDLE Enemies

CASING_KICK handler called `_transition_to_pursuing()` unconditionally from IDLE
(line 607), which set `_has_left_idle = true`. Enemy then returns to IDLE after failed
search, and ally intel with medium confidence (≥ 0.6) triggers pursuit again.

**Fix applied:** Guard CASING_KICK pursuit with `_has_left_idle`:
```gdscript
if _current_state == AIState.IDLE and _has_left_idle: _transition_to_pursuing()
```

RELOAD and EMPTY_CLICK retain unconditional pursuit (player explicitly vulnerable).

---

## 9. Online References

- [Godot 4 Navigation Overview](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_overview.html) — explains parse/bake pipeline
- [NavigationServer2D.bake_from_source_geometry_data](https://docs.godotengine.org/en/stable/classes/class_navigationserver2d.html#class-navigationserver2d-method-bake-from-source-geometry-data) — note on physics frame delay
- [Godot Issue #77396](https://github.com/godotengine/godot/issues/77396) — NavigationAgent2D path not updated after bake in same frame
- [Godot Navigation Agent Radius](https://docs.godotengine.org/en/stable/classes/class_navigationpolygon.html#class-navigationpolygon-property-agent-radius) — erodes obstacles by agent_radius before baking

---

---

## Session 5 — game_log_20260321_110936.txt (2026-03-21 11:09)

**User report:** "possibly need to make adjustment for new enemy collisions (enemies now bump into walls instead of walking along them), update from main."

**Log analysis:**

| Observation | Detail |
|---|---|
| Levels visited | LabyrinthLevel → BuildingLevel (13s) → CastleLevel → [others] |
| BuildingLevel enemies | 10 enemies spawned correctly; Enemy7 at (1700,870) and Enemy10 at (1200,1550) |
| Patrol snaps | Enemy7 and Enemy10 both logged "Patrol points snapped to navmesh (Issue #1216)" ✓ |
| Enemy10 patrol | Cycling E/W offsets (±200,0) as intended |
| No STUCK events | No PATROL STUCK entries in BuildingLevel session |

**Root Cause (Session 5): Patrol wall-pressing from old movement code**

The user's build predates Issue #1220 fix (`_move_to_target_nav` for patrol). Prior to that fix,
patrol used raw `_nav_agent.get_next_path_position()` direction without wall avoidance or ORCA
steering. Enemies would walk directly toward the next nav waypoint and press against any wall
they encountered.

**Fix merged (Session 5):** Merged upstream/main which includes:
- `_move_to_target_nav` for patrol (Issue #1220): patrol now uses wall-avoidance + ORCA + slide-collision corner escape
- All prior #1216 fixes retained: `_has_left_idle` guards, patrol snap timing, Main Hall entrance widening
- `nav_region.bake_navigation_polygon(false)` for labyrinth2 nav overlay (Issue #1224)

*Case study updated: 2026-03-21*
