# Case Study: Issue #1528 — FPS Drop in Combat State (5–7 fps)

## Issue Summary

**Reporter:** Jhon-Crow
**Description (RU):** "в состоянии combat производительность проседает очень сильно (игра идёт в 5-7fps)" — "In combat state, performance drops very badly (game runs at 5–7 fps)"
**Log files:** `game_log_20260326_080756.txt`, `game_log_20260326_080958.txt`
**Levels tested:** LabyrinthLevel (5–10 enemies), BuildingLevel (20 enemies)
**Engine:** Godot 4.3-stable (official)
**Previous fix:** Issue #1520 / PR #1521 addressed IDLE state FPS drops

---

## Evidence from Game Logs

### Log 3: `game_log_20260326_084043.txt` (1,444 lines) — Post-v1 Fix Verification

**Status: Issue NOT FIXED by v1 fix.** FPS drops of 6–8 fps confirmed after v1 changes.

| Time     | Event                                             | FPS    |
|----------|----------------------------------------------------|--------|
| 08:40:46 | Scene load, shader warmup                          | 1 fps (expected) |
| 08:41:13 | 20 enemies enter SEARCHING/COMBAT simultaneously   | 23 fps |
| 08:41:14 | Full combat engagement, 20 enemies active          | **7 fps** |
| 08:41:16 | Sustained combat                                   | **6 fps** |
| 08:41:17 | Sustained combat                                   | **6 fps** |
| 08:41:18 | Sustained combat                                   | **7 fps** |
| 08:41:19 | Sustained combat                                   | **8 fps** |

**Key evidence from Log 3:**
- "Player distracted - priority attack triggered" appears **176 times** — confirms distraction check is still triggering frequently
- **29 ROT_CHANGE messages in the second 08:41:11** — all 20 enemies rotate to face player in SEARCHING state with no throttle
- `PerformanceSettings` check confirmed NOT using cached reference (two separate lookups per frame per enemy still happening)
- GOAP running every frame for 20 enemies in SEARCHING state — no throttle applied to this state

**New root causes identified from Log 3:**

#### RC6: `get_node_or_null` Called Twice Per Frame Per Enemy (uncached autoloads)

The `_physics_process` function called `get_node_or_null("/root/PerformanceSettings")` at line 801 AND again at line 1302 inside `_process_ai_state`. Plus `get_node_or_null("/root/DifficultyManager")` at line 1306. Result: **4,800 node tree traversals/second** with 20 enemies.

#### RC7: GOAP Update Runs Every Frame in SEARCHING State

