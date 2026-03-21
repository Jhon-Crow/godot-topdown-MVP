# Case Study: Issue #1255 — Add Waypoint Display Toggle to Experimental Menu

**Issue:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1255
**PR:** https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1256
**Date:** 2026-03-21

---

## Problem Statement

PR #1232 added `passage_waypoints` (Marker2D nodes in the `passage_waypoints` group) to `BuildingLevel` for AI cross-room routing. These waypoints were visualized only when the **Debug Mode** (F7) global toggle was active — there was no dedicated on/off switch for waypoint display alone.

PR #1247 then added `search_path_waypoints` to all 11 remaining maps, but none of those levels had any visualization code at all.

The owner requests a dedicated debug toggle in the **Experimental** menu that shows/hides all transition/passage waypoints — for visual debugging without activating the full debug mode (which also shows AI state labels, enemy vision cones, etc.).

---

## Root Cause Analysis

### Current State (before this fix)

| Feature | Status |
|---|---|
| `passage_waypoints` visualization in BuildingLevel | Tied to `GameManager.debug_mode_toggled` (F7) |
| `search_path_waypoints` visualization in all other levels | **No visualization at all** |
| Dedicated experimental toggle | **Missing** |

### Why It Matters

Level designers and testers need to see waypoint positions during gameplay to verify correct placement — without turning on the full debug HUD that floods the screen with AI state text. A focused toggle is cleaner and more ergonomic.

### Related Work

- **PR #1232** (`fix(#1226): add passage waypoints to BuildingLevel for cross-room AI routing`): Introduced `passage_waypoints` group, added `_draw()` in `building_level.gd` keyed to `debug_mode_toggled`.
- **PR #1247** (`feat(#1246): add predefined search path waypoints to all maps`): Added `search_path_waypoints` group to 11 levels — but no visualization.
- **PR #1187** (`NavMeshMonitor`): Pattern reference — a standalone autoload draws an overlay for NavigationRegion2D nodes, toggled from ExperimentalSettings. Same pattern used here.

---

## Proposed Solution

### Architecture

Create a **`WaypointMonitor`** autoload (following the `NavMeshMonitor` pattern) that:

1. Listens for `ExperimentalSettings.settings_changed`
2. When `passage_waypoints_visible_enabled` is `true`, creates a `CanvasLayer` overlay
3. The overlay draws colored circles + labels for every node in:
   - `passage_waypoints` group (green circles — doorway waypoints, BuildingLevel only)
   - `search_path_waypoints` group (yellow circles — search path waypoints, all levels)
4. Refreshes on scene change (node added event)

### Files Changed

| File | Change |
|---|---|
| `scripts/autoload/experimental_settings.gd` | Add `passage_waypoints_visible_enabled` bool + getter/setter + save/load |
| `scripts/autoload/waypoint_monitor.gd` | **New** — standalone overlay autoload (WaypointMonitor pattern) |
| `project.godot` | Register `WaypointMonitor` autoload after `NavMeshMonitor` |
| `scenes/ui/ExperimentalMenu.tscn` | Add `WaypointVisibleContainer`, `WaypointVisibleLabel`, `WaypointVisibleCheckbox`, `WaypointVisibleDescription` |
| `scripts/ui/experimental_menu.gd` | Add `@onready` ref, `_setup_row_hover`, checkbox connect, `_update_ui` branch, handler |
| `scripts/levels/building_level.gd` | Keep existing `_draw()` but also connect to new setting so both paths work |

### Known Existing Components / Libraries

- **Godot 4 `CanvasLayer` + `Node2D._draw()`**: Built-in rendering pipeline used for the overlay. No external libraries needed.
- **`NavigationServer2D.set_debug_enabled()`**: Only works in editor/debug builds — custom drawing is required for release builds (same reasoning as `NavMeshMonitor`).
- **`get_tree().get_nodes_in_group()`**: Standard Godot API for finding all nodes in a named group at runtime.

---

## Evidence

- `building_level.gd:75` — `var _debug_mode: bool = false`
- `building_level.gd:128-131` — Connects to `GameManager.debug_mode_toggled`
- `building_level.gd:1904-1916` — `_on_debug_mode_toggled()` + `_draw()` renders green circles
- `nav_mesh_monitor.gd` — Full reference implementation of the autoload overlay pattern
- `scenes/levels/BuildingLevel.tscn:976-1003` — 13 `passage_waypoints` Marker2D nodes
- `scenes/levels/ArenaLevel.tscn:230` (and 10 other level files) — `search_path_waypoints` group nodes

---

## Implementation Notes

- Default: **off** (consistent with all other debug overlays)
- `passage_waypoints` rendered as **green** circles (matches existing `building_level.gd` color)
- `search_path_waypoints` rendered as **yellow/orange** circles to distinguish from passage waypoints
- Circle radius: 12px, label offset: +14px right (matches existing building_level style)
- The overlay uses `follow_viewport_enabled = true` so it tracks the camera correctly
- `building_level.gd`'s existing `_draw()` remains — it still works with F7. The new toggle is additive.

---

## Post-Implementation Incident: "AI Completely Broken" (2026-03-21)

### Game Log
Saved at: `game_log_20260321_084257.txt`

### Timeline of Events

| Time | Event |
|---|---|
| 08:02 | Owner tests build **before** PR #1255 — `has_died_signal=true` for all enemies, 5 enemies registered |
| 08:42 | Owner tests build **from** PR #1255 branch — `has_died_signal=false` for all enemies, **0 enemies registered** |
| 08:43 | Owner reports: "полностью сломан ai" (AI completely broken) |

### Root Cause

In commit `2d8ae94a` (reduce enemy.gd line count to 5000), the original:

```gdscript
_connect_debug_mode_signal(); call_deferred("_cache_passage_waypoints")
```

was changed to:

```gdscript
_connect_debug_mode_signal(); call_deferred(func(): _passage_waypoints = get_tree().get_nodes_in_group("passage_waypoints"))
```

In Godot 4, `Object.call_deferred(method: StringName, ...)` expects a **StringName** as the first argument. Passing a Callable (lambda) coerces it to a string (e.g., `"GDScriptLambda"`), causing a **runtime error** in `_ready()`. This prevents the waypoints cache from being populated.

The correct Godot 4 syntax for deferred Callable execution is:
```gdscript
(func(): _passage_waypoints = ...).call_deferred()
```

Additionally, the intermediate `_cache_passage_waypoints()` function was removed, which is fine once the call site is fixed.

**Why `has_died_signal=false`:** The runtime error in `_ready()` may cause the Godot script runtime to mark the instance as errored, which can prevent `has_signal()` from returning correct results in release builds. In debug builds the error is visible; in release builds it fails silently.

### Fix Applied

Changed `call_deferred(func(): ...)` to `(func(): ...).call_deferred()` in `enemy.gd:384`. Same line count (5000) — only the syntax was corrected.

### Merge Conflict Resolution

Between the broken build and the fix, `origin/main` was merged. Two PRs from main added features to the same files:
- PR #1253: Sound propagation visualizer (adds `SoundVisualizer` autoload, `sound_visualizer_enabled` setting)
- PR #1248: Nav mesh monitor fix

Conflicts in `project.godot`, `experimental_settings.gd`, and `experimental_menu.gd` were resolved by **keeping both features** (waypoint toggle from #1255 and sound visualizer from #1253).
