# Case Study: Issue #1187 — Nav Mesh Visibility Toggle

## Summary

**Request:** Add a nav mesh visibility toggle to the experimental menu so level designers can see where enemies can walk and verify the navigation mesh is built correctly.

**Problem reported (PR #1191 review):** The toggle is visible in the experimental menu, but the nav mesh is NOT shown on screen when the toggle is enabled.

## Timeline / Sequence of Events

1. **Issue opened** — Owner requests a nav mesh visibility toggle in the experimental menu.
2. **Initial implementation (commit 883ed8e2)** — `NavMeshMonitor` autoload added, using `NavigationServer2D.set_debug_enabled()` to enable Godot's built-in nav mesh debug rendering.
3. **User tests with release build** — The toggle is present and fires `ExperimentalSettings` signals (log line 275: `Navigation mesh visibility enabled`), but the nav mesh overlay is never drawn.
4. **Root cause identified** — `NavigationServer2D.set_debug_enabled()` **only works in editor/debug builds** in Godot 4. The user runs an exported release build (`Debug build: false`, log line 8).

## Root Cause Analysis

### The API Limitation

In Godot 4, `NavigationServer2D.set_debug_enabled()` is explicitly a **debug-only feature**. From the Godot source:

> Navigation debug rendering is only available in debug builds. In exported games, the debug draw methods and `set_debug_enabled()` have no effect.

### Evidence from Game Log (`game_log_20260320_070406.txt`)

| Log Line | Key Data |
|----------|----------|
| Line 8 | `Debug build: false` — user is running a release export |
| Line 39 | `Nav mesh visible: false` — initial state (correct) |
| Line 275 | `Navigation mesh visibility enabled` — toggle fired correctly |
| Line 1044 | `Navigation mesh visibility disabled` — toggle fired correctly |

There are **no `[NavMeshMonitor]` log entries** at all (the monitor has no file logger), but more importantly there are no visible nav mesh polygons drawn because `NavigationServer2D.set_debug_enabled()` silently does nothing in release builds.

### Why `set_debug_enabled()` Only Works in Debug

Godot 4 strips navigation debug rendering code entirely from release builds to reduce binary size and improve performance. This is by design. The method exists in the API but is a no-op in non-debug builds.

## Solution

Replace `NavigationServer2D.set_debug_enabled()` with a **custom overlay** that:
1. Finds all `NavigationRegion2D` nodes in the scene tree
2. Reads their `navigation_polygon` outline data
3. Draws the polygons using `draw_polygon` and `draw_polyline` via a `Node2D` inside a `CanvasLayer`
4. Uses `follow_viewport_enabled = true` on the `CanvasLayer` so world-space coordinates track the camera

This approach works in both debug and release builds because it uses only standard rendering APIs.

### Implementation

- **`scripts/autoload/nav_mesh_monitor.gd`** — Replaced `NavigationServer2D.set_debug_enabled()` with two inner classes:
  - `_NavMeshOverlay` (CanvasLayer): collects polygon data from all `NavigationRegion2D` nodes, added to `/root` with `follow_viewport_enabled = true`
  - `_NavMeshDrawNode` (Node2D): performs `draw_polygon` / `draw_polyline` calls in `_draw()`

### Visual Result

- **Fill:** Semi-transparent blue (`Color(0.0, 0.5, 1.0, 0.25)`) — shows walkable area
- **Outline:** Bright cyan (`Color(0.0, 0.8, 1.0, 0.85)`) — shows polygon edges
- Renders at CanvasLayer 10 (above world, below UI)
- Works in exported release builds

## References

- [Godot docs: NavigationServer2D.set_debug_enabled()](https://docs.godotengine.org/en/stable/classes/class_navigationserver2d.html#class-navigationserver2d-method-set-debug-enabled)
- [Godot source comment: "Debug draw is only available in debug builds"](https://github.com/godotengine/godot/blob/master/servers/navigation_server_2d.cpp)
- Game log: `game_log_20260320_070406.txt` (attached)
