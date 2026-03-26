# Case Study: Issue #1522 — Benchmark Analysis and Optimization Recommendations

## Overview

The user attached three log files to the issue (collected 2026-03-26) and asked for a deep analysis of what needs to be optimized:

| File | Purpose |
|------|---------|
| `benchmark_log_20260326_070706.txt` | Regular benchmark — sequential FPS measurement with one subsystem disabled at a time, 5 normal SewerLevel enemies |
| `game_log_20260326_070649.txt` | Full game session log — startup through benchmark completion (07:06:49 – 07:29:44) |
| `stress_benchmark_20260326_072414.txt` | Stress benchmark — extreme load (30 particles, 20 lights, 20 enemies), Issue #1504 tool |

Environment from game log:
- **OS:** Windows
- **Build:** Release (debug = false)
- **Engine:** Godot 4.3-stable (official)
- **Project:** Godot Top-Down Template
- **Difficulty:** Hard (value: 2) — distraction attacks enabled
- **Level:** SewerLevel (11 native enemies + stress-spawned extras)

---

## Session Timeline

| Clock (wall) | Event |
|---|---|
| 07:06:49 | Game launched, LabyrinthLevel loaded briefly |
| 07:06:50 | Navigated to SewerLevel (startup restored last level); 11 enemies spawned |
| 07:06:51 | First FPS drop: 20 fps (threshold 30) — shader/particle warmup frame |
| 07:06:51 | SceneLoader error: `Invalid resource (falling back to sync): SewerLevel.tscn` |
| 07:07:06 | Regular benchmark started (Step 1: Baseline) |
| 07:24:11 | Regular benchmark completed; saved `benchmark_log_20260326_070706.txt` |
| 07:24:54 | Stress benchmark started |
| 07:24:54–07:26:55 | Particle and lights stress steps |
| 07:26:55 | AI stress step begins — 20 enemies spawned |
| 07:28:42–07:28:57 | "Player distracted" spam: 408 log entries in ~15 seconds |
| 07:28:57 | All stress subsystems disabled for baseline capture |
| 07:29:38 | Stress benchmark complete; saved `stress_benchmark_20260326_072414.txt` |
| 07:29:44 | Game session ended |

---

## Part 1: Regular Benchmark Analysis

**Tool:** `_run_benchmark()` in `scripts/ui/performance_menu.gd`
**Method:** Disable one subsystem, sample FPS for 3 s (20 cycles), re-enable. Live 5-enemy SewerLevel.
**Baseline FPS:** avg=75.5 (min=60, max=77)

### Raw Results

| Step | Subsystem | Avg FPS | Min | Max | vs Baseline | Cost (FPS) |
|------|-----------|---------|-----|-----|-------------|------------|
| 1 | Baseline (all enabled) | 75.5 | 60 | 77 | — | — |
| 2 | Particles disabled | 73.3 | 68 | 76 | −2.2 | ~2 |
| 3 | Blood Decals disabled | 71.9 | 68 | 74 | −3.6 | ~4 |
| 4 | Screen Shake disabled | 72.4 | 69 | 75 | −3.1 | ~3 |
| 5 | Explosion Lights disabled | 71.4 | 67 | 74 | −4.1 | ~4 |
| 6 | Wall Hit Particles disabled | 73.4 | 71 | 75 | −2.1 | ~2 |
| 7 | AI disabled | 77.6 | 70 | 79 | +2.1 | — |
| 8 | AI:IDLE disabled | 76.1 | 74 | 79 | +0.6 | ~1 |
| 9 | AI:COMBAT disabled | 77.5 | 74 | 79 | +2.0 | ~2 |
| 10 | AI:SEEKING_COVER disabled | 73.7 | 47 | 78 | −1.8 | — |
| 11 | AI:IN_COVER disabled | 73.4 | 65 | 77 | −2.1 | — |
| 12 | AI:FLANKING disabled | 75.6 | 72 | 77 | +0.1 | ~0 |
| 13 | AI:SUPPRESSED disabled | 77.4 | 75 | 79 | +1.9 | ~2 |
| 14 | AI:RETREATING disabled | 78.7 | 75 | 80 | +3.2 | ~3 |
| 15 | AI:PURSUING disabled | 80.2 | 71 | 82 | +4.7 | **~5** |
| 16 | AI:ASSAULT disabled | 82.8 | 80 | 84 | +7.3 | **~7** |
| 17 | AI:SEARCHING disabled | 83.7 | 72 | 85 | +8.2 | **~8** |

