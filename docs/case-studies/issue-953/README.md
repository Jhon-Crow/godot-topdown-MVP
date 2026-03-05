# Case Study: Issue #953 — FPS Performance Analysis

**Issue:** [#953 — Analyze causes of FPS drops](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/953)
**Date of log capture:** 2026-03-02 19:13:29–19:16:24 (2 min 55 sec of gameplay)
**Platform:** Windows, Godot 4.3-stable, release build
**Log file:** [game_log_20260302_191329.txt](./game_log_20260302_191329.txt)

---

## 1. Session Overview

| Parameter | Value |
|---|---|
| Levels played | LabyrinthLevel → BuildingLevel → DocksLevel |
| Enemy count | 5 (Labyrinth) → 10 (Building) → 20 (Docks) |
| Weapon selected | Revolver (player start), AKGL used mid-session |
| Debug options | FOV: on, AI prediction: on, Invincibility: on |
| FPS drop logging | Enabled at 19:14:45 |
| FPS counter | Enabled at 19:14:55 |

**Total FPS drop events:** 31
**First drop:** 19:15:08 (after ~1 min 39 sec of play)
**Worst FPS recorded:** 4 fps
**Average FPS during drops:** ~17 fps
**All drops occurred exclusively during 20-enemy sessions.**

---

## 2. Timeline Reconstruction

```
19:13:29  Session starts — 5 enemies (LabyrinthLevel)
19:13:30  Scene reload — 10 enemies (BuildingLevel)
19:13:30  Enemy grenade components initialized
19:13:39  BuildingLevel — 10 enemies (new scene)
19:13:44  BuildingLevel — 10 enemies (another reload)
19:13:53  First grenade-related log spam begins:
            "Unsafe throw distance (224 < 275 safe)" — fires every physics frame
19:13:58  "Target not visible to enemy" spam begins — fires every physics frame
            (x-coordinate increments ~4.4 px/frame = enemy moving while checking)
19:14:23  Log volume spikes: 426 entries/second
19:14:27  Log volume: 593 entries/second
19:14:30  Log volume: 661 entries/second
19:14:34–37  Peak log storm: 805–1250 entries/second
            (sound_propagation, bullet, blood_decal events all coincide)
19:14:45  FPS drop logging enabled by player
19:14:55  FPS counter enabled
[FPS drops are not yet logged because the feature was just enabled]
19:15:08  FIRST FPS drop logged: 27 fps (line 15,851)
            Context: 19 listeners in SoundPropagation, CASING_KICK event fired
19:15:10  7 fps drop — worst sustained cluster begins
19:15:11  6 fps drop
19:15:12  7 fps drop
19:15:17–21  5, 6, 7, 8 fps (worst cluster)
19:15:24–36  Mixed drops: 25, 29, 19, 15, 6, 13, 20, 29, 20, 17, 28 fps
19:15:44–48  Partial recovery with mild drops: 28, 29, 26, 26 fps
19:16:17–18  Second log storm: 1012–960 entries/second
19:16:18–24  Second severe drop cluster: 9, 4, 14, 23, 27 fps
              (4 fps = worst FPS of entire session)
19:16:24  Session ends
```

---

## 3. Root Cause Analysis

### 3.1 Root Cause #1 (PRIMARY): EnemyGrenadeComponent — Per-frame Raycast Storm

**Evidence:**
- 10,357 `[EnemyGrenade]` log entries in 175 seconds = **59 grenade log calls per second**
- 7,509 lines matching: "Unsafe throw distance", "Target not visible to enemy", "Target not in enemy FOV", "Throw path blocked"
- Log at 19:13:53 shows: 9 consecutive "Unsafe throw distance (224/220/.../195 < 275 safe)" with distance decrementing by ~4 pixels per frame — proving the check runs **every physics frame (60 fps)**
- Log at 19:13:58 shows: "Target not visible to enemy" at x=2176.342, 2180.7, 2185.1… incrementing by ~4.4 px/frame — same per-frame execution confirmed

**Root cause in code:**
In `scripts/objects/enemy.gd`, both `_update_grenade_triggers(delta)` (line ~851) and `_update_grenade_danger_detection()` (line ~852) are called **every physics frame** (60 Hz) from `_physics_process()`. The `_is_target_visible()` function in `EnemyGrenadeComponent` (Issue #712) fires **two raycasts per enemy per frame**:
1. Line-of-sight raycast to check if target is behind a wall
2. FOV check via `_enemy._is_position_in_fov(target)` (which itself may raycast)

With 20 enemies, this is up to **40 raycasts/frame from grenade visibility alone**, plus `_path_clear()` adds another raycast, for up to **60 raycasts/frame**.

**Impact:** O(n) CPU cost with enemy count. At 20 enemies, this alone can consume a significant fraction of each frame budget.

**Fix:** Throttle grenade readiness checks to run at most every 0.2–0.5 seconds, not every physics frame.

---

### 3.2 Root Cause #2: SoundPropagation — O(n) Broadcast with 19 Listeners

**Evidence:**
- 7,041 `[SoundPropagation]` log entries
- 3,394 sound events emitted (2,508 CASING_KICK, 769 GUNSHOT, 94 EMPTY_CLICK, 13 EXPLOSION, 10 RELOAD)
- Context at first FPS drop: "listeners=19" on every CASING_KICK event
- CASING_KICK propagation range = 900 pixels — covers almost the entire map
- Every CASING_KICK iterates all 19 listeners and calls `distance_to()` + potentially `on_sound_heard_with_intensity()` on each

**Root cause in code:**
`sound_propagation.gd: emit_sound()` iterates `_listeners` array (size 19) on every call. CASING_KICK fires for every shot from every weapon. With AKGL (full-auto), this is potentially **6 bullets/burst × 2 sounds each = 12 `emit_sound` calls per burst × 19 listeners = 228 function calls per burst**.

**Fix:** Rate-limit CASING_KICK to at most once per 100ms per source, and/or reduce CASING_KICK propagation range from 900px to 150–200px (casings don't realistically roll far).

---

### 3.3 Root Cause #3: Blood Decal Accumulation — 2,274 Persistent Scene Nodes

**Evidence:**
- 2,274 `BloodDecal` nodes confirmed created (grep of log)
- `MAX_BLOOD_DECALS: int = 0` (unlimited) in `impact_effects_manager.gd:34`
- Each decal is a `Sprite2D` + `Area2D` + `CollisionShape2D` (3 nodes minimum)
- 2,274 × 3 = **6,822 persistent scene tree nodes** from blood alone
- `auto_fade: bool = false` by default — decals never expire

**Root cause in code:**
`impact_effects_manager.gd` spawns real scene tree nodes for blood with no budget cap (`MAX_BLOOD_DECALS = 0`). Although the code has budget limiting logic, it is disabled. Each decal's `Area2D` with `monitorable = true` participates in collision detection, adding physics overhead proportional to decal count.

**Fix:** Add a configurable `max_blood_decals` option in `ExperimentalSettings` to cap at ~200 decals (oldest removed when exceeded). This is already architecturally supported — the cleanup code exists but is gated behind `MAX_BLOOD_DECALS > 0`.

---

### 3.4 Root Cause #4: Bullet Physics Raycasts — Multiple Raycasts Per Bullet

**Evidence:**
- 3,302 `[Bullet]` log entries
- Log at FPS drop time: multiple consecutive "Within ricochet range - trying ricochet first", "_get_distance_to_shooter", "Caliber cannot penetrate walls" per second
- Each bullet line shows a distance-to-shooter computation + ricochet raycast + potential penetration raycast

**Root cause in code:**
`bullet.gd` performs per-bullet physics work: distance-to-shooter calculation, ricochet check (1 raycast), and penetration check (up to 2 raycasts). With AKGL firing ~10 rounds/second and 20 enemies firing simultaneously, this means **dozens of raycasts per second from bullets alone**.

**Fix:** Skip ricochet/penetration raycasts for enemy bullets that hit within point-blank range, or use a simpler distance check as a pre-filter before full physics queries.

---

### 3.5 Root Cause #5: BloodyFeet Component — Per-Enemy Footprint Overhead

**Evidence:**
- 1,182 `[BloodyFeet]` log entries
- Each enemy has a `BloodyFeetComponent` that spawns `BloodFootprint.tscn` nodes

**Root cause in code:**
`bloody_feet_component.gd` spawns footprint `Node2D` instances on each movement step. With 20 enemies creating blood footprints throughout the session, this adds further scene-tree nodes. The component uses `Area2D` overlap detection with a fallback physics check every 30 frames, adding overlap query cost.

**Fix:** Pool `BloodFootprint` nodes rather than instantiating/freeing them, and limit total footprints per enemy (e.g., 20 max footprints per enemy with recycling).

---

### 3.6 Contributing Factor: Debug Logging Overhead

**Evidence:**
- `debug_logging: bool = false` is set on all components, but the game uses `FileLogger` which writes to disk on every log call
- Peak log rate: 1,250 lines/second at 19:14:37
- Every `_log()` call in EnemyGrenadeComponent unconditionally calls `_logger.log_info()` even when `debug_logging` is false

**Root cause in code:**
`enemy_grenade_component.gd _log()`:
```gdscript
func _log(msg: String) -> void:
    if debug_logging:
        print("[EnemyGrenadeComponent] %s" % msg)
    if _logger and _logger.has_method("log_info"):
        _logger.log_info("[EnemyGrenade] %s" % msg)  # ALWAYS logs to file!
```
The file logger call is NOT gated behind `debug_logging`, so even in non-debug mode, every grenade check logs to disk. This I/O overhead compounds the physics cost.

**Fix:** Gate the `_logger.log_info()` call behind `debug_logging` as well, or add a separate `file_logging: bool` flag.

---

## 4. Optimization Plan

Each item is a separate actionable fix. Items marked with `[HIGH]` have the largest impact based on log data.

### Performance Issues

- [ ] [HIGH] **Throttle EnemyGrenadeComponent readiness checks** — Add a `_check_interval: float = 0.3` timer to `update()` so `is_ready()` and its raycasts fire at most ~3 times/second instead of 60 times/second. Expected reduction: **~95% of grenade raycast volume** (Issue #954)

- [ ] [HIGH] **Fix EnemyGrenadeComponent unconditional file logging** — Gate `_logger.log_info()` in `_log()` behind `debug_logging` flag, eliminating 10,357 file I/O calls during normal gameplay. Expected reduction: **~29% of total log volume** (Issue #955)

- [ ] [HIGH] **Add configurable blood decal budget** — Add `max_blood_decals_enabled: bool` and `max_blood_decals_count: int = 200` to `ExperimentalSettings`, wire it to the existing `MAX_BLOOD_DECALS` constant logic in `impact_effects_manager.gd`. Expected reduction: **6,000+ scene nodes** at end of long sessions (Issue #956)

- [ ] [MEDIUM] **Reduce CASING_KICK sound propagation range** — Reduce from 900px to 150px in `sound_propagation.gd`. CASING_KICK is fired on every shot but casings only roll a short distance realistically. This reduces the fraction of enemies notified per casing event from ~19 to ~1-3. (Issue #957)

- [ ] [MEDIUM] **Throttle SoundPropagation CASING_KICK** — Rate-limit CASING_KICK emissions to at most one per 150ms per source position, deduplicating rapid-fire casing events. (Issue #958)

- [ ] [MEDIUM] **Pool BloodFootprint nodes** — Add a per-enemy footprint pool in `BloodyFeetComponent` with a maximum of 20 recycled footprints instead of creating new nodes on every step. (Issue #959)

- [ ] [LOW] **Skip bullet ricochet/penetration checks at point-blank range** — When bullet distance to shooter is less than 50px, skip the expensive ricochet and penetration raycasts (these scenarios are physically meaningless anyway). (Issue #960)

- [ ] [LOW] **Add FPS-based quality scaling** — When FPS drops below 30, automatically disable non-critical effects (BloodyFeet, CASING_KICK sounds, excess blood decal spawning). This graceful degradation ensures playability. (Issue #961)

### Observability Improvements

- [ ] [LOW] **Add performance profiler overlay** — Extend `FpsMonitor` to display counts of active enemies, blood decals, and sound listeners alongside FPS counter, so players and developers can immediately see scaling factors during FPS drops. (Issue #962)

- [ ] [LOW] **Add scene-tree node count monitoring** — Log total scene tree node count when FPS drops, to catch runaway node accumulation issues early. (Issue #963)

---

## 5. Quantitative Impact Summary

| Root Cause | Log Evidence | Estimated FPS Impact |
|---|---|---|
| EnemyGrenade per-frame raycasts | 10,357 entries, 7,509 redundant skip logs | **Very High** (60 raycasts/frame at 20 enemies) |
| Blood decal scene nodes | 2,274 nodes × 3 = 6,822 nodes | **High** (accumulates over session) |
| SoundPropagation broadcast | 2,508 CASING_KICK × 19 listeners | **Medium** (O(n) per shot) |
| Bullet raycasts | 3,302 entries | **Medium** (scales with bullets in-flight) |
| BloodyFeet node spawning | 1,182 entries | **Low-Medium** |
| File I/O logging | ~29% of log volume from unconditional writes | **Low-Medium** (disk I/O in main thread) |

---

## 6. References

### Godot Documentation
- [Ray-casting — Godot Engine docs](https://docs.godotengine.org/en/stable/tutorials/physics/ray-casting.html)
- [General optimization tips — Godot Engine docs](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html)
- [Idle and Physics Processing — Godot Engine docs](https://docs.godotengine.org/en/stable/tutorials/scripting/idle_and_physics_processing.html)
- [Using Area2D — Godot Engine docs](https://docs.godotengine.org/en/stable/tutorials/physics/using_area_2d.html)

### Community
- [Raycast VS ShapeCast VS Area — Godot Forum](https://forum.godotengine.org/t/raycast-vs-shapecast-vs-area/95569)
- [Object pooling — Godot Forum](https://forum.godotengine.org/t/what-is-the-best-way-to-do-object-pooling/28960)
- [Slowdown with many nodes — Godot Forum](https://forum.godotengine.org/t/slowdown-with-many-nodes/133487)
- [Add a batch RayCast method — GitHub Issue #25695](https://github.com/godotengine/godot/issues/25695)

### Related Issues in This Project
- Issue #712: `_is_target_visible()` added to EnemyGrenadeComponent (source of double raycast per check)
- Issue #886: `_blast_radius_cache` added to avoid repeated grenade scene instantiation
- Issue #375: `min_safe_distance` check added (source of per-frame "Unsafe throw distance" log spam)
- Issue #363: EnemyGrenadeComponent extracted from enemy.gd
- Issue #293/#370: `MAX_BLOOD_DECALS = 0` (unlimited decals — by design)
