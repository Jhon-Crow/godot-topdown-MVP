# Case Study: Issue #1275 — Pathfinding Paths Don't Account for Walls

## Issue Summary

**Title:** сейчас пути поиска построены не правильно (pathfinding paths are currently built incorrectly)

**Requirements:**
1. Paths must account for walls — they should be built optimally, without going through walls.

**Related issues:**
- Issue #1289 — Fix Enemy Paths (earlier iteration that addressed navmesh baking and reassignment)
- Issue #1216 — Enemies Walk Into Walls (empty source geometry passed to bake)

---

## Root Cause Analysis

### The Problem

Despite the fixes applied in Issue #1289 (adding `nav_region.navigation_polygon = nav_poly` after bake and `await get_tree().physics_frame` before bake), enemy pathfinding paths still go through walls in all levels.

### Root Cause: Missing `await` on `_setup_navigation()` Coroutine

**Location:** All 13 level scripts — `_ready()` function.

**Root cause:** The `_setup_navigation()` function is a GDScript coroutine (it contains `await get_tree().physics_frame`), but it is called **without `await`** in every level's `_ready()` method.

In GDScript, calling a coroutine without `await` starts it but does NOT wait for it to complete. The caller (`_ready()`) immediately continues executing subsequent lines — including `_setup_enemy_tracking()`, `_setup_player_tracking()`, and other initialization that spawns and activates enemies.

**Timeline of the race condition:**

1. `_ready()` calls `_setup_navigation()` (without `await`)
2. `_setup_navigation()` begins executing, hits `await get_tree().physics_frame`, and yields
3. `_ready()` immediately continues to the next line: `_setup_enemy_tracking()`
4. Enemies are found and begin navigating using the **UN-BAKED** navmesh (a single large rectangle with NO wall cutouts)
5. NavigationAgent2D computes paths through the unbaked rectangle — straight through walls
6. Eventually (next physics frame), `_setup_navigation()` resumes, bakes the navmesh, and carves walls
7. Enemies that request NEW paths after this point get correct wall-respecting paths, but initial paths were already computed incorrectly

**Key evidence from the screenshot:** The orange/yellow debug path lines (from EnemyPathMonitor, Issue #1277) clearly show paths cutting diagonally through interior walls in the Building level, indicating the navmesh had no wall cutouts when those paths were first computed.

### Why Issue #1289 Fixes Were Incomplete

Issue #1289 correctly identified two problems:
- **Problem 0:** `nav_region.navigation_polygon = nav_poly` was missing after bake → Fixed
- **Problem 0b:** `await get_tree().physics_frame` was missing before bake → Fixed

However, both fixes were applied **inside** `_setup_navigation()`, making it a coroutine. The callers in `_ready()` were never updated to `await` the coroutine. This created the race condition described above.

---

## Solution

### Fix Applied

Changed all calls from `_setup_navigation()` to `await _setup_navigation()` in the `_ready()` function of all 13 level scripts:

1. `arena_level.gd` (line 168)
2. `beach_level.gd` (line 45)
3. `building_level.gd` (line 103)
4. `castle_level.gd` (line 73)
5. `city_level.gd` (line 83)
6. `decadence_level.gd` (line 46)
7. `docks_level.gd` (line 45)
8. `factory_level.gd` (line 43)
9. `labyrinth_level.gd` (line 235)
10. `labyrinth2_level.gd` (line 96)
11. `revolver_level.gd` (line 97)
12. `roguelike_level.gd` (lines 218, 278, 294 — three call sites)
13. `test_tier.gd` (line 100)

### How the Fix Works

By adding `await`, `_ready()` now pauses until `_setup_navigation()` fully completes — including the `await get_tree().physics_frame` and the subsequent navmesh bake. Only after the navmesh is fully baked and reassigned to the NavigationServer does `_ready()` continue to set up enemies and other game systems. This ensures all NavigationAgent2D path queries use the correctly carved navmesh from the very first frame.

---

## Similar Problems in Game Development

This is a well-known class of bug in Godot (and game engines generally):

1. **GDScript coroutine fire-and-forget:** Calling a coroutine without `await` is syntactically valid but the caller doesn't wait. This is a common source of race conditions in Godot 4.
2. **Navmesh bake timing:** Godot's NavigationServer requires physics shapes to be registered before parsing source geometry, which happens asynchronously. Multiple `await` points are needed for correct initialization order.
3. **Initialization order dependencies:** When system A (navigation) must complete before system B (enemy AI) starts, the dependency must be explicit via `await`, signals, or state flags.

### Relevant Godot Documentation

- [NavigationServer2D — Runtime Navigation Mesh Baking](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationservers.html#2d-navigation-mesh-baking)
- [GDScript — Using await](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html#awaiting-for-signals-or-coroutines)

### Alternative Solutions Considered

1. **Signal-based approach:** Connect enemies to a `bake_finished` signal and delay navigation until fired. More complex, but decouples initialization order.
2. **Deferred enemy activation:** Spawn enemies in a disabled state and activate after bake. Would require a new activation mechanism.
3. **Re-query paths after bake:** Force all enemies to recompute paths after bake completes. Would cause visible path snapping.

The `await` approach was chosen as the simplest and most correct fix — it preserves the natural initialization order while ensuring the navmesh is ready before any navigation queries occur.
