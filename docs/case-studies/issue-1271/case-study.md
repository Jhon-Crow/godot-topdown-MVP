# Case Study: Issue #1271 — Enemies Walk Into Walls Instead of Navigating Around Them

## Issue Summary

**Title**: "сделай чтоб враги не долбились об стену а обходили её"
("Make enemies not bump into walls but navigate around them")

**Owner suggestion**: use `NavigationRegion2D` or check if the navmesh overlaps walls.

---

## Timeline of Investigation

### Log 1 (game_log_20260321_134324.txt — from PR #1272 comments)

```
[NavMeshMonitor] refresh: region 'NavigationRegion2D' poly_count=1 vertex_count=4
```

The navmesh was just the outer rectangle — no walls carved at all.

### Log 2 (game_log_20260321_140512.txt — from PR #1272 comments)

On BuildingLevel with the C# fallback path:
```
[LevelInitFallback] GDScript _ready() did NOT execute - performing C# fallback initialization
[Enemy1] GLOBAL STUCK  [Enemy7] GLOBAL STUCK  (all enemies stuck)
```

### Log 3 (game_log_20260321_152551.txt — "enemies don't move at all")

```
[NavMeshMonitor] poly_count=0 vertex_count=0  ← AFTER bake!
[LevelInitFallback] Navigation mesh baked successfully (C# fallback)  ← bake ran but produced nothing
[Enemy1] GLOBAL STUCK  → SEARCHING  (enemies not moving)
```

---

## Root Cause Analysis

### Root Cause 1: source_geometry_mode=0 (all levels)

All level `.tscn` files had `NavigationPolygon` with:
```
source_geometry_mode = 0        ← ROOT_NODE_CHILDREN
source_geometry_group_name = &"navigation_source"
```

In Godot 4, `source_geometry_mode = 0` (`ROOT_NODE_CHILDREN`) means:
"Scan the NavigationRegion2D node and its direct children for geometry."

But in all levels, the `NavigationRegion2D` has **zero children** — all walls are under
`Environment/Walls/*` (siblings of NavigationRegion2D, not children).

Result: Baking scans zero objects, produces only the bounding outline polygon →
**navmesh = flat rectangle**, walls are not carved.

### Root Cause 2: No `navigation_source` group on Environment node

While `source_geometry_group_name = &"navigation_source"` was set, the `Environment` node
was NOT in the `"navigation_source"` group. So even with `source_geometry_mode = 1`
(GROUPS_WITH_CHILDREN), baking would find no group members → same issue.

### Root Cause 3: Stale pre-baked data in .tscn files

Most level `.tscn` files had old baked navmesh data inline:
```
vertices = PackedVector2Array(64, 64, 2464, 64, 2464, 2064, 64, 2064)
polygons = [PackedInt32Array(0, 1, 2, 3)]
outlines = [PackedVector2Array(64, 64, 2464, 64, 2464, 2064, 64, 2064)]
```

Godot uses this stored data when the scene loads. If `bake_navigation_polygon()` is not called
at runtime (or fails), Godot uses the stale 1-polygon rectangle.

### Root Cause 4: C# fallback does not bake navmesh + runs before physics frame

