# Case Study: Issue #1218 — fix построение маршрутов врагов (Fix Enemy Pathfinding Through Walls)

## Issue Summary

**Title:** fix построение маршрутов врагов (Fix enemy route building)

**Description (translated from Russian):**
> Make it so that enemy routes are built taking walls into account (currently enemies try to pass through the wall to the player). Implement it.

**Core complaint:** Enemies move directly toward the player in a straight line, ignoring walls. They get stuck pressing against walls instead of navigating around them.

---

## Codebase Architecture: How Enemy Movement Currently Works

### Navigation Stack

The game uses Godot 4's `NavigationAgent2D` for pathfinding. The `Enemy.tscn` scene (line 81–91) defines:

```gdscript
[node name="NavigationAgent2D" type="NavigationAgent2D" parent="."]
path_desired_distance = 40.0
target_desired_distance = 10.0
avoidance_enabled = true
radius = 24.0
neighbor_distance = 100.0
max_neighbors = 10
time_horizon_agents = 1.5
time_horizon_obstacles = 1.0
max_speed = 320.0
```

The `enemy.gd` script references this as `_nav_agent: NavigationAgent2D = $NavigationAgent2D`.

### Core Navigation Functions

**`_move_to_target_nav(target_pos, speed)`** — the primary movement function. Sets `_nav_agent.target_position`, calls `_nav_agent.get_next_path_position()`, applies wall avoidance via `_apply_wall_avoidance()`, and sets `velocity`. Called from SEEKING_COVER, PURSUING, FLANKING, SEARCHING, and grenade EVASION states.

**`_get_nav_direction_to(target_pos)`** — thin wrapper that sets `_nav_agent.target_position` and returns direction to `_nav_agent.get_next_path_position()`.

**`_apply_wall_avoidance(direction)`** — a secondary raycast-based system that blends 8 wall-detection raycasts (±0°, ±20°, ±45°, ±70°, 180°) with the nav direction. Only fires if the nav agent gives a bad path or none.

### Where Navmesh IS Used (correct behavior)

- `_process_seeking_cover_state()` → `_move_to_target_nav(_cover_position, ...)`
- `_process_pursuing_state()` → `_move_to_target_nav(_pursuit_next_cover, ...)` and `_move_to_target_nav(target_pos, ...)`
- `_process_flanking_state()` → `_move_to_target_nav(_flank_target, ...)`
- `_process_grenade_evasion_state()` → nav agent used correctly

### Where Nav Is BYPASSED (the problem)

**COMBAT approach phase** (`_process_combat_state()`, lines ~1563–1570):
```gdscript
var move_direction := direction_to_player
move_direction = _apply_wall_avoidance(move_direction)
velocity = move_direction * combat_move_speed
```
This moves the enemy **directly toward the player** using only the lightweight raycast wall avoidance — not the navmesh path. If the player is across a wall, the enemy walks into the wall.

**RETREATING state** (`_process_retreating_state()`, lines ~1933–1937):
```gdscript
var nav_direction: Vector2 = _get_nav_direction_to(_cover_position)
if nav_direction != Vector2.ZERO:
    nav_direction = _apply_wall_avoidance(nav_direction)
    velocity = nav_direction * combat_move_speed * 0.7
```
This does use `_get_nav_direction_to`, but if nav_direction is ZERO (nav agent not yet synced) it stops, and the wall avoidance blend can still push into walls.

**PURSUING approach sub-phase** (`_process_pursuing_state()`, lines ~2086–2120):
When `_pursuit_approaching = true` and no cover is found, the enemy enters a direct-move-toward-player fallback. Though it calls `_move_to_target_nav()`, if the nav agent has no valid path, `_get_nav_direction_to` falls back to `(target_pos - global_position).normalized()` (raw direction, line 4717):
```gdscript
func _get_nav_direction_to(target_pos: Vector2) -> Vector2:
    if _nav_agent == null: return (target_pos - global_position).normalized()
```

