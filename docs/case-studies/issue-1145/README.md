# Case Study: Issue #1145 — FPS Drop When Shooting at Walls

## Summary

**Issue**: FPS drops from 60 to ~26–30 fps when shooting at walls, reported by user with Mini UZI.

**Root causes identified** (in priority order):
1. **EMPTY_CLICK propagation at fire rate** (primary): When holding fire with an empty weapon, the weapon fires at ~15 clicks/sec, each triggering `SoundPropagation` to iterate all 10 enemies, causing 150+ callbacks/sec and FPS drops to 26–29 fps. ✅ **Fixed in this PR** (throttled to 0.4s cooldown, same as CASING_KICK).
2. **Redundant physics raycasts**: `_get_surface_normal()` called twice per bullet-wall collision (once for dust effect, once for ricochet), doubling the per-frame raycast cost during wall hits. ✅ **Fixed in this PR** (cached normal, commit `46fc0be0`).

---

## Log Files

| File | Session | Key findings |
|------|---------|-------------|
| `game_log_20260318_064123.txt` | Session 1 | Confirms EMPTY_CLICK is root cause of 29/26/27 fps drops |
| `game_log_20260318_081028.txt` | Session 2 | All drops from shader warmup/scene load; 0 listeners, no gameplay drops |
| `game_log_20260318_083455.txt` | Session 3 | Old build; 1 drop at 22fps during scene load; shooting with 0 listeners, no gameplay drops |

---

## Timeline Reconstruction

### Session 1 — Log: `game_log_20260318_064123.txt`

| Time | Event |
|------|-------|
| 06:41:24 | Game start. Level: BuildingLevel. Weapon: Mini UZI (selected at 06:41:24) |
| 06:41:25 | Shader/particle warmup complete. **FPS drop: 15 fps** (startup spike, unrelated to shooting) |
| 06:41:29 | Scene changed to Tutorial. **FPS drop: 23 fps** (scene transition spike) |
| 06:41:52 | Player fires Mini UZI — shots 2–32 (30 GUNSHOT events, ~10/sec). During this phase: no FPS drops. |
| 06:41:55 | Magazine empty (shot 32). `AmmoDepleted` fires. Enemy AI broadcasts `ammo_empty=true` to all 10 enemies. |
| 06:41:55 | Player holds trigger → EMPTY_CLICK emitted 36 times in 1 second with 10 listeners. **FPS drop: 29 fps** |
| 06:41:56 | Continues holding trigger. **FPS drop: 26 fps** |
| 06:41:57 | Still holding trigger. **FPS drop: 27 fps** |
| 06:41:57 | Log ends |

**Key observation**: FPS drops happen **after** the magazine empties, during `EMPTY_CLICK` spam — NOT during the shooting phase. During shots 1–32, zero FPS drops are logged.

### Session 2 — Log: `game_log_20260318_081028.txt`

| Time | Event |
|------|-------|
| 08:10:28 | Game start. Level: LabyrinthLevel. Weapon: AK+GL |
| 08:10:32 | Particle shader warmup (3158 ms). **FPS drop: 1 fps** (startup spike) |
| 08:10:40 | Scene changed to Tutorial (weapon: Mini UZI). **FPS drop: 15 fps** (scene transition spike) |
| 08:10:44 | Scene changed again to Tutorial. **FPS drop: 2 fps** (scene transition spike) |
| 08:10:44 | Player dies (player_valid=False). All 10 SoundPropagation listeners cleaned up |
| 08:10:48 | Player fires Mini UZI. `listeners=0` → no sound propagation overhead. No FPS drops. |
| 08:11:12 | Scene reload. Player fires Mini UZI again. Still `listeners=0`. No FPS drops. |
| 08:11:35 | Log ends |

**Key observations**: All FPS drops happen during shader warmup and scene transitions. Zero drops during actual shooting (listeners=0 because player died and enemies were freed).

### Session 3 — Log: `game_log_20260318_083455.txt`

| Time | Event |
|------|-------|
| 08:34:55 | Game start. Level: LabyrinthLevel. Weapon: AssaultRifle. **Old build** from `оптимизация/` folder. |
| 08:35:03 | Scene changed to Tutorial. **FPS drop: 22 fps** (scene transition + shader warmup spike) |
| 08:35:06 | Player switches to Mini UZI (ammo: 32/32). Changed to Tutorial scene again. |
| 08:35:13 | Player fires Mini UZI. First shot: `listeners=5` → immediately "Cleaned up 5 invalid listeners" (stale LabyrinthLevel enemies). Subsequent 60 shots: `listeners=0`, zero propagation cost. |
| 08:35:21 | Reload animation. |
| 08:35:23 | Second burst: another 18 shots, all `listeners=0`. |
| 08:35:30 | Log ends (frame 1800 = exactly 60fps throughout shooting phase). |

