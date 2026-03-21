# Case Study: Issue #1218 — Enemy Routes Don't Respect Walls

## Problem Statement

Enemies try to walk through walls instead of navigating around them. When an enemy
spots the player through a doorway or around a corner, it moves in a straight line
toward the player, ignoring solid wall geometry.

**Level**: LabyrinthLevel (confirmed via game log `game_log_20260321_153957.txt`)

## Root Cause Analysis

Three distinct root causes were identified through game log analysis and code review.

### Root Cause 1: Wrong `source_geometry_mode` in NavigationPolygon

**File**: `scenes/levels/LabyrinthLevel.tscn` (and all other level .tscn files)

```
source_geometry_mode = 0   # SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
```

In Godot 4, `source_geometry_mode=0` (`ROOT_NODE_CHILDREN`) makes the navmesh baking
scan only the **direct children of the NavigationRegion2D node itself** — which has no
children in these scenes. Walls live in `Environment/Walls/*` and `Environment/InteriorWalls/*`,
which are siblings of `NavigationRegion2D`, not its children.

**Result**: The navmesh bake finds no geometry to exclude, producing a flat rectangle
covering the entire floor area. No walls are carved out. Enemies navigate in straight
lines through walls.

**Fix**: Change to `source_geometry_mode=1` (`GROUPS_WITH_CHILDREN`) and add
`groups=["navigation_source"]` to the `Environment` node. This tells the baking system
to scan all descendants of any node in the `navigation_source` group — including all
wall `StaticBody2D` nodes with `collision_layer=4`.

### Root Cause 2: Stale Pre-baked Polygon Data in Scene Files

**File**: `scenes/levels/LabyrinthLevel.tscn` (and other level files)

```gdscript
vertices = PackedVector2Array(48, 48, 1968, 48, 1968, 1128, 48, 1128)
polygons = [PackedInt32Array(0, 1, 2, 3)]
outlines = [PackedVector2Array(48, 48, 1968, 48, 1968, 1128, 48, 1128)]
```

This stale data is a simple 4-vertex rectangle with no walls carved out. Godot loads
this pre-baked polygon on scene load and uses it until a runtime bake happens. Since
pre-baked data is available, enemies start navigating immediately using the bad navmesh.

**Fix**: Remove the stale `vertices`, `polygons`, and `outlines` lines from `.tscn` files.
This forces Godot to start with an empty navmesh and wait for the runtime bake.

### Root Cause 3: Navmesh Bake During `_ready()` Queries PhysicsServer2D Too Early

**File**: `scripts/levels/labyrinth_level.gd` (and other level scripts)

```gdscript
func _ready() -> void:
    _setup_navigation()  # Called during _ready()
    ...

func _setup_navigation() -> void:
    nav_region.bake_navigation_polygon(false)  # Bakes immediately
```

`bake_navigation_polygon()` with `parsed_geometry_type=1` (`STATIC_COLLIDERS`) queries
`PhysicsServer2D` to find static body collision shapes. However, `PhysicsServer2D` only
registers shapes after the **first physics frame sync**, which happens after `_ready()`
completes. Calling bake during `_ready()` returns 0 polygons because the physics server
has no shapes registered yet.

**Evidence from game log** (first load at 15:39:57):
```
[NavMeshMonitor] refresh: region 'NavigationRegion2D' poly_count=1 vertex_count=4
```
Only 1 polygon (the prebaked rectangle) — walls were NOT carved.

**Evidence after proper bake** (15:40:52 via C# fallback):
```
[LevelInitFallback] Navigation mesh baked (C# fallback, Issue #1273): poly_count=97 vertex_count=138
```
97 polygons — walls properly carved.

**Fix**: Add `await get_tree().physics_frame` before `bake_navigation_polygon()` in all
level scripts. This defers the bake to after the first physics frame, ensuring
`PhysicsServer2D` has all static body shapes registered.

Also: `LevelInitFallback.cs` (C# fallback when GDScript `_ready()` fails due to Godot 4.3
binary tokenization bug) must also await a physics frame and call `SetupNavigation()`.

### Root Cause 4: Missing `agent_radius` Before Bake

Several level scripts call `bake_navigation_polygon()` without setting `agent_radius` first.
Without proper agent radius, the navmesh polygon edges touch wall boundaries, causing
enemies to hug walls and get stuck in corners.

**Fix**: Set `nav_region.navigation_polygon.agent_radius = 24.0` before baking (24px
matches the enemy `NavigationAgent2D` radius configured in `_ready()`).

## Evidence: Game Log Analysis

From `game_log_20260321_153957.txt`:

```
[15:39:57] [NavMeshMonitor] poly_count=1 vertex_count=4   ← flat rectangle, no walls
[15:39:57] [ENEMY] [Enemy1] NavAgent configured: radius=24 max_speed=320
... (enemies start navigating with bad navmesh)
[15:40:52] [LevelInitFallback] Navigation mesh baked: poly_count=97 vertex_count=138
```

The 55-second gap between scene load and proper bake is because:
1. GDScript `_ready()` failed (Godot 4.3 bug)
2. `LevelInitFallback` deferred initialization

During that ~55 seconds, all 5 enemies were navigating with the flat-rectangle navmesh,
walking straight through walls.

## Related Issues

- **Issue #1224**: Previous fix used `bake_navigation_polygon(false)` but didn't address
  `source_geometry_mode` or the physics frame timing.
- **Issue #1273**: Investigated navmesh baking in `LevelInitFallback` when GDScript fails.
- **Issue #1271**: Comprehensive fix identifying all 3 root causes above.
- **Issue #1216**: Fixed patrol points snapping to navmesh (related navmesh quality issue).
- **Issue #1119**: Previous fix replaced wall-avoidance with `NavigationAgent2D` for patrol.

## Solution Applied

1. Changed `source_geometry_mode = 1` (GROUPS_WITH_CHILDREN) in all 13 level `.tscn` files
2. Added `groups=["navigation_source"]` to `Environment` node in all 13 level `.tscn` files
3. Removed stale `vertices`/`polygons`/`outlines` from 12 static level `.tscn` files
4. Added `await get_tree().physics_frame` before bake in all 13 level scripts
5. Set `agent_radius = 24.0` in level scripts that were missing it
6. Added `async` + physics frame await + `SetupNavigation()` to `LevelInitFallback.cs`

## References

- Godot docs: [NavigationPolygon.source_geometry_mode](https://docs.godotengine.org/en/4.3/classes/class_navigationpolygon.html)
- Godot docs: [NavigationRegion2D.bake_navigation_polygon](https://docs.godotengine.org/en/4.3/classes/class_navigationregion2d.html)
- Godot bug tracker: [#94150 - Binary tokenization issue](https://github.com/godotengine/godot/issues/94150)
