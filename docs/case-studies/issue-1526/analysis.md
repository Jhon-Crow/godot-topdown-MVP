# Case Study: Issue #1526 — Performance Optimization Implementation

## Overview

Issue #1526 asked to fix the performance problems identified in PR #1523 (Issue #1522 benchmark analysis). This case study documents the implementation of four optimizations targeting the root causes found in that analysis.

## Timeline / Sequence of Events

| Date | Event |
|------|-------|
| 2026-03-26 07:06 | Benchmark data collected (Issue #1522) |
| 2026-03-26 ~04:30 | PR #1523 merged — analysis and recommendations published |
| 2026-03-26 | Issue #1526 opened — requesting implementation of the fixes |
| 2026-03-26 | This PR implements all four recommended optimizations |

## Root Causes Identified (from PR #1523 analysis)

### RC1: AI SEARCHING/ASSAULT/PURSUING navmesh path updates every frame

**Evidence:** Benchmark steps 15–17 showed +8.2/+7.3/+4.7 FPS gain when disabled.

**Root cause:** `_get_nav_direction_to()` and `_process_searching_state()` both set `_nav_agent.target_position` every physics frame. This triggers Godot's NavigationServer2D to recalculate the path each frame, even when targets (search waypoints, cover positions) are stationary. With 5 enemies, this means 5 × 60 = 300 path calculations per second.

### RC2: Distraction-attack log spam from `_log_to_file()`

**Evidence:** 408 log entries from 2 enemies in ~100 seconds; inflated AI benchmark delta from ~9 to 28.6 FPS.

**Root cause:** In `enemy.gd` line 1310, the log call fires at the weapon shoot rate (up to 10×/sec per enemy) because it's inside the per-shot code path, not a state-transition path. On Hard difficulty with 20 stress enemies, this generates up to 200 file I/O writes per second.

### RC3: Stress benchmark particle measurement inaccurate

**Evidence:** Particle delta = −0.1 FPS (near zero, understated).

**Root cause:** The "enabled" FPS sample starts immediately after spawning GPUParticles2D nodes. GPU particle pipelines need several frames to ramp up to steady-state emission. The 2-second sample window captures a partially warmed-up state.

### RC4: SceneLoader sync fallback freeze

**Evidence:** `[SceneLoader] ERROR: Invalid resource (falling back to sync): SewerLevel.tscn` at 07:06:51.

**Root cause:** When navigating to a previously loaded scene, `ResourceLoader.load_threaded_request()` succeeds but `load_threaded_get_status()` returns `THREAD_LOAD_INVALID_RESOURCE` because the resource is already in the engine cache. This triggers `_fallback_sync_load()` which blocks the main thread.

## Fixes Implemented

### Fix 1: Rate-limit distraction-attack log (HIGH PRIORITY)

**File:** `scripts/objects/enemy.gd`

**Change:** Added `_distraction_attack_logged` boolean that tracks whether the distraction log has fired for the current episode. Logs once on first trigger, resets when `player_distracted` becomes false (player aims back).

**Impact:** Eliminates 400+ unnecessary file I/O writes per minute during Hard difficulty combat. Improves benchmark accuracy by removing I/O overhead from the AI measurement.

### Fix 2: Stagger navmesh path updates (HIGH PRIORITY)

**File:** `scripts/objects/enemy.gd`

**Change:** Added `_nav_path_update_frame` counter and `NAV_PATH_UPDATE_INTERVAL = 10` constant. In SEARCHING and PURSUING states, `_nav_agent.target_position` is only updated every 10 physics frames (~6×/sec at 60 Hz). Applied to both `_get_nav_direction_to()` and the direct navmesh calls in `_process_searching_state()`.

**Rationale:** SEARCHING targets are stationary waypoints generated in a spiral pattern. PURSUING targets are cover positions that change infrequently. Sub-frame path accuracy is unnecessary for these states. Other states (COMBAT, FLANKING) continue with per-frame updates where responsiveness matters.

**Expected impact:** ~8–13 FPS improvement with 5 enemies (SEARCHING + PURSUING combined). With 20 stress enemies, the reduction from 1200 to ~120 path calculations per second should be substantial.

### Fix 3: Particle warm-up delay (MEDIUM PRIORITY)

**File:** `scripts/ui/performance_menu.gd`

**Change:** Added 1-second `create_timer` delay after spawning stress particles and before the first FPS sample. Applied to both the standalone particle step and the combined step.

**Impact:** Enables accurate measurement of GPU particle cost at steady-state emission. Previous measurements showed ~0 FPS cost which understated the true GPU overhead.

### Fix 4: SceneLoader cache check (LOW PRIORITY)

**File:** `scripts/autoload/scene_loader.gd`

**Change:** Before calling `load_threaded_request()`, checks `ResourceLoader.has_cached()`. If the resource is already cached, uses it directly via `load()` (which returns the cached version instantly) without triggering the threaded load pipeline.

**Impact:** Eliminates the startup freeze when transitioning to previously loaded scenes. The sync fallback (which blocks the main thread) is no longer reached for cached resources.

## Expected Benchmark Results (Before → After)

| Metric | Before | Expected After | Notes |
|--------|--------|----------------|-------|
| SEARCHING disabled delta | +8.2 FPS | ~+1 FPS | Path updates reduced by ~10× |
| PURSUING disabled delta | +4.7 FPS | ~+1 FPS | Path updates reduced by ~10× |
| AI stress delta (20 enemies) | +28.6 FPS | ~+12 FPS | Log I/O overhead removed |
| Particle stress delta | −0.1 FPS | +2–5 FPS (est.) | Accurate steady-state measurement |
| Startup FPS drop | 20 fps | ~40+ fps | Cache path avoids sync load |

## Verification Checklist

- [ ] Run regular benchmark: SEARCHING step delta should drop significantly
- [ ] Run regular benchmark: PURSUING step delta should drop significantly
- [ ] Run stress benchmark: AI delta should be lower (pure CPU cost without log I/O)
- [ ] Run stress benchmark: Particle delta should be positive and meaningful
- [ ] Navigate to SewerLevel: No `Invalid resource` error in log
- [ ] Play on Hard difficulty: `Player distracted` log appears once per episode, not per shot
- [ ] Enemy pathfinding in SEARCHING state still looks smooth (no visible stuttering)
- [ ] Enemy pathfinding in PURSUING state still looks smooth
