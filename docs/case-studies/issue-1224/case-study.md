# Case Study: Issue #1224 — Nav Mesh Display Not Working

## Summary

**Issue:** The nav mesh display toggle in the experimental menu stopped working after the initial
custom overlay implementation from issue #1187.

**Root causes identified (two separate bugs):**

1. **`nav_mesh_monitor.gd` was reading raw input outlines instead of baked polygon data.**
   After `bake_navigation_polygon(false)`, Godot populates `get_polygon_count()`/`get_vertices()`
   with the walkable area (walls carved out), but does NOT update the raw input outlines
   returned by `get_outline_count()`/`get_outline()`. The original code read input outlines,
   so it was always showing the raw floor boundary — and often nothing at all, because baked
   data wasn't present at the time of reading.

2. **Level scripts used `NavigationServer2D.bake_from_source_geometry_data` instead of
   `nav_region.bake_navigation_polygon(false)`.** The `bake_from_source_geometry_data` path
   does not reliably populate the `NavigationPolygon`'s baked vertex/polygon data. The
   `bake_navigation_polygon(false)` method both bakes the mesh and populates the polygon
   data that `nav_mesh_monitor.gd` reads.

3. **Timing race condition:** The overlay refreshed before the navmesh bake completed,
   reading zero polygons. The `_on_node_added` callback fired immediately when the
   `NavigationRegion2D` was added to the tree, before `bake_navigation_polygon` was called.

4. **CanvasLayer layer too low:** Layer 10 was below some game UI elements. Increased to 50.

5. **FileLogger path bug in inner class:** `tree.root.get_node_or_null("FileLogger")` used
   a relative path (failing to find the node), while the correct absolute path is
   `tree.root.get_node_or_null("/root/FileLogger")`.

## Timeline / Sequence of Events

1. **Issue #1187 (2026-03-20):** Initial nav mesh overlay added using
   `NavigationServer2D.set_debug_enabled()`, which silently failed in release builds.
   Fixed with a custom `CanvasLayer` + `Node2D` draw overlay using `draw_polygon`.

2. **Issue #1224 opened (2026-03-21):** Owner reports the toggle still doesn't work.

3. **Root cause analysis:** The custom overlay reads `get_outline_count()`/`get_outline()`,
   which returns the raw input boundary (unchanged after baking). Baked data
   (`get_polygon_count()`, `get_vertices()`) is what the level scripts populate,
   but several levels used `NavigationServer2D.bake_from_source_geometry_data` which
   does NOT update the `NavigationPolygon`'s internal baked data.

4. **Fix applied:** See Implementation section below.

## Root Cause Analysis

### Bug 1: Wrong data source in `nav_mesh_monitor.gd`

The Godot 4 `NavigationPolygon` API has two separate data stores:

| API | What it contains | Updated by |
|-----|-----------------|------------|
| `get_outline_count()` / `get_outline(i)` | Raw input outlines (floor boundary) | `add_outline()` |
| `get_polygon_count()` / `get_polygon(i)` + `get_vertices()` | Baked triangulated walkable area | `bake_navigation_polygon()` |

The original code fell back to outlines if no baked data was available. But many levels
used `NavigationServer2D.bake_from_source_geometry_data()` which fills the
`NavigationMeshSourceGeometryData2D` but does NOT write back into `NavigationPolygon`'s
baked polygon data. So `get_polygon_count()` returned 0, the code fell back to outlines,
and the floor boundary (not the carved walkable area) was drawn.

### Bug 2: Level scripts using wrong bake API

`NavigationServer2D.bake_from_source_geometry_data(nav_poly, source)` does not populate
`nav_poly.get_polygon_count()` / `get_vertices()`. Only `nav_region.bake_navigation_polygon(false)`
(or `true` for async) reliably does this.

Affected levels: `arena_level`, `building_level`, `castle_level`, `city_level`,
`labyrinth_level`, `labyrinth2_level`, `revolver_level`, `test_tier`.

### Bug 3: Timing race condition

`_on_node_added` triggered `_deferred_refresh()` via `call_deferred()` — but this only
deferred to the next frame, which was before `bake_navigation_polygon()` completed. Fix:

- Connect to `NavigationRegion2D.bake_finished` signal for accurate post-bake refresh
- Add a 1.0 second timer fallback (increased from 0.2s to handle slow hardware)

### Bug 4: CanvasLayer rendering order

Layer 10 was below some level UI elements. Increased to 50. `CinemaEffects` uses layer 99,
so the nav mesh overlay stays below the vignette overlay.

### Bug 5: FileLogger path in inner class

Inner class used `tree.root.get_node_or_null("FileLogger")` (relative path) instead of
`tree.root.get_node_or_null("/root/FileLogger")` (absolute path). The relative path failed
silently and all inner-class log messages went to stdout instead of the log file.

## Solution

### `scripts/autoload/nav_mesh_monitor.gd`

- Read baked polygon data (`get_polygon_count()` / `get_polygon()` / `get_vertices()`)
  as primary data source; fall back to outlines only if baked data is absent.
- Connect to `NavigationRegion2D.bake_finished` signal in `_on_node_added()`.
- Add `BAKE_WAIT_SECONDS = 1.0` timer fallback (was `call_deferred` / 0.2s).
- Change `layer = 10` → `layer = 50` in `_NavMeshOverlay._ready()`.
- Fix `_log_inner()` to use absolute path `/root/FileLogger`.
- Add `[NavMeshMonitor]` prefix logging throughout for diagnostics.

### Level scripts (8 files)

Replace the `NavigationServer2D.parse_source_geometry_data` +
`NavigationServer2D.bake_from_source_geometry_data` pattern with
`nav_region.bake_navigation_polygon(false)` in:

- `scripts/levels/arena_level.gd`
- `scripts/levels/building_level.gd`
- `scripts/levels/castle_level.gd`
- `scripts/levels/city_level.gd`
- `scripts/levels/labyrinth_level.gd`
- `scripts/levels/labyrinth2_level.gd`
- `scripts/levels/revolver_level.gd`
- `scripts/levels/test_tier.gd`

The `NavigationPolygon` resources in the `.tscn` files already have the correct outlines
configured (floor boundary with correct dimensions). `bake_navigation_polygon(false)` uses
these outlines plus the `parsed_geometry_type` / `parsed_collision_mask` settings in the
resource to carve walls and populate the baked polygon data.

## References

- Issue #1187: Initial nav mesh visibility toggle implementation
- Godot 4 docs: `NavigationPolygon.bake_navigation_polygon()`
- Godot 4 docs: `NavigationRegion2D.bake_finished` signal
