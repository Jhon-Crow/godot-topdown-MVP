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

---

## Root Cause Analysis

### Root Cause 1: Impact Position Inaccuracy

`_rpg_explode()` calls `WallBreachHelper.open_wall_passage(_rpg_hit_wall, global_position)`
where `global_position` is the rocket's **current center position** at explosion time.

The **Breaching Charges** implementation (breaching_charges_effect.gd) uses the precise
**wall surface hit point** obtained from a raycast intersection (`result["position"]`).
This is more accurate than using the rocket center because:
- The rocket's `CollisionShape2D` is offset 32px to the nose tip (since Issue #1135)
- When `body_entered` fires, the rocket Area2D may already be overlapping the wall by
  several pixels, so `global_position` is inside the wall, not on its surface
- For wide walls (> 120px), this shifts the breach center away from the actual impact point

The existing raycast (`_rpg_prev_position` → `global_position`) already computes
`result.position` (exact wall surface point) but discards it, using `global_position`
instead.

### Root Cause 2: Explosion Radius Obstacles Not Breached

`_rpg_damage_in_radius()` damages enemies within `rpg_explosion_radius` (150px) but does
**NOT** destroy/breach `StaticBody2D` obstacles in that radius.

For destructible obstacles (crates 80×80, barrels 48×48, tables 120×48) near the impact
point but not directly hit by the rocket body, `WallBreachHelper` is never called. The
explosion visual effect (orange flash) runs over them but doesn't remove their collision.

### Root Cause 3: `_split_visual_*` Functions Miss LightOccluder2D

`_split_visual_horizontal()` and `_split_visual_vertical()` in `WallBreachHelper` only
hide `ColorRect` and `Sprite2D` children. `LightOccluder2D` children are not hidden,
leaving a shadow cast by the "removed" wall — creating a visual artifact (dark shadow
strip with no visible wall body).

**Note**: This root cause is secondary and contributes to visual confusion rather than
the primary "invisible walls" issue.

---

## Affected Code

### Primary: `scripts/projectiles/bullet.gd`

- Lines 398–401: Raycast path — stores `_rpg_hit_wall` but discards `result.position`
- Lines 479–481: `body_entered` path — stores `_rpg_hit_wall`, no surface hit position
- Lines 1960–1965: `_rpg_explode()` — uses `global_position` instead of surface hit point
- Lines 2007–2017: `_rpg_damage_in_radius()` — only processes enemies, not obstacles

### Secondary: `scripts/effects/wall_breach_helper.gd`

- Lines 167–195: `_split_visual_horizontal()` — doesn't hide `LightOccluder2D`
- Lines 199–227: `_split_visual_vertical()` — doesn't hide `LightOccluder2D`

---

## How Breaching Charges Handles This Correctly

`scripts/effects/breaching_charges_effect.gd`:

```gdscript
# Gets EXACT wall surface hit position from raycast:
result["position"]  # ← precise surface point

# Uses it when calling WallBreachHelper:
WallBreachHelper.open_wall_passage(wall, result["position"])  # ← exact hit point
```

The Breaching Charges implementation:
1. Uses `intersect_ray()` to find walls and get surface hit positions
2. Passes the exact hit position to `WallBreachHelper.open_wall_passage`
3. This gives correct breach centering regardless of the charge position

---

## Fix

### Fix 1: Use Raycast Hit Position in `_rpg_explode()`

Store `_rpg_hit_position` (Vector2) alongside `_rpg_hit_wall`. Populate it from:
1. `result.position` in the raycast path (exact surface hit)
2. A backward raycast from `global_position` in the `body_entered` path

Use `_rpg_hit_position` instead of `global_position` in `WallBreachHelper.open_wall_passage`.

### Fix 2: Breach Obstacles in Explosion Radius

In `_rpg_explode()`, after the direct wall passage, also process all `StaticBody2D`
obstacles within `rpg_explosion_radius` of the explosion, calling
`WallBreachHelper.open_wall_passage` for each.

### Fix 3 (Secondary): Hide LightOccluder2D in `_split_visual_*`

Add `LightOccluder2D` handling to `_split_visual_horizontal()` and `_split_visual_vertical()`
to disable shadow casting in the passage gap.

---

## Impact Assessment

- **Primary fix** (hit position accuracy): Low risk. Only changes which position is passed
  to `WallBreachHelper`, making it more accurate. No behavioral change for direct center hits.
- **Secondary fix** (explosion radius obstacles): Medium risk. Adds new logic to destroy
  nearby obstacles. Could affect level balance (more walls destroyed than expected).
- **Visual fix** (LightOccluder2D): Low risk. Purely cosmetic improvement.

---

## Test Plan

1. Unit test: `_rpg_hit_position` is set to raycast hit point (not rocket position)
2. Integration test (manual): RPG rocket hitting a StaticBody2D wall leaves walkable gap
3. Integration test (manual): RPG rocket exploding near obstacles destroys their collision
4. Regression test: RPG rocket still explodes on enemy hits (no wall passage for enemies)
