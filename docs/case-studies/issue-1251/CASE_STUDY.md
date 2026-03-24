# Case Study: Issue #1251 — Add Search Path Visualization in Experimental Mode

**Date:** 2026-03-21
**Issue:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1251
**PR:** https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1252
**Related:** Issue #1246 (add predefined search path waypoints to all maps), PR #1247

---

## Problem Statement

The game uses predefined `SearchPathWaypoints` nodes (placed by designers in level scenes) to
guide enemy search behavior after the player is lost from sight. PR #1247 added these waypoints
to all 11 remaining maps. However, there is no way to **visualize** these search paths at
runtime — designers and developers cannot see where the waypoints are without opening the editor.

The issue requests adding a **"Show Search Paths"** toggle in the Experimental menu that renders
the waypoint positions and connecting lines on screen during gameplay.

---

## Codebase Analysis

### SearchPathWaypoints System (Issue #1225, PR #1230)

**Key files:**
- `scripts/objects/enemy.gd` — `_load_predefined_search_path()` (line 2226), `_search_waypoints` array
- `scenes/levels/*.tscn` — `SearchPathWaypoints` node with `Marker2D` children in group `search_path_waypoints`

The mechanism:
1. Enemy enters `SEARCHING` state → calls `_load_predefined_search_path()`
2. Finds nodes in group `"search_path_waypoints"` via `get_tree().get_nodes_in_group()`
3. Collects all `Marker2D` children as waypoints
4. Loops through the waypoint list, pausing to scan at each point

**Group name:** `"search_path_waypoints"` (lower-snake-case, registered on `SearchPathWaypoints` Node2D)

### Existing Debug Visualization Patterns

