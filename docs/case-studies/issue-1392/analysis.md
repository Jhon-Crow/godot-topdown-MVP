# Case Study: Issue #1392 — Debug Visualization Overlays Not Visible

## Problem

The following debug visualizations stopped being visible in exported (release) builds:
1. Navigation mesh display (NavMeshMonitor)
2. Search path display (SearchPathMonitor)
3. Cover search display (CoverRaycastMonitor)
4. Enemy navigation path display (EnemyPathMonitor)

The user reported these features "stopped working" despite the settings being enabled.
All overlays create successfully, populate with valid data (97+ polygons), but produce
no visible output on screen.

## Environment

- Godot 4.3-stable (official)
- Renderer: `gl_compatibility`
- Stretch mode: `canvas_items` (1280x720 design resolution)
- Platform: Windows (exported release build, `Debug build: false`)

## Timeline

| Date | Event |
|------|-------|
| 2026-03-21 | PR #1278: Added EnemyPathMonitor (layer 10) |
| 2026-03-22 | PR #1286: Fixed SearchPathMonitor/WaypointMonitor _init vs _ready bug |
| 2026-03-23 | PR #1360: Added CoverRaycastMonitor (layer 10) |
| 2026-03-23 | PR #1366: Reorganized experimental menu into categories |
| 2026-03-24 | Issue #1392: Debug visualizations reported as broken |
| 2026-03-24 | Fix attempt 1: Raise layers to 150 (still broken) |
| 2026-03-24 | Fix attempt 2: Replace follow_viewport_enabled with canvas_transform sync |
| 2026-03-24 | Diagnostic build pushed with rendering pipeline tests |

## Root Cause Analysis

### What the Game Logs Show

All game logs consistently show:

1. **Settings correctly loaded**: `Nav mesh visible: true, Search path visible: true, ...`
2. **Overlays created**: `[NavMeshMonitor] Overlay node created`
3. **Data populated**: `[NavMeshMonitor] Overlay shown with 97 polygon(s)`
4. **No errors**: No script errors, null references, or crashes

The overlays are logically correct but produce no visible output.

### Contributing Factor 1: CanvasLayer Z-Order

The debug overlays were originally at layers 10-50, below visual effects at layers 97-103.
The cinema effects manager (layer 99) draws a full-screen ColorRect with a shader that
produces semi-transparent output, which could obscure overlays below it.

However, raising layers to 150 (above all effects) did NOT fix the problem.

### Contributing Factor 2: follow_viewport_enabled Behavior (Primary Suspect)

All debug overlays used `follow_viewport_enabled = true` on their CanvasLayer. According
to Godot Issue godotengine/godot#98463, this property's behavior is inverted/unreliable
in Godot 4.3:

- **Documentation says**: `follow_viewport_enabled = true` makes the layer "follow" the
  camera (like a HUD)
- **Actual behavior**: `follow_viewport_enabled = true` makes the layer affected by the
  viewport's canvas transform (content moves with the world, not the camera)

The naming confusion led to a documentation fix in PR godotengine/godot#99754 (for 4.4).
While the actual behavior (`true` = affected by canvas transform) is what we want for
world-space debug overlays, reports suggest this can silently fail in exported builds
with `gl_compatibility` renderer.

### Fix Approach: Manual canvas_transform Sync

Replaced `follow_viewport_enabled = true` with:
```gdscript
follow_viewport_enabled = false

func _process(_delta: float) -> void:
    var vp: Viewport = get_viewport()
    if vp:
        transform = vp.canvas_transform
```

This manually syncs the CanvasLayer's transform to the viewport's canvas transform each
frame. According to Godot 4.3 source code analysis:

- `canvas_transform` contains the Camera2D offset/zoom transform
- The stretch transform (`canvas_items` mode) is applied automatically by the renderer
  to ALL canvases, so it doesn't need to be included manually
- Setting `CanvasLayer.transform = viewport.canvas_transform` with `follow_viewport_enabled = false`
  should produce identical results to a working `follow_viewport_enabled = true`

### Status: Awaiting Confirmation

The user's game log showing "nothing was restored" was from **before** the canvas_transform
fix was pushed. A diagnostic build has been pushed to verify:

1. Whether Node2D `_draw()` is being called (logged to FileLogger)
2. Whether the CanvasLayer renders anything visible (diagnostic Label at layer 199)
3. Whether basic `draw_circle()` works in the CanvasLayer (magenta test marker)
4. Complete transform chain state at time of drawing

## Layer Map (Current)

```
Game World:          0 (default)
Visual Effects:      97-103 (cinema, hit, flashbang, etc.)
Debug Overlays:      150-151 (nav mesh, search paths, enemy paths, etc.)
Diagnostic Label:    199
FPS Counter:         200
```

## Files Modified

All 6 debug overlay autoloads:
- `scripts/autoload/nav_mesh_monitor.gd` — NavMesh polygon visualization
- `scripts/autoload/search_path_monitor.gd` — Search path waypoints
- `scripts/autoload/enemy_path_monitor.gd` — Enemy navigation paths
- `scripts/autoload/cover_raycast_monitor.gd` — Cover search raycasts
- `scripts/autoload/waypoint_monitor.gd` — Passage/search waypoint markers
- `scripts/autoload/sound_visualizer.gd` — Sound propagation ripples

## Relevant PRs and Issues

- PR #1278: feat(#1277): add enemy navigation path display
- PR #1286: fix(#1285): restore path/search path/navmesh display (_init vs _ready)
- PR #1360: feat(#1359): add cover raycast visualization toggle
- Godot Issue godotengine/godot#98463: follow_viewport_enabled inverted behavior
- Godot PR godotengine/godot#99754: Documentation fix for follow_viewport_enabled

## Key Lessons

1. **Debug overlays must render above all visual effects**. Their purpose is debugging —
   if they're obscured by effects, they're useless.

2. **`follow_viewport_enabled` is unreliable** in Godot 4.3. Manual canvas_transform
   sync is more predictable.

3. **Export builds may behave differently from editor**. `Debug build: false` means
   some code paths and rendering behaviors differ. Always test in exported builds.

4. **Diagnostic instrumentation is critical** when the rendering pipeline appears to
   work correctly in code but produces no visible output. Adding a Label (which uses
   a different rendering path than Node2D._draw()) helps isolate whether the issue is
   in the CanvasLayer, the draw calls, or the transform chain.
