# Case Study: Game Crash on Restart at DocksLevel (Issue #1334)

## Issue Summary

The game crashes when restarting on the Docks map ("Доки"). The crash occurs
after the player dies and the scene attempts to reload via
`get_tree().reload_current_scene()`.

## Data Sources

- `game_log_20260322_164021.txt` — full game log from the initial crash report
  (9144 lines, 16:40:21 to 16:42:11).
- `game_log_20260322_173332.txt` — crash log after first fix attempt (4945 lines,
  17:33:32 to 17:34:51). Crash during death sequence with 908 blood decals.
- `game_log_20260322_173505.txt` — crash log after first fix attempt (3925 lines,
  17:35:05 to 17:35:46). Crash during normal gameplay with 500 blood decals.

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

## Second Crash Report (After Initial Fix)

After the initial fixes (scene-change guards, validity checks, double-restart
guard), the user reported the crash still occurs. Two new logs were provided.

### New Log Analysis

**Log `game_log_20260322_173332.txt` (4945 lines):**
- Crash during the LastChance death sequence (freeze + visual effects)
- **908 blood decals** created before crash
- FPS progressively dropping: 26 → 15 → 7 → 12 fps at crash
- Last lines: blood puddle creation + FPS drop warning
- **No restart was attempted** — crash happened during death, not reload

**Log `game_log_20260322_173505.txt` (3925 lines):**
- Crash during normal gameplay (active combat, no death/restart)
- **500 blood decals** created before crash
- Last line: "Blood puddle created at (3196.918, 415.5444)"
- **No restart, no death** — crash happened during normal play

### Root Cause 5: Per-puddle Area2D physics overload (PRIMARY CRASH CAUSE)

**File:** `scripts/effects/blood_decal.gd`, function `_setup_puddle_area()`.

Each blood decal creates 3 physics nodes:
- 1 `Sprite2D` (the visual decal)
- 1 `Area2D` (for bloody footprint collision detection, layer 7)
- 1 `CollisionShape2D` with `CircleShape2D` (physics shape)

With `MAX_BLOOD_DECALS = 0` (unlimited), these accumulate indefinitely:

| Log | Blood Decals | Area2D Nodes | CollisionShape2D Nodes | Total Physics Objects |
|-----|-------------|-------------|----------------------|---------------------|
| Log 1 | 908 | 908 | 908 | 1,816 |
| Log 2 | 500 | 500 | 500 | 1,000 |

Additionally, 20 enemies each have `BloodyFeetComponent` with a `BloodDetector`
Area2D (collision mask = layer 7). The physics broadphase must evaluate:
- 20 detectors × N puddle Area2D = O(20N) collision pair checks per physics frame
- At 908 puddles: 20 × 908 = **18,160 broadphase pair evaluations per frame**

The `_on_area_exited` handler in `BloodyFeetComponent` (line 314) also calls
`get_overlapping_areas()` which iterates all overlapping areas — O(N) per exit
event, further amplifying the physics load.

This matches the evidence perfectly:
- **Hard crash (segfault)** — no GDScript error, log just stops
- **Progressive FPS degradation** — 26 → 15 → 7 fps as decals accumulate
- **Crash during normal gameplay** (log 2) — NOT related to scene reload at all
- **Crash at blood decal creation** — both logs end during blood puddle creation

Note: A previous fix for the same issue exists in an unmerged branch (commit
`faac32b9` from issue #1027) which identified this exact problem:
> "RCA-28: BloodDecal created Area2D + CircleShape2D per puddle, causing
> 21 detectors × 90 puddles = 1890 physics broadphase pairs/frame at 60fps
> → 6fps drops during heavy combat"

The comment in `impact_effects_manager.gd` line 51 incorrectly states
"Issue #1027 removed per-puddle Area2D physics" — that fix was never merged
to `main`.

### Fix 5: Remove per-puddle Area2D from blood_decal.gd

Removed `_setup_puddle_area()` entirely from `blood_decal.gd`. Blood decals
remain in the `"blood_puddle"` group for detection by `BloodyFeetComponent`,
which has a distance-based fallback (`_check_blood_puddle_by_distance()`) that
works without per-decal Area2D. The fallback check interval was reduced from
30 to 10 frames to compensate for loss of signal-based detection.

## Conclusion

This crash has **two independent causes** that both manifest on DocksLevel:

1. **Coroutine-after-reload crashes** (Root Causes 1-4): Fixed in the initial
   commit with scene-change guards, validity checks, and reentrancy flags.

2. **Physics broadphase overload** (Root Cause 5): Each blood decal creates
   Area2D + CollisionShape2D physics nodes. With unlimited decals and 20
   enemies, the physics server accumulates thousands of broadphase pairs and
   crashes with a segfault. Fixed by removing per-puddle Area2D — decals are
   now pure Sprite2D nodes with no physics overhead. Bloody footprint detection
   uses distance-based group queries instead.

DocksLevel triggers both issues due to its 20 enemies producing the highest
blood decal density and coroutine count of any map.
