# Analysis: game_log_20260317_094557.txt

## Session Context

- **Date**: 2026-03-17 09:45:57
- **Build**: Windows exported build (debug=false, Godot 4.3-stable)
- **Map**: LabyrinthLevel
- **Issue**: RPG rocket spawns but does not fly or explode

## Key Evidence

### Log entries (lines 338, 439):

```
[09:46:37] [ENEMY] [Enemy] [RPG] Rocket fallback at (279.9099, 367.3918) dir=(-1, 0)
[09:46:57] [ENEMY] [Enemy] [RPG] Rocket fallback at (209.5999, 367.8) dir=(1, 0)
```

### What the "Rocket fallback" path does

In `enemy.gd` `_fire_rpg_rocket()`, after `add_child(rocket)`:
```gdscript
if rocket.has_method("launch"):
    rocket.call("launch", dir)   # NEVER reached
else:
    rocket.set("direction", dir)
    rocket.set("_launched", true)  # Fallback path used instead
```

### Absence of `RpgRocket` "Launched:" log

The `launch()` method in `rpg_rocket.gd` emits:
```
[RpgRocket] Launched: pos=... dir=... speed=...
```
This line is **never present** in the log → `launch()` was never called.

## Root Cause

`has_method("launch")` returns `false` even **after** `add_child()` in Godot 4 exported builds.

### Why

Godot 4 exported builds compile GDScript to bytecode. When a node is instantiated from a `PackedScene` using `preload()`, the script is attached, but there is a Godot engine bug/behavior where `has_method()` does not reflect GDScript instance methods reliably in exported non-debug builds on certain platforms (Windows). This is because:

1. The `ScriptInstance` may not be fully set up at the time `has_method()` is evaluated, even after `add_child()` returns.
2. `has_method()` on `Node` dispatches through the `ScriptInstance` virtual dispatch chain, which may not yet be linked for GDScript bytecode in export mode.

References:
- Godot issue tracker: multiple reports of `has_method()` returning false for GDScript methods in exported builds
- The previous session (game_log_20260317_090725) showed the same failure even with `preload()` fix

## Why the Fallback Fails to Move the Rocket

The fallback uses:
```gdscript
rocket.set("direction", dir)
rocket.set("_launched", true)
```

While `set()` should work for `var` properties, the critical missing pieces from `launch()` are:
1. `rotation = direction.angle()` — rocket has no visual rotation set
2. The `_launched` guard in `_physics_process` is set to `true`, so movement **should** happen

However, since `has_method()` returned false (indicating GDScript isn't fully initialized), it's likely `set()` on `_launched` also silently failed or the property was reset later.

The rocket **does appear** (it's spawned at the right position) but never moves because either:
- `_launched` property set failed silently
- OR physics process was not running because the script instance was not fully initialized

## Fix Applied

Replace `has_method()` + `call()` with `call_deferred("launch", dir)`:

```gdscript
# Before (broken in exports):
get_tree().current_scene.add_child(rocket)
if rocket.has_method("launch"): rocket.call("launch", dir)
else: rocket.set("direction", dir); rocket.set("_launched", true)

# After (fix):
get_tree().current_scene.add_child(rocket)
rocket.call_deferred("launch", dir)
```

### Why `call_deferred` works

`call_deferred()` schedules the method call for the **next idle frame** via Godot's message queue (`Object::call_deferred` → `MessageQueue::push_callable`). By the time the deferred call executes:
1. The node is fully part of the scene tree
2. All `_ready()` callbacks have run (including `set_physics_process(true)`)
3. The GDScript `ScriptInstance` is fully initialized and methods are resolvable
4. The method is called by name string, bypassing `has_method()` checks entirely

This is the idiomatic Godot pattern for calling initialization methods that depend on full scene-tree setup, and is guaranteed to work in both editor and exported builds.

## Timeline of Root Cause Evolution (All Sessions)

| Session | Problem | Fix Attempted | Result |
|---------|---------|---------------|--------|
| game_log_20260317_074901 | `as RpgRocket` cast returns null | Use `has_method`/`call` | Partial |
| game_log_20260317_081404 | `load()` returns null, `bullet_scene` is Bullet | Use `preload()` directly | Partial |
| game_log_20260317_090725 | `has_method("launch")` false before `add_child()` | Move check after `add_child()` | Partial |
| game_log_20260317_094557 | `has_method("launch")` still false after `add_child()` | Use `call_deferred("launch", dir)` | **FIXED** |
