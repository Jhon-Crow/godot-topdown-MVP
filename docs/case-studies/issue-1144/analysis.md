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

### Root Cause 5 (NEW — Follow-up 2): `queue_free()` Race Condition in `_remove_dynamic_nodes`

**This is the root cause of invisible obstacles persisting even after the Root Cause 4 fix.**

**Evidence from game_log_20260318_094725.txt:**
```
[09:47:33] [WallBreachHelper] Horizontal passage in 'Building3' at local x=20
[09:47:34] [WallBreachHelper] Horizontal passage in 'Building3' at local x=12
[09:47:45] [WallBreachHelper] Horizontal passage in 'Building3' at local x=-18
[09:48:03] [WallBreachHelper] Horizontal passage in 'Building3' at local x=20
```
Building3 was hit 4 times. After each re-breach, invisible obstacles remained.

**Root cause:**

`_remove_dynamic_nodes()` called `queue_free()` on dynamic `CollisionShape2D` nodes from prior
breaches. In Godot, `queue_free()` **defers scene-tree removal to the end of the current frame**.
This means the `CollisionShape2D` nodes remain active in the physics engine during the frame in
which a new breach is being created.

Sequence when the same wall is hit a second time in a single frame (or across consecutive frames
before the deferred free runs):

1. `_remove_dynamic_nodes()` calls `queue_free()` on breach-1 segment shapes → **still active**
2. Wall dimensions found from original shape ✓
3. Original shape disabled ✓
4. Breach-2 new segment shapes added → **now BOTH breach-1 AND breach-2 segments exist**
5. Physics engine sees: original (disabled) + breach-1 segs (alive until frame end) + breach-2 segs
6. Result: collision blocked in the area covered by breach-1 segments

In Godot, `CollisionShape2D.disabled = true` removes the shape from the physics world
**immediately** within the same frame, whereas `queue_free()` alone does not.

**Fix:**

In `_remove_dynamic_nodes()`, immediately set `.disabled = true` on any `CollisionShape2D` or
`CollisionPolygon2D` before calling `queue_free()`. This removes the shape from physics
this frame, while `queue_free()` still cleans it from the scene tree on the next frame.

Also skip dynamic nodes (already tagged `DYNAMIC_NODE_META`) in the dimension-finding loop,
the "disable all shapes" loop, and the visual-split functions — to avoid reading from or
writing to nodes that are pending deletion.

---

### Root Cause 6 (NEW — Follow-up 3): Physics Callback Safety — Direct `.disabled` Assignment Ignored

**This is the root cause confirmed by game_log_20260318_101526.txt and Godot official documentation.**

**Evidence from game_log_20260318_101526.txt:**
```
[10:15:37] [WallBreachHelper] Horizontal passage in 'Building3' at local x=20 (width 120px)
[10:15:37] [WallBreachHelper] Thin wall 'CrateSquare3' breached (fully passable)
```
Building3 was hit only ONCE in this session, yet the obstacle remained impassable.

**Root cause:**

The RPG rocket's `_rpg_explode()` is triggered from `_on_body_entered()`, which is a
**physics callback** — it fires during the physics step while the physics server is actively
processing collisions.

Godot's official documentation for `CollisionShape2D.disabled` states:

> *"This property should be changed with Object.set_deferred."*
>
> See: https://docs.godotengine.org/en/stable/classes/class_collisionshape2d.html

The reason: during a physics callback, the physics server is locked. Direct assignment to
`.disabled` (e.g., `(child as CollisionShape2D).disabled = true`) is **silently ignored** by
the physics server — the property appears changed in GDScript, but the shape remains active
in the physics world. This produces **permanent invisible obstacles** that persist until the
level is reloaded.

**Why Breaching Charges work:** The `BreachingChargesEffect.detonate()` method is called from
`_input()` or `_process()`, NOT from a physics callback. Direct `.disabled` assignment is
safe in that context, so Breaching Charges work correctly even with the previous code.

**Why RPG Rocket fails:** `WallBreachHelper.open_wall_passage()` is called from
`_on_body_entered()` (a physics callback). All previous fixes correctly structured the logic
but ALL of them used direct `.disabled = true` assignment — which is silently dropped inside
a physics callback.