**`PursuingState` class** (`scripts/ai/states/pursuing_state.gd`, lines 62–69):
```gdscript
var direction: Vector2 = (enemy._player.global_position - enemy.global_position).normalized()
if enemy.has_method("_apply_wall_avoidance"):
    direction = enemy._apply_wall_avoidance(direction)
enemy.velocity = direction * enemy.combat_move_speed
```
The `PursuingState` state object (the newer state-machine architecture) uses **no navmesh at all** — pure direct movement with raycast avoidance blending. This is a separate code path from `enemy.gd`'s `_process_pursuing_state()` function.

---

## Navigation Mesh Setup Analysis

### Per-Level Nav Polygon Configuration

All level scenes (ArenaLevel, BeachLevel, BuildingLevel, CastleLevel, CityLevel, DecadenceLevel, DocksLevel, FactoryLevel, Labyrinth2Level, LabyrinthLevel, RevolverLevel, RoguelikeLevel, TestTier) share the same NavigationPolygon settings:

```
parsed_geometry_type = 1      # PARSED_GEOMETRY_STATIC_COLLIDERS
parsed_collision_mask = 4     # Layer 3 (walls)
source_geometry_mode = 0      # SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
agent_radius = 24.0
```

This is correct in principle: walls on collision layer 3 (mask = 4) will be excluded from the walkable area.

### Runtime Baking Pattern

All levels call `NavigationServer2D.parse_source_geometry_data()` + `NavigationServer2D.bake_from_source_geometry_data()` at runtime in `_ready()`. Several also call `nav_poly.clear()` and re-add a floor outline before baking. This is the correct pattern.

### Known Godot 4 Baking Issues