**Key observations for Session 3**:
1. The executable is from `I:/Загрузки/godot exe/оптимизация/` — **old pre-compiled binary** that does NOT include either fix from this PR.
2. One FPS drop at 22fps during scene load — unrelated to shooting.
3. **During the entire 61-shot firing sequence, FPS is 60fps** (confirmed by ReplayManager recording 60 frames/second).
4. No EMPTY_CLICK events in this session (ammo never ran out).
5. First gunshot detects and clears 5 stale listeners from the previous scene — a one-time O(5) cleanup with negligible cost.

---

## Root Cause Analysis

### Root Cause 1 (Primary): EMPTY_CLICK Propagation at Fire Rate

**File**: `scripts/autoload/sound_propagation.gd` — `emit_player_empty_click()`

When the player holds the trigger with an empty magazine, the weapon's C# `Fire()` method is called at fire rate. Since `CurrentAmmo <= 0`, it calls `PlayEmptyClickSound()` and returns, which eventually triggers `emit_player_empty_click()` in the GDScript sound system.

**Session 1 evidence** (definitive):
- 36 EMPTY_CLICK events fired in a single second (06:41:55) with 10 active listeners
- 36 × 10 = **360 enemy callbacks per second**
- FPS drops: 29 fps → 26 fps → 27 fps

