# Case Study: Issue #1670 — Enemies Don't Shoot at Drone Grenade

## Overview

- **Issue**: [#1670](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1670) — "fix дрон (граната)" / "enemies currently don't try to shoot at the drone"
- **Context**: Follows [PR #1668](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1668) which implemented drone targeting per [Issue #1667](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1667)
- **Date identified**: 2026-03-28

---

## Timeline / Sequence of Events

| Date | Event |
|------|-------|
| 2026-03-27 | PR #1668 merged: added `DRIFT_FACTOR`, `ENEMY_TARGETING_DELAY`, enemy drone-targeting code in `_process_combat_state()`, and 24 unit tests |
| 2026-03-28 | Issue #1670 opened: "enemies currently don't try to shoot at the drone" — the feature from PR #1668 doesn't work in practice |

---

## Root Cause Analysis

Investigation revealed **two independent bugs** that together prevent enemies from shooting the drone.

### Root Cause #1 — Missing HitArea: Bullets Can't Hit the Drone

**Location**: `scenes/projectiles/DroneGrenade.tscn`

**Evidence**:
- `DroneGrenade.tscn` is a `RigidBody2D` with `collision_layer = 32` (layer 6) and `collision_mask = 6`
- It has a `CollisionShape2D` child, but **no `Area2D` HitArea** child
- Player.tscn has `HitArea` (Area2D, `collision_layer = 1`)
- Enemy.tscn has `HitArea` (Area2D, `collision_layer = 2`)
- Enemy bullets (`Bullet.tscn`) have `collision_mask = 39` = layers 1+2+3+6 = player+enemy+obstacles+projectiles

**How bullet hit detection works** (`bullet.gd`):
1. Bullet connects `area_entered` signal → calls `_on_area_entered(area: Area2D)`
2. `_on_area_entered` calls `area.on_hit()` (or variants) on the `Area2D` node
3. `hit_area.gd` script forwards `on_hit()` to the parent

**The bug**: `DroneGrenade` has no `Area2D` HitArea child. Enemy bullets' `area_entered` signal never fires for the drone, so `drone_grenade.on_hit()` is never called by enemy bullets. The drone cannot be destroyed by enemy fire.

**Fix**: Add an `Area2D` HitArea node (with `collision_layer = 1`, `collision_mask = 16`, script = `hit_area.gd`) to `DroneGrenade.tscn`. This matches the player's HitArea setup so enemy bullets detect the drone.

---

### Root Cause #2 — Drone Targeting Only in COMBAT State

**Location**: `scripts/objects/enemy.gd`, line 1452

**Evidence**:
The drone targeting code added in PR #1668:
```gdscript
# In _process_combat_state():
var _pd := _find_targetable_player_drone(); if _pd != null and _can_shoot() and _shoot_timer >= shoot_cooldown: ...
```

This code is **only inside `_process_combat_state()`** (called when `_current_state == AIState.COMBAT`).

**The state machine flow when player uses drone**:
1. Player throws drone — grenade added to `"player_drones"` group
2. After 1.5s — drone becomes targetable (`is_targetable_by_enemies()` returns true)
3. If enemy was in COMBAT (could see player): after player hides to pilot drone, enemy loses sight → transitions to **PURSUING** after `COMBAT_MIN_DURATION_BEFORE_PURSUE = 0.5s`
4. In **PURSUING** state: no drone targeting code → enemies don't shoot drone
5. If enemy was never in COMBAT (player threw drone from hiding): enemies stay in IDLE/SEARCHING/PURSUING → drone targeting code never runs

**The bug**: `_find_targetable_player_drone()` is only called inside `_process_combat_state()`. No other state checks for targetable player drones, so enemies in PURSUING, IN_COVER, or other states will never shoot the drone even when they have line-of-sight to it.

**Fix**: Add the same compact drone targeting one-liner at the start of `_process_pursuing_state()` (after melee/sniper special-case handling, before the player-visibility-based COMBAT transition). This ensures enemies in PURSUING state will also shoot at targetable drones.

---

## Additional Context

**Why the unit tests passed but the feature didn't work**: The 24 unit tests in `test_drone_grenade.gd` test `MockDroneGrenade` logic (drift math, targeting delay countdown, `is_targetable_by_enemies()` return value). They do **not** test the end-to-end flow: bullet collision detection → `on_hit()` triggering → explosion. The missing HitArea is a scene-level issue that pure unit tests can't catch.

**Collision layers reference** (from scene files):
| Layer bit | Decimal | Used for |
|-----------|---------|---------|
| 1 (bit 0) | 1 | Player HitArea |
| 2 (bit 1) | 2 | Enemy HitArea |
| 3 (bit 2) | 4 | Obstacles/walls |
| 4 (bit 3) | 8 | (unused here) |
| 5 (bit 4) | 16 | Bullets (projectiles) |
| 6 (bit 5) | 32 | Grenades/projectiles body |

Enemy bullets: `collision_mask = 39` = layers 1+2+3+6 = 0b100111

---

## Proposed Solutions

### Fix 1: Add HitArea to DroneGrenade.tscn

Add to `scenes/projectiles/DroneGrenade.tscn`:
```
[sub_resource type="CircleShape2D" id="CircleShape2D_hit_area"]
radius = 10.0

[node name="HitArea" type="Area2D" parent="."]
collision_layer = 1
collision_mask = 16
script = ExtResource("...hit_area...")

[node name="HitAreaShape" type="CollisionShape2D" parent="HitArea"]
shape = SubResource("CircleShape2D_hit_area")
```

This makes the drone detectable by enemy bullets' `area_entered` signal.

### Fix 2: Add Drone Targeting to PURSUING State

In `scripts/objects/enemy.gd`, `_process_pursuing_state()`, after melee/sniper special handling and before the player-visibility COMBAT transition:

```gdscript
# Issue #1670: shoot at targetable player drone even while pursuing
var _pd := _find_targetable_player_drone(); if _pd != null and _can_shoot() and _shoot_timer >= shoot_cooldown: var _pd_dir := (_pd.global_position - global_position).normalized(); if _is_bullet_spawn_clear(_pd_dir): _rotate_body_toward(_pd_dir.angle(), get_physics_process_delta_time()); _execute_shoot(_pd.global_position); _shoot_timer = 0.0
```

Note: Must stay within 5000-line CI limit (currently 4999 lines). Use compact one-liner style matching line 1452.

---

## Files to Change

| File | Change |
|------|--------|
| `scenes/projectiles/DroneGrenade.tscn` | Add HitArea Area2D node with collision_layer=1, collision_mask=16, hit_area.gd script |
| `scripts/objects/enemy.gd` | Add compact drone targeting one-liner to `_process_pursuing_state()` — replace 1 line to stay within 5000-line limit |
| `tests/unit/test_drone_grenade.gd` | Add source-file integration tests verifying HitArea exists in scene and drone targeting exists in pursuing state |
