# Game Log Analysis: game_log_20260318_032745.txt

## Session Info
- Date: 2026-03-18 03:27:45
- Build: Godot 4.3-stable, Windows export (non-debug)
- User report: "ракета не взрывается, а просто исчезает при столкновении" (rocket doesn't explode, just disappears on collision)

## Key Evidence

### Rocket launches found (5 total):
```
[03:28:08] [ExperimentalMenu] Enemy spawner: spawned 'RPG + PM pistol' at (350, 360)
[03:28:09] [ENEMY] [Enemy] [RPG] Rocket launched at (280.329, 367.5201) dir=(-1, 0)
[03:28:15] [ENEMY] [Enemy] [RPG] Rocket launched at (280.329, 367.5201) dir=(-1, 0)
[03:28:22] [ENEMY] [Enemy] [RPG] Rocket launched at (280.329, 367.5201) dir=(-1, 0)
[03:28:29] [ENEMY] [Enemy] [RPG] Rocket launched at (464.638, 351.7045) dir=(0.65103, -0.759052)
[03:28:34] [ENEMY] [Enemy] [RPG] Rocket launched at (281.3701, 344.7567) dir=(-0.947731, -0.31907)
```

### RpgRocket entries: **ZERO**
`grep "[RpgRocket]"` returns 0 results. This means:
- `bullet.gd`'s `_ready()` RPG initialization block never ran
- `is_rpg_rocket` was `false` at runtime despite being `true` in `RpgRocket.tscn`

## Root Cause

`is_rpg_rocket` and all RPG variables in `bullet.gd` are declared as plain `var` (not `@export`):

```gdscript
var is_rpg_rocket: bool = false   # NO @export
var rpg_speed_initial: float = 600.0
...
```

In Godot 4, `.tscn` scene file property assignments ONLY work for `@export` variables. The `RpgRocket.tscn` line `is_rpg_rocket = true` is silently ignored because the property has no `@export` annotation. At runtime, `is_rpg_rocket = false`, so the rocket runs as a plain bullet:

1. No `[RpgRocket] Spawned:` in `_ready()` — RPG init block skipped
2. No raycast hit detection in `_physics_process()` — RPG raycast block skipped  
3. `_on_body_entered()` falls through to normal bullet logic (ricochet/penetrate/destroy)
4. Rocket "disappears" = `_destroy()` called via normal bullet wall-hit path with no explosion

## Fix

Added `@export` to all RPG variables in `bullet.gd`:

```gdscript
@export var is_rpg_rocket: bool = false
@export var rpg_speed_initial: float = 600.0
@export var rpg_speed_max: float = 1800.0
@export var rpg_accel_distance: float = 800.0
@export var rpg_explosion_radius: float = 150.0
@export var rpg_explosion_damage: int = 3
@export var rpg_spawn_immunity: float = 0.15
```

Now `RpgRocket.tscn` can properly configure these values, `is_rpg_rocket` will be `true` at runtime, and the full explosion pipeline will execute:

1. `_ready()`: initializes `_rpg_current_speed`, logs `[RpgRocket] Spawned:`
2. `_physics_process()`: raycast-based hit detection active
3. `_on_body_entered()`: calls `_rpg_explode()` on wall/body hit
4. `_rpg_explode()`: `ImpactEffectsManager.spawn_explosion_effect()` + sound + AoE damage

## Godot 4 Lesson: @export is Required for Scene Serialization

| Declaration | Set from `.tscn`? | Visible in editor? |
|-------------|-------------------|--------------------|
| `@export var foo: bool` | ✅ Yes | ✅ Yes |
| `var foo: bool` | ❌ No (silently ignored) | ❌ No |

This is different from Godot 3 where non-exported properties could sometimes be set from scene files.
