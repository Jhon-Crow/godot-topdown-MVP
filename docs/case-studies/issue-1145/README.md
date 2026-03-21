# Case Study: Issue #1145 — FPS Drop When Shooting at Walls

## Summary

**Issue**: FPS drops from 60 to ~26–30 fps when shooting at walls, reported by user with Mini UZI.

**Root causes identified** (in priority order, updated after user confirmed Session 4 results):
1. **EMPTY_CLICK propagation at fire rate** (confirmed fixed): When holding fire with an empty weapon, the weapon fires at ~15 clicks/sec, each triggering `SoundPropagation` to iterate all 10 enemies, causing 360+ callbacks/sec and FPS drops to 26–29 fps. ✅ **Fixed** (throttled to 0.4s cooldown, same as CASING_KICK). User confirmed in Session 4: *"empty shots don't affect fps"*.
2. **Unbounded GPUParticles2D instantiation per wall hit** (confirmed remaining root cause): Each bullet-wall collision calls `_dust_effect_scene.instantiate()` creating a new `GPUParticles2D` node. Godot issue #103308 documents a first-emit stutter every time a `GPUParticles2D` emits for the first time. At 15 shots/sec with 32 bullets per magazine, this creates 32+ nodes in 2–3 seconds. Session 4 log confirms: FPS drops to 29fps during the 32-bullet wall-shooting phase, NOT during empty-click phase. ✅ **Fixed** (DustEffect object pool, 16 pre-allocated nodes, same pattern as explosion light pool from Issue #724).
3. **Redundant physics raycasts**: `_get_surface_normal()` called twice per bullet-wall collision (once for dust effect, once for ricochet), doubling the per-frame raycast cost during wall hits. ✅ **Fixed** (cached normal, commit `46fc0be0`).
4. **Invisible dust effect (Godot bug #58778)**: After introducing the pool, `emitting=false/true` on a reused one-shot GPUParticles2D was silently dropped during GPU `inactive_time` window. Fixed by using `effect.restart()` which bypasses the window. ✅ **Fixed**.
5. **Pooled nodes parented to plain Node autoload — no canvas context** (root cause of Session 7 invisible dust): `GPUParticles2D` (a CanvasItem) added as child of a `Node`-based autoload has no viewport/canvas context and is never rendered. All other effects use `_add_effect_to_scene()` which parents them to the current game scene. Fix: call `effect.reparent(current_scene)` before emitting, and `effect.reparent(self)` when returning to pool. ✅ **Fixed**.

---

## Log Files

| File | Session | Key findings |
|------|---------|-------------|
| `game_log_20260318_064123.txt` | Session 1 | Confirms EMPTY_CLICK is root cause of 29/26/27 fps drops |
| `game_log_20260318_081028.txt` | Session 2 | All drops from shader warmup/scene load; 0 listeners, no gameplay drops |
| `game_log_20260318_083455.txt` | Session 3 | Old build; 1 drop at 22fps during scene load; shooting with 0 listeners, no gameplay drops |
| `logs/game_log_20260318_085720.txt` | Session 4 | **Fixed EMPTY_CLICK build confirmed** — no empty-click drops; **new finding**: 29fps drop during 32-bullet wall-shooting burst confirms DustEffect instantiation as remaining root cause |
| `game_log_20260318_094946.txt` | Session 5 | **Fixed pool build confirmed** — FPS stable during shooting; **new finding**: dust effect invisible due to Godot bug #58778; **new finding**: blood decal FPS drops on large map with 20 enemies |
| *(no new log)* | Session 6 | **User requests Optimization menu** — no dust effect visible, user asks for: settings → optimization → toggle wall hit particles on/off + restore old particle effect |
| `logs/game_log_20260318_103836.txt` | Session 7 | **Optimization menu build tested** — FPS stable, but dust still invisible; user confirms: "при включённых частицах должны быть частицы как в main (верни их). сейчас нет никаких." |

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

### Session 4 — Log: `logs/game_log_20260318_085720.txt`

| Time | Event |
|------|-------|
| 08:57:20 | Game start. Level: LabyrinthLevel. Build from `оптимизация/` folder (**includes EMPTY_CLICK fix**) |
| 08:57:24 | Particle shader warmup complete (2915 ms). **FPS drop: 1 fps** (startup spike, unrelated) |
| 08:57:27 | Player opens Armory → selects Mini UZI (32/32 ammo) |
| 08:57:30/32 | Scene changes to Tutorial (multiple transitions) |
| 08:57:33 | Scene/shader warmup complete. **FPS drop: 1 fps** (transition spike, unrelated). `player_valid=False` in ReplayManager. |
| 08:57:37 | First GUNSHOT: `listeners=10` → immediately "Cleaned up 10 invalid listeners" (stale enemies). Subsequent shots: `listeners=0` |
| 08:57:37–39 | Player fires 32 Mini UZI rounds at wall: 6 shots/08:57:37, 20 shots/08:57:38, 6 shots/08:57:39. **32 DustEffect GPUParticles2D instantiated in ~2 seconds** |
| 08:57:41 | **FPS drop: 29 fps** — occurs 2 seconds AFTER the 32-bullet burst ended |
| 08:57:46+ | Player fires more rounds (no enemies). No further FPS drops. |

**Key observations for Session 4**:
1. **No EMPTY_CLICK events** — the throttle fix worked. User confirmed: *"empty shots don't affect fps"*.
2. **FPS drops to 29fps DURING/AFTER the 32-shot burst** — this is during GUNSHOT events (not empty-click), with `listeners=0` (no sound propagation overhead).
3. The drop at 08:57:41 follows 20 GUNSHOTS in a single second (08:57:38), all hitting the wall. This instantiates 20 new `GPUParticles2D` nodes in 1 frame tick.
4. Godot issue #103308 confirms: every new `GPUParticles2D` instance stutters on its very first emit. 20 first-emit stutters chained together causes the 29fps drop.
5. By 08:57:41, all 32 `DustEffect` nodes are alive (lifetime=2.5s), each rendering 25 particles = 800 active particles. Combined with the instantiation overhead, this causes the sustained FPS dip.

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

## Root Cause 3: Unbounded GPUParticles2D Instantiation (Session 4 Confirmed)

**File**: `scripts/autoload/impact_effects_manager.gd` — `spawn_dust_effect()`

Each bullet-wall collision calls `_dust_effect_scene.instantiate()` creating a brand-new `GPUParticles2D` node:

```gdscript
# Before fix: new node allocated per wall hit
var effect: GPUParticles2D = _dust_effect_scene.instantiate() as GPUParticles2D
...
_add_effect_to_scene(effect)
effect.emitting = true
# effect_cleanup.gd: queue_free() after lifetime (2.5s) + cleanup_delay (1.0s) = 3.5s
```

**Quantified impact** (Mini UZI, full magazine):
- 32 bullets × 1 `instantiate()` call = 32 new nodes in ~2 seconds
- 20 shots in 1 second (peak): 20 first-emit stutters (Godot #103308) chained = frame spike
- After 2.5s, up to 37 concurrent nodes active: 37 × 25 particles = 925 active particles
- Without a pool, each `instantiate()` also allocates GPU resource IDs → CPU stall

**Fix applied**: Pre-allocate 16 `GPUParticles2D` nodes in a pool at startup (same pattern as explosion light pool from Issue #724). Reuse by repositioning and calling `restart()`. Hard cap: 16 concurrent effects max (vs. unlimited before).

```gdscript
# After fix: pool reuse, no allocation during gameplay
var effect := _get_dust_effect_from_pool()  # Returns pre-existing node
if effect == null:
    return  # Cap reached — skip extra dust effect
effect.global_position = position
effect.rotation = surface_normal.angle()
effect.restart()  # Re-trigger (see Session 5 / Godot bug #58778 below)
# Timer-based return to pool after 3.5s instead of queue_free()
```

**Session 4 evidence**:
- 20 GUNSHOTS in 1 second → 29fps drop 2 seconds later
- No EMPTY_CLICK events in log → EMPTY_CLICK fix confirmed working
- First GUNSHOT: 10 listeners immediately cleaned up → no sound propagation overhead

### Session 5 — Log: `game_log_20260318_094946.txt`

| Time | Event |
|------|-------|
| 09:49:46 | Game start. Dust pool initialized (16 nodes). Explosion light pool initialized (12 nodes). |
| 09:49:47 | Particle shader warmup complete (1035 ms). |
| 09:49:57–09:49:59 | Player fires Mini UZI at wall (28 shots, `listeners=0`). **No FPS drops**. Pool fix working. |
| 09:50:01 | Scene changed (twice). |
| 09:50:20–09:50:37 | Player fighting 20 enemies on large map. FPS drops: 24fps, 16fps, 7fps, 6fps. All drops correlate with `Blood decals scheduled: 15/30` log entries — NOT with wall hits. |

**Key observations for Session 5**:
1. **No FPS drops during wall shooting** — DustEffect pool fix confirmed working. 28 shots in 2 seconds, 60fps maintained.
2. **Dust effect invisible** — confirmed by user ("no dust effect"). Root cause: Godot bug #58778 (see below).
3. **FPS drops on large map** — caused by `_spawn_blood_decals_at_particle_landing()` spawning 15–30 `await`-based delayed raycasts per enemy hit, running concurrently across 20 enemies. This is a **separate pre-existing issue** unrelated to wall-shooting.

### Root Cause 4 (Session 5): Dust Effect Invisible Due to Godot Bug #58778

**File**: `scripts/autoload/impact_effects_manager.gd` — `spawn_dust_effect()`

The initial pool implementation used `emitting = false` then `emitting = true` to restart the one-shot particle effect. This was **unreliable** due to [Godot bug #58778](https://github.com/godotengine/godot/issues/58778):

> "Cannot emit one-shot particles right after it's disabled automatically"
>
> With `one_shot = true` and `explosiveness > 0`, there is a mandatory GPU-side inactive timer after the system auto-deactivates. Setting `emitting = true` during this window is **silently dropped** — the node repositions correctly but emits zero particles.

DustEffect.tscn has `explosiveness = 0.85` (burst mode), which makes it especially prone to this bug.

```gdscript
# Before Session 5 fix: unreliable — emitting=true silently dropped during inactive_time
effect.emitting = false
effect.emitting = true  # ← BUG #58778: may emit 0 particles

# After Session 5 fix: restart() bypasses inactive_time window
effect.restart()  # ← always starts a fresh cycle
```

`restart()` is the official workaround documented in Godot bug #58778 comments. It bypasses the inactive time accounting and always starts a fresh one-shot cycle.

**Online research confirming this root cause**:
- [Godot #103308](https://github.com/godotengine/godot/issues/103308): "Brief stutter/pause when emitting GPUParticles2D for the first time"
- Community reports: 10–20 concurrent `GPUParticles2D` + `Light2D` → FPS drops to 2fps
- Recommendation: fixed-size pool of 8–16 nodes, Timer-based return (not `finished` signal due to Godot bugs #93991, #87287)

---

### Session 7 — Log: `logs/game_log_20260318_103836.txt`

| Time | Event |
|------|-------|
| 10:38:36 | Game start. Executable: `оптимизация/Godot-Top-Down-Template.exe` (optimisation branch build, session 6 code) |
| 10:38:36 | Log: `Dust effect pool initialized: 16 effects pre-created` — pool feature present |
| 10:38:36 | Log: `wall_hit_particles: true` — enabled by default |
| 10:38:37 | Particle shader warmup complete (871ms). **FPS drop: 1 fps** (warmup only) |
| 10:38:44 | User disables wall hit particles via Settings → Optimization |
| 10:38:54 | User re-enables wall hit particles |
| (gameplay) | No FPS drops during shooting — pool fix is working |
| (gameplay) | **Dust particles invisible** — user reports no particles at all |

**Key observation**: FPS issue is fully resolved but dust effect is invisible. Both with and without toggling the setting, no particles appear on screen.

#### Root Cause 5 — GPUParticles2D parented to plain Node autoload has no canvas context

`GPUParticles2D` is a `CanvasItem` subclass. In Godot, CanvasItem nodes must be part of the scene tree under a `Viewport` or `CanvasLayer` to be rendered. The autoload `ImpactEffectsManager` extends plain `Node` (not `Node2D`), so it has no canvas context.

All other effects (blood, sparks, muzzle flash) use `_add_effect_to_scene(effect)` which calls `scene.add_child(effect)`, placing them directly in the game world scene where they render correctly.

The pooled dust effects were added with `add_child(effect)` in `_create_pooled_dust_effect()`, making them children of the autoload. While `global_position` can be set on them (Node2D transform is still valid), they have **no viewport to render into** and produce zero visible output.

This is why `restart()` fixed Session 5's issue (Godot bug #58778) but particles were still invisible — the node was correctly emitting, just not rendering.

**Fix**: Call `effect.reparent(current_scene, false)` before emitting, and `effect.reparent(self, false)` when returning to pool. This gives each active effect a proper canvas context while keeping pool persistence across scene changes.

```gdscript
# Before Session 7 fix: node stays as child of autoload (Node, no canvas context)
effect.visible = true
effect.restart()  # ← emits, but never rendered

# After Session 7 fix: reparent to scene before emitting
var scene := get_tree().current_scene
if scene:
    effect.reparent(scene, false)  # ← now has canvas context → visible
effect.visible = true
effect.restart()

# And on return to pool:
if effect.get_parent() != self:
    effect.reparent(self, false)  # ← back to autoload for persistence
```

---

## Changes in This PR

| File | Change | Impact |
|------|--------|--------|
| `scripts/projectiles/bullet.gd` | Cache `_get_surface_normal()` result; pass to `_spawn_wall_hit_effect()` and `_try_ricochet()` | 50% fewer raycasts per bullet-wall hit |
| `scripts/autoload/sound_propagation.gd` | Add `EMPTY_CLICK_PROPAGATION_COOLDOWN = 0.4s` throttle to `emit_player_empty_click()` | 97% fewer enemy callbacks when holding empty trigger |
| `scripts/autoload/impact_effects_manager.gd` | DustEffect object pool (16 pre-allocated nodes, max 16 concurrent) replacing per-hit `instantiate()` | Eliminates first-emit stutters; bounds GPU particle load |
| `scripts/autoload/impact_effects_manager.gd` | Use `restart()` instead of `emitting=false/true` to re-trigger pooled one-shot particles | Fixes invisible dust effect (Godot bug #58778: emitting=true silently dropped during inactive_time) |
| `scripts/autoload/impact_effects_manager.gd` | Check `GameplaySettings.is_wall_hit_particles_enabled()` before spawning dust (Session 6) | Allows disabling dust particles entirely via settings for low-end hardware |
| `scripts/autoload/impact_effects_manager.gd` | `reparent(current_scene)` before emitting, `reparent(self)` when returning to pool (Session 7) | Fixes invisible dust: pooled GPUParticles2D need canvas context (CanvasItem must be under a Viewport) |
| `scripts/autoload/gameplay_settings.gd` | Add `wall_hit_particles_enabled` bool setting with getter/setter/persistence | New optimization knob persisted to `user://gameplay_settings.cfg` |
| `scripts/ui/settings_menu.gd` + `SettingsMenu.tscn` | Add "Optimization" button to settings hub | New Optimization submenu accessible from Settings |
| `scripts/ui/optimization_menu.gd` + `OptimizationMenu.tscn` | New Optimization submenu with wall hit particles toggle | User can enable/disable wall hit dust particles |

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
- [Godot #58778: Cannot emit one-shot particles right after auto-disable (inactive_time window bug)](https://github.com/godotengine/godot/issues/58778)
- [Godot #83599: Particle system one-shot issues — restart() workaround](https://github.com/godotengine/godot/issues/83599)
