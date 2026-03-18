# Analysis: game_log_20260317_081404.txt

## Summary

All RPG firing attempts result in: `[RPG] ERROR: rocket has no launch() method!`

This means `_fire_rpg_rocket` **is** being called, `bullet_scene.instantiate()` **succeeds** (returns a Node2D),
but `has_method("launch")` returns `false`.

## Root Cause

`has_method("launch")` fails because `bullet_scene` is pointing to **`Bullet.tscn`**, not `RpgRocket.tscn`.

The sequence:
1. `_ready()` sets `bullet_scene = preload("res://scenes/projectiles/Bullet.tscn")` (fallback).
2. `_apply_weapon_config()` calls `load("res://scenes/projectiles/RpgRocket.tscn")`.
3. In the **exported build**, `load()` returns `null` if the path isn't explicitly included in export config,
   so `bullet_scene` stays as `Bullet.tscn`.
4. `Bullet.tscn` instances don't have a `launch()` method → error.

## Fix Applied (commit after this log)

In `_fire_rpg_rocket()`, replaced:
```gdscript
var rocket: Node2D = bullet_scene.instantiate() as Node2D
```
with:
```gdscript
var rpg_scene: PackedScene = preload("res://scenes/projectiles/RpgRocket.tscn")
var rocket: Node2D = rpg_scene.instantiate() as Node2D
```

`preload()` is resolved at **compile time** and is guaranteed to be included in the export.
`load()` is resolved at runtime and can silently fail in exports.

## Evidence

- Lines 763, 797, 1083, 1645, 2903, 3257, 3856, 4493, 5859, 6030, 7091, 7362, 7806, 8072, 8920, 9029, 10147, 10994:
  `[RPG] ERROR: rocket has no launch() method!`
- No "bullet_scene is null" error → `bullet_scene` is non-null (it's `Bullet.tscn`)
- No "[RPG] Rocket spawned at..." messages → no successful rocket spawns in this session
