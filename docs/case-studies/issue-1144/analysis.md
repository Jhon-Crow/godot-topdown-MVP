# Case Study: Issue #1144 — RPG Rocket Destroys Obstacles Only Visually

## Issue Summary

The enemy RPG rocket destroys obstacles only visually — after an explosion, the visual
representation disappears but invisible physics walls remain, blocking movement.

**Issue URL**: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1144
**Reporter**: Jhon-Crow
**Request**: Fix RPG rocket to destroy obstacles (both visually AND physically), the same way
Piercing/Breaching Charges do.

---

## Timeline / Sequence of Events

1. **Issue #583** — RPG rocket introduced: `Area2D` + `bullet.gd` with `is_rpg_rocket = true`
2. **Issue #1131** — Wall penetration added: `WallBreachHelper.open_wall_passage()` called on
   direct hits against `StaticBody2D` walls, using rocket's `global_position` as breach point
3. **Issue #1135** — Homing added: `rpg_homing_steer_speed`, `rpg_homing_max_turn_angle`
4. **Issue #1144** — Report: obstacles are destroyed visually but invisible walls remain
5. **PR #1152 (first pass)** — Three root causes fixed: impact position, radius breach,
   LightOccluder2D; CI passed, bot reported "ready to merge"
6. **Issue #1144 follow-up (2026-03-18)** — Owner confirms invisible obstacles still persist
   after RPG explosions. Provided two game logs (game_log_20260318_085249.txt,
   game_log_20260318_085336.txt) showing breach events that still leave impassable areas.

---

## Root Cause Analysis

### Root Cause 1 (Fixed in PR #1152): Impact Position Inaccuracy

`_rpg_explode()` previously called `WallBreachHelper.open_wall_passage(_rpg_hit_wall, global_position)`
where `global_position` is the rocket's center at explosion time.

**Fix**: Store `_rpg_hit_position` from the raycast surface hit point and pass it to
`WallBreachHelper` instead of the rocket center.

### Root Cause 2 (Fixed in PR #1152): Explosion Radius Obstacles Not Breached

Nearby obstacles (not directly hit by the rocket body) were not breached.

**Fix**: `_rpg_breach_obstacles_in_radius()` added to bullet.gd, finding all StaticBody2D
on collision layer 4 within `rpg_explosion_radius` via `PhysicsShapeQueryParameters2D`.

### Root Cause 3 (Fixed in PR #1152): LightOccluder2D Not Hidden After Breach

Visual shadow strips remained from LightOccluder2D nodes not being hidden.

**Fix**: Added `LightOccluder2D` handling to `_split_visual_horizontal()` and
`_split_visual_vertical()` in WallBreachHelper.

---

### Root Cause 4 (NEW — Follow-up): Double-Breach Ghost Collision Shapes

**This is the root cause of the persistent invisible obstacles confirmed by the game logs.**

When `WallBreachHelper.open_wall_passage()` is called multiple times on the **same wall**
(for example: rocket hits Barricade1 at local x=4 at 08:54:12, and again at x=-4 at
08:55:20 as seen in game_log_20260318_085336.txt), the following sequence produces ghost
collision shapes:

**First breach:**
1. Original `CollisionShape2D` disabled.
2. Left segment `CollisionShape2D` added (active).
3. Right segment `CollisionShape2D` added (active).
4. Visual `ColorRect` segments added.

**Second breach (same wall, different position):**
1. `open_wall_passage` loops through children to find a `RectangleShape2D` — it finds the
   original shape (which is disabled). Uses its `size` to compute new breach geometry.
2. Disables original shape (no-op, already disabled).
3. **Does NOT disable the first-breach segment shapes** → they remain active!
4. Adds two MORE new segment shapes for the second breach position.

**Result:** After two breaches on the same wall, there are up to 4 active collision shapes
whose combined coverage leaves impassable invisible barriers, even though the visual appears
breached correctly.

**Evidence from game logs:**
```
game_log_20260318_085336.txt:
  [08:54:12] [WallBreachHelper] Horizontal passage in 'Barricade1' at local x=4 (width 120px)
  ...
  [08:55:20] [WallBreachHelper] Horizontal passage in 'Barricade1' at local x=-4 (width 120px)
```
Two separate breach events on the same Barricade1 wall. After the second, the first breach's
segment shapes were still active, blocking movement at x=4 while the visual showed a gap at x=-4.