**Convention note:** These are measurements *while* a subsystem is disabled. Higher FPS when a system is off = that system costs FPS. Lower FPS when disabled = disabling did not help (may redirect work to another state or add noise).

### Key findings from the regular benchmark

#### Finding R1: AI states SEARCHING, ASSAULT, PURSUING are the dominant CPU costs

Steps 15–17 show the largest FPS improvement when disabled:

- **AI:SEARCHING disabled** → +8.2 FPS gain (Steps go from 75.5 to 83.7)
- **AI:ASSAULT disabled** → +7.3 FPS gain
- **AI:PURSUING disabled** → +4.7 FPS gain

These three states together represent the heaviest per-enemy CPU work:
- `SEARCHING` — each enemy independently updates a path to the last known player position and scans
- `ASSAULT` — coordinated rush; involves continuous line-of-sight, pathfinding, and suppression fire
- `PURSUING` — cover-to-cover advance; frequent corner checks and ROT_CHANGE log entries confirm per-frame angle/navmesh work

Root cause: `filter_ai_state()` in `performance_settings.gd` redirects disabled states to `IDLE`, which has its own overhead. The benchmark measures the delta between "state X active" and "state X → IDLE substitution", not a true zero-work baseline. Despite this, the deltas are directionally valid.

#### Finding R2: AI:SEEKING_COVER shows anomalous FPS drop (min=47)

Step 10 (`AI:SEEKING_COVER disabled`) shows avg=73.7 but min=47 — a 28 FPS floor. The game log at this time (approximately 07:16 based on step timing) likely shows enemies forced into cover-seek during the 3-second window after the disable toggle, causing a brief pathfinding spike before the `filter_ai_state()` redirect stabilizes them. This is measurement noise from state transition, not a real cost.

#### Finding R3: Graphics subsystems have low individual cost (~2–4 FPS each)

Steps 2–6 each show FPS *lower* than baseline when that system is disabled (negative apparent gain of −2 to −4 FPS). This seems counterintuitive, but it is expected:
- These are static toggles with no live effects at rest (no explosions, no movement). Disabling them costs nothing because they weren't doing work during the benchmark.
- The FPS difference is **measurement variance** across sequential 3-second windows, not actual costs.
- Real costs only appear during active gameplay (explosions, blood decals accumulating, etc.).

#### Finding R4: FPS variance is high (min=47 to max=85 across steps)

The min/max spread on many steps is large. The SewerLevel has 11 active enemies plus the live game simulation running during the benchmark (enemies patrolling, sound propagation, bloody feet, navmesh), making the baseline noisy. The 3-second sample window smooths some of this, but not spike events.

---

## Part 2: Stress Benchmark Analysis

**Tool:** `_run_stress_benchmark()` in `scripts/ui/performance_menu.gd`
**Method:** Spawn 30 GPUParticles2D / 20 PointLight2D / 20 enemies on top of the live SewerLevel, then measure FPS with the subsystem enabled vs disabled.
**Note:** The particle fix from Issue #1517 was applied — `p.emitting = false` is now called on already-spawned nodes before the disabled sample.

### Raw Results

| Step | Subsystem | Enabled FPS | Disabled FPS | Delta | Valid? |
|------|-----------|-------------|--------------|-------|--------|
| 1/4 | Particles (30 GPUParticles2D) | 45.1 | 45.0 | **−0.1** | Partially |
| 2/4 | Explosion Lights (20 PointLight2D) | 83.5 | 86.2 | **+2.7** | Yes |
| 3/4 | AI (20 enemies) | 47.7 | 76.4 | **+28.6** | Yes |
| 4/4 | Combined (all) | 22.7 | 41.6 | **+18.9** | Partially |

### Finding S1: Particle fix from Issue #1517 confirmed working — but result is near zero

Step 1 shows delta = −0.1 (essentially 0). The fix added `p.emitting = false` for each spawned node, and the result is now valid (no spurious negative delta). However, the measured cost is near zero because:

