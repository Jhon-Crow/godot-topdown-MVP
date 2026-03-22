# Case Study: Game Crash on Restart at DocksLevel (Issue #1334)

## Issue Summary

The game crashes when restarting on the Docks map ("Доки"). The crash occurs
after the player dies and the scene attempts to reload via
`get_tree().reload_current_scene()`.

## Data Sources

- `game_log_20260322_164021.txt` — full game log from the session that produced
  the crash (9144 lines, 16:40:21 to 16:42:11).

## Timeline Reconstruction

| Time     | Event                                                        |
|----------|--------------------------------------------------------------|
| 16:40:21 | Game starts on LabyrinthLevel (5 enemies)                    |
| 16:40:27 | Transition to BeachLevel (8 enemies)                         |
| 16:40:42 | BeachLevel reload (restart or scene change)                  |
| 16:40:49 | BeachLevel reload                                            |
| 16:40:53 | BeachLevel reload                                            |
| 16:41:43 | Transition to DocksLevel (20 enemies) — 1st load             |
| 16:41:46 | DocksLevel reload (Q key quick restart, ~3s after load)      |
| 16:41:52 | DocksLevel reload (~6s)                                      |
| 16:41:54 | DocksLevel reload (~2s)                                      |
| 16:41:56 | DocksLevel reload (~2s)                                      |
| 16:41:58 | DocksLevel reload (~2s)                                      |
| 16:42:00 | DocksLevel reload (~2s)                                      |
| 16:42:06 | Player dies on DocksLevel (health reaches 0)                 |
| 16:42:07 | DocksLevel reload after death — **this succeeds**            |
| 16:42:10 | Player dies again on DocksLevel (health reaches 0)           |
| 16:42:11 | Log ends abruptly — **CRASH**                                |

Key observations:
- The player successfully restarted DocksLevel **7 times** before the crash.
- The first death + restart cycle (16:42:06 → 16:42:07) worked fine.
- The crash occurred on the **second death** (16:42:10), meaning the issue is
  related to accumulated state from prior restarts.

## Root Causes Identified

### Root Cause 1: Delayed blood decal coroutines survive scene reload

**File:** `scripts/autoload/impact_effects_manager.gd`, function
`_schedule_delayed_decal()` (line 685).

The `ImpactEffectsManager` is an autoload that persists across scene reloads.
When blood effects are spawned, it creates dozens of delayed coroutines using
`await get_tree().create_timer(delay).timeout`. Each blood hit spawns 15-30
delayed decals.

When `reload_current_scene()` is called:
1. The old scene is freed, but the autoload's pending coroutines survive.
2. The coroutines resume after their timers fire and attempt to:
   - Perform `PhysicsDirectSpaceState2D` raycasts against the new scene with
     old-scene coordinates.
   - Call `_add_effect_to_scene()` which does
     `get_tree().current_scene.add_child(effect)`, adding stale nodes to the
     new scene.
3. With 20 enemies in DocksLevel and active combat, there can be **hundreds**
   of pending decal coroutines at restart time.

After multiple restarts, the accumulation of stale coroutines interacting with
the new scene causes a crash.

### Root Cause 2: Navigation setup coroutine survives scene reload

**Files:** All 13 level scripts in `scripts/levels/`.