**Secondary issue found:** Each breach call also added new visual `ColorRect` segment nodes
without removing the previous ones. While the prior segments were hidden by re-running the
visual split, they accumulated as orphaned invisible nodes — minor memory leak.

---

## Affected Code

### Primary: `scripts/effects/wall_breach_helper.gd`

- **Root Cause 4 (follow-up)**: `open_wall_passage()` — did not disable/remove collision
  shapes added by prior calls on the same wall; did not remove prior dynamic visual nodes.

### Also Affected (Fixed in PR #1152): `scripts/projectiles/bullet.gd`

- Root Cause 1: `_rpg_explode()` — used `global_position` instead of surface hit point
- Root Cause 2: Missing radius breach logic
- Root Cause 3: `WallBreachHelper` missing LightOccluder2D handling

---

## Fix (Root Cause 4)

### Solution Chosen: Metadata-tagged cleanup + full collision disable

Modified `WallBreachHelper.open_wall_passage()` to:

1. **Remove dynamic nodes from prior breaches**: A new `DYNAMIC_NODE_META` constant
   (`&"wall_breach_dynamic"`) is used to tag all collision shapes and ColorRects added by
   this helper. At the start of each `open_wall_passage` call, `_remove_dynamic_nodes()`
   queue_frees any tagged nodes, cleaning up ghost shapes and stale visuals.

2. **Disable ALL collision shapes upfront**: After removing dynamic nodes, ALL remaining
   `CollisionShape2D` and `CollisionPolygon2D` children are disabled (the original shapes).
   This ensures the original shape is disabled even without needing a separate `col_shape.disabled`
   call in each branch.

3. **Find largest shape for wall dimensions**: When searching for the `RectangleShape2D` to
   determine wall size, use the shape with the **largest area**. This is more robust — the
   original full-wall shape has the largest area, while segment shapes from prior breaches
   are smaller.

### Alternatives Considered

- **Just disable all shapes**: Prevents invisible obstacles but leaves visual orphans. Chosen
  approach (metadata cleanup) is cleaner and prevents memory accumulation.

- **Check `disabled` state to skip already-disabled shapes**: Fragile — the original shape
  might legitimately be disabled if a thin wall was fully passable.

- **Store breach state on the wall node**: More complex, requires extra state management.

---

## Godot Engine Reference

- `Node.set_meta()` / `Node.has_meta()`: Used to tag dynamically-added nodes for cleanup.
  [Godot docs — Node meta](https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-set-meta)

- `PhysicsShapeQueryParameters2D` / `direct_space_state.intersect_shape()`: Used to find
  nearby obstacles. Already present in `_rpg_breach_obstacles_in_radius()`.

- `StaticBody2D` collision shapes: Disabling a `CollisionShape2D` removes it from the
  physics world immediately, unlike `queue_free()` which defers until next frame.

---

## Test Plan

1. Manual: RPG rocket hitting Barricade1 once — walkable 120px gap, no invisible wall.
2. Manual: RPG rocket hitting Barricade1 twice — only ONE gap at the second hit position,
   no invisible walls from the first breach remain.
3. Manual: RPG rocket exploding near obstacles that are not directly hit — obstacles in blast
   radius are also breached (physics + visual).
4. Regression: Breaching Charges still work correctly (they also call `open_wall_passage`).
5. Unit tests: `tests/unit/test_rpg_obstacle_destruction.gd`

---

## Game Log Evidence

### game_log_20260318_085336.txt — Key events:
```
[08:54:12] [WallBreachHelper] Horizontal passage in 'Barricade1' at local x=4
           → First breach at x=4, segment shapes added
[08:55:20] [WallBreachHelper] Horizontal passage in 'Barricade1' at local x=-4
           → Second breach at x=-4, but x=4 segment shapes STILL ACTIVE
           → Result: collision blocked at x=4 region despite "breached" appearance
```

### game_log_20260318_085249.txt:
- No wall breach events logged (player used Breaching Charges in this session).
- Confirms issue is RPG-specific (not Breaching Charges — those call `open_wall_passage`
  the same way but are less likely to hit the same wall twice in close succession).