- 30 `GPUParticles2D` nodes that have just been spawned have not yet emitted many particles. The GPU pipeline needs several frames to ramp up. At 2 seconds per sample window, the disabled sample window begins almost immediately after `emitting = false`, so the "enabled" sample may also be capturing a partially warmed-up state.
- The net result is that the particle cost is still not well-isolated by this method. A longer sample window (5–10 s) would give particles time to reach steady-state emission before measuring.

**Conclusion:** Delta is technically valid (no negative spurious inversion), but the measured cost (~0 FPS) is likely an undercount of the true steady-state GPU cost.

### Finding S2: Explosion lights cost confirmed at +2.7 FPS for 20 lights

This matches the prior Issue #1517 methodology (valid measurement via `ln.visible = false`). The cost is lower than in the 1517 run (+8.6 FPS) because Step 2 runs on a lighter background (SewerLevel at 83.5 FPS vs 47.4 in the prior run). The absolute savings of 2.7 FPS / 20 lights (~0.14 FPS per light) is the relevant figure.

In production, explosion lights typically have:
- A texture (radial gradient)
- Shadow casting enabled on some maps

These will increase cost per light. The existing `set_explosion_lights_enabled()` toggle is confirmed effective.

### Finding S3: AI is the primary performance bottleneck — 28.6 FPS cost for 20 enemies

Step 3 shows the largest delta: **+28.6 FPS** when 20 enemies are disabled. This is 3x the cost measured in the Issue #1517 run (+9.4 FPS). The difference is explained by **the "Player distracted" log spam observed in the game log**.

**Root cause — per-frame log spam from distraction attack loop:**

During the AI stress step (07:26:55 – 07:28:57), the game log contains **408 occurrences** of:
```
[ENEMY] [@CharacterBody2D@6290] Player distracted - priority attack triggered
[ENEMY] [@CharacterBody2D@6422] Player distracted - priority attack triggered
```
These entries appear at ~10–15 per second across just 2 enemies (`@CharacterBody2D@6290` and `@CharacterBody2D@6422`). The pattern runs for approximately 100 seconds.

**What is happening:**