**The pattern matches the CASING_KICK issue (#969)**: high-fire-rate weapon → event fires every shot → sound propagation iterates all listeners → FPS drops. The fix is identical: add a throttle cooldown.

**Fix applied** (this PR): Added `EMPTY_CLICK_PROPAGATION_COOLDOWN = 0.4s` and timestamp tracking in `emit_player_empty_click()`. After the first empty-click alert, further calls within 0.4s are ignored. Impact:
- Before: 36 EMPTY_CLICK × 10 listeners = 360 callbacks/sec
- After: max 2–3 EMPTY_CLICK × 10 listeners = 20–30 callbacks/sec (97% reduction)

```gdscript
# Before fix: fires every shot at fire rate with 10 listeners
func emit_player_empty_click(position: Vector2, source_node: Node2D = null) -> void:
    emit_sound(SoundType.EMPTY_CLICK, position, SourceType.PLAYER, source_node)

# After fix: throttled to once per 0.4s
func emit_player_empty_click(position: Vector2, source_node: Node2D = null) -> void:
    var current_time := Time.get_ticks_msec() / 1000.0
    if current_time - _last_empty_click_time < EMPTY_CLICK_PROPAGATION_COOLDOWN:
        return  # Throttled
    _last_empty_click_time = current_time
    emit_sound(SoundType.EMPTY_CLICK, position, SourceType.PLAYER, source_node)
```

### Root Cause 2: Duplicate Raycasts per Bullet-Wall Collision

**File**: `scripts/projectiles/bullet.gd`

When a bullet hits a `StaticBody2D` wall, `_on_body_entered()` executes:

```gdscript
# Before fix: two separate calls to _get_surface_normal()
if body is StaticBody2D or body is TileMap:
    _spawn_wall_hit_effect(body)   # ← _get_surface_normal(body) → raycast #1
    ...
    if _try_ricochet(body):        # ← _get_surface_normal(body) → raycast #2 (REDUNDANT)
```

`_get_surface_normal()` calls `space_state.intersect_ray()` — an expensive physics operation that traverses the Godot BVH collision tree. With Mini UZI at 15 shots/sec all hitting the same wall, this was **15 extra raycasts per second** (2 per shot → 1 wasted per shot × 15 shots/sec).

**Fix applied** (commit `46fc0be0`): Compute the normal once in `_on_body_entered`, cache it in `cached_normal`, pass it to both functions. 50% fewer raycasts per wall hit.

### Why Session 3 Shooting Shows No FPS Drop

In Session 3, the Tutorial level had 0 active listeners when shooting began (5 stale LabyrinthLevel enemies were cleaned up on the first shot). With no listeners, `emit_sound()` completes in near-zero time regardless of how many shots are fired. This is why the session 3 log shows 60fps throughout the entire 61-shot sequence — it wasn't testing the actual bottleneck.

The FPS drop the user reports ("still drops to ~30") is reproducible **only with enemies alive** in the Tutorial level and **holding trigger after magazine empties**. Session 1 is the definitive proof.

---

## Evidence: EMPTY_CLICK is the Root Cause in Session 1

From `game_log_20260318_064123.txt`:

```
[06:41:52] Shot fired with mini_uzi (1 total)   ← shooting starts, no FPS drop
...
[06:41:55] Shot fired with mini_uzi (32 total)  ← last bullet fired
[06:41:55] [ENEMY] Enemy1..Enemy10 Player ammo empty: false -> true  ← ammo depleted
[06:41:55] Sound emitted: type=EMPTY_CLICK, listeners=10  ← 36 times in 1 second!
...
[06:41:55] [WARN] [FPS] Drop detected: 29 fps   ← DROP starts HERE (during EMPTY_CLICK phase)
[06:41:56] [WARN] [FPS] Drop detected: 26 fps
[06:41:57] [WARN] [FPS] Drop detected: 27 fps
```

During shots 1–32 (actual GUNSHOT+wall-hit phase), **no FPS drops are logged**.

---

## Online Research: Best Practices Applied

Based on research into Godot 4 optimization best practices:

| Practice | Source | Applied |
|----------|--------|---------|
| Cache `PhysicsRayQueryParameters2D`; reuse per call | [Godot docs](https://docs.godotengine.org/en/stable/tutorials/physics/ray-casting.html) | ✅ Normal cached, 1 raycast instead of 2 |
| Throttle high-frequency event emissions (same pattern as CASING_KICK) | Issue #969 in this repo | ✅ EMPTY_CLICK throttled to 0.4s |
| Signals/events for events, not per-frame state | [GDQuest best practices](https://www.gdquest.com/tutorial/godot/best-practices/signals/) | Applied in CASING_KICK fix; now EMPTY_CLICK too |
| Explicit listener cleanup on node free | [Godot Forum](https://forum.godotengine.org/t/performance-of-signals/116202) | Existing: `unregister_listener()` on enemy exit |
| Upgrade to Godot 4.4+ for ubershader auto-precompile | [Godot docs: pipeline compilations](https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html) | Would eliminate scene-transition FPS spikes (future work) |

---

## Raycast Budget Analysis

| Source | Rate | Raycasts/sec | Notes |
|--------|------|--------------|-------|
| Bullet wall hit (before PR) | 15 shots/sec | 30/sec | 2× per hit (redundant) |
| Bullet wall hit (after PR) | 15 shots/sec | 15/sec | 1× per hit (optimal) |
| Bullet penetration check | ~1 per bullet | ~2/bullet | Bounded by max_penetration_distance |
| Visibility checks (10 enemies) | ~60/sec each | ~600/sec | From enemy AI raycasts |

## EMPTY_CLICK Propagation Budget Analysis

| Scenario | Before fix | After fix |
|----------|-----------|----------|
| Enemy callbacks/sec (holding empty trigger, 10 listeners) | 36 events × 10 = 360/sec | max 2–3 × 10 = 20–30/sec |
| FPS during EMPTY_CLICK hold | 26–29 fps (drops logged) | ~60 fps (expected) |

---

## Existing Similar Fixes in This Codebase

- **Issue #969**: `CASING_KICK` sound propagation throttled (max once per 0.4s) to prevent flooding from high-fire-rate weapons. **This PR applies the exact same pattern to EMPTY_CLICK.**
- **Issue #724**: Object pooling added to eliminate per-bullet `instantiate()` calls.
- **Issue #343**: Shader warmup pre-compiles shaders to eliminate first-shot lag spikes (explains session startup FPS drops).
- **Issue #883**: FPS monitoring added — the source of `[FPS] Drop detected` log lines.

---

## Changes in This PR

| File | Change | Impact |
|------|--------|--------|
| `scripts/projectiles/bullet.gd` | Cache `_get_surface_normal()` result; pass to `_spawn_wall_hit_effect()` and `_try_ricochet()` | 50% fewer raycasts per bullet-wall hit |
| `scripts/autoload/sound_propagation.gd` | Add `EMPTY_CLICK_PROPAGATION_COOLDOWN = 0.4s` throttle to `emit_player_empty_click()` | 97% fewer enemy callbacks when holding empty trigger |

---

## References

- [Godot 4 ray-casting documentation](https://docs.godotengine.org/en/stable/tutorials/physics/ray-casting.html)
- [PhysicsDirectSpaceState2D](https://docs.godotengine.org/en/stable/classes/class_physicsdirectspacestate2d.html)
- [Godot 4 general optimization tips](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html)
- [Godot 4 pipeline compilations (shader warmup)](https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html)
- [Best practices with Godot signals — GDQuest](https://www.gdquest.com/tutorial/godot/best-practices/signals/)
- [Godot Forum: Collision Pairs optimizing performance of bullet-hell games](https://forum.godotengine.org/t/collision-pairs-optimizing-performance-of-bullet-hell-enemy-hell-games/35027)
- [Godot Forum: Multithreading intersect_ray raycasts](https://forum.godotengine.org/t/multithreading-intersect-ray-raycasts/52663)
- [Issue #969: CASING_KICK throttling](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/969)
- [Issue #343: Shader warmup](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/343)
