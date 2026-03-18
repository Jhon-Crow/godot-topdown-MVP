# Analysis: game_log_20260317_100552.txt

## Session Context
- Date: 2026-03-17, 10:05–10:06
- Build: exported Windows (Debug: false)
- Engine: Godot 4.3-stable
- Reported by: Jhon-Crow (PR #599 comment)

## Key Observation
Line 333: `[RPG] Rocket queued launch at (198.9333, 367.8) dir=(1, 0)`

**No "Launched:" log entry appears after this.** No explosion log either.

This confirms `call_deferred("launch", dir)` scheduled the call but it was never executed.

## Root Cause: call_deferred("launch") Never Fires

`call_deferred` adds a call to Godot's `MessageQueue`. In an exported Windows build, after
`add_child(rocket)`, the deferred call is queued — but it appears the queue processes the
call on a node that may be in an unexpected state, or the method string `"launch"` is not
resolved (GDScript ScriptInstance not fully initialized when MessageQueue processes it).

The previous session (session 4, `game_log_20260317_094557`) showed `has_method("launch")`
returning false even AFTER `add_child()` in exported builds. The theory was that
`call_deferred` would bypass this by deferring until the frame settles. But this log
confirms that `call_deferred` also fails.

## Fix Applied (Session 5)

**Root cause identified**: The `launch()` method approach (whether called directly, via
`call()`, or via `call_deferred()`) is unreliable in exported Godot 4 GDScript because
the ScriptInstance may not be fully initialized when the method lookup occurs.

**Solution**: Apply the same pattern used by regular `Bullet.tscn` projectiles:
- Set `direction` as a **property** via `rocket.set("direction", dir)` BEFORE `add_child()`
- In `rpg_rocket.gd._ready()`, read `direction` to set rotation and exhaust orientation
- Remove `_launched` flag and guard from `_physics_process` — spawn_immunity_time (0.3s)
  already prevents immediate collision explosion

This mirrors exactly how `_spawn_projectile()` works for regular bullets:
```gdscript
var p := bullet_scene.instantiate()
p.global_position = pos
get_tree().current_scene.add_child(p)
if p.get("direction") != null: p.direction = dir
```

Property assignment (`set()`) works reliably regardless of ScriptInstance initialization
state because it writes to the object's property dict directly — no method lookup needed.

## Files Changed
- `scripts/projectiles/rpg_rocket.gd`: removed `_launched` flag/guard; moved rotation+exhaust init to `_ready()`
- `scripts/objects/enemy.gd` `_fire_rpg_rocket()`: set `direction` property instead of `call_deferred("launch")`