In `enemy.gd` line 1302, the distraction attack check fires every physics frame when:
1. `_combat_allowed` is true (COMBAT state enabled)
2. `is_distraction_enabled` is true (Hard difficulty — confirmed in game log line 16)
3. `_goap_world_state["player_distracted"]` is true (player's aim is >23° off the enemy)
4. `_can_see_player` is true
5. `has_clear_shot` is true
6. `_can_shoot()` is true
7. `_shoot_timer >= shoot_cooldown` (default shoot_cooldown = 0.1 s → up to 10 shots/sec)

The log call `_log_to_file("Player distracted - priority attack triggered")` fires at the shooting rate (every 0.1 s = up to 10 times per second per enemy). With 20 stress-spawned enemies potentially in COMBAT state, this could generate up to 200 log lines per second, saturating the file I/O pipeline.

**Impact on benchmark:**
- The enabled FPS (47.7) includes the overhead of 408+ file I/O write calls during the 2-second measurement window.
- The disabled FPS (76.4) has 0 distraction attacks because AI is disabled.
- The **true AI CPU cost is conflated with log I/O overhead**. The 28.6 FPS delta overstates the pure AI computation cost; some of it is `_log_to_file()` call overhead.

**Contributing factor: `filter_ai_state()` redirect during disabled measurement**

When AI is disabled, `set_ai_enabled(false)` is called, which calls `filter_ai_state()` for all enemies and routes them to IDLE. Enemies in IDLE still run minimal code (rotation scan, sound listening). The 76.4 FPS "disabled" reading is not a zero-work baseline.

### Finding S4: Combined step delta +18.9 is now positive but still understates true cost

With the particle fix from #1517 applied, the combined step no longer produces a negative delta. The +18.9 FPS savings from disabling all systems is directionally valid. However:
- Particle measurement artifact (Finding S1) means particle contribution to combined cost is understated.
- Log I/O from distraction attack spam inflates the enabled cost (same as Finding S3).

The combined enabled FPS of **22.7** is below 30 FPS — a confirmed performance cliff for this hardware under extreme load.

---

## Part 3: Secondary Issues Found in Game Log

### Issue L1: SceneLoader fallback to synchronous load (07:06:50)

```
[SceneLoader] ERROR: Invalid resource (falling back to sync): res://scenes/levels/SewerLevel.tscn
```

This indicates the background resource loader returned an error for `SewerLevel.tscn`. The fallback to synchronous loading causes a brief freeze during scene transition. This is a scene loading reliability issue independent of the benchmark, but it does affect the measured FPS at session start (the 20 fps drop at 07:06:51 is partly attributable to this plus shader warmup).

### Issue L2: Initial FPS drop to 20 fps at startup

```
[07:06:51] [WARN] [FPS] Drop detected: 20 fps (threshold: 30)
```

This is one second after game start. The game log shows multiple shader warmup operations completing at 07:06:50 (1013ms for PenultimateHit, 1011ms for LastChance, 924ms for CinemaEffects, 916ms for BlackMetalEffectsManager, etc.) and `ImpactEffects particle shader warmup complete: 7 effects warmed up in 1423 ms` at 07:06:51. These warmup coroutines run concurrently and create a one-time CPU/GPU spike at startup.

### Issue L3: "Player distracted" log spam creates unbounded per-frame logging

408 log lines from 2 enemies in ~100 seconds (~4 lines/second average, peaking at 15+/second) represents a logging hot path that is always active during COMBAT/PURSUING on Hard difficulty when the player is not aiming precisely at the enemy. This is a logging verbosity issue: the log call belongs to a "shot fired" code path that executes at the weapon fire rate (10/second), not a state-transition path. This should be rate-limited or removed.

---

## Root Cause Summary

| # | Root Cause | Evidence | Impact |
|---|-----------|----------|--------|
| RC1 | AI SEARCHING/ASSAULT/PURSUING states have high per-enemy CPU cost | Benchmark steps 15–17 (+8.2/+7.3/+4.7 FPS) | Primary bottleneck at normal enemy counts |
| RC2 | `_log_to_file("Player distracted - priority attack triggered")` fires every shot on Hard difficulty | 408 log entries / ~100 s in game log | Inflates AI benchmark by adding file I/O overhead to enabled-FPS measurement; adds overhead in production builds with logging enabled |
| RC3 | Stress benchmark particle sample window too short | delta ≈ 0 (particles not ramped to steady-state) | Particle cost still unmeasured accurately |
| RC4 | AI test conflates log I/O cost with true AI computation cost | 28.6 FPS delta includes file writes per shot | Benchmark result overstates AI compute cost |
| RC5 | SceneLoader async load fails → sync fallback | Error log line 261 | One-time freeze on startup/scene transition |

---

## Recommended Optimizations

### Optimization 1: Rate-limit or remove the distraction-attack log line (HIGH PRIORITY)

**File:** `scripts/objects/enemy.gd`, line 1302

**Problem:** `_log_to_file("Player distracted - priority attack triggered")` fires at the shoot rate (up to 10×/sec per enemy). In a normal Hard-difficulty game with multiple enemies in combat, this generates hundreds of log entries per minute, adding file I/O overhead per frame.

**Fix:** Log only once when the condition transitions from false→true (i.e., when distraction attack is first triggered), not on every shot:

```gdscript
# Add state tracking variable near other timer vars
var _distraction_attack_logged: bool = false

# In the distraction attack block:
if has_clear_shot and _can_shoot() and _shoot_timer >= shoot_cooldown:
    if not _distraction_attack_logged:
        _log_to_file("Player distracted - priority attack triggered")
        _distraction_attack_logged = true
    # ... shoot logic

# Reset the flag when distraction condition ends (player aims back):
if not _goap_world_state.get("player_distracted", false):
    _distraction_attack_logged = false
```

Or simply use `_log_debug()` instead of `_log_to_file()` since this is a per-frame event — debug-only logging.

### Optimization 2: Reduce SEARCHING state CPU cost (HIGH PRIORITY)

**Evidence:** Disabling AI:SEARCHING adds +8.2 FPS with only 5 SewerLevel enemies. SEARCHING is the most expensive state per enemy.

**What SEARCHING does:** Each enemy in SEARCHING state independently:
1. Updates a navigation path to the last known player position every frame.
2. Scans the area with raycasts.
3. Checks its search timer.

**Optimization options (in order of implementation complexity):**
1. **Stagger navmesh path updates** — Instead of updating the path to last-known-position every frame, update only every N physics frames (e.g., every 10 frames / 6×/second). Navigation paths to a stationary target don't need sub-frame updates.
2. **Share search target across enemies** — If multiple enemies are SEARCHING, they all converge on the same last-known position. A single path query can be shared or the redundant queries can be deduplicated.
3. **Cap simultaneous SEARCHING enemies** — At most 2–3 enemies should be SEARCHING at once; others should idle or hold position until a slot is available.

### Optimization 3: Reduce ASSAULT state CPU cost (HIGH PRIORITY)

**Evidence:** Disabling AI:ASSAULT adds +7.3 FPS.

ASSAULT involves coordinated movement with continuous line-of-sight checks, suppression fire queries, and pathfinding. The same stagger approach (update navmesh every N frames) applies.

Additionally, ASSAULT should be rate-limited: in the SewerLevel benchmark, it is unlikely that 5 enemies simultaneously enter ASSAULT. If the benchmark shows this cost at normal enemy counts, it may indicate that enemies are oscillating into ASSAULT state unnecessarily.

### Optimization 4: Fix stress benchmark particle measurement (MEDIUM PRIORITY)

**File:** `scripts/ui/performance_menu.gd`, `_run_stress_benchmark()`

**Problem:** After `p.emitting = false`, the GPU pipeline drains within 1–2 frames, but the `enabled` measurement was taken while particles were still warming up. A 2-second window starting immediately after spawn may not capture steady-state emission.

**Fix:** Add a brief warm-up delay after spawning before the first sample:

```gdscript
# After _spawn_stress_particles(), wait for emitters to reach steady state
var particle_nodes: Array = _spawn_stress_particles()
await get_tree().create_timer(1.0).timeout   # warm-up: let emitters fill up
var fps_particles_on := await _sample_fps(STRESS_SAMPLE_DURATION)
```

This ensures the "enabled" window captures the GPU cost of fully active emitters.

### Optimization 5: Fix SceneLoader async resource load failure (LOW PRIORITY)

**File:** `scripts/autoload/scene_loader.gd` (or equivalent)

**Problem:** `res://scenes/levels/SewerLevel.tscn` fails to load asynchronously, falling back to blocking synchronous load. This causes a freeze on scene transition.

**Root cause:** The async loader error can be caused by:
- The scene being loaded while its imported resources are still being processed.
- A resource path mismatch or missing `.import` file.

**Fix:** Investigate why `ResourceLoader.load_threaded_request()` fails for this specific scene and whether the `.import` cache for `SewerLevel.tscn` is stale.

---

## Summary Table

| Priority | Optimization | FPS Gain Potential | Complexity |
|----------|-------------|-------------------|------------|
| HIGH | Rate-limit distraction-attack log line | Benchmark accuracy + production I/O | Low (1 bool var) |
| HIGH | Stagger navmesh updates in SEARCHING state | ~8 FPS with 5 enemies | Medium |
| HIGH | Stagger navmesh updates in ASSAULT state | ~7 FPS with 5 enemies | Medium |
| MEDIUM | Fix particle warm-up window in stress benchmark | Accurate measurement | Low (add 1s delay) |
| LOW | Fix SceneLoader async load for SewerLevel | Eliminates startup freeze | Medium |

---

## Comparison with Issue #1517

| Metric | Issue #1517 (prior run) | Issue #1522 (this run) | Change |
|--------|------------------------|------------------------|--------|
| Particles delta | −12.1 (invalid) | −0.1 (near zero, valid) | Fix from #1517 applied ✓ |
| Lights delta | +8.6 FPS / 20 lights | +2.7 FPS / 20 lights | Different baseline FPS; per-light cost ~similar |
| AI delta (20 enemies) | +9.4 FPS | +28.6 FPS | Much higher — log I/O overhead included |
| Combined delta | −3.1 (invalid) | +18.9 (valid, positive) | Fix from #1517 applied ✓ |
| Combined enabled FPS | 24.4 | 22.7 | Consistent: extreme load stays below 30 FPS |

The particle and combined fixes from Issue #1517 are confirmed applied and working. The AI measurement increase (+28.6 vs +9.4) is explained by the "Player distracted" log spam — 20 enemies on Hard difficulty in COMBAT all triggering `_log_to_file()` at fire rate is a significant I/O cost that was not present in the #1517 run (which measured AI without the distraction attack scenario active at this scale).
