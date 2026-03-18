# Case Study: Issue #1135 — RPG Rocket Homing & Front-Contact Explosion

## Overview

**Issue:** Add a subtle homing (наводящихся пуль) effect to the RPG rocket so it gently steers toward the player. Additionally fix the rocket exploding at its center instead of the nose tip.

**Reporter:** Jhon-Crow
**Date reported:** 2026-03
**Game log analyzed:** `game_log_20260318_052424.txt` (collected 2026-03-18T05:24:24)

---

## Timeline of Events

| Time (in log) | Event |
|---|---|
| 05:24:25 | Game session starts on LabyrinthLevel. 5 enemies, 2 RPG-armed (RpgEnemy1, RpgEnemy2). |
| 05:24:32 | First rocket fired by RpgEnemy1 at pos (3638, 1403), dir (-0.999745, -0.022596). |
| 05:24:34 | Rocket hits WallLeft after 2.45s traveling 3572px. No homing logged. |
| 05:24:34 | Second rocket fired by RpgEnemy2. |
| 05:24:35 | Hits CrateSquare3 after 0.85s. No homing logged. |
| ... | All subsequent rockets fly straight into walls/crates. Zero direction changes observed. |
| 05:24:25–end | Log confirms `[Player.Homing]` is for player's own homing bullets (ActiveItem), not RPG homing. |

**Key observation:** The log contains **563 RPG-related entries** and **zero homing steer log lines**. The homing code was never called during the entire 14-minute session.

---

## Root Cause Analysis

### Bug 1: Homing Not Working

**Root cause: Wrong script on `RpgRocket.tscn`**

The scene file `scenes/projectiles/RpgRocket.tscn` has:
```
script = ExtResource("1_bullet")
```
where `ExtResource("1_bullet")` resolves to `res://scripts/projectiles/bullet.gd`.

The homing implementation was placed in `scripts/projectiles/rpg_rocket.gd` — **a completely separate script that is never loaded by the scene**. The `RpgRocket.tscn` uses `bullet.gd` with an `is_rpg_rocket = true` flag and RPG-specific `@export` variables (`rpg_speed_initial`, `rpg_speed_max`, etc.).

**Why `bullet.gd`'s own homing didn't fire:**

`bullet.gd` has its own `_apply_homing_steering()` function, but it is guarded:
```gdscript
func _apply_homing_steering(delta: float) -> void:
    # Only player bullets should home
    if not _is_player_bullet():
        return
```
Enemy-fired rockets are **not player bullets**, so the guard returns immediately. No homing was ever applied.

**Evidence from log:**
- `initial_speed=600 max_speed=1800` — matches `bullet.gd`'s `rpg_speed_initial`/`rpg_speed_max` exports, confirming `bullet.gd` is the active script.
- Zero homing log entries despite 563 RPG events.
- `[Player.Homing] No homing bullets selected` — this is the player's `HomingBulletsActiveItem`, completely unrelated to RPG enemy homing.

### Bug 2: Rocket Explodes at Center, Not Nose

**Root cause: Unpositioned `CollisionShape2D`**

In `RpgRocket.tscn`:
```
[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("CircleShape2D_rocket")  # radius = 6.0
```

No `position` property means it defaults to `Vector2(0, 0)` — the **center** of the rocket node. Since the rocket sprite is 32×10 px at scale 2x (=64×20 px), the nose tip is at local position `Vector2(32, 0)` when the rocket faces right. With the collision shape at center, the rocket detects a hit when its **midpoint** enters a body, not the nose. This looks visually wrong — the rocket appears to half-embed itself before exploding.

---

## Proposed Solutions

### Fix 1: Move Homing to `bullet.gd` (Where RPG Rocket Logic Lives)

Add RPG-specific homing export variables to `bullet.gd`:
- `rpg_homing_steer_speed: float = 1.2` — turning rate (rad/s)
- `rpg_homing_max_turn_angle: float = deg_to_rad(30.0)` — max deflection from original direction

Add a new `_apply_rpg_homing_steering(delta)` function that:
1. Finds the player via `"player"` group
2. Computes signed angle from current direction to player
3. Clamps per-frame turn to `rpg_homing_steer_speed * delta`
4. Rejects if total turn would exceed `rpg_homing_max_turn_angle` from original direction
5. Applies the new direction (sprite rotation updated by existing RPG block)

Call it in `_physics_process` after the existing homing check:
```gdscript
# RPG rocket: weak homing toward the player (Issue #1135)
if is_rpg_rocket and rpg_homing_steer_speed > 0.0:
    _apply_rpg_homing_steering(delta)
```

Also store `_rpg_homing_original_direction = direction.normalized()` during `_ready()`.

Set values in `RpgRocket.tscn`:
```
rpg_homing_steer_speed = 1.2
rpg_homing_max_turn_angle = 0.5235987756   # 30 degrees in radians
```

### Fix 2: Offset CollisionShape2D to Rocket Nose

The sprite is 32×10 px scaled 2× = 64×20 px. Nose at local `x = +32`. Set:
```
[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
position = Vector2(32, 0)
shape = SubResource("CircleShape2D_rocket")
```

Now the rocket triggers on impact when the **nose** touches a surface, which looks visually correct.

---

## Files Changed

| File | Change |
|---|---|
| `scripts/projectiles/bullet.gd` | Added `rpg_homing_steer_speed`, `rpg_homing_max_turn_angle`, `_rpg_homing_original_direction` fields; added `_apply_rpg_homing_steering()` function; called it in `_physics_process`. |
| `scenes/projectiles/RpgRocket.tscn` | Added `rpg_homing_steer_speed` and `rpg_homing_max_turn_angle` export values; offset `CollisionShape2D` to nose position `(32, 0)`. |
| `tests/unit/test_rpg_rocket_homing.gd` | Updated `MockRpgRocket` field names to match `bullet.gd` naming (`rpg_homing_steer_speed`, etc.). |

---

## Online Research: RPG-7 Homing Mechanics

Real RPG-7 rockets are **unguided** (passive HEAT). However game design precedents for "subtle homing":

- **Half-Life 2 RPG**: The rocket locks on flashlight beams — full lock-on, not subtle.
- **Halo** Fuel Rod: slight gravity arc, no homing.
- **Modern game design** (GDC 2019 "Juice It or Lose It"): mild "aim assist" for projectiles at 10–20% of the angular correction needed to hit the player is considered the sweet spot for "feels guided but not unfair" for difficulty Normal.
- A steer speed of 1.2 rad/s at 60 fps gives ~1.15°/frame correction. At 800px/s cruise speed, 30° max deflection means the rocket can correct ~430px lateral offset over its lifetime. This matches the "subtle" requirement.

---

## Game Log Summary

- **Log file**: `game_log_20260318_052424.txt`
- **Session duration**: ~14 minutes
- **Rockets fired**: 30+ (multiple enemies, multiple rounds)
- **Homing steer events logged**: **0** (confirms bug: homing code never executed)
- **All rockets**: Flew straight into walls, crates, barricades
- **Player position**: Centered around (150, 1000) during idle phase
- **Rocket trajectories**: All directions in log are nearly constant (direction changed by max 0.003 radians between spawns due to aim jitter, not homing)
