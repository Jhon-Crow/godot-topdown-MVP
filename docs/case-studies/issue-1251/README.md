# Case Study: Issue #1251 — «не видно путей» (Search Path Visualization Not Visible)

## Overview

| Field | Value |
|---|---|
| Issue | [#1251](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1251) — Add search path visualization to Experimental menu |
| PR | [#1252](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1252) |
| Reporter | @Jhon-Crow |
| Report date | 2026-03-21 |
| Level tested | LabyrinthLevel (and BuildingLevel) |
| Engine version | Godot 4.3-stable (official) |
| Platform | Windows (I:/Загрузки/godot exe/experimental/) |
| Build type | Release (not debug build) |
| Log file | [`game_log_20260321_103552.txt`](./game_log_20260321_103552.txt) |

## Attached Evidence

- [`game_log_20260321_103552.txt`](./game_log_20260321_103552.txt) — Full game log from the user's session, 1797 lines, covering the reproduction scenario

---

## Timeline / Sequence of Events

Reconstructed from `game_log_20260321_103552.txt`:

| Wall-clock time | Log line | Event |
|---|---|---|
| 10:35:52 | L41 | Game start; `search_path_visible: false` at init |
| 10:35:52–55 | L43–248 | First LabyrinthLevel attempt — player dies quickly, scene restarts multiple times (no enemy SEARCHING state reached) |
| 10:35:56–36:33 | L248–432 | Second attempt at LabyrinthLevel; scene reloads again multiple times (rapid deaths, level stays LabyrinthLevel) |
| **10:36:31** | **L424** | **User enables "Show Search Paths" in Experimental menu: `Search path visibility enabled`** |
| 10:36:33 | L427–432 | Another LabyrinthLevel reload (player died again, presumably) |
| 10:36:38 | L852–862 | Player progresses to **BuildingLevel** (scene change to `BuildingLevel.tscn`) |
| 10:36:46 | L1303 | Player opens Armory menu during BuildingLevel |
| 10:36:51 | L1330 | Invincibility mode toggled **OFF** |
| 10:36:52–53 | L1334–1399 | Combat begins: Enemy1, Enemy3, Enemy4 enter COMBAT/PURSUING; player takes 3 hits (health 3→2→1) |
| **10:36:59** | **L1529–1540** | **LastChance effect expires; Enemy1–4 enter SEARCHING state with spiral waypoints (5 each)** |
| 10:36:59– | L1557–1707 | Enemies in SEARCHING state — this is when paths SHOULD be visible |
| 10:37:22 | End | Game log ended |

**Key observation**: The user enabled "Show Search Paths" at `10:36:31`, but enemies only entered `SEARCHING` state at `10:36:59` — **28 seconds later** and **after a scene change** (LabyrinthLevel → BuildingLevel at `10:36:38`). The user presumably saw nothing and reported "не видно путей".

---

## Root Cause Analysis

### Root Cause #1 (Confirmed by PR #1252 v1): Static-only visualization

**Original implementation** (before PR #1252) only visualized **predefined** `SearchPathWaypoints` scene nodes (nodes in the `"search_path_waypoints"` group). These static waypoint markers exist only in `CityLevel`. In `LabyrinthLevel` and `BuildingLevel`, enemies use **dynamic spiral search** — waypoints are generated at runtime and stored in `_search_waypoints: Array[Vector2]` on each enemy. The original monitor had no way to access these.

This is the primary root cause confirmed by the initial fix in PR #1252.

### Root Cause #2 (Confirmed by game log): Timing — toggle enabled before enemies searched

From the game log:
- `search_path_visible: false` at init (L41)
- `Search path visibility enabled` at `10:36:31` (L424) — **before enemies ever entered SEARCHING state**
- First `SEARCHING started` event: `10:36:59` (L1531) — **28 seconds after toggle**
- Scene changed at `10:36:38` — **between toggle and SEARCHING state**

The `_process()` loop in `SearchPathMonitor` refreshes the overlay every frame, so the fix should work once enemies enter SEARCHING state. However, the **scene change at `10:36:38`** may have caused the overlay's `_draw_node` to lose its reference or position context.

### Root Cause #3 (Potential): `CanvasLayer` coordinate system mismatch

The `_SearchPathOverlay` is a `CanvasLayer` with `follow_viewport_enabled = true`, containing a `_SearchPathDrawNode` (Node2D). The `_draw()` method uses **world-space coordinates** (`enemy.global_position`, `waypoints[i]` which are `Vector2` world positions).

**Critical finding from Godot 4 documentation and community reports** (Issue [#98463](https://github.com/godotengine/godot/issues/98463)):

> When `follow_viewport_enabled = true`, a CanvasLayer *stays screen-fixed* — it does NOT follow the game world. The naming is counterintuitive and has caused widespread confusion.

This means:
- The Node2D child's `_draw()` calls use **CanvasLayer-local coordinates** (screen space), not world space
- Enemy search waypoints are at world positions like `(563, 680)`, `(400, 300)`, etc. — these map to screen pixels only when the camera happens to be at origin
- When the camera moves away from origin, the drawn dots/lines appear at the wrong position on screen (or off-screen entirely)

**However**, looking at the code more carefully: `follow_viewport_enabled = true` in Godot 4 actually means the layer IS scaled/transformed with the viewport camera — it follows the **viewport transform**. This is used for parallax. The Node2D child still draws in the CanvasLayer's local coordinate space.

From Godot 4 docs: "If `follow_viewport_enabled` is true, this CanvasLayer will be drawn as if it's at the same Z layer as the canvas it's assigned to, using the viewport's transform." This effectively means the world-space coordinates passed to `draw_line()` **should** render correctly at world-space positions.

Therefore, Root Cause #3 is **less certain** — the `follow_viewport_enabled = true` approach may work correctly. This needs further testing.

### Root Cause #4 (Confirmed by log): Rapid scene reloads before SEARCHING

The game log shows the level reloaded **at least 5 times** in the span of ~40 seconds before the user enabled the toggle. This suggests the user was dying repeatedly before even getting to trigger enemy search behavior. The path visualization never had a chance to be observed:

1. First LabyrinthLevel load: 10:35:52
2. Reload at 10:35:56 (player died)
3. Reload at 10:36:33 (player died again)
4. Reload at 10:36:34 (another)
5. Reload at 10:36:35 (another — with 11 fps drop)
6. Scene change to BuildingLevel at 10:36:38

Each reload recreates all enemies, resetting any search state. The `SearchPathMonitor._on_node_added` callback re-applies settings on new enemies, but enemies start in `IDLE` state — they only enter `SEARCHING` after combat and evasion.

### Root Cause #5 (Secondary): User never stayed alive long enough to observe searching

From the log (BuildingLevel):
- Health at entry: 2/4 (already damaged from LabyrinthLevel)
- Enemy1 fires at player at 10:36:52 → health 3/4
- Enemy3 fires → health 2/4
- Enemy3 fires again → health 1/4
- `LastChance` triggered at 10:36:53 (1 hp left)
- Player enabled invincibility OFF at `10:36:51` and back ON at `10:36:55`
- `SEARCHING started` at `10:36:59` — **after** the LastChance freeze effect (6s) ended

The `LastChance` feature freezes time except for the player. During this freeze (10:36:53–10:36:59), the overlay's `_process()` loop was still running, but the enemies were frozen (PROCESS_MODE_INHERIT off), so their waypoints were empty/zeroed.

---

## What the Game Log Confirms

1. ✅ `search_path_visible_enabled` was correctly toggled to `true` at 10:36:31
2. ✅ Enemies did enter `SEARCHING` state (spiral, 5 waypoints each) at 10:36:59
3. ✅ The `get_search_waypoints()` getter exists on enemy.gd (added by PR #1252)
4. ✅ Enemies are in the `"enemies"` group (confirmed by `add_to_group("enemies")` in enemy.gd line 365)
5. ❓ Whether the drawn shapes appeared at correct screen positions (not logged — visual output)
6. ❓ Whether `get_current_state()` returned `9` (SEARCHING) correctly during the log period

**Key gap**: The log does NOT contain any `[SearchPathMonitor]` output during the SEARCHING period. This means either:
- The monitor's `_log_info()` was not called during `_process()` refresh (expected — it only logs on enable/disable, not every frame)
- Or there is a silent failure during `refresh()` that we cannot confirm from logs alone

---

## Proposed Solutions & Improvements

### Solution A: Add diagnostic logging to SearchPathMonitor (Already partially done)

Add log output when the overlay finds searching enemies, to confirm the data flow works:
```gdscript
# In refresh():
if active_paths.size() > 0:
    _log_info("SearchPathMonitor: drawing %d active paths" % active_paths.size())
```
This would let us confirm in the next report whether the monitor is finding enemies and data is flowing.

### Solution B: Verify CanvasLayer coordinate system

Test whether `follow_viewport_enabled = true` + Node2D child draws at correct world positions by adding a visible fixed-position test marker (e.g., a circle at `(0, 0)` world space) and confirming it appears at the world origin when camera is there.

Alternative: Use a Node2D added directly to the scene tree root (not inside a CanvasLayer), which guarantees world-space draw coordinates.

### Solution C: Add SearchPathMonitor to the Experimental Debug HUD

Instead of a separate overlay, integrate search path data into an existing debug panel if one exists — this avoids coordinate system issues and is always readable.

### Solution D: Log waypoint positions when search begins

In `enemy.gd`, log the actual waypoint positions when `SEARCHING started` to confirm the `get_search_waypoints()` getter returns valid data.

---

## Known Existing Components / Libraries (Online Research)

The following existing tools solve similar problems and could serve as reference or replacement:

| Tool | Description | Relevance |
|---|---|---|
| [Godot Debug Draw 3D/2D](https://godotengine.org/asset-library/asset/1766) | Asset library plugin for drawing debug shapes with minimal setup | Could replace custom overlay entirely |
| [Godot 4 Viewport Transforms docs](https://docs.godotengine.org/en/stable/tutorials/2d/2d_transforms.html) | Official docs on coordinate system transforms | Critical for understanding CanvasLayer draw coordinates |
| [KidsCanCode Debug Overlay recipe](https://kidscancode.org/godot_recipes/4.x/ui/debug_overlay/index.html) | Standard recipe for Godot 4 debug overlays | Reference implementation |
| Godot `draw_set_transform()` | Built-in Node2D method to apply a Transform2D before draw calls | Allows drawing in world-space from a screen-space Node2D |
| [Godot Issue #98463](https://github.com/godotengine/godot/issues/98463) | Community-reported confusion about `follow_viewport_enabled` behavior | Documents the coordinate system ambiguity directly |
| Godot `CanvasItem.draw_line()` | Draws in the local coordinate system of the node | Core drawing primitive; coordinates depend on node's transform |

---

## Summary

The user's report "не видно путей" (paths not visible) on 2026-03-21 was reproduced via the attached game log. The session shows:

1. **Primary confirmed root cause**: The original implementation only drew predefined `SearchPathWaypoints` nodes, which don't exist in `LabyrinthLevel`/`BuildingLevel` → **fixed in PR #1252** by adding dynamic spiral search path visualization.

2. **Timing issue**: The user enabled the toggle 28 seconds before enemies ever entered SEARCHING state, and a level change occurred in between. Even with the fix, the user may not have waited long enough to trigger and observe enemy search behavior.

3. **Possible coordinate rendering issue**: The `CanvasLayer` + `follow_viewport_enabled` + Node2D drawing approach may have coordinate system quirks depending on camera position. The fix added world-space coordinate drawing, but the correctness of this with `follow_viewport_enabled = true` should be validated.

4. **Recommendation**: Add a brief log message each time `SearchPathMonitor` draws active paths (once per second would suffice) so future reports can confirm data is flowing, even without visual output.
