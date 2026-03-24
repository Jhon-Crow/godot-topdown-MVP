# Case Study: Issue #1187 — Navigation Mesh Visibility Toggle

## Issue Summary

**Title:** добавь переключатель видимости nav mash
**Translation:** Add a nav mesh visibility toggle

**Request (translated):** Add a toggle to the Experimental menu to show/hide the navigation mesh for the AI, so it is visible where enemies can walk and where the mesh is built incorrectly.

---

## Context & Motivation

The project is a top-down tactical shooter built in Godot 4. Enemy AI uses `NavigationRegion2D` + `NavigationAgent2D` for pathfinding. All 13 level scenes include a `NavigationRegion2D` node baked at runtime.

**Developer need:** During level design and AI debugging, it is useful to see the navigation mesh overlay — to verify:
- Where enemies can and cannot walk
- Whether the mesh is baked correctly (no gaps, holes, or over/under-reach)
- Whether walls and obstacles are correctly excluded from the walkable area

Currently there is no way to visualize the nav mesh at runtime without opening the Godot editor.

---

## Codebase Analysis

### Experimental Settings System

The project has a mature experimental features system:

- **`scripts/autoload/experimental_settings.gd`** — Central singleton, persists settings to `user://experimental_settings.cfg`
- **`scripts/ui/experimental_menu.gd`** — UI controller with toggle checkboxes for each feature
- **`scenes/ui/ExperimentalMenu.tscn`** — Scene with scrollable list of experimental toggles

Each feature follows the same pattern:
1. `var feature_enabled: bool = false` in `experimental_settings.gd`
2. `set_feature_enabled(enabled: bool)` + `is_feature_enabled() -> bool` methods
3. Persistence in `_save_settings()` / `_load_settings()`
4. Checkbox + description in `ExperimentalMenu.tscn`
5. Handler in `experimental_menu.gd` calling `set_feature_enabled()`

### FPS Monitor Pattern

The `FpsMonitor` autoload (`scripts/autoload/fps_monitor.gd`) demonstrates how to build a runtime-reactive debug overlay:
- Created in `_ready()`, synced to `ExperimentalSettings.settings_changed` signal
- Shows/hides based on the setting
- Uses a `CanvasLayer` at high layer order (200) to render above gameplay

### Navigation Mesh in Levels

All levels have a `NavigationRegion2D` node named `"NavigationRegion2D"` at the root of each level scene. The mesh is baked in `_setup_navigation()` called from `_ready()`.

### Godot 4 Navigation Debug API

Godot 4 provides a built-in way to show navigation mesh debug overlays at runtime:

```gdscript
# Enable/disable navigation debug rendering for all NavigationRegion2D nodes
NavigationServer2D.set_debug_enabled(true)
```

This uses the built-in Godot navigation debug renderer which draws:
- The walkable polygon area (filled green/blue overlay by default)
- Navigation mesh edges
- Agent paths (optional, controlled by separate flags)

The debug state persists for the session and applies globally to all navigation regions.

**Key API calls:**
- `NavigationServer2D.set_debug_enabled(bool)` — Toggle debug rendering on/off
- Controlled by `ProjectSettings` prefix `debug/shapes/navigation/...` but can be overridden at runtime

---

## Known Solutions / Libraries

### Approach 1: `NavigationServer2D.set_debug_enabled()` (Recommended)

Godot's built-in navigation debug system. Call `NavigationServer2D.set_debug_enabled(true)` to enable visual overlay of all navigation meshes.

**Pros:**
- Zero additional code in level scenes
- Works for all 13+ levels automatically
- Uses Godot's built-in visual style (consistent with editor)
- One-line enable/disable

**Cons:**
- Works in debug builds only (Godot strips debug rendering in export builds by default)
- Visual style is not customizable without project settings changes

### Approach 2: Draw NavigationPolygon outline via `draw_polyline`

Manually draw the polygon vertices in `_draw()` on each `NavigationRegion2D`.

**Pros:** Works in release builds, customizable color/style
**Cons:** Requires modifying all 13 level scenes or injecting a script at runtime; more complex

### Approach 3: Overlay polygon via `Polygon2D` node

At runtime when toggled, find `NavigationRegion2D`, read its `navigation_polygon.vertices`, and create a semi-transparent `Polygon2D` overlay.

**Pros:** Works in release builds, exact polygon match
**Cons:** Requires per-level injection logic

---

## Chosen Solution

**Approach 1** — `NavigationServer2D.set_debug_enabled()` — is ideal for an experimental/developer feature:

1. Add `nav_mesh_visible_enabled: bool = false` to `ExperimentalSettings`
2. Add a `NavMeshMonitor` autoload (or handle in `ExperimentalSettings._ready`) that calls `NavigationServer2D.set_debug_enabled()` based on the setting
3. Add a checkbox to `ExperimentalMenu.tscn` and handler in `experimental_menu.gd`

This follows the exact same pattern as `FpsMonitor` and integrates cleanly into the existing system.

---

## Files to Modify

| File | Change |
|------|--------|
| `scripts/autoload/experimental_settings.gd` | Add `nav_mesh_visible_enabled` property, getter, setter, save/load |
| `scripts/ui/experimental_menu.gd` | Add `@onready` var, connect signal, handle toggle, update status |
| `scenes/ui/ExperimentalMenu.tscn` | Add new HBoxContainer with label, checkbox, and description |
| `project.godot` | No change needed |

The `NavigationServer2D.set_debug_enabled()` call will be made directly from `experimental_menu.gd` when the toggle changes, and re-applied on scene load via `ExperimentalSettings._ready()` (similar to how `FpsMonitor` applies its setting).

Since debug rendering needs to be applied each time a scene loads (Godot resets it), a new autoload `NavMeshMonitor` (mirroring `FpsMonitor`) will watch for scene changes and re-apply the setting.