A documented Godot 4 bug ([#85550](https://github.com/godotengine/godot/issues/85550)) shows that `bake_from_source_geometry_data` can handle obstructions improperly in some cases. When called async, the mesh appears to bake but agents cannot find paths. The synchronous call used here should be safe.

Another known issue ([#90125](https://github.com/godotengine/godot/issues/90125)): NavigationPolygon 2D's `parsed_collision_mask` uses 3D physics layer terminology in the inspector, which can confuse designers but works correctly in code.

---

## Root Cause Analysis

### Root Cause 1 (PRIMARY): COMBAT State Bypasses NavigationAgent2D

When an enemy is close enough to see the player and enters the COMBAT approach phase, movement is computed as:

```gdscript
var move_direction := direction_to_player  # raw straight-line vector
move_direction = _apply_wall_avoidance(move_direction)  # lightweight raycast blend
velocity = move_direction * combat_move_speed
```

The `NavigationAgent2D` is **never consulted**. This means:
- If the player is visible but behind a corner or thin wall, the enemy walks directly into the wall
- The 8-raycast wall avoidance (`_apply_wall_avoidance`) can partially redirect the enemy along a wall surface, but cannot route it around a corner or through a doorway
- The enemy oscillates at the wall corner because the avoidance raycasts cancel each other out (described in detail in Case Study #1107)

### Root Cause 2: `PursuingState` Class Uses No Navmesh

The `scripts/ai/states/pursuing_state.gd` class (the newer modular state architecture) bypasses `_move_to_target_nav()` entirely in its `_process_approach_phase()` and `_process_cover_movement()` methods. Both use raw `direction * speed` with only `_apply_wall_avoidance()` blending. This is a separate code path from the navmesh-using `_process_pursuing_state()` in `enemy.gd`.

### Root Cause 3: Nav Agent Null Fallback Goes Direct

`_get_nav_direction_to()` has a critical null guard:
```gdscript
if _nav_agent == null: return (target_pos - global_position).normalized()
```
If `_nav_agent` is null for any reason (scene tree order, deferred loading), all nav-based movement silently degrades to straight-line movement with no warning.

### Root Cause 4: Wall Avoidance Constants Are Too Lenient

```gdscript
const WALL_CHECK_DISTANCE: float = 60.0   # Wall check distance
const WALL_AVOIDANCE_MIN_WEIGHT: float = 0.7  # Weight when very close to wall
const WALL_AVOIDANCE_MAX_WEIGHT: float = 0.3  # Weight when far from wall
```

At 60 pixels (enemy radius = 24px), the raycasts detect walls but the blending weights mean even when very close to a wall, only 70% of the motion is corrected. In narrow corridors this can still result in the enemy pressing into a wall.

### Root Cause 5: No Navmesh Used for Close-Range Retreat

When backing toward cover in the retreating state, `_get_nav_direction_to()` is called but if it returns `Vector2.ZERO` (navigation finished / target unreachable), the enemy stops moving entirely instead of using a fallback.

---

## Behavior Observed by User

The user reports enemies "пытаются пройти к игроку сквозь стену" (try to pass to the player through the wall). This is consistent with Root Causes 1 and 2: in the COMBAT approach phase and in the PursuingState approach phase, enemies move directly toward the player's position with only weak raycast-based wall avoidance, which cannot route around walls.

### Affected States

| AI State | Uses Navmesh? | Wall Handling |
|----------|---------------|---------------|
| SEEKING_COVER | Yes (`_move_to_target_nav`) | Correct |
| PURSUING (main path) | Yes (`_move_to_target_nav`) | Correct |
| PURSUING (approach fallback) | Yes | Correct |
| FLANKING | Yes (`_move_to_target_nav`) | Correct |
| EVADING_GRENADE | Yes | Correct |
| SEARCHING | Yes | Correct |
| **COMBAT approach** | **No** | **Broken — walks into walls** |
| **PursuingState class** | **No** | **Broken — walks into walls** |
| RETREATING | Partial | Broken when nav returns ZERO |

---

## Proposed Solutions

### Solution 1 (RECOMMENDED): Replace Direct Movement in COMBAT Approach with `_move_to_target_nav()`

**File:** `scripts/objects/enemy.gd`, in `_process_combat_state()`, the approach phase block (around line 1563–1570).

Replace:
```gdscript
var move_direction := direction_to_player
move_direction = _apply_wall_avoidance(move_direction)
velocity = move_direction * combat_move_speed
rotation = direction_to_player.angle()
```

With:
```gdscript
_move_to_target_nav(_player.global_position, combat_move_speed)
rotation = direction_to_player.angle()  # Keep facing player while navigating
```

This makes the COMBAT approach use the full navmesh path, routing around walls and corners. The rotation override keeps the enemy aimed at the player (for shooting) even while the velocity follows the curved path.

**Impact:** Low risk. `_move_to_target_nav()` already sets both velocity and rotation; the rotation override restores aiming behavior.

---

### Solution 2: Fix `PursuingState` Class to Use `_move_to_target_nav()`

**File:** `scripts/ai/states/pursuing_state.gd`

In `_process_approach_phase()`, replace direct velocity assignment:
```gdscript
var direction: Vector2 = (enemy._player.global_position - enemy.global_position).normalized()
if enemy.has_method("_apply_wall_avoidance"):
    direction = enemy._apply_wall_avoidance(direction)
enemy.velocity = direction * enemy.combat_move_speed
```

With a call to the enemy's nav-based movement:
```gdscript
if enemy.has_method("_move_to_target_nav"):
    enemy._move_to_target_nav(enemy._player.global_position, enemy.combat_move_speed)
```

Same fix needed in `_process_cover_movement()` — replace the direction/velocity block with `_move_to_target_nav(_pursuit_next_cover, ...)`.

---

### Solution 3: Guard Against Null Nav Agent Degrading to Direct Movement

**File:** `scripts/objects/enemy.gd`, `_get_nav_direction_to()`

Add a log warning when nav_agent is null so this silent fallback is surfaced:
```gdscript
func _get_nav_direction_to(target_pos: Vector2) -> Vector2:
    if _nav_agent == null:
        _log_to_file("WARNING: _nav_agent is null - falling back to direct movement")
        return (target_pos - global_position).normalized()
    ...
```

---

### Solution 4: Add Navmesh Validity Check Before Approaching

Before entering the COMBAT approach phase or the PursuingState approach phase, check if the navmesh has a valid path to the target. If not, stay at current position or transition to a different state rather than walking into walls:

```gdscript
func _has_nav_path_to(target_pos: Vector2) -> bool:
    if _nav_agent == null: return false
    _nav_agent.target_position = target_pos
    return not _nav_agent.is_navigation_finished() or \
           global_position.distance_to(target_pos) < 30.0
```

This function already exists in `enemy.gd` (around line 4765) but is not used in the COMBAT approach phase.

---

### Solution 5 (Alternative Architecture): AStarGrid2D for Fine-Grained Wall Avoidance

For levels with complex wall geometry (LabyrinthLevel, Labyrinth2Level, BuildingLevel), `AStarGrid2D` can complement `NavigationAgent2D`. AStarGrid2D maps a grid over the level, marks wall cells as solid, and returns cell-by-cell paths that rigorously avoid walls.

**Trade-off:** AStarGrid2D requires a discrete grid resolution and doesn't natively do agent-to-agent avoidance (ORCA). Best used in addition to, not instead of, `NavigationAgent2D`.

**Reference:** [Pathfinding Guide for 2D Top-View Tiles in Godot 4.3](https://casraf.dev/2024/09/pathfinding-guide-for-2d-top-view-tiles-in-godot-4-3/)

---

### Solution 6 (Enhancement): Increase Wall Check Distance

The current `WALL_CHECK_DISTANCE = 60.0` (slightly more than 2× enemy radius of 24px) means the enemy detects walls late. Increasing to 100–120px gives more room to steer around walls before collision:

```gdscript
const WALL_CHECK_DISTANCE: float = 100.0   # Increased from 60
const WALL_AVOIDANCE_MIN_WEIGHT: float = 0.9  # Stronger correction when close
```

This is a minor improvement; it won't route around corners, but reduces wall-hugging in open corridors.

---

## Implementation Priority

1. **Solution 1** (COMBAT approach navmesh): Highest priority. Most reported wall-walking happens during combat approach. One-line change in a known location.
2. **Solution 2** (PursuingState class): Second priority. The modular state class bypasses navmesh entirely.
3. **Solution 3** (null guard logging): Low effort, high diagnostic value.
4. **Solution 4** (navmesh validity check): Medium effort, prevents state-machine thrash.
5. **Solution 6** (wall check distance): Minor tuning enhancement.

---

## Existing Components and Libraries That Solve Similar Problems

| Component / Library | Description | Relevance |
|--------------------|-------------|-----------|
| `NavigationAgent2D` (Godot built-in) | Pathfinding via nav polygon + ORCA agent avoidance | Already in use; needs to be used in COMBAT approach |
| `AStarGrid2D` (Godot built-in) | Grid-based A* pathfinding with explicit wall cells | Complementary option for tile-heavy levels |
| `NavigationObstacle2D` (Godot built-in) | Dynamic obstacle that agents path around at runtime | Could be added to moving obstacles (player, allies) |
| `_apply_wall_avoidance()` (custom) | 8-raycast blended avoidance | Already in use as secondary layer; keep as fallback |
| `_check_wall_ahead()` (custom) | Wall ahead detection for 8 radial angles | Works but cannot route around corners |

---

## Related Issues in This Repo

- **Issue #1107**: Machete enemy gets stuck at L-shaped wall corners — root cause identical (physics body pinned at concave corner when using direct velocity). Fix: corner escape using `get_slide_collision()` normals in `_move_to_target_nav()`.
- **Issue #1146**: Enemies pass through each other — fix: ORCA avoidance enabled on `NavigationAgent2D`, separation force added.
- **Issue #1187**: Nav mesh visibility toggle — added `NavMeshMonitor` autoload with custom polygon overlay for debugging.
- **Issue #318**: Movement toward memory-based target position — already fixed with `_move_to_target_nav()` in pursuing state.

---

---

## Round 2 Analysis: Remaining Issues After Initial Fix (2026-03-21)

### Logs Analyzed

| Log File | Level | Key Findings |
|---|---|---|
| `game_log_20260320_235331.txt` | BuildingLevel | Enemy7/Enemy10 patrol stuck — old nav bake pattern |
| `game_log_20260320_235426.txt` | BuildingLevel | Same stuck patterns — confirmed root cause |
| `game_log_20260321_065153.txt` | LabyrinthLevel → BuildingLevel | Enemy10 stuck at (1200,1424), Enemy7 stuck; IDLE→PURSUING via memory |
| `game_log_20260321_065417.txt` | LabyrinthLevel | Patrol corner check oscillation in Enemy3 |
| `game_log_20260321_065842.txt` | LabyrinthLevel → BuildingLevel | **Enemy7 still stuck at (1611.806, 900); FPS: 2-3 fps; Enemy10 sees player on spawn** |

Screenshot: `office2_stuck_screenshot.png` — two enemies in IDLE state visible near Office 2 top-left; red arrow indicates bottom-left stuck area.

### New Root Cause A: Enemy7 Stuck at Table2 East Nav Boundary

**Geometry analysis (BuildingLevel.tscn):**

- `Table2` at (1550, 950), shape `cover_table` (80×80px):
  - Physical bounds: x:[1510,1590], y:[910,990]
  - With agent_radius=24: **nav exclusion x:[1486,1614], y:[886,1014]**
- `Room4_WallTop` at (1576, 788), shape `interior_wall_h` (400×24px):
  - Physical bounds: x:[1376,1776], y:[776,800]
  - With agent_radius=24: **nav exclusion x:[1352,1800], y:[752,824]**
- Enemy7 spawn (after previous fix): (1650, 900)
- Patrol targets: (1800, 900) [east], (1450, 900) [west]

**Why it gets stuck at x=1611:**

Enemy7 at x=1650 is only 36px east of Table2's east nav exclusion (x=1614). The nav agent routes Enemy7 WEST first (to patrol target index 0 = spawn position), bringing it to x=1611 — just inside Table2's nav exclusion east boundary. The corridor between Table2 (x=1614) and spawn (x=1650) is only 36px, narrower than one agent body. The enemy gets pinned against the nav exclusion boundary and oscillates due to corner-check interference.

Additionally, patrol target (1800, 900) sits at exactly x=1800 — the eastern nav exclusion boundary of Room4_WallTop (1776+24=1800). At this boundary, the snapped target is at the absolute edge of navigable space and the path may oscillate or round-trip.

**Fix:** Move Enemy7 spawn **far east** to (2000, 900), well clear of Table2 and Room4_WallTop. Offsets (+200, 0)/(-200, 0) give targets (2200, 900) and (1800, 900) in the open Room5 corridor. Alternatively, patrol in a north-south direction within the wider open space.

### New Root Cause B: FPS Drops (2-3 fps on BuildingLevel)

**Evidence from `game_log_20260321_065842.txt`:**
```
[06:58:45] [WARN] [FPS] Drop detected: 1 fps
[06:58:54] [WARN] [FPS] Drop detected: 3 fps
[06:58:57] [WARN] [FPS] Drop detected: 3 fps
[06:58:59] [WARN] [FPS] Drop detected: 3 fps
... (repeating every 1-2 seconds throughout the session)
```

The user has `Nav mesh visible: true` in ExperimentalSettings. The `nav_mesh_monitor.gd` autoload:
1. Connects `get_tree().node_added` to `_on_node_added` → fires for **every node** added during level loading
2. `_on_node_added` calls `call_deferred("_deferred_refresh")` for every `NavigationRegion2D` found
3. `_deferred_refresh()` calls `refresh()` which traverses the entire scene tree searching for nav regions

With 10 enemies × ~15 child nodes each = ~150 `node_added` signals during BuildingLevel load. Each fires a `_deferred_refresh`. While deferred calls are coalesced somewhat, this still causes excessive refreshes.

**During gameplay**: `map_get_closest_point()` is called **every frame** for every patrol enemy in `_process_patrol()`. With 2 patrol enemies at 60fps = 120 NavServer2D queries/second. This is not the main FPS culprit.

**Primary FPS culprit**: The nav mesh polygon overlay (`_draw()` in `_NavMeshDrawNode`) runs every frame. After our `bake_navigation_polygon(false)` fix, the nav polygon is now a complex shape (walls subtracted from floor polygon) with many vertices. The custom `draw_polygon` + `draw_polyline` on a complex polygon with many points runs every frame.

**Contributing factor**: The user has the nav mesh overlay enabled as a debug tool — this is expected to cause performance overhead. The fix is to either (a) optimize the overlay drawing, or (b) add a clear warning that nav mesh visible mode impacts FPS.

**Additional factor**: The `source_geometry_mode = 0` (ROOT_NODE_CHILDREN) means baking must traverse the entire scene tree, which may cause a main-thread stall during `_ready()`. This causes the initial `1 fps` drop at load time.

### New Root Cause C: Enemy10 Engages Player Immediately on Spawn

**Evidence:**
- Enemy10 spawns at (1200, 1550)
- Player spawns at (450, 1250)
- Distance: √((1200-450)² + (1550-1250)²) = √(562500+90000) ≈ 808px
- Line 487: `[Enemy10] Player distracted - priority attack triggered` — immediately after spawn
- This fires because Enemy10 has **line of sight** to the player across the main hall

**Analysis:** The MainHall has walls:
- `MainHall_WallTop` at (1200, 1388), x:[1000,1400], y:[1376,1400] — blocks y=1388 but not y=1400+
- `MainHall_WallLeft` at (900, 1600), y:[1400,1800] — blocks x=900 area
- `MainHall_WallRight` at (1500, 1600), y:[1400,1800] — blocks x=1500 area

The hallway from y=1400 to y=1600 between x=900 and x=1500 is open. Player at (450,1250) and Enemy10 at (1200,1550): the line of sight passes through the corridor opening. Enemy10 spawns already alert because the player is visible from its spawn position.

**This is NOT a code bug** — it's a level design issue. The player's entry position (450,1250) is within detection range of Enemy10's patrol spawn (1200,1550) with clear LoS. Fix: either move Enemy10 further east or add an occluding wall between the player spawn area and the main hall entrance.

### New Root Cause D: map_get_closest_point Called Every Frame in Patrol Hot Path

In `_process_patrol()` (line 4062):
```gdscript
var snapped_target := NavigationServer2D.map_get_closest_point(nav_map, target_point)
_nav_agent.target_position = snapped_target
```

This issues a NavigationServer query every frame even when the target hasn't changed. The nav agent's `target_position` setter already validates and snaps internally. The additional `map_get_closest_point` call adds redundant work.

**Fix:** Cache the snapped target and only re-snap when the patrol index changes.

---

## References

- [Godot docs: Using NavigationAgents](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationagents.html)
- [Godot docs: 2D Navigation Overview](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_introduction_2d.html)
- [Godot docs: NavigationPolygon](https://docs.godotengine.org/en/stable/classes/class_navigationpolygon.html)
- [Godot docs: Using Navigation Meshes](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationmeshes.html)
- [Godot Issue #85550: bake_from_source_geometry_data handles obstructions improperly](https://github.com/godotengine/godot/issues/85550)
- [Godot Issue #90125: NavigationPolygon uses 3D parsed_collision_mask](https://github.com/godotengine/godot/issues/90125)
- [Godot Issue #60354: NavigationAgent colliding with walls when rounding corners](https://github.com/godotengine/godot/issues/60354)
- [Godot Forum: NavigationAgent2D ignoring bounds of NavigationPolygon](https://forum.godotengine.org/t/navigationagent2d-ignoring-the-bounds-of-navigationregion2ds-navigationpolygon/57061)
- [Godot Forum: Enemy navigation issues](https://forum.godotengine.org/t/enemy-navigation-issues/110518)
- [Medium: 2D Navigation in Godot 4](https://stephan-bester.medium.com/2d-navigation-in-godot-4-b710902e609c)
- [casraf.dev: Pathfinding Guide for 2D Top-View Tiles in Godot 4.3](https://casraf.dev/2024/09/pathfinding-guide-for-2d-top-view-tiles-in-godot-4-3/)
- Case Study #1107 (machete corner stuck): `docs/case-studies/issue-1107/case-study.md`
- Case Study #1146 (enemy separation/ORCA): `docs/case-studies/issue-1146/analysis.md`
- Case Study #1187 (nav mesh visibility): `docs/case-studies/issue-1187/case-study.md`