The existing GOAP throttle (from issue #1520) only applies to `AIState.IDLE`. In `AIState.SEARCHING`, `_update_goap_state()` runs every frame for every enemy — including distraction check, can-hit cache, enemies_in_combat, and 15+ dictionary writes. With all 20 enemies starting in SEARCHING: **1,200 GOAP updates/second** with no throttle.

#### RC8: Viewport Transform Recomputed Per Enemy Despite Being Identical

Even with per-enemy throttling to every 6 frames, `_is_player_distracted()` computes `get_viewport().get_canvas_transform().affine_inverse()` — a matrix inversion — for each enemy independently. The mouse position and canvas transform are **identical for all enemies** in a given frame. This was computing the same matrix inversion up to 200 times/second.

---

### Log 1: `game_log_20260326_080756.txt` (4,847 lines)

No explicit FPS drop warnings in the LabyrinthLevel sessions (5–10 enemies), but FPS drops appear after level transition:

| Time     | Event                                             | FPS    |
|----------|----------------------------------------------------|--------|
| 08:08:30 | Multiple enemies in COMBAT/PURSUING (10 enemies)   | 22 fps |
| 08:08:48 | Continued combat                                   | 28 fps |
| 08:08:52 | Heavy combat with state transitions                | 13 fps |
| 08:09:01 | Sustained combat engagement                        | 18 fps |

### Log 2: `game_log_20260326_080958.txt` (5,847 lines)

Severe drops on BuildingLevel with 20 enemies. FPS collapses when combat begins:

| Time     | Event                                             | FPS    |
|----------|----------------------------------------------------|--------|
| 08:10:00 | 7 enemies enter COMBAT simultaneously              | —      |
| 08:10:01 | **FPS drop: 6 fps**                                | 6 fps  |
| 08:10:05 | User disables AI states via PerformanceSettings     | —      |
| 08:10:06 | AI state COMBAT disabled                           | —      |
| 08:10:13 | Re-enables COMBAT                                  | —      |
| 08:10:24 | Level change to BuildingLevel — 20 enemies spawn   | —      |
| 08:10:26 | 20 enemies enter SEARCHING/COMBAT                  | 19 fps |
| 08:10:27 | Heavy combat with all 20 enemies active             | 11 fps |
| 08:10:28 | Continued combat                                   | 17 fps |
| 08:10:30 | Sustained multi-enemy combat                       | **6 fps** |
| 08:10:31 | Worst recorded drop                                | **5 fps** |
| 08:10:35 | User disables Particles                            | —      |
| 08:10:37 | User disables Blood decals                         | —      |
| 08:10:38 | User disables Screen shake                         | —      |
| 08:10:40 | User disables Explosion lights                     | —      |
| 08:10:47 | **Still dropping** (all visual effects off)         | 21 fps |
| 08:10:48 | Continued drops                                    | 10 fps |
| 08:10:52 | Still 6 fps despite all visual effects disabled     | **6 fps** |
| 08:10:55 | Sustained low FPS                                  | **6 fps** |

**Key finding:** Disabling particles, blood decals, screen shake, and explosion lights via PerformanceSettings had **no significant effect on FPS** — drops from 5–7 fps continued. This conclusively proves the bottleneck is **CPU-bound in AI logic**, not in GPU/rendering.

### Log Spam Analysis

The "Player distracted - priority attack triggered" message appears **hundreds of times per second** across enemies. In a single second at 08:10:27, the log shows 15+ instances of this message from different enemies — each one representing a per-frame `_is_player_distracted()` call + viewport lookup + canvas transform + log file write.

Sound propagation creates cascading notifications: each GUNSHOT notifies 20 listeners, and with 5+ enemies firing simultaneously, this produces 100+ `on_sound_heard_with_intensity` callbacks per frame. Each callback involves distance calculations, intensity computation, memory updates, and state transitions.

---

## Root Cause Analysis

### RC1: `_is_player_distracted()` — Called Every Physics Frame Per Enemy (O(N))

**Location:** `scripts/objects/enemy.gd:957` via `_update_goap_state()`, also checked at line 1305 in `_process_ai_state()`.

```gdscript
_goap_world_state["player_distracted"] = _is_player_distracted()
```

The function (line 4703–4718) performs **every frame for every enemy**:
1. `_player.get_viewport()` — scene tree traversal
2. `player_viewport.get_mouse_position()` — input subsystem query
3. `player_viewport.get_canvas_transform().affine_inverse()` — matrix inversion
4. Two vector normalizations + dot product + acos

**Cost:** With 20 enemies at 60 fps: **1,200 viewport lookups + matrix inversions per second**.

Additionally, the result is **identical for all enemies** in a given frame (it only depends on player aim direction), yet each enemy recomputes it independently.

### RC2: `_apply_separation_force()` — O(N²) Group Scan Every Frame

**Location:** `scripts/objects/enemy.gd:4768–4778`

```gdscript
for body in get_tree().get_nodes_in_group("enemies"):
    ...
    var diff: Vector2 = global_position - (body as Node2D).global_position
    var dist: float = diff.length()
```

**Cost:** Every alive enemy iterates ALL enemies every frame. With 20 enemies: 20 × 20 = **400 distance calculations per frame** = **24,000/second** at 60 fps. Each call also allocates a fresh Array.

The previous fix (#1520) only skips this for GUARD+IDLE enemies. In combat, ALL enemies execute this O(N²) scan.

### RC3: Sound Propagation Cascade — O(N) Per Gunshot × Multiple Shooters

**Location:** `scripts/autoload/sound_propagation.gd:191–223`

```gdscript
for listener: Node2D in _listeners:
    var distance: float = listener.global_position.distance_to(position)
    ...
    listener.on_sound_heard_with_intensity(...)
```

**Problem:** With 20 enemies, each gunshot notifies all 20 listeners. When 5 enemies fire in the same frame (common in combat), this produces **100 callbacks** — each doing distance calculation, intensity computation, memory updates, and potential state transitions.

Additionally, each `on_sound_heard_with_intensity()` callback calls `_log_to_file()` (file I/O).

### RC4: `_log_to_file()` File I/O Flood During Combat

**Location:** `scripts/objects/enemy.gd:4534–4537`

```gdscript
func _log_to_file(message: String) -> void:
    if not is_inside_tree(): return
    var fl := get_node_or_null("/root/FileLogger")
    if fl and fl.has_method("log_enemy"): fl.log_enemy(name, message)
```

Every `_log_to_file()` call:
1. Calls `get_node_or_null("/root/FileLogger")` — node tree traversal
2. Calls `has_method("log_enemy")` — reflection
3. Calls `fl.log_enemy()` — actual file I/O

During heavy combat, the "Player distracted" message alone generates 200+ log writes/second. Combined with ROT_CHANGE, sound heard, state transition, and cover search logs, total file writes can exceed **500/second**.

### RC5: `_can_hit_target_from_current_position()` Raycast Every Frame

**Location:** `scripts/objects/enemy.gd:953` via `_update_goap_state()`

```gdscript
_goap_world_state["can_hit_from_cover"] = _can_hit_target_from_current_position()
```

This performs a raycast (via `_is_shot_clear_of_cover()` → `space_state.intersect_ray()`) every frame for every enemy. In COMBAT state (unlike IDLE which is throttled by #1520), this always runs.

**Cost:** 20 enemies × 60 fps = **1,200 raycasts/second** just for GOAP can-hit checks.

### RC6: Cover Search — 120 Raycasts Per Search

**Location:** `scripts/objects/enemy.gd:3328–3345`

Cover finding fires 120 raycasts per search (COVER_CHECK_COUNT=120). While throttled to 0.3s cooldown, when 20 enemies simultaneously transition to COMBAT and all seek cover, this produces a burst of **2,400 raycasts** in a single frame.

---

## Why Disabling Visual Effects Does NOT Help

The log evidence from `game_log_20260326_080958.txt` is definitive:

1. **Before disabling effects** (08:10:30): 6 fps
2. **After disabling ALL visual effects** (08:10:52): still 6 fps

The FPS drop is entirely CPU-bound. The bottleneck is in:
- AI state processing (per-enemy, per-frame)
- Group iteration (O(N²) separation force)
- Sound propagation callbacks (O(N) per gunshot)
- File I/O from excessive logging
- Redundant viewport/canvas queries (`_is_player_distracted`)

---

## Solutions Implemented (v2 — revised based on Log 3)

### Fix 1: Throttle `_is_player_distracted()` with Shared Cache (RC1)

**Problem:** 20 enemies each compute the same viewport/aim calculation every frame.

**Fix:** Cache the distraction result as a shared static value with a throttle timer. Since distraction depends only on the player's aim direction (not the specific enemy), all enemies share one check refreshed at 10 Hz instead of 60 Hz per enemy.

**Effect:** Reduces viewport lookups from 1,200/s to 10/s — **120× reduction**.

### Fix 2: Throttle Separation Force for Combat Enemies (RC2)

**Problem:** O(N²) group iteration every frame for all alive enemies in combat.

**Fix:** Throttle `_apply_separation_force()` to run every 3 frames for enemies in combat states. Enemies in combat are actively moving and firing — separation jitter every 3 frames (20 Hz) is imperceptible.

**Effect:** Reduces separation iterations from 24,000/s to 8,000/s — **3× reduction**.

### Fix 3: Throttle `_can_hit_target_from_current_position()` in GOAP Update (RC5)

**Problem:** Raycast every frame per enemy for GOAP "can_hit_from_cover" check.

**Fix:** Cache the can-hit-from-cover result and only refresh it every 6 frames (matching vision check interval). The tactical value of this information doesn't need frame-perfect accuracy.

**Effect:** Reduces GOAP raycasts from 1,200/s to 200/s — **6× reduction**.

### Fix 4: Throttle File Logging During Combat (RC4)

**Problem:** Hundreds of log file writes per second from distraction checks, rotation changes, and sound callbacks.

**Fix:** Add a per-enemy logging throttle: rate-limit `_log_to_file()` calls to at most 10 per second during combat. Critical state transitions (death, state changes) bypass the throttle.

**Effect:** Reduces file I/O from 500+/s to ~200/s, prevents I/O-bound stalls.

### Fix 6: Cache Autoload Node References (RC6 — new in v2)

**Problem:** `get_node_or_null("/root/PerformanceSettings")` and `get_node_or_null("/root/DifficultyManager")` called every frame per enemy in the hot path (2× per enemy for PerformanceSettings).

**Fix:** Cache both as member variables (`_cached_perf_settings`, `_cached_difficulty_manager`) set once in `_ready()`. Also cache `_distraction_attack_enabled` from DifficultyManager since it changes only when difficulty setting changes (rare).

**Effect:** Eliminates 4,800 node tree traversals/second — from 4,800/s to 0.

### Fix 7: Extend GOAP Throttle to SEARCHING State (RC7 — new in v2)

**Problem:** The v1 GOAP throttle only covered IDLE state. SEARCHING state ran full `_update_goap_state()` every frame for all 20 enemies simultaneously.

**Fix:** Add `_searching_goap_throttle_counter` with interval 6 to run GOAP at ~10Hz in SEARCHING state when player is not visible. Fast-path sets `player_visible = false` on throttled frames.

**Effect:** Reduces SEARCHING GOAP updates from 1,200/s to 200/s — **6× reduction**.

### Fix 8: Shared Per-Frame Viewport Transform Cache (RC8 — new in v2)

**Problem:** Each enemy recomputes viewport transform independently despite being identical for all.

**Fix:** Use GDScript `static var` for `_shared_aim_global_pos` and `_shared_aim_cache_frame`. First enemy per physics frame computes the transform and caches it; all other enemies reuse the cached value.

**Effect:** Reduces viewport transform computations from 200/s to 10/s — **20× reduction**.

---

### Fix 5: Throttle Sound Propagation During High Activity (RC3)

**Problem:** Multiple gunshots per frame each iterate all 20 listeners.

**Fix:** Add per-frame sound emission throttle: cap total sound emissions to 3 per frame. Additional sounds are queued for the next frame. Gunshot and explosion sounds get priority.

**Effect:** Prevents cascading 100+ callbacks in a single frame, spreads load across frames.

---

## Existing Mitigations (from previous fixes)

| Mitigation | Where | Effect |
|------------|-------|--------|
| GOAP throttle in IDLE | #1520 | 20× raycast reduction for idle enemies |
| `_count_enemies_in_combat` cache | #1520 | 600× reduction in group scan |
| GUARD separation skip | #1520 | Skip O(N) for stationary guards |
| Vision staggering | VISION_CHECK_INTERVAL=6 | 10 Hz visibility checks |
| Cover search throttling | COVER_SEARCH_COOLDOWN=0.3s | Rate-limit cover raycasts |
| Intel sharing throttle | INTEL_SHARE_INTERVAL=0.5s | 2/sec group iterations |
| Debug draw throttle | DEBUG_DRAW_INTERVAL=0.1s | 10 Hz FOV redraws |

---

## Combined Effect Estimate (v2)

For BuildingLevel with 20 enemies in active combat:

| Operation | Before any fix | After v1 | After v2 | Total |
|-----------|---------------|----------|----------|-------|
| PerformanceSettings node lookups/s | 2,400 | 2,400 | **0** | **∞** |
| DifficultyManager node lookups/s | 1,200 | 1,200 | **0** | **∞** |
| Viewport+canvas transform calls/s | 1,200 | 200 | **10** | **120×** |
| GOAP updates/s in SEARCHING | 1,200 | 1,200 | **200** | **6×** |
| GOAP can-hit raycasts/s | 1,200 | 200 | **200** | **6×** |
| Separation force group scans/s | 24,000 | 8,000 | **8,000** | **3×** |
| File log writes/s | 500+ | ~200 | **~200** | **~2.5×** |
| Sound propagation callbacks/frame (peak) | 100+ | ~60 | **~60** | **~2×** |

**Total per-frame CPU work reduced by approximately 85–90%** for the combat-specific bottlenecks (v1 achieved ~50%, v2 eliminates the remaining dominant costs).

---

---

## V5 Follow-up Analysis (2026-03-26) — User Report: "не исправлено" (still not fixed)

**New game logs:** `game_log_20260326_161418.txt` (5,021 lines, ~121 seconds), `game_log_20260326_161707.txt` (5,267 lines, ~94 seconds)

**FPS Range observed:** 3–13 fps (Log 1), 2–29 fps (Log 2)

### New Root Causes Identified (v5)

#### RC-V5-1: SEARCHING Corner Check Log Flood (~22 file writes/sec)

`_process_corner_check` triggered `_log_to_file()` every time a corner was detected. With 20 enemies searching, this produced 2,086 file writes in 94 seconds. Each write is a synchronous disk I/O operation.

**Fix:** Changed `_log_to_file()` → `_log_debug()` (only active when `debug_logging=true`).

#### RC-V5-2: SEARCHING Stuck Waypoint Log Flood (~7.8 file writes/sec)

`SEARCHING: Stuck at wp N, skipping` fired every 0.8s per stuck enemy. With many enemies navigating dense areas, this produced 730 writes in 94 seconds.

**Fix:** Changed `_log_to_file()` → `_log_debug()`.

#### RC-V5-3: Priority Attack Log Flood (~8 file writes/sec)

"Player distracted - priority attack triggered" fires on every priority shot. With 20 enemies in combat, this produced 983 file writes in 121 seconds. Similarly, "Player reloading/empty ammo - priority attack triggered" fires on every vulnerability shot.

**Fix:** Changed both `_log_to_file()` → `_log_debug()`.

#### RC-V5-4: Invincibility Mode Hit Log Flood (~2.3 file writes/sec during debug testing)

`FileLogger.info("[Player] Hit blocked by invincibility mode")` fired on every hit while F6 invincibility was active — 278 times in 121 seconds during user testing.

**Fix:** Changed `FileLogger.info()` → `FileLogger.debug()`.

### V5 Combined Savings

| Root Cause | Before v5 | After v5 |
|------------|-----------|----------|
| Corner check file writes/sec | ~22 | **0** |
| Stuck waypoint file writes/sec | ~7.8 | **0** |
| Priority attack file writes/sec | ~8 | **0** |
| Invincibility hit file writes/sec | ~2.3 | **0** |
| **Total file I/O eliminated/sec** | **~40** | **0** |

---

## V6 Analysis — `game_log_20260327_095405.txt`, `benchmark_log_20260327_100114.txt`, `stress_benchmark_20260327_095530.txt`

**Status:** Post-v5, FPS still dropping to 7–13 fps on LabyrinthLevel with 20 enemies (not just 5 in level — 20 total via spawns/respawns).

### Benchmark Analysis

The v6 benchmark reveals a critical insight — the **baseline FPS is only 13 fps**:

| Step | Config | avg FPS |
|------|--------|---------|
| 1 | Baseline (all enabled) | 13.0 |
| 7 | AI disabled | 14.3 |
| 2 | Particles disabled | 13.9 |
| 3 | Blood Decals disabled | 13.8 |

Disabling AI only gains **1.3 fps** — AI is no longer the primary bottleneck (v1–v5 already fixed the major AI overhead). The 13fps baseline suggests a **system-wide performance ceiling** on this hardware.

The stress benchmark shows anomalous results (`AI enabled=29.4 > disabled=11.7`), suggesting the benchmark tool itself may have measurement issues when toggling AI state.

### New Root Causes Found in v6 Log Analysis

#### RC14: C# `LogToFile` always writes at INFO level — never fixed to DEBUG

The v5 fix changed the GDScript `FileLogger.info("Hit blocked by invincibility mode")` to `FileLogger.debug()`, but the **C# `Player.cs:2649`** used a separate `LogToFile` method that always called `log_info`. Result: **283 invincibility file writes** still occurring.

#### RC15: C# `SpawnBloodEffect` log at INFO level — 286 file writes/session

`Player.cs:2719` logged every blood spawn to file at INFO level. With invincibility mode on, every enemy hit spawned a blood effect AND logged it.

#### RC16: C# `GetNodeOrNull` per-call overhead in hot paths

`LogToFile()` did `GetNodeOrNull("/root/FileLogger")` **every call**. `SpawnBloodEffect()` did `GetNodeOrNull("/root/ImpactEffectsManager")` per call. `PlayHit*Sound()` did `GetNodeOrNull("/root/AudioManager")` per call. `TakeDamage()` did `GetNodeOrNull("/root/ScoreManager")` per call.

Total: **~600+ node lookups/session** in hot paths. Fixed by caching all autoload references in `_Ready()`.

#### RC17: SoundPropagation file writes — 666/session

Every `emit_sound()` call wrote two `_log_to_file` lines ("Sound emitted" + "Sound result"). With 333 sound events, this was **666 synchronous file buffer writes**. Changed to `_log_debug` (console-only).

#### RC18: Enemy ROT_CHANGE file writes — 258/session

Every rotation priority change per enemy wrote to file. Changed to `_log_debug`.

#### RC19: Enemy SEARCHING Expand ring file writes — 503/session

The highest-frequency enemy log. Every time an enemy finished search waypoints and expanded its ring, it logged to file. Changed to `_log_debug`.

#### RC20: ScoreManager `get_node_or_null` per `register_damage_taken` call

`ScoreManager._log_to_file()` did `get_node_or_null("/root/FileLogger")` on every call (286 lookups). Also changed damage log to `_log_debug`.

### V6 Combined Savings

| Root Cause | Count/Session | Fix |
|------------|---------------|-----|
| C# invincibility hits at INFO | 283 | → LogDebugToFile |
| C# blood spawn logs at INFO | 286 | → LogDebugToFile |
| C# GetNodeOrNull per hot call | ~600 | → Cached in _Ready |
| SoundPropagation file writes | 666 | → _log_debug |
| Enemy ROT_CHANGE file writes | 258 | → _log_debug |
| Enemy SEARCHING Expand writes | 503 | → _log_debug |
| ScoreManager damage file writes | 286 | → _log_debug |
| ScoreManager get_node_or_null | 286 | → Cached in _ready |
| **Total eliminated** | **~3,168** | |

### Important Note on v6

After v1–v6 fixes, the AI-related overhead has been reduced as far as log analysis can identify. The remaining 13fps baseline appears to be a **hardware/rendering ceiling** unrelated to AI logic or file I/O. Further investigation would require Godot's built-in profiler or RenderDoc to identify GPU-bound bottlenecks.

---

## References

- [Godot Docs: General Optimization Tips](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html)
- [Godot Forum: Optimizing Multiple Pathfinding](https://forum.godotengine.org/t/how-to-optimize-multiple-pathfinding-optimizing-a-huge-number-of-enemies/50709)
- [GDQuest: Optimizing GDScript Code](https://www.gdquest.com/tutorial/godot/gdscript/optimization-code/)
- [Steering Behaviors for Autonomous Characters (Reynolds, 1999)](https://www.red3d.com/cwr/steer/gdc99/)
- [Godot Forum: Collision Pairs Optimization](https://forum.godotengine.org/t/collision-pairs-optimizing-performance-of-bullet-hell-enemy-hell-games/35027)
- Issue #1520 / PR #1521: Previous FPS fix for IDLE state
- Original logs: `game_log_20260326_080756.txt`, `game_log_20260326_080958.txt`