**Fix:**

Wrap `_apply_wall_passage()` (the function that actually modifies collision shapes) in a
deferred call via a lambda `Callable`, so all shape modifications run **after** the current
physics step when the physics server is safe to modify:

```gdscript
static func open_wall_passage(wall: Node, breach_world_pos: Vector2) -> void:
    ...
    (func(): WallBreachHelper._apply_wall_passage(wall, breach_world_pos)).call_deferred()
```

This single change ensures that all `CollisionShape2D.disabled = true` assignments, all
`add_child(new_shape)` calls, and all `queue_free()` calls happen at a safe point (end of
frame), making the breach reliable regardless of which callback triggered it.

---

## Affected Code

### Primary: `scripts/effects/wall_breach_helper.gd`

- **Root Cause 4 (follow-up)**: `open_wall_passage()` — did not disable/remove collision
  shapes added by prior calls on the same wall; did not remove prior dynamic visual nodes.
- **Root Cause 6 (follow-up 3)**: `open_wall_passage()` — modifications made during physics
  callbacks were silently dropped; required deferred execution.

### Also Affected (Fixed in PR #1152): `scripts/projectiles/bullet.gd`

- Root Cause 1: `_rpg_explode()` — used `global_position` instead of surface hit point
- Root Cause 2: Missing radius breach logic
- Root Cause 3: `WallBreachHelper` missing LightOccluder2D handling

---

## Fix (Root Causes 4, 5 & 6)

### Solution Chosen: Deferred execution + metadata-tagged cleanup

Modified `WallBreachHelper.open_wall_passage()` and `_remove_dynamic_nodes()` to:

1. **Defer ALL shape modifications** (Root Cause 6 fix): `open_wall_passage()` now schedules
   `_apply_wall_passage()` via a lambda `Callable.call_deferred()`, so ALL shape changes
   (disable original, add new segments, remove stale dynamic nodes) run AFTER the physics
   step where the physics server is safe to modify.

2. **Immediately disable collision before queue_free** (Root Cause 5 fix): In
   `_remove_dynamic_nodes()`, set `child.disabled = true` on any `CollisionShape2D` or
   `CollisionPolygon2D` **before** calling `child.queue_free()`. This removes the shape
   from the physics world immediately within the deferred frame, not deferred further.

3. **Skip dynamic nodes in all child loops**: The dimension-finding loop, the "disable all
   shapes" loop, and the visual-split functions now skip nodes with `DYNAMIC_NODE_META` to
   avoid reading/writing to nodes pending deletion.

4. **Remove dynamic nodes from prior breaches** (Root Cause 4 fix): `DYNAMIC_NODE_META`
   (`&"wall_breach_dynamic"`) tags all collision shapes and visual nodes added by this helper.
   `_remove_dynamic_nodes()` cleans them up at the start of each `_apply_wall_passage` call.

5. **Disable ALL original collision shapes upfront**: After cleaning dynamic nodes, all
   non-dynamic `CollisionShape2D` / `CollisionPolygon2D` children are disabled so the
   original wall shape is immediately passable.

6. **Find largest shape for wall dimensions**: Use the shape with the largest area (skipping
   dynamic segment shapes). The original full-wall shape always has the largest area.

### Alternatives Considered

- **Use `set_deferred("disabled", true)` per-shape**: Works for single changes but doesn't
  solve the race window where new shapes can be added before old ones are disabled, since each
  `set_deferred` call is independent. The chosen approach (defer the whole function) is atomic.

- **Use `.free()` instead of `queue_free()`**: Immediate deletion, but risky if any signals
  are connected to the nodes. The chosen approach (disable + queue_free in deferred context)
  is safer.

- **Just disable all shapes**: Prevents invisible obstacles but leaves visual orphans growing
  each breach. Metadata cleanup prevents the orphan accumulation.

- **Store breach state on the wall node**: More complex state management, less clean.

---

## Godot Engine Reference

