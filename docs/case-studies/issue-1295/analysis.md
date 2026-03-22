# Case Study: Issue #1295 — Enemy Movement Broken in Roguelike Mode

## Problem Statement

In the roguelike mode, most enemy movements do not work ("большая часть перемещений не работает").
Enemies stand still or fail to navigate to their intended positions, making combat trivial
and the game unplayable.

## Timeline / Sequence of Events

1. **Issue #1061**: Roguelike mode was initially implemented with fixed room size (1280×720).
   Navigation mesh was baked with a floor outline matching this size. Enemy movement worked.

2. **Issue #1240**: Room size was made dynamic — three options were introduced:
   - Compact: 1280×720
   - Standard: 1600×900
   - Large: 1920×1080

   The `_build_room_scene()` function was updated to pick a random size and store it in
   `_room_w` / `_room_h`. Wall generation, floor rendering, and enemy positioning were all
   updated to use these dynamic dimensions.

3. **Bug introduced**: The `_setup_navigation()` function was **not** updated to use the
   dynamic room dimensions. It continued to use the hardcoded constants `ROOM_WIDTH` (1280)
   and `ROOM_HEIGHT` (720) for the navigation polygon floor outline.

## Root Cause Analysis

The navigation mesh floor outline in `_setup_navigation()` (line 836–841 of
`scripts/levels/roguelike_level.gd`) uses:

```gdscript
var floor_outline: PackedVector2Array = PackedVector2Array([
    Vector2(0, 0),
    Vector2(ROOM_WIDTH, 0),          # ← always 1280
    Vector2(ROOM_WIDTH, ROOM_HEIGHT), # ← always 1280×720
    Vector2(0, ROOM_HEIGHT)           # ← always 720
])
```

When a room is generated at 1600×900 or 1920×1080:

- **Navigation mesh covers only 1280×720** — the inner portion of the room.
- **Enemies spawn at positions based on `_room_w`/`_room_h`** — potentially outside the
  navigable area (e.g., `Vector2(w * 0.80, h * 0.76)` = `(1536, 684)` in a 1920×900 room).
- **Walls beyond 1280×720 are not parsed** as obstacles for the navmesh, so even
  enemies within range may get incorrect paths.
- The `NavigationAgent2D` on each enemy reports `is_navigation_finished() = true` immediately
  (target is unreachable), causing `_get_nav_direction_to()` to return `Vector2.ZERO` and
  `_move_to_target_nav()` to set `velocity = Vector2.ZERO`.

### Why "most" movements are broken

Only 1 out of 3 room sizes (1280×720) produces a correctly-sized navmesh. For the other
two sizes (66% of rooms), the navmesh is undersized, breaking pathfinding for enemies near
the edges and for any path that crosses the boundary.

## Fix

Replace hardcoded `ROOM_WIDTH` / `ROOM_HEIGHT` in `_setup_navigation()` with the dynamic
`_room_w` / `_room_h` variables:

```gdscript
var floor_outline: PackedVector2Array = PackedVector2Array([
    Vector2(0, 0),
    Vector2(_room_w, 0),
    Vector2(_room_w, _room_h),
    Vector2(0, _room_h)
])
```

This ensures the navigation mesh always matches the actual room dimensions, regardless
of which size was randomly selected.

## Verification

After the fix:
- Enemies in all three room sizes (1280×720, 1600×900, 1920×1080) should navigate correctly.
- Patrol, pursuit, flanking, cover-seeking, and all other movement states should function.
- The navmesh bake correctly excludes walls at the actual room boundaries.
