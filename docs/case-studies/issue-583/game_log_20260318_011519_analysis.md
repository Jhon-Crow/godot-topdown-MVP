# Game Log Analysis: game_log_20260318_011519.txt

**Date:** 2026-03-18
**Issue:** Rocket spawns but does not fly or explode (Area2D + custom rpg_rocket.gd)

## Key Evidence

```
[01:15:43] [RPG] Rocket launched at (289.5456, 363.1273) dir=(-1, 0)
```

**No `[RpgRocket] Spawned:` log follows.**

This proves:
- `_fire_rpg_rocket()` calls `add_child(rocket)` successfully (enemy-side log appears)
- `_ready()` in `rpg_rocket.gd` **never executes** in the exported Windows build
- The rocket node enters the scene tree but its GDScript is not initialized

## Root Cause

`rpg_rocket.gd` has `class_name RpgRocket` and extends `Area2D`. In Godot 4 exported builds,
GDScript class instances dynamically created via `PackedScene.instantiate()` may fail to initialize
their script (known issue with `class_name` registration in export builds). The `_ready()` callback
is never called, so `_current_speed` stays 0, `body_entered` is never connected → rocket is static.

This was confirmed across **15+ debugging sessions** from 2026-02-08 to 2026-03-17, trying:
- `as RpgRocket` cast → `null` in exports
- `has_method("launch")` → false before/after add_child
- `call_deferred("launch")` → never executes
- Direction as property before/after add_child
- RigidBody2D + linear_velocity (flew once as "plastic bottle", but no explosion)
- Area2D + _physics_process (moved in editor, not in export)

## Solution

**Rewrite RpgRocket to use `bullet.gd` directly** — the script that powers every working projectile.

Added to `bullet.gd`:
- `is_rpg_rocket: bool` flag
- RPG acceleration properties (`rpg_speed_initial`, `rpg_speed_max`, `rpg_accel_distance`)
- `_rpg_explode()` — explosion on impact with AoE damage, effects, sound
- Hooks in `_on_body_entered` and `_on_area_entered` to trigger `_rpg_explode()`
- RPG acceleration curve in `_physics_process`

Updated `RpgRocket.tscn`:
- Changed script from `rpg_rocket.gd` → `bullet.gd`
- Set `is_rpg_rocket = true`, `speed = 300.0`, RPG explosion properties

Updated `enemy.gd` `_fire_rpg_rocket()`:
- Spawns rocket, calls `add_child()`, then sets `direction`/`shooter_id`/`shooter_position`
- **Direction set AFTER add_child** — identical to `_spawn_projectile()` pattern used by all bullets

This is **the same code path** as every working bullet. No custom class_name, no launch() method,
no RigidBody2D physics quirks — just bullet.gd doing what it always does.