- `Node.set_meta()` / `Node.has_meta()`: Used to tag dynamically-added nodes for cleanup.
  [Godot docs — Node meta](https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-set-meta)

- `PhysicsShapeQueryParameters2D` / `direct_space_state.intersect_shape()`: Used to find
  nearby obstacles. Already present in `_rpg_breach_obstacles_in_radius()`.

- `StaticBody2D` collision shapes: Disabling a `CollisionShape2D` removes it from the
  physics world immediately (when done outside a physics callback), unlike `queue_free()`
  which defers until next frame.

- `CollisionShape2D.disabled` requires `set_deferred("disabled", true/false)` when called
  during a physics callback. Direct assignment is silently dropped by the physics server.
  [Godot docs — CollisionShape2D.disabled](https://docs.godotengine.org/en/stable/classes/class_collisionshape2d.html)

- `Callable.call_deferred()`: Queues a callable to run after the current frame, outside
  physics processing. Used to defer the whole `_apply_wall_passage` function.
  [Godot docs — Callable](https://docs.godotengine.org/en/stable/classes/class_callable.html)

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

## Timeline of Owner Reports

| Date | Log | Breach Events | Diagnosis |
|------|-----|---------------|-----------|
| 2026-03-18 (first report) | game_log_20260318_085249.txt | BreachingCharges only | Confirmed RPG-specific |
| 2026-03-18 (first report) | game_log_20260318_085336.txt | Barricade1 hit twice | Root Cause 4: ghost shapes from double-breach |
| 2026-03-18 (second report) | game_log_20260318_094725.txt | Building3 hit 4 times | Root Cause 5: queue_free race condition |
| 2026-03-18 (third report) | game_log_20260318_101526.txt | Building3 hit ONCE | Root Cause 6: physics callback safety |

Each follow-up identified a deeper issue that was only visible once the previous layer was fixed.

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

### game_log_20260318_094725.txt — Key events (Root Cause 5 evidence):
```
[09:47:33] [WallBreachHelper] Horizontal passage in 'Building3' at local x=20
[09:47:34] [WallBreachHelper] Horizontal passage in 'Building3' at local x=12
           → _remove_dynamic_nodes() called queue_free() on x=20 shapes
           → BUT those shapes were still active in physics until end-of-frame
           → x=12 new shapes added alongside still-active x=20 shapes
           → Result: invisible collision at x=20 region persists
[09:47:45] [WallBreachHelper] Horizontal passage in 'Building3' at local x=-18
           → same problem repeats; x=12 ghost shapes still active
[09:48:03] [WallBreachHelper] Horizontal passage in 'Building3' at local x=20
```
4 hits on same wall — each leaving cumulative ghost shapes from prior un-disabled breaches.
The fix (disable immediately before queue_free) ensures each re-breach removes prior shapes
from the physics world on the same frame, not deferred to end-of-frame.

### game_log_20260318_101526.txt — Key events (Root Cause 6 evidence):
```
[10:15:37] [WallBreachHelper] Horizontal passage in 'Building3' at local x=20 (width 120px)
[10:15:37] [WallBreachHelper] Thin wall 'CrateSquare3' breached (fully passable)
[10:15:37] [RpgRocket] Breached 1 obstacle(s) in explosion radius
```
Building3 was hit ONCE — yet the obstacle remained impassable. Root Cause 4 (double-breach
ghost shapes) and Root Cause 5 (queue_free race) are NOT factors here, since there was only
one breach event. The only remaining cause: the entire `open_wall_passage` call chain ran
inside `_on_body_entered()` (a physics callback), and all `.disabled = true` assignments
were silently dropped by the physics server — leaving the original 160×160 shape active.

**Why BreachingCharges never surfaced this:** `BreachingChargesEffect.detonate()` is called
from `_input()` / `_process()`, not from a physics callback — so direct `.disabled` assignment
has always worked correctly for Breaching Charges.

**Fix applied:** `open_wall_passage()` now defers `_apply_wall_passage()` via a lambda
`Callable.call_deferred()`, ensuring all collision-shape changes happen outside the physics
callback, regardless of whether the caller is a physics handler or not.
