# Case Study: Issue #1189 — Godot Performance Optimization (FPS Drops / Underutilized RAM)

## Problem Statement

The game experiences severe FPS drops while system RAM is underutilized. This indicates the bottleneck is **CPU-bound, single-threaded work** — not a lack of memory.

---

## Root Cause Analysis

### 1. Physics Runs on the Main Thread (Default)

By default in Godot 4, all `_physics_process()` calls execute on the **main thread**, serialized with rendering. This means even if the OS has 8 cores, the game only uses one core for all game logic + rendering.

**Identified heavy `_physics_process()` work per enemy per frame:**
- 5× raycast for player visibility check (`vision_component.gd`)
- GOAP A\* planner evaluation (`goap_planner.gd`)
- 13+ AI state handlers (`enemy.gd:1191–2430`)
- NavigationAgent2D path query
- Sound propagation listener checks

With 9+ enemies (CityLevel has 9), this means **45+ raycasts per physics frame** for vision alone.

### 2. Vision Raycasts Are Excessively Frequent

`VisionComponent.check_visibility()` is called every `_physics_process()` frame (60× per second by default). Each call performs:
- 1 center raycast (line-of-sight check)
- Up to 5 additional raycasts (visibility ratio: center + top/bottom/left/right)

**Total: 6 raycasts per enemy per frame × 9 enemies = 54 raycasts/frame at 60 Hz.**

Enemies' reaction time is `detection_delay = 0.2s`. Checking vision 60×/sec while enemies can only respond every 200ms is wasteful — checking at 20 Hz (every 3rd physics frame) is imperceptibly different to the player.

### 3. Physics Interpolation Disabled (jitter)

Without `physics/common/physics_interpolation`, visual positions are only updated at the physics tick rate (60 Hz). On frames rendered between physics ticks, objects appear to stutter/jitter because their visual position is not interpolated.

### 4. Object Pooling: Already Well Implemented

`ProjectilePoolManager` (`scripts/autoload/projectile_pool_manager.gd`) pre-allocates 300 bullets, 150 shrapnel, and 200 breaker shrapnel at startup. **This is not a bottleneck.**

### 5. RAM Underutilization Explained

The game uses `gl_compatibility` renderer (already set in `project.godot`) and pre-allocates projectile pools at startup. RAM usage is intentionally conservative. The performance problem is CPU (specifically single-threaded main thread saturation), not memory.

---

## Online Research Findings

