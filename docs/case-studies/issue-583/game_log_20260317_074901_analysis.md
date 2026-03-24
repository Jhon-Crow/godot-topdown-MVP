# Analysis: game_log_20260317_074901.txt

## Key Finding

**Line 490:**
```
[RpgEnemy1] [RPG] ERROR: bullet_scene is not an RpgRocket!
```

## Root Cause

The `as RpgRocket` cast in `_fire_rpg_rocket()` fails in Godot 4 **exported (non-debug)** builds.

In exported builds, GDScript `class_name` registrations may not be available at runtime when the script is loaded via `load()` from a string path. The `as ClassName` syntax relies on the class being registered in the class database, which is unreliable for dynamically loaded scripts in export builds.

As a result, `bullet_scene.instantiate() as RpgRocket` returns `null` even when the scene is correctly referencing `rpg_rocket.gd`, causing the early return and no rocket spawn.

## Fix Applied

Replaced `as RpgRocket` cast with:
1. `as Node2D` cast (always works for Area2D nodes)
2. `has_method("launch")` check to verify the rocket is the right type
3. `rocket.call("launch", dir)` instead of direct method call (export-safe)
4. `rocket.set(...)` instead of direct property assignment (export-safe)

This pattern is reliable in both debug and exported Godot 4 builds.

## Evidence

- RpgEnemy1 and RpgEnemy2 both spawn correctly (lines 427, 431)
- RPG shot sound fires correctly (line 491: `range=2500` = RPG weapon_loudness)
- But no rocket spawns due to the cast failure
- After weapon switch: PM shots fire with `range=1469` (line 522) — weapon switch logic works fine