`LevelInitFallback.cs` handles initialization when GDScript `_ready()` fails
(Godot 4.3 binary tokenization bug — godotengine/godot#94150). It did not call
`BakeNavigationPolygon()`.

Additionally, even after adding the bake call, if it runs before the first physics frame,
the `PhysicsServer2D` has not yet registered static body shapes. The bake query finds
zero wall shapes → `poly_count=0`.

**This explains log 3**: bake ran, printed "success", but produced 0 polygons because
`CallDeferred` executes before physics frame sync.

### Root Cause 5: GDScript also bakes before physics frame on some levels

For levels where GDScript runs, `_setup_navigation()` is called inside `_ready()`.
In Godot 4, `_ready()` runs before the first physics frame. Static bodies (walls) register
their collision shapes with PhysicsServer2D during the first physics frame.

On some levels with complex scenes, the bake call may also run before shapes are registered.

### Root Cause 6: Missing outline polygon on NavigationPolygon (CONFIRMED, session 2)

**Log 4 (game_log_20260321_160811.txt)** — user tested with session-1 fix applied:
```
[LevelInitFallback] Awaiting first physics frame...  ← physics frame fix is present
[LevelInitFallback] Navigation mesh baked: poly_count=0 vertex_count=0  ← STILL 0!
```

Root cause analysis of Godot 4.3 engine source (`nav_mesh_generator_2d.cpp`) reveals:

`bake_navigation_polygon()` has a critical guard before processing:
```cpp
if (outline_count == 0 && traversable_outlines.size() == 0) {
    return;  // No traversable area defined → 0 polygons
}
```

**StaticBody2D collision shapes define OBSTACLES (holes), NOT the traversable area.**

The baking pipeline works as:
- `NavigationPolygon.add_outline()` → defines the **walkable boundary** (required)
- `StaticBody2D` collision shapes → **subtracted** from that area (walls become holes)

Without an outline polygon, the bake has nothing to subtract walls from → returns immediately
with `poly_count=0` regardless of how correct the geometry mode and physics frame timing are.

Most levels had no `outlines` array in their `.tscn` `NavigationPolygon` sub-resource, and
no code to add one dynamically before baking. The `clear()` call in the previous session's
fix may have also cleared any existing outlines.

**CastleLevel exception**: CastleLevel's `.tscn` has `outlines = [PackedVector2Array(...)]`
defining the castle boundary perimeter — this is why CastleLevel would work but others don't.

---

## Solution

### Fix 1: source_geometry_mode = 1 (GROUPS_WITH_CHILDREN)

Change all 13 level `.tscn` files:
```diff
-source_geometry_mode = 0
+source_geometry_mode = 1
```

### Fix 2: Add Environment to navigation_source group

In all 13 levels, add `groups = ["navigation_source"]` to the `Environment` node:
```diff
 [node name="Environment" type="Node2D" parent="."]
+groups = ["navigation_source"]
```

Now when baking, Godot finds `Environment` in the `navigation_source` group,
scans all its children (walls, cover, obstacles) and carves them from the walkable area.

### Fix 3: Clear stale pre-baked data

Remove `vertices`, `polygons`, and `outlines` from `NavigationPolygon` sub-resources
in all level `.tscn` files. This forces a fresh bake at runtime using the corrected settings.

### Fix 4: Fix C# fallback — await physics frame before baking

In `LevelInitFallback.cs`:
- Add `SetupNavigation()` call in `PerformFallbackInit()`
- Convert `CheckAndInitialize()` to `async` and `await ToSignal(GetTree(), SceneTree.SignalName.PhysicsFrame)` before `PerformFallbackInit()`

This ensures the PhysicsServer2D has processed its first frame (registering all static body shapes) before the navmesh bake queries it.

### Fix 5: agent_radius before baking (all level scripts)

Set `nav_region.navigation_polygon.agent_radius = 24.0` before calling
`bake_navigation_polygon()` in level scripts that don't already have this.

The agent radius erodes the navmesh inward from walls, preventing enemies from
pathfinding through wall borders.

### Fix 6: Add bounding outline polygon before baking (session 2)

In every GDScript level `_setup_navigation()` and in `LevelInitFallback.SetupNavigation()`,
add the level's walkable area as an outline polygon before calling bake:

```gdscript
# GDScript (in each level's _setup_navigation):
var bg: ColorRect = get_node_or_null("Environment/Background")
if bg != null:
    var w := bg.size.x
    var h := bg.size.y
    nav_region.navigation_polygon.clear_outlines()
    nav_region.navigation_polygon.add_outline(PackedVector2Array([
        Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)
    ]))
```

```csharp
// C# (LevelInitFallback.SetupNavigation):
var bg = levelRoot.GetNodeOrNull<ColorRect>("Environment/Background");
if (bg != null)
{
    navPoly.ClearOutlines();
    navPoly.AddOutline(new Vector2[] {
        new Vector2(0, 0), new Vector2(bg.Size.X, 0),
        new Vector2(bg.Size.X, bg.Size.Y), new Vector2(0, bg.Size.Y)
    });
}
```

CastleLevel is exempt — its outline is the irregular castle perimeter boundary defined
in `CastleLevel.tscn`, which must not be cleared.

---

## References

- Godot 4 NavigationRegion2D docs: https://docs.godotengine.org/en/stable/classes/class_navigationregion2d.html
- Godot NavigationPolygon source_geometry_mode: https://docs.godotengine.org/en/stable/classes/class_navigationpolygon.html#enum-navigationpolygon-sourcegeometrymode
- Godot binary tokenization bug: https://github.com/godotengine/godot/issues/94150
- GodotRu Pathfinding2D reference: https://github.com/D0NM/GodotRu/tree/main/Lessons/L001%20Pathfinding2D

---

## Files Changed

- `scenes/levels/*.tscn` (13 files) — source_geometry_mode, Environment groups, stale data
- `scripts/levels/roguelike_level.gd` — dynamic NavigationPolygon source geometry mode
- `Scripts/Components/LevelInitFallback.cs` — async + await physics frame + bake call
- `scripts/levels/*.gd` (level scripts without agent_radius) — set agent_radius before bake
