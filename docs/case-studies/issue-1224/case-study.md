# Case Study: Issue #1224 — Nav Mesh Display Stopped Working

## Issue Summary

**Title:** fix не работает отображение nav mesh
**Translation:** fix: nav mesh display does not work

**Reporter:** Jhon-Crow
**Date opened:** 2026-03-21
**Linked feature:** Issue #1187 (nav mesh visibility toggle), PR #1191

**Description (translated):**
> "When this experimental option was first added it worked, now it doesn't work. It was added yesterday morning or a bit earlier."

---

## Timeline / Sequence of Events

### 2026-03-20 03:28 UTC — Initial feature added (commit `883ed8e2`)
- `feat(#1187)`: `NavMeshMonitor` autoload added, using `NavigationServer2D.set_debug_enabled()`.
- Issue: `set_debug_enabled()` **only works in editor/debug builds**, not in exported (release) builds.
- PR #1191 opened.

### 2026-03-20 04:10 UTC — Fix: custom drawing overlay (commit `e950c52c`)
- `fix(#1187)`: Replaced `set_debug_enabled()` with custom `_NavMeshOverlay` (CanvasLayer) + `_NavMeshDrawNode` (Node2D).
- The overlay reads `NavigationPolygon` data via **`get_outline_count()` / `get_outline(i)`** (input outlines, not baked polygons).
- This works **when the nav mesh has pre-drawn outlines** (e.g., outlines added via `add_outline()` that haven't been cleared).
- For levels that call `nav_poly.clear()` before baking, there are no outlines left to display after the bake.

### 2026-03-20 04:27 UTC — PR #1191 merged into upstream main
- The feature is now on `Jhon-Crow/godot-topdown-MVP:main`.
- At this point the nav mesh display **appeared to work** on some levels (those with pre-baked outline data in their `.tscn` file), but **not on all levels**.

### 2026-03-20 04:40–08:17 UTC — More commits merged (PR #1127, #1179, #1196, #1197, etc.)
- Unrelated features merged. No changes to nav mesh code.

### 2026-03-20 06:35 UTC — Root cause discovered in issue-1188 branch (commit `e181d136`)
- Working on issue #1188 (enemy pathfinding), a deeper bug in the nav mesh display was found:
  - `nav_mesh_monitor.gd` reads `get_outline()` data (raw input boundaries), NOT the baked polygon data.
  - After `bake_navigation_polygon()`, Godot updates `get_vertices()` / `get_polygon()` (triangulated walkable area), **not** `get_outline()`.
  - Levels that call `nav_poly.clear()` before baking (building, arena, castle, city, labyrinth, revolver, test_tier) erase their outline data, leaving zero outlines for the monitor to read.
  - **Fix implemented** in commit `e181d136` on `origin/issue-1188-92d193c02cfa`: switch to reading baked polygon data + connect to `bake_finished` signal.
- **This fix was NEVER merged to main** — the issue-1188 branch is still open.

### 2026-03-21 — Issue #1224 opened
- Reporter confirms the experimental nav mesh display feature is non-functional.
- The nav mesh display either shows nothing or shows the wrong (uncarved, pre-wall-exclusion) boundary.

---

## Root Cause Analysis

### Primary Root Cause: Wrong NavigationPolygon API in nav_mesh_monitor.gd

In Godot 4, `NavigationPolygon` has two separate sets of data:

| API | Contents | Updated by |
|-----|----------|------------|
| `get_outline_count()` / `get_outline(i)` | Raw input outlines (floor boundary + obstacle outlines added via `add_outline()`) | `add_outline()` calls in GDScript |
| `get_polygon_count()` / `get_polygon(i)` + `get_vertices()` | Triangulated baked walkable area (with walls carved out) | `bake_navigation_polygon()` |

The current `nav_mesh_monitor.gd` (commit `e950c52c`) reads `get_outline_count()` / `get_outline()`. This means:

- On levels where the `.tscn` file contains pre-drawn outlines AND no `clear()` is called → outlines exist → some display works (but shows the **entire floor boundary**, not the carved walkable mesh).
- On levels where GDScript calls `nav_poly.clear()` before baking (building, arena, castle, city, labyrinth, revolver, test_tier) → **zero outlines** → nothing is displayed.
- In all cases, even when outlines are displayed, they show the raw boundary, NOT the actual walkable area with walls excluded.

### Secondary Root Cause: Refresh Timing (call_deferred too early)

`_on_node_added()` calls `call_deferred("_deferred_refresh")` when a `NavigationRegion2D` is added. `call_deferred` runs at end-of-frame, but `bake_navigation_polygon()` is itself often deferred. This means the refresh can run **before** the bake completes, reading empty baked data.

The fix (`e181d136`) addresses this by:
1. Connecting to `NavigationRegion2D.bake_finished` signal (fires after bake completes).
2. Adding a 0.2s timer fallback (for cases where the bake was already done before the monitor connected).

### Evidence

```
# Current refresh() logic (broken):
var outline_count: int = nav_poly.get_outline_count()
if outline_count > 0:
    for i in range(outline_count):
        var outline: PackedVector2Array = nav_poly.get_outline(i)
        # ...
else:
    # Falls back to polygon data — but only if no outlines exist
    var vertex_count: int = nav_poly.get_polygon_count()
    # ...
```

The fallback to polygon data **only triggers when `outline_count == 0`**. But on most levels, either:
- Outlines exist (from `.tscn` file) → outline path taken → shows raw boundary, not carved mesh.
- Outlines were cleared by `nav_poly.clear()` → no outlines AND the fallback may run before bake → nothing shown.

---

## Proposed Fix

Apply the changes from commit `e181d136` (already written, never merged):

### 1. nav_mesh_monitor.gd — Read baked polygon data

```gdscript
# BEFORE (reads raw input outlines — wrong after baking):
var outline_count: int = nav_poly.get_outline_count()
if outline_count > 0:
    for i in range(outline_count):
        var outline: PackedVector2Array = nav_poly.get_outline(i)
        ...

# AFTER (reads baked triangulated polygons — correct):
var poly_count: int = nav_poly.get_polygon_count()
if poly_count > 0:
    var all_vertices: PackedVector2Array = nav_poly.get_vertices()
    for i in range(poly_count):
        var indices: PackedInt32Array = nav_poly.get_polygon(i)
        var verts: PackedVector2Array = PackedVector2Array()
        for idx in indices:
            verts.append(all_vertices[idx])
        polygons.append(...)
else:
    # Fallback to outlines only if no baked data yet
    ...
```

### 2. nav_mesh_monitor.gd — Connect to bake_finished signal

```gdscript
# BEFORE:
func _on_node_added(node: Node) -> void:
    if node is NavigationRegion2D:
        call_deferred("_deferred_refresh")  # Too early — bake not done yet

# AFTER:
func _on_node_added(node: Node) -> void:
    if node is NavigationRegion2D:
        if not node.bake_finished.is_connected(_deferred_refresh):
            node.bake_finished.connect(_deferred_refresh)
        get_tree().create_timer(BAKE_WAIT_SECONDS).timeout.connect(_deferred_refresh)
```

### 3. Level scripts — Remove unnecessary clear()+add_outline()

Levels that call `nav_poly.clear()` + `nav_poly.add_outline()` before baking do not need these calls — their `.tscn` files already contain the correct outlines. Clearing them erases the floor boundary that the nav mesh monitor's fallback path depends on.

Only `building_level.gd` still has this pattern on main (the other levels were already cleaned up in earlier commits).

---

---

## Follow-up: Game Log from 2026-03-21 (PR #1229 still in draft)

**File:** `game_log_20260321_064641.txt` (attached to PR #1229 comment by Jhon-Crow)

### Log Analysis

| Field | Value |
|-------|-------|
| Build | Exported release (Debug build: false) |
| Engine | Godot 4.3-stable (official) |
| Build info | not available (build_info.cfg not found) — **old build, predates PR #1229 fix** |
| Executable path | `I:/Загрузки/godot exe/experimental/Godot-Top-Down-Template.exe` |

### Key observations

1. **No `[NavMeshMonitor]` log entries** — confirms the user is running a build from before our logging additions in PR #1229.
2. The `ExperimentalSettings` initialization line (line 41) shows `Nav mesh visible: true` — the setting is saved from a previous session where the user enabled it.
3. Line 274: `Navigation mesh visibility disabled` — user toggled it off.
4. Line 493: `Navigation mesh visibility enabled` — user toggled it back on.
5. Line 513: Scene changes to `BuildingLevel` — at this point the overlay should refresh, but cannot because the game binary is old.
6. The absence of any `NavMeshMonitor` log (even from `_ready()`) confirms **this test was done with the old binary, not with the fix from PR #1229**.

### Conclusion

The user's "still not working" report is based on testing an **old exported build** that does not include the fix from PR #1229. The fix needs to be merged and a new release exported for the user to test.

---

## References

- Issue #1187: Original nav mesh visibility request
- PR #1191: Implementation that was merged (but with the outline-reading bug)
- PR #1229: Fix for issue #1224 (reads baked polygon data, connects to `bake_finished`)
- Commit `e950c52c`: The merged fix — replaced `set_debug_enabled()` with custom overlay, but reads wrong data
- Commit `e181d136` (branch `issue-1188-92d193c02cfa`): The correct fix — reads baked polygon data, connects to `bake_finished`
- Commit `56cdf595` (branch `issue-1224-feba1278811f`): PR #1229 — applies the same fix to all 8 affected levels
- Godot 4 docs: [NavigationPolygon](https://docs.godotengine.org/en/stable/classes/class_navigationpolygon.html) — `get_polygon()` / `get_vertices()` hold baked data; `get_outline()` holds input boundaries
- Game log: `game_log_20260321_064641.txt` (from Jhon-Crow's comment on PR #1229, 2026-03-21)
