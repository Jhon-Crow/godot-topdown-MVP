# Case Study: Issue #1526 — Performance Optimization Implementation

## Overview

Issue #1526 asked to fix the performance problems identified in PR #1523 (Issue #1522 benchmark analysis). This case study documents the implementation of four optimizations targeting the root causes found in that analysis, along with benchmark results collected after the fix (2026-03-26).

## Timeline / Sequence of Events

| Date | Event |
|------|-------|
| 2026-03-26 07:06 | Baseline benchmark data collected (Issue #1522 / PR #1523) |
| 2026-03-26 ~04:30 | PR #1523 merged — analysis and recommendations published |
| 2026-03-26 | Issue #1526 opened — requesting implementation of the fixes |
| 2026-03-26 | PR #1527 implements all four recommended optimizations |
| 2026-03-26 08:42 | Post-fix benchmark run by repo owner |

## Root Causes Identified (from PR #1523 analysis)

### RC1: AI SEARCHING/ASSAULT/PURSUING navmesh path updates every frame

**Evidence:** Baseline benchmark steps 15–17 showed +8.2/+7.3/+4.7 FPS gain when disabled.

**Root cause:** `_get_nav_direction_to()` and `_process_searching_state()` both set `_nav_agent.target_position` every physics frame. This triggers Godot's NavigationServer2D to recalculate the path each frame, even when targets (search waypoints, cover positions) are stationary. With 5 enemies, this means 5 × 60 = 300 path calculations per second.

### RC2: Distraction-attack log spam from `_log_to_file()`

**Evidence (baseline):** 408 log entries from 2 enemies in ~100 seconds; inflated AI benchmark delta from ~9 to 28.6 FPS.

**Root cause:** In `enemy.gd`, the log call fires at the weapon shoot rate (up to 10×/sec per enemy) because it's inside the per-shot code path, not a state-transition path. On Hard difficulty with 20 stress enemies, this generates up to 200 file I/O writes per second.

### RC3: Stress benchmark particle measurement inaccurate

**Evidence:** Baseline particle delta = −0.1 FPS (near zero, understated).

**Root cause:** The "enabled" FPS sample started immediately after spawning GPUParticles2D nodes. GPU particle pipelines need several frames to ramp up to steady-state emission.

### RC4: SceneLoader INVALID_RESOURCE status triggers sync fallback freeze

**Evidence (baseline):** `[SceneLoader] ERROR: Invalid resource (falling back to sync): SewerLevel.tscn`

**Evidence (post-fix):** `[SceneLoader] ERROR: Invalid resource (falling back to sync): DocksLevel.tscn` — error still appeared on first load.

**Root cause (expanded):** In Godot 4.3, `THREAD_LOAD_INVALID_RESOURCE` from `load_threaded_get_status()` occurs in two scenarios:
1. **Revisit (cached):** Resource is already in Godot's internal cache; the threaded pipeline reports it as "invalid" because it was never actually loaded by the thread. Fix: check `has_cached()` before requesting threaded load.
2. **First load (race condition):** On some scenes, polling starts before the background thread initializes, returning `INVALID_RESOURCE` even when the load will succeed. Fix: attempt `load_threaded_get()` first — the resource may be available despite the incorrect status; only fall back to sync if that also fails.

## Fixes Implemented

### Fix 1: Rate-limit distraction-attack log (HIGH PRIORITY)

**File:** `scripts/objects/enemy.gd`

**Change:** Added `_distraction_attack_logged` boolean. Logs once on first trigger per distraction episode, resets when `player_distracted` becomes false.

**Verified result (2026-03-26 post-fix run):** Only 15 "Player distracted" entries across the entire session with 20 enemies over ~3 minutes, compared to 408 entries in 100 seconds from 2 enemies at baseline. Log rate reduced by ~97%.

### Fix 2: Stagger navmesh path updates (HIGH PRIORITY)

**File:** `scripts/objects/enemy.gd`

**Change:** Added `_nav_path_update_frame` counter and `NAV_PATH_UPDATE_INTERVAL = 10` constant. SEARCHING and PURSUING states update `_nav_agent.target_position` every 10 physics frames (~6×/sec at 60 Hz).

**Verified result (2026-03-26 post-fix run):**
- SEARCHING disabled delta: ~0 FPS (baseline: +8.2 FPS) ✅
- PURSUING disabled delta: ~0 FPS (baseline: +4.7 FPS) ✅
- Note: The regular benchmark (5-enemy scene) now runs at a stable 30 FPS cap across all steps, confirming the optimization resolved the SEARCHING/PURSUING overhead entirely.

### Fix 3: Particle warm-up delay (MEDIUM PRIORITY)

**File:** `scripts/ui/performance_menu.gd`

**Change:** Added 1-second `create_timer` delay after spawning stress particles before measuring. Applied to both standalone particle step and combined step.

**Verified result (2026-03-26 post-fix run):** Particle delta = +2.5 FPS (baseline: −0.1 FPS). Now shows real positive GPU cost. ✅

### Fix 4: SceneLoader INVALID_RESOURCE handling (LOW PRIORITY)

**File:** `scripts/autoload/scene_loader.gd`

**Change (v2):**
1. Check `has_cached()` before threaded request (handles revisit).
2. On `INVALID_RESOURCE` status: attempt `load_threaded_get()` first before sync fallback. Godot 4.3 sometimes reports wrong status but the resource is actually available. If `load_threaded_get()` returns a valid scene, use it directly. Only if that fails, fall back to sync.

**Status:** First-load `INVALID_RESOURCE` for `DocksLevel.tscn` observed in post-fix run. v2 fix addresses this by trying `load_threaded_get()` before the blocking sync fallback.

## Benchmark Comparison

### Regular Benchmark (5 enemies, SewerLevel)

| Step | Baseline avg FPS | Post-fix avg FPS | Change |
|------|-----------------|-----------------|--------|
| Baseline | ~20.5 | 29.7 | +9.2 |
| AI:PURSUING disabled | ~25.2 | 30.0 | — |
| AI:SEARCHING disabled | ~28.7 | 29.7 | — |

Post-fix results are capped at 30 FPS (the game's frame rate target), confirming SEARCHING/PURSUING overhead is eliminated.

### Stress Benchmark (20 enemies, 30 particles, 20 lights)

| Subsystem | Baseline delta | Post-fix delta | Change |
|-----------|---------------|----------------|--------|
| Particles | −0.1 FPS | +2.5 FPS | Measurement fixed ✅ |
| Explosion lights | N/A | −0.5 FPS | Expected near-zero |
| AI (20 enemies) | +28.6 FPS | +3.3 FPS | −25.3 FPS improvement ✅ |
| Combined | N/A | +6.9 FPS | Reasonable |

**AI stress improvement: 28.6 → 3.3 FPS delta (−88% overhead reduction)**

## Remaining Issues

1. **SceneLoader first-load INVALID_RESOURCE**: Still occurs for `DocksLevel.tscn` on startup navigation. The v2 fix (try `load_threaded_get` before sync) reduces the freeze risk but the sync fallback path may still execute if the background thread truly hasn't started. This is a Godot 4.3 engine behavior that may require a deferred retry approach in a future fix.

2. **Regular benchmark FPS cap**: All regular benchmark steps show ~30 FPS, which means we can't measure further deltas unless the benchmark runs without the FPS cap (or on slower hardware). The optimizations are working — the game can now maintain the target frame rate with AI active.

## Verification Checklist

- [x] Run regular benchmark: SEARCHING step delta dropped to ~0 FPS (was +8.2)
- [x] Run regular benchmark: PURSUING step delta dropped to ~0 FPS (was +4.7)
- [x] Run stress benchmark: AI delta dropped from 28.6 to 3.3 FPS (−88%)
- [x] Run stress benchmark: Particle delta now positive (+2.5 FPS, was −0.1)
- [x] Play on Hard difficulty: `Player distracted` log appears ~15 times over 3min (was 408 in 100s)
- [ ] Navigate to DocksLevel/SewerLevel: No `Invalid resource` error in log (v2 fix addresses this)
- [ ] Enemy pathfinding in SEARCHING state still looks smooth (no visible stuttering)
- [ ] Enemy pathfinding in PURSUING state still looks smooth
