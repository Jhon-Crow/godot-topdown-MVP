# Case Study: Issue #1277 — Add Enemy Navigation Path Display in Experimental Mode

**Date:** 2026-03-21
**Issue:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1277
**PR:** https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1278

---

## Problem Statement

The issue requests displaying the **built (computed) navigation path** for enemies in the
Experimental menu — showing it for **all AI states**, analogous to how the Search Path
visualization (Issue #1251) shows paths only during the `SEARCHING` state.

Currently, enemies use `NavigationAgent2D` for pathfinding. The agent computes an A\*-based
path from the enemy's current position to the current target. This path is only visible in
Godot editor debug builds (via `NavigationServer2D.set_debug_enabled()`), not at runtime
in exported/play builds.

The request: add a toggle in the Experimental menu that draws the **actual navigation path**
(the green polyline you see in Godot's editor debug view) for every active enemy, showing
where each enemy intends to walk regardless of its current AI state.

---

## Codebase Analysis

### Enemy Navigation System

**Key file:** `scripts/objects/enemy.gd`

The enemy uses `NavigationAgent2D` (node name `NavigationAgent2D`, field `_nav_agent`)
for all path-based movement. Navigation path computation:

1. `_move_to_target_nav(target_pos, speed)` — sets `_nav_agent.target_position`,
   then follows `_nav_agent.get_next_path_position()`.
2. `_get_nav_direction_to(target_pos)` — sets target, returns direction to next path point.
3. All states (COMBAT, SEEKING_COVER, RETREATING, PURSUING, FLANKING, SEARCHING,
   EVADING_GRENADE, ASSAULT, PATROL) eventually call these to move.

**Godot 4 API:**
- `NavigationAgent2D.get_current_navigation_path()` → `PackedVector2Array` — returns
  the full computed path in **global coordinates** (updated each time `target_position`
  is set or the agent recalculates).
- The path is empty if no target is set or navigation is finished.
- Returns world-space positions, suitable for direct overlay drawing.

### Existing Debug Visualization Pattern

All existing overlay monitors follow the same pattern (Issue #1187, #1251, #1253, #1255):

| Component | File | Setting |
|---|---|---|
| NavMeshMonitor | `scripts/autoload/nav_mesh_monitor.gd` | `nav_mesh_visible_enabled` |
| SearchPathMonitor | `scripts/autoload/search_path_monitor.gd` | `search_path_visible_enabled` |
| WaypointMonitor | `scripts/autoload/waypoint_monitor.gd` | `passage_waypoints_visible_enabled` |
| SoundVisualizer | `scripts/autoload/sound_visualizer.gd` | `sound_visualizer_enabled` |

Each follows this structure:
1. **Autoload singleton** extending `Node`
2. **Inner CanvasLayer** class (`_Overlay extends CanvasLayer`)
   - `layer = 10`, `follow_viewport_enabled = true`
3. **Inner Node2D** draw class (`_DrawNode extends Node2D`)
   - Collects data each frame, calls `queue_redraw()`
4. **ExperimentalSettings** persisted bool (getter/setter/save/load)
5. **ExperimentalMenu** checkbox + description label + toggle handler + `_update_ui()`
6. **ExperimentalMenu.tscn** scene nodes for the UI row

### Enemy Public API

`get_current_state() -> AIState` — already public (used by SearchPathMonitor).

We need to add:
- `get_nav_path() -> PackedVector2Array` — returns `_nav_agent.get_current_navigation_path()`
  (or empty if no agent). Returns world-space path points.

### All AI States and Their Movement Targets

| State | Movement Target |
|---|---|
| IDLE (patrol) | patrol waypoints |
| COMBAT | cover position or player (cover-to-cover) |
| SEEKING_COVER | cover position |
| IN_COVER | cover position (minimal movement) |
| FLANKING | flank target |
| SUPPRESSED | cover position |
| RETREATING | retreat cover position |
| PURSUING | next pursuit cover toward player |
| ASSAULT | player position (rush) |
| SEARCHING | search waypoints |
| EVADING_GRENADE | evasion target |
| PACIFIST | pacifist cover |

All of these eventually call `_move_to_target_nav()` which sets `_nav_agent.target_position`,
causing the agent to compute a fresh path.

---

## Proposed Solutions

### Option A: Query NavigationAgent2D.get_current_navigation_path() (Chosen)

Add a public `get_nav_path()` method to `enemy.gd` that delegates to the agent.
Create `enemy_path_monitor.gd` autoload following the established overlay pattern.
Draw the path as a colored polyline with dots at each waypoint, colored by AI state.

**Pros:**
- Shows the actual computed A\* path (exactly what the agent follows)
- Updates automatically every frame as agent recomputes
- Works for ALL states without any state-specific logic
- Consistent with existing monitor architecture

**Cons:**
- Path may flicker if agent recomputes frequently (acceptable for debug view)

### Option B: Emit path via signal on each target_position set

Add a signal from `enemy.gd` whenever `_nav_agent.target_position` is set.

**Cons:** More invasive changes to enemy.gd, same result.

### Option C: Hook into NavigationServer2D debug rendering

Enable `NavigationServer2D.set_debug_enabled(true)` at runtime.

**Cons:** Only works in editor/debug builds, not exported builds. Colors not configurable.

---

## State Color Scheme

To show which state produces which path, color-code by AI state category:

| Category | States | Color |
|---|---|---|
| Idle/Patrol | IDLE | Gray |
| Combat | COMBAT, ASSAULT | Red |
| Cover | SEEKING_COVER, IN_COVER, SUPPRESSED, RETREATING | Orange |
| Flanking | FLANKING | Magenta |
| Pursuing | PURSUING | Yellow |
| Searching | SEARCHING | Cyan (same as SearchPathMonitor predefined) |
| Evasion | EVADING_GRENADE | White |
| Pacifist | PACIFIST | Green |

---

## Implementation Plan

1. **`scripts/objects/enemy.gd`**: Add `get_nav_path() -> PackedVector2Array` public method.
2. **`scripts/autoload/enemy_path_monitor.gd`**: New autoload following NavMeshMonitor pattern.
3. **`scripts/autoload/experimental_settings.gd`**: Add `enemy_path_visible_enabled` setting.
4. **`project.godot`**: Register `EnemyPathMonitor` autoload.
5. **`scenes/ui/ExperimentalMenu.tscn`**: Add UI row nodes.
6. **`scripts/ui/experimental_menu.gd`**: Add checkbox reference, signal handler, `_update_ui()`.

---

## References

- Godot 4 `NavigationAgent2D` docs: `get_current_navigation_path()` returns `PackedVector2Array`
  of waypoints in global space. Updated each navigation tick.
- Issue #1251 (SearchPathMonitor): exact same overlay pattern.
- Issue #1187 (NavMeshMonitor): established the autoload+inner-class overlay pattern.
- Issue #1253 (SoundVisualizer): another example of the pattern.
- Issue #1255 (WaypointMonitor): another example with multiple colors.
