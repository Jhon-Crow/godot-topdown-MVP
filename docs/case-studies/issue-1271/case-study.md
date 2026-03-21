# Case Study: Issue #1271 — Enemies bumping into walls instead of navigating around them

## Issue Summary

**Title (RU):** сделай чтоб враги не долбились об стену а обходили её
**Title (EN):** Make enemies navigate around walls instead of bumping into them

**Reporter suggestion:** Use `NavigationRegion2D` or fix the navmesh overlapping with walls. Use the most recent reliable approach.

## Session 1 Root Cause Analysis (Committed: 95ce5af5)

### Initial Hypothesis

The game already uses Godot 4's `NavigationAgent2D` + `NavigationRegion2D` stack with infrastructure in place:

- All 13 levels have `NavigationRegion2D` nodes with `NavigationPolygon` set to bake from collision shapes on layer 4
- All levels call `nav_region.bake_navigation_polygon(false)` at runtime in `_ready()`
- Enemy nodes (`Enemy.tscn`) have `NavigationAgent2D` with `avoidance_enabled = true`, `radius = 24.0`
- The helper `_move_to_target_nav(target_pos, speed)` uses navmesh pathfinding

Initial fix applied: replaced `_apply_wall_avoidance()` calls in COMBAT approach, seeking-clear-shot, and PACIFIST states with `_move_to_target_nav()`. This matched the pattern already used in PATROL, PURSUING, FLANKING, etc.

### Why the First Fix Was Insufficient