Sources: [Godot CPU Optimization](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html), [Thread-safe APIs](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html), [Jitter/Stutter Fix](https://docs.godotengine.org/en/stable/tutorials/rendering/jitter_stutter.html), [WorkerThreadPool](https://docs.godotengine.org/en/stable/classes/class_workerthreadpool.html)

### Key Findings

| Setting | Default | Recommended | Impact |
|---------|---------|-------------|--------|
| `physics/2d/run_on_separate_thread` | `false` | `true` | Moves all `_physics_process()` off main thread |
| `physics/common/physics_interpolation` | `false` | `true` | Eliminates inter-tick visual jitter |
| Vision check frequency | 60 Hz | 10–20 Hz | Reduces raycasts by 66–83% |
| `threading/worker_pool/max_threads` | `-1` (auto) | `-1` (auto) | Already uses all CPU cores for background tasks |

### Why RAM Is Underutilized

RAM ≠ performance in a CPU-bound game. The engine is waiting on the main thread to complete its work each frame. Adding more RAM would not help. The fix is to distribute CPU work across threads (physics thread separation) and reduce per-frame work (vision throttling).

---

## Implemented Solutions

### Solution 1: Enable 2D Physics on a Separate Thread (`project.godot`)

```ini
[physics]
2d/run_on_separate_thread=true
common/physics_interpolation=true
```

**Effect:** All `_physics_process()` calls (enemy AI, raycasts, pathfinding) move off the main thread. The main thread is freed to handle rendering and input. On a 4-core CPU, this roughly doubles available CPU budget for game logic.

**Caveat:** Scene tree modifications from physics callbacks must use `call_deferred()`. The existing codebase already uses this pattern (e.g., `ProjectilePoolManager` uses deferred calls).

### Solution 2: Throttle Vision Raycasts (`vision_component.gd`)

Added a configurable `vision_check_interval` (seconds between full vision checks). The component tracks elapsed time and only runs the full 5-raycast visibility calculation when the interval has passed. Between checks, the last known visibility state is preserved.

**Default interval: 0.05s (20 checks/second)** — reduces raycasts by 66% compared to 60 Hz physics, while keeping enemy reaction time accurate to within 50ms (imperceptible at normal gameplay speed).

**Configurable via Experimental Menu** (`vision_check_interval_seconds` setting, range 0.0–0.2s).

### Solution 3: Vision Check Interval Tunable in Experimental Menu

Added a slider in the Experimental Menu to let developers tune the vision check interval from 0.0s (every physics frame, legacy) to 0.2s (5 Hz, aggressive throttle for low-end hardware).

---

## Measured Impact (Theoretical)

| Scenario | Before | After |
|----------|--------|-------|
| Vision raycasts/frame (9 enemies, 60 Hz physics) | 54 | ~18 (at 0.05s interval) |
| Physics thread | Main thread (shared with render) | Dedicated thread |
| Inter-tick visual jitter | Present | Eliminated by interpolation |

---

## Possible Future Optimizations (Not Implemented)

1. **WorkerThreadPool for AI planning**: Move GOAP A\* search to `WorkerThreadPool.add_group_task()` for parallel enemy AI evaluation. Requires careful thread-safety review of `enemy.gd`.
2. **LOD for distant enemies**: Enemies far from the player reduce their AI update frequency automatically.
3. **Cover detection caching**: Cache the 16-raycast cover search result for 0.5–1.0s instead of recalculating every time an enemy seeks cover.
4. **Sound listener cleanup**: Replace per-emit `filter()` allocation in `sound_propagation.gd` with an index-based sweep, avoiding GC pressure.
5. **Texture atlas**: Verify all bullet/enemy sprites use a shared texture atlas to minimize draw calls.

---

---

## Bug: Laser Sight Broken by Physics Thread Separation

**Report** (2026-03-20, `game_log_20260320_080136.txt`): After enabling `2d/run_on_separate_thread=true`, the laser sight (`LaserSight` Line2D on all weapons) stopped working correctly.

### Root Cause

All weapon classes (`MakarovPM`, `AKGL`, `Shotgun`, `Revolver`, `MiniUzi`, `SniperRifle`, `AssaultRifle`, `SilencedPistol`) called `UpdateLaserSight()` inside `_Process()` (the **render/main thread**). Inside `UpdateLaserSight()`, each weapon called:

```csharp
var spaceState = GetWorld2D()?.DirectSpaceState;
var result = spaceState.IntersectRay(query);
```

`DirectSpaceState` is owned by the **physics thread**. Calling it from `_Process()` (render thread) while `2d/run_on_separate_thread=true` is a **thread-safety violation** — it can produce incorrect results, crashes, or silent failures.

**Source:** Godot docs on [Thread-safe APIs](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html) — physics space state must only be accessed from `_physics_process()` when using a separate physics thread.

### Fix

Moved all `UpdateLaserSight()` calls from `_Process()` to `_PhysicsProcess()` in each of the 8 weapon files. The laser sight runs at 60 Hz physics rate — sufficient for a visual aim indicator.

---

## Files Changed

| File | Change |
|------|--------|
| `project.godot` | Added `physics/2d/run_on_separate_thread=true`, `physics/common/physics_interpolation=true` |
| `scripts/components/vision_component.gd` | Added `vision_check_interval` + timer-based throttling |
| `scripts/autoload/experimental_settings.gd` | Added `vision_check_interval_seconds` setting with save/load |
| `scripts/ui/experimental_menu.gd` | Added slider for vision check interval |
| `scenes/ui/ExperimentalMenu.tscn` | Added UI nodes for vision check interval slider |
| `Scripts/Weapons/MakarovPM.cs` | Moved `UpdateLaserSight()` to `_PhysicsProcess()` (thread safety) |
| `Scripts/Weapons/AKGL.cs` | Moved `UpdateLaserSight()` to `_PhysicsProcess()` (thread safety) |
| `Scripts/Weapons/Shotgun.cs` | Moved `UpdateLaserSight()` to `_PhysicsProcess()` (thread safety) |
| `Scripts/Weapons/Revolver.cs` | Moved `UpdateLaserSight()` to `_PhysicsProcess()` (thread safety) |
| `Scripts/Weapons/MiniUzi.cs` | Moved `UpdateLaserSight()` to `_PhysicsProcess()` (thread safety) |
| `Scripts/Weapons/SniperRifle.cs` | Moved `UpdateLaserSight()` to `_PhysicsProcess()` (thread safety) |
| `Scripts/Weapons/AssaultRifle.cs` | Moved `UpdateLaserSight()` to `_PhysicsProcess()` (thread safety) |
| `Scripts/Weapons/SilencedPistol.cs` | Moved `UpdateLaserSight()` to `_PhysicsProcess()` (thread safety) |