**Nav Mesh Visualizer** (Issue #1187):
- `scripts/autoload/nav_mesh_monitor.gd` — autoload singleton
- `ExperimentalSettings.nav_mesh_visible_enabled` — persisted toggle
- `ExperimentalMenu` — checkbox + description + `_on_nav_mesh_visible_toggled()` handler
- Inner class `_NavMeshOverlay` (CanvasLayer) + `_NavMeshDrawNode` (Node2D) pattern
- Re-applies on scene change via `node_added` signal
- Uses `follow_viewport_enabled = true` on CanvasLayer so world coordinates align

**Enemy Debug Draw** (`enemy.gd:_draw()`):
- Active only when `debug_label_enabled` is true
- Draws FOV cone, lines to player/cover/flanking positions directly on the enemy node

### What SearchPathWaypoints Look Like in Scene Files

```
[node name="SearchPathWaypoints" type="Node2D" parent="."]
groups = ["search_path_waypoints"]

[node name="Arena_Center" type="Marker2D" parent="SearchPathWaypoints"]
position = Vector2(576, 384)

[node name="Arena_TopLeft" type="Marker2D" parent="SearchPathWaypoints"]
position = Vector2(192, 128)
...
```

Each level has 12–32 waypoints. The `SearchPathWaypoints` node itself is in world space.

---

## Online Research

### Godot 4 — Debug Visualization Best Practices

1. **CanvasLayer with `follow_viewport_enabled = true`** — the standard approach for debug overlays
   that need to follow the camera and draw in world space. Used by nav mesh monitor in this project.

2. **`Node2D._draw()` + `queue_redraw()`** — immediate-mode drawing API. Called every frame when
   `queue_redraw()` is invoked. Zero-allocation, ideal for overlay lines and circles.

3. **`get_tree().get_nodes_in_group(group_name)`** — built-in Godot method to find all nodes in
   a group. Used by enemy AI to locate `SearchPathWaypoints` nodes; perfect for the visualizer too.

4. **Line2D node** — alternative for persistent path drawing; heavier than `_draw()` but useful
   when path rarely changes. Overkill here since waypoints are fixed per level.

### Similar Solutions in Game Development

- **Unreal Engine Navigation Mesh Visualization**: built-in debug draw for nav mesh + path queries.
  Godot equivalent: `NavigationServer2D.set_debug_enabled()` (editor/debug builds only).
- **Unity Gizmos**: editor-only `Gizmos.DrawSphere()` and `Gizmos.DrawLine()`. Godot equivalent:
  `Node2D._draw()` calls.
- **libGDX ShapeRenderer**: render-time path/circle drawing. Exact Godot equivalent: `draw_circle()`
  and `draw_polyline()` in Node2D._draw().

### Existing Godot Community Approaches

The standard pattern for **runtime** debug overlays in exported Godot 4 games:
1. Create a `CanvasLayer` with `layer = 10` (above game, below UI) and `follow_viewport_enabled = true`
2. Add a `Node2D` child that performs `_draw()` calls
3. Query scene data (navigation regions, groups, etc.) and pass to the draw node
4. Call `queue_redraw()` to refresh

This is exactly the pattern used in `nav_mesh_monitor.gd` — the cleanest approach for this project.

---

## Proposed Solution

### Overview

Implement `SearchPathMonitor` — a new autoload singleton mirroring `NavMeshMonitor` — that:

1. Reads `ExperimentalSettings.is_search_path_visible_enabled()`
2. Finds all nodes in group `"search_path_waypoints"` in the current scene
3. Creates a `CanvasLayer` overlay with a `Node2D` draw node
4. Draws:
   - **Dots/circles** at each waypoint position (radius 8px, semi-transparent cyan)
   - **Lines** connecting consecutive waypoints (forming the patrol loop, cyan lines)
   - **Labels** with waypoint order number (optional, at small font size)
5. Re-applies on scene changes (reloading or switching levels clears old waypoints)

### Key Design Decisions

- **Cyan color** (#00FFFF, like nav mesh monitor but distinguishable) with ~70% alpha fill,
  100% alpha outline
- **Waypoint circles** radius 8px, unfilled outline
- **Path lines** connecting consecutive waypoints, 2px thick, closing the loop
- **Waypoint index labels** drawn near each waypoint circle

### Files to Change

| File | Change |
|------|--------|
| `scripts/autoload/experimental_settings.gd` | Add `search_path_visible_enabled` var + getter/setter + save/load |
| `scripts/autoload/search_path_monitor.gd` | New file — autoload singleton |
| `project.godot` | Register `SearchPathMonitor` autoload after `NavMeshMonitor` |
| `scenes/ui/ExperimentalMenu.tscn` | Add `SearchPathVisibleContainer` row + description |
| `scripts/ui/experimental_menu.gd` | Add `@onready` ref, `_setup_row_hover`, toggle handler, `_update_ui` |
| `tests/unit/test_experimental_settings.gd` | Add `search_path_visible_enabled` to mock + tests |
| `tests/unit/test_search_path_monitor.gd` | New test file for `SearchPathMonitor` logic |

---

## Alternative Solutions Considered

1. **Draw inside `enemy.gd._draw()`**: only shows waypoints for enemies currently in SEARCHING state,
   not the full designed path. Rejected — designer needs full path always visible.

2. **Permanent debug markers in editor**: editor-only, not useful for runtime testing. Rejected.

3. **Line2D nodes spawned in levels**: permanent scene modifications, hard to toggle. Rejected.

4. **NavMeshMonitor extension**: adding search path logic to NavMeshMonitor would conflate two
   distinct concerns. Rejected — separate autoload is cleaner.

---

## Implementation Summary

The chosen implementation follows the `NavMeshMonitor` pattern exactly:
- New `SearchPathMonitor` autoload with inner `_SearchPathOverlay` (CanvasLayer) + `_SearchPathDrawNode` (Node2D)
- Overlay re-built when scene changes (handles level transitions)
- New `search_path_visible_enabled` setting in `ExperimentalSettings`
- Checkbox in Experimental Menu

This gives level designers a real-time view of all search waypoints with zero performance cost
when disabled (the overlay node is hidden, draw calls skipped).