The reporter confirmed (comment on PR #1272) that enemies were still walking into walls after the fix: *"враги идёт в стену, опять не отображается навмеш"* ("enemies go into walls, navmesh still not displaying").

## Session 2 Root Cause Analysis (Game Log: game_log_20260321_134324.txt)

### Evidence from Game Log

The game log collected 2026-03-21T13:43:24 provides the definitive root cause evidence:

```
[13:43:24] [NavMeshMonitor] refresh: region 'NavigationRegion2D' poly_count=1 vertex_count=4 outline_count=1
```

**The navmesh only ever has 1 polygon with 4 vertices — the outer rectangle only. No walls are carved.**

This is reproduced consistently across every refresh throughout the entire session:
- At startup: `poly_count=1 vertex_count=4`
- After scene reload (13:44:22): `poly_count=1 vertex_count=4`
- After another reload (13:44:33): `poly_count=1 vertex_count=4`
- After every subsequent refresh: `poly_count=1 vertex_count=4`

A correct navmesh for a labyrinth level would show 50–200+ polygons with many vertices (each wall creates cut-outs).

### Root Cause: Wrong `source_geometry_mode`

**File:** All level `.tscn` files (13 levels) — `NavigationPolygon` sub-resource

**Problem:** `source_geometry_mode = 0` = `SOURCE_GEOMETRY_ROOT_NODE_CHILDREN`

In Godot 4, `SOURCE_GEOMETRY_ROOT_NODE_CHILDREN` scans the **children of the NavigationRegion2D node itself**. But `NavigationRegion2D` has **no children** — it is a leaf node in all levels:

```
LabyrinthLevel (root)
├── Environment            ← walls live here
│   ├── Walls/
│   │   ├── WallTop (StaticBody2D, collision_layer=4)
│   │   └── ... (13 more StaticBody2D nodes)
│   └── InteriorWalls/
│       ├── HorizontalDivider (StaticBody2D, collision_layer=4)
│       └── ... (20+ more StaticBody2D nodes)
├── Entities/
└── NavigationRegion2D    ← has NO children, sibling of Environment
```

When `bake_navigation_polygon(false)` is called with mode=0, it scans `NavigationRegion2D`'s children — finding zero physics bodies — and produces only the input outline (the rectangular boundary). The walls are never parsed, so the navmesh is just a flat rectangle that lets enemies walk anywhere, including through walls.

The `parsed_collision_mask = 4` and wall `collision_layer = 4` settings are correct — the problem is purely that the scan never reaches the wall nodes.

### How `bake_navigation_polygon(false)` behaves with mode=0

The key distinction in Godot 4's `NavigationPolygon.source_geometry_mode`:

| Value | Enum | Scans |
|-------|------|-------|
| 0 | `SOURCE_GEOMETRY_ROOT_NODE_CHILDREN` | Children of the NavigationRegion2D itself |
| 1 | `SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN` | Nodes in the named group AND their children |
| 2 | `SOURCE_GEOMETRY_GROUPS` | Only nodes directly in the named group |

The `source_geometry_group_name = "navigation_source"` was already set in all level files but was never used because mode=0 ignores groups entirely.

### Additional Evidence: bake_finished Never Fires

The game log shows no NavMeshMonitor refresh entries between `[13:43:24]` (startup) and `[13:44:21]` (scene reload). The `NavMeshMonitor` connects to `bake_finished` when a `NavigationRegion2D` is added — but `bake_finished` appears to not be emitted when mode=0 baking produces no new geometry changes vs the stored data.

### Consequence for Pathfinding

With a flat rectangular navmesh (no wall holes):
- `NavigationAgent2D.get_next_path_position()` returns the direct line to the target
- Enemies move in a straight line toward their target
- When a wall is in the way, direct velocity hits the wall → enemy presses against it
- Even `_move_to_target_nav()` (the fix from Session 1) cannot help because the pathfinding graph itself has no walls
- The `_apply_wall_avoidance()` raycasts provide only local deflection, insufficient for corner navigation

## Fix Applied in Session 2

### Change 1: Fix source_geometry_mode in all 13 level `.tscn` files

```
source_geometry_mode = 0  →  source_geometry_mode = 1
```

Mode `1` = `SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN`: scans nodes in the `navigation_source` group and all their children/descendants.

### Change 2: Add Environment node to `navigation_source` group in all 13 level `.tscn` files

```
[node name="Environment" type="Node2D" parent="."]
→
[node name="Environment" type="Node2D" parent="." groups=["navigation_source"]]
```

The `Environment` node contains all wall `StaticBody2D` nodes with `collision_layer = 4`. By adding it to the group and using `SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN`, the bake now:
1. Finds `Environment` (in group `navigation_source`)
2. Recursively scans all its children (Walls, InteriorWalls, Cover, etc.)
3. Finds all `StaticBody2D` with `collision_layer = 4`
4. Uses their `CollisionShape2D` rectangles to carve holes in the navmesh

### Change 3: Update RoguelikeLevel GDScript (dynamic room generation)

`roguelike_level.gd` creates walls at runtime via `_create_wall()`. Changes:
- Updated `_setup_navigation()` to use `SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN` and set `source_geometry_group_name = "navigation_source"`
- Added `room_container.add_to_group("navigation_source")` in both `_build_room_scene()` and `_build_room_scene_treasure()` so the dynamically created room is in the group before baking

### Expected Result

After this fix, `bake_navigation_polygon(false)` will correctly produce:
- `poly_count >> 1` (typically 30–200 triangles depending on level complexity)
- `vertex_count >> 4` (many vertices carving around wall shapes)

The NavMeshMonitor overlay will now show the actual walkable area (blue polygons between walls) instead of just the map boundary rectangle.

Enemies using `_move_to_target_nav()` will now receive proper pathfinding routes that go around walls, corridors, and corners.

## Timeline of Events

| Time (log) | Event |
|------------|-------|
| 13:43:24 | Game starts, LabyrinthLevel loads |
| 13:43:24 | NavMeshMonitor refreshes: `poly_count=1 vertex_count=4` — bake failed, only rectangle |
| 13:43:24 | `_setup_navigation()` called → `bake_navigation_polygon(false)` → scans NavigationRegion2D children → zero walls found |
| 13:43:24–13:44:20 | Enemies use `_move_to_target_nav()` but pathfinding routes straight through walls |
| 13:43:30 | Enemy1: "No valid flank position (both sides behind walls)" |
| 13:44:21 | Scene reloaded, NavMeshMonitor picks up new NavigationRegion2D |
| 13:44:22 | NavMeshMonitor refresh after bake: still `poly_count=1 vertex_count=4` |
| 13:44:25–37 | Multiple enemies PATROL STUCK, GLOBAL STUCK, FLANKING stuck |

## References

- Game log: `docs/case-studies/issue-1271/game_log_20260321_134324.txt`
- [Godot 4: NavigationPolygon.source_geometry_mode](https://docs.godotengine.org/en/stable/classes/class_navigationpolygon.html#enum-navigationpolygon-sourcegeometrymode)
- [2D navigation overview — Godot 4 docs](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_introduction_2d.html)
- [Using NavigationAgents — Godot 4 docs](https://docs.godotengine.org/en/latest/tutorials/navigation/navigation_using_navigationagents.html)
- Issue #1119 / #1220: PATROL state navmesh fix (first time navmesh was used for enemies)
- Issue #1107: Prior attempt at navmesh baking fix (used `NavigationServer2D.parse_source_geometry_data` approach, not merged)
- PR #1272: Fix implementation