The `_setup_navigation()` function (introduced in Issue #1289) uses
`await get_tree().physics_frame` to defer navmesh baking. It is called from
`_ready()` without `await`, making it fire-and-forget. When the scene reloads
before the physics frame arrives, the old coroutine resumes and calls
`NavigationServer2D.parse_source_geometry_data(nav_poly, source_geometry, self)`
where `self` may be a freed node.

### Root Cause 3: No double-restart guard

**File:** `scripts/autoload/game_manager.gd`, function `restart_scene()`.

The Q key (quick restart) and `_on_player_died()` (death timer) can both call
`restart_scene()`. If Q is pressed during the 0.5-second death timer,
`reload_current_scene()` gets called twice, causing a crash.

### Root Cause 4: C# Player async method on freed node

**File:** `Scripts/Characters/Player.cs`, method `ShowHitFlash()`.

This `async void` method uses `await ToSignal(GetTree().CreateTimer(...))`.
If the scene reloads during the await, `GetTree()` returns null and the
continuation crashes.

## Fixes Applied

### Fix 1: Scene-change guard in `_schedule_delayed_decal()`

Captures `get_tree().current_scene` before the `await` and checks after
resumption whether the scene has changed. If it has, the coroutine aborts
without performing raycasts or adding nodes.

### Fix 2: `is_instance_valid(self)` guard in all level `_setup_navigation()`

Added immediately after `await get_tree().physics_frame` in all 13 level
scripts. If the node was freed by a scene reload, the coroutine returns early.

### Fix 3: Double-restart guard in `GameManager.restart_scene()`

Added a `_restart_in_progress` flag that prevents `reload_current_scene()`
from being called more than once per restart cycle.

### Fix 4: Null-safety in `Player.ShowHitFlash()`

Caches `GetTree()` before the await and adds `IsInstanceValid(this)` check
after the await to prevent operating on a freed C# node.

## Why DocksLevel Specifically?

While the underlying bugs exist in all levels, DocksLevel is the most
susceptible because:
1. **20 enemies** (vs 5-8 on other maps) = more blood effects per frame.
2. **Large map** (5000x4000 pixels) = more navigation complexity.
3. **Fast deaths** from sniper and multi-enemy crossfire = rapid restarts.
4. The combination produces the highest density of pending coroutines at
   restart time, making the race condition practically guaranteed.

## Evidence from Game Log: Final Crash Moment

The log ends abruptly at line 9143 (16:42:11) during heavy combat activity:

```
[16:42:11] [INFO] [ImpactEffects] Blood decals scheduled: 15 to spawn at particle landing times
[16:42:11] [INFO] [BloodDecal] Blood puddle created at (3701, 1624.604) (added to group)
[16:42:11] [ENEMY] [ContainerYardB_Machete] [#1311] Player bullet entered threat sphere — suppression triggered
```

The last entries show:
- **15 new blood decals scheduled** — each creates a delayed coroutine in
  `_schedule_delayed_decal()` that will try to resume after the scene reloads.
- **Active combat with multiple enemies** — LoadingDock_UZI, LoadingDock_Rifle1,
  LoadingDock_Rifle2, ContainerYardB_Machete all actively engaged.
- **Blood puddles being created rapidly** — at least 8 blood puddle creations in
  the final second of the log.

The crash occurred without any error message being logged, consistent with a
hard crash (segfault or null dereference in engine internals) rather than a
caught GDScript exception.

## Known Godot Engine Issues (External Research)

The root causes identified in this crash are instances of well-documented Godot
Engine architectural limitations. Coroutines in GDScript and C# are **not
lifecycle-managed** — freeing a node does not cancel its pending `await`
operations.

### Relevant Godot Issues

| Issue | Title | Relevance |
|-------|-------|-----------|
| [godot#72629](https://github.com/godotengine/godot/issues/72629) | Hanging await leaks memory, throws error (resume after free) | Core issue: freeing an object does not disconnect coroutine state. Directly explains Root Causes 1, 2, and 4. |
| [godot#100439](https://github.com/godotengine/godot/issues/100439) | Resumed function after await, but script is gone | Reports the exact error pattern from Root Cause 2 — await resumes on a freed node. |
| [godot#69227](https://github.com/godotengine/godot/issues/69227) | reload_current_scene crashes the game | Directly reports that `reload_current_scene()` crashes when timer-related async operations are pending. |
| [godot#93608](https://github.com/godotengine/godot/issues/93608) | queue_free on node with async coroutine still lets coroutine run | Explains why `queue_free()` during scene reload doesn't prevent one more coroutine execution. |
| [godot#54572](https://github.com/godotengine/godot/issues/54572) | Crash on scene exit when using await on a Timer node | Same crash pattern — `await` on Timer + scene exit = crash. |
| [godot#84860](https://github.com/godotengine/godot/issues/84860) | Memory leak when calling queue_free() before SceneTreeTimer | Timer and coroutine state not cleaned up on node free. |
| [godot#61944](https://github.com/godotengine/godot/issues/61944) | Scene crashes on reload while navigation is processing | NavigationServer crashes when scene reloads during active navigation processing. Directly relevant to Root Cause 2. |

### Godot Forum Discussions

- [Using await interferes with reload_current_scene()?](https://forum.godotengine.org/t/using-await-interferes-with-reload-current-scene/73990) —
  Community reports of crashes caused by pending `await` operations during scene
  reload.
- [get_tree().reload_current_scene() crashes game](https://forum.godotengine.org/t/get-tree-reload-current-scene-crashes-game/56999) —
  Null reference errors when async operations outlive their scene.

### Established Mitigation Patterns

The Godot community has converged on these patterns to work around the engine's
lack of coroutine lifecycle management:

1. **`is_instance_valid(self)` after every `await`** — The most common guard.
   Used in our Fix 2 and Fix 4.
2. **Scene-reference comparison** — Capture `current_scene` before `await`,
   compare after. Used in our Fix 1. Particularly important for autoloads that
   survive scene reloads.
3. **Signal disconnection in `_exit_tree()`** — Clean up server-side resources
   and disconnect signals before the node is freed.
4. **Reentrancy guards** — Prevent double-invocation of scene reload functions.
   Used in our Fix 3.

## Conclusion

This crash is a manifestation of a well-known Godot 4.x architectural
limitation: **the engine does not cancel pending coroutines when nodes are
freed or scenes are reloaded**. The fix applies the community-standard
mitigation patterns (validity checks, scene-change guards, reentrancy flags)
to all four code paths where coroutines could outlive their scene. DocksLevel
was the trigger due to its high enemy count producing the highest density of
pending coroutines at restart time, but the underlying bugs affected all 13
levels.
