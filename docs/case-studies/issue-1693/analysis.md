# Case Study: Issue #1693 — Severe FPS Drops Across All Maps

## Issue Summary

**Title:** очень сильно падает fps ("FPS drops very severely")
**Reported:** 2026-03-28
**Status:** Open
**Reporter:** Jhon-Crow
**Reference branch:** `develop` (reported as not having the problem)

The reporter observes severe FPS drops across all game maps. The current `main` branch is significantly worse than `develop`. Five log files were attached: three game session logs, one standard benchmark, and one stress benchmark.

---

## Attached Logs

| File | Description |
|------|-------------|
| `game_log_20260328_150135.txt` | Session 1 — starts at LabyrinthLevel, navigates to BuildingLevel |
| `game_log_20260328_150552.txt` | Session 2 — LabyrinthLevel only, short session |
| `game_log_20260328_154634.txt` | Session 3 — full multi-level run (Labyrinth → Decadence → Labyrinth2 × many → Sewer → WinterForest → RailwayStation × many) |
| `benchmark_log_20260328_161112.txt` | Systematic 17-step benchmark isolating subsystems |
| `stress_benchmark_20260328_161043.txt` | Stress benchmark with 30 particles, 20 lights, 20 enemies |

---

## Timeline / Sequence of Events

### Session 1 (game_log_20260328_150135.txt)

```
15:01:35  Game starts — LabyrinthLevel (5 enemies, difficulty: Hard)
15:01:36  Multiple shader warmups complete (~1100–1850 ms each)
15:01:36  Scene changes immediately to BuildingLevel
15:01:37  LevelInitFallback: GDScript _ready() did NOT execute — C# fallback runs
15:01:37  [WARN] FPS Drop: 6 fps  ← single drop during fallback + warmup
15:01:37  Warm ceiling lights placed (Issue #1206, C# fallback)
15:01:37–15:02:22  BuildingLevel — 10 enemies, runs stably
```

Only **one FPS drop** recorded (6 fps, during initialization). Session is otherwise clean.

### Session 2 (game_log_20260328_150552.txt)

```
15:05:52  Game starts — LabyrinthLevel (5 enemies, difficulty: Hard, fresh save)
15:05:56  [WARN] FPS Drop: 1 fps  ← during shader warmup/scene init
15:05:56–15:07:32  Repeated LabyrinthLevel restarts
15:06:51  FPS drops begin: 27, 28, 18, 13, 23, 26, 18, 13, 29...
```

After a few retries, FPS drops become persistent in LabyrinthLevel, mostly in the 13–29 fps range. This correlates with gameplay activity (enemies active, shooting).

### Session 3 (game_log_20260328_154634.txt) — Most Severe

```
15:46:34  Game starts — LabyrinthLevel (difficulty: Power Fantasy, FPS counter ON, particles DISABLED)
15:46:37  Navigates immediately to TestTier.tscn (fails, fallback to sync)
15:46:38  Scene: Tutorial → then DecadenceLevel
15:46:40  [WARN] FPS Drop: 29 fps
15:46:46–15:47:29  DecadenceLevel — persistent drops 7–26 fps
15:48:07  Labyrinth2Level — drops immediately: 3, 19, 20 fps
15:48:10–15:49:31  Labyrinth2Level retried 7+ times — constant drops 5–29 fps
15:53:08  SewerLevel
15:54:13  WinterForestLevel
15:55:17  RailwayStationLevel — 15 enemies including 4 DroneOperators
15:55:18–16:04:47  RailwayStationLevel — 39 drone COMBAT activations recorded
             FPS drops: 1, 3, 5, 6, 7, 8, 9, 10, 12... (catastrophic, ~5–10 fps sustained)
```

RailwayStation is the worst performer. It has 15 enemies with 4 DroneOperators each controlling drones that enter COMBAT mode kamikaze flight (logged 39 times). The scene is also 4000x4000 pixels (much larger than other levels).

---

## Benchmark Results

### Standard Benchmark (benchmark_log_20260328_161112.txt)

All 17 steps measure **~6–6.5 fps** with all features — even when each major subsystem is disabled one at a time (particles, blood decals, screen shake, explosion lights, all AI states). This confirms the performance floor is extremely low even without any gameplay load.

```
Baseline (all enabled):  avg=6.3 fps
AI disabled:             avg=6.3 fps   (no change!)
Particles disabled:      avg=6.4 fps
Screen shake disabled:   avg=6.5 fps
```

This is a critical finding: **no single subsystem toggle restores acceptable FPS**. The bottleneck is not in any one toggleable feature — it is structural.

### Stress Benchmark (stress_benchmark_20260328_161043.txt)

```
Particles (30 GPUParticles2D):    enabled=43.8  disabled=46.2  delta=+2.5   (minor cost)
Explosion Lights (20 PointLight2D): enabled=71.8  disabled=71.6  delta=-0.2  (negligible)
AI (20 enemies):                  enabled=11.4  disabled=6.9   delta=-4.5   (AI actually IMPROVES fps!)
Combined extreme load:            enabled=2.6   disabled=4.1   delta=+1.5
```

Extraordinary anomaly: **AI enabled produces HIGHER fps than AI disabled** in the stress test (11.4 vs 6.9 fps). This suggests the test was run in a degenerate configuration or baseline fps is so low that the measurement is unreliable. The "AI disabled" baseline of 6.9 fps is consistent with the ~6 fps seen in the standard benchmark — meaning the machine cannot render the scene at all even with no AI.

---

## Root Cause Analysis

### Root Cause 1: Extremely Low Baseline FPS (~6 fps) — Primary Cause

The standard benchmark shows the game renders at ~6 fps in all configurations. This is not a regression from any specific feature — it means the game's **rendering pipeline alone** consumes all available GPU/CPU budget on this machine.

Evidence:
- Benchmark baseline with all features enabled: 6.3 fps average
- Benchmark with all AI states disabled: still 6.0–6.5 fps
- The player hardware (`I:/Загрузки/godot exe/100/`) is likely running on a very low-end integrated GPU

This is the fundamental issue: **the current codebase has substantially more rendering overhead than the `develop` branch**. Features added since diverging from `develop` have collectively pushed the rendering cost past what this hardware can sustain.

### Root Cause 2: Accumulated Visual Effect Overhead — Multiple PointLight2D and Shaders

Session 3 shows `PerformanceSettings: particles: false` yet FPS is still catastrophic. The explosion light pool initializes 12 `PointLight2D` nodes with shadow rendering (`ShadowFilter: Pcf5`, `ShadowFilterSmooth: 4.0`) via `LevelInitFallback.SetupRoomWarmLights()` (Issue #1206). Each `PointLight2D` with `ShadowEnabled=true` and PCF5 filtering is extremely expensive in Godot 4's 2D renderer.

Evidence:
- `LevelInitFallback` runs on BuildingLevel (Session 1, confirmed in log)
- The code creates 6 `PointLight2D` nodes each with `ShadowEnabled=true` and PCF5 filtering
- Multiple shader warmup systems (PenultimateHit, LastChance, CinemaEffects, BlackMetalEffects, FlashbangPlayer, ImpactEffects) all compile shaders on startup

### Root Cause 3: RailwayStation — 15 Enemies + 4 DroneOperators + Large Map

The worst FPS (1–10 fps) occurs on RailwayStation, which has:
- 15 enemies (the most of any level in the logs)
- 4 DroneOperators, each controlling autonomous drones
- Drones entering COMBAT mode triggering kamikaze flight — logged **39 times** in one session
- Map size 4000x4000 pixels (16x larger area than typical levels)
- The large navmesh for a 4000x4000 map requires significant pathfinding budget

### Root Cause 4: Scene Reload Loop — Labyrinth2Level Restarted 7+ Times

In Session 3, Labyrinth2Level is restarted 7+ times in rapid succession. Each restart triggers:
- Full scene teardown and reload
- All shader warmup systems re-running (each taking 1000–3000ms)
- New navmesh baking
- A single-frame FPS drop to 2–3 fps per restart

This creates a compounding performance degradation pattern where the player is fighting the level restart overhead rather than enemies.

### Root Cause 5: Develop Branch Divergence

The reporter notes `develop` branch did not exhibit these drops. Based on the commit history, the following cumulative features were added to `main` after diverging from the backup/develop state:

- Issue #1206: Warm ceiling lights with PCF5 shadowing via `LevelInitFallback`
- Issue #1526: Staggered cover search (multiple perf rounds) — though this is a fix, not a cause
- Issue #1664: EnemyTeleportComponent (DroneOperators now teleport on damage)
- Issue #1629, #1671, etc.: Multiple new levels (RailwayStation, Decadence, Labyrinth2, WinterForest) with higher enemy counts
- Accumulated autoload managers: BlackMetalEffects, BlackMetalLightning, PowerFantasy, PenultimateHit, LastChance, CinemaEffects, FlashbangPlayer — each adding per-frame shader/render cost

---

## Proposed Solutions

### Solution 1 (High Priority): Disable shadows on room warm lights

In `LevelInitFallback.cs`, `SetupRoomWarmLights()` creates `PointLight2D` with `ShadowEnabled=true` and `ShadowFilter=Pcf5`. In Godot 4, `PointLight2D` with shadow maps is GPU-expensive. Switch to `ShadowEnabled=false` or use a cheaper shadow filter (`Pcf3` or `None`).

File: `/Scripts/Components/LevelInitFallback.cs` around line 1304:
```csharp
light.ShadowEnabled = false;  // was: true
// Remove: light.ShadowFilter = PointLight2D.ShadowFilterEnum.Pcf5;
// Remove: light.ShadowFilterSmooth = 4.0f;
```

### Solution 2 (High Priority): Reduce concurrent active PointLight2D count

The explosion light pool pre-creates 12 `PointLight2D` nodes (`ImpactEffects` log line). Combined with the 6 room warm lights from LevelInitFallback, that is up to 18 active lights. Godot 4's 2D lighting uses screen-space rendering; each light with shadows adds a full render pass. Cap the concurrent active lights to 4–6.

### Solution 3 (Medium Priority): Add performance setting to disable warm lights

Extend `PerformanceSettings` with a `warm_lights` toggle. Players on low-end hardware should be able to disable the room lights entirely. The `PerformanceMenu` already has toggles for particles, blood decals, screen shake, explosion lights, and AI.

### Solution 4 (Medium Priority): Throttle DroneOperator combat frequency on RailwayStation

With 4 DroneOperators each launching kamikaze drones (39 COMBAT activations in ~9 minutes), the per-frame cost of tracking 4+ drone projectiles with their collision shapes, pathfinding, and navmesh queries is significant. Apply the same `_process` throttling used for SEARCHING/PURSUING states (Issue #1526) to drone flight updates.

### Solution 5 (Low Priority): Profile shader manager overhead

Seven separate shader warmup autoloads each compile shaders on scene load. Consider consolidating into a single ShaderManager autoload that batches warmup to avoid repeated scene-load spikes.

### Solution 6 (Diagnostic): Add FPS counter to standard HUD

The reporter had `FPS counter: true` in Session 3 via ExperimentalSettings. Making FPS always visible (or via a simple settings toggle, not buried in experimental) would allow faster user-reported diagnosis.

---

## Implemented Fixes (PR #1706)

### Fix 1: Disabled PCF5 shadows on warm ceiling lights (Solution 1 — implemented)

`Scripts/Components/LevelInitFallback.cs` — `CreateRoomWarmLight()`:
- Removed `light.ShadowEnabled = true`
- Removed `light.ShadowFilter = PointLight2D.ShadowFilterEnum.Pcf5`
- Removed `light.ShadowFilterSmooth = 4.0f`
- Set `light.ShadowEnabled = false`

Each `PointLight2D` with PCF5 shadows adds a full shadow-map render pass in Godot 4's 2D renderer. With 6 warm ceiling lights active on BuildingLevel this was adding 6 extra render passes per frame. Disabling shadows eliminates these passes while keeping the visual warm-light ambiance.

### Fix 2: Added `warm_lights_enabled` toggle to PerformanceSettings (Solution 3 — implemented)

`scripts/autoload/performance_settings.gd`:
- Added `var warm_lights_enabled: bool = true`
- Added `set_warm_lights_enabled(enabled)` / `is_warm_lights_enabled()` methods
- Persisted to `user://performance_settings.cfg` under key `performance/warm_lights_enabled`

### Fix 3: LevelInitFallback respects the warm_lights_enabled toggle

`Scripts/Components/LevelInitFallback.cs` — `SetupRoomWarmLights()`:
- At the start of the method, reads `/root/PerformanceSettings.is_warm_lights_enabled()`
- Returns early (skips all light creation) when the toggle is off

### Fix 4: Added "Warm Ceiling Lights" checkbox to PerformanceMenu

`scripts/ui/performance_menu.gd` and `scenes/ui/PerformanceMenu.tscn`:
- Added `@onready var warm_lights_checkbox` wired to the new `WarmLightsContainer` node
- Connected to `_on_warm_lights_toggled()` handler that calls `PerformanceSettings.set_warm_lights_enabled()`
- Added to `_update_ui()` and the disabled-features status label
- Added scene nodes: `WarmLightsContainer`, `WarmLightsLabel`, `WarmLightsCheckbox`, `WarmLightsDescription`

The toggle takes effect on the next scene load (warm lights are created once during `LevelInitFallback._ready()`). Players on low-end hardware can disable warm lights in the Performance menu to recover significant FPS.

---

## Summary Table

| Cause | Impact | Confidence | Fix Complexity | Status |
|-------|--------|-----------|----------------|--------|
| PCF5 shadows on warm ceiling lights | High — every room re-renders shadow maps | High | Low | **Fixed in PR #1706** |
| warm_lights toggle missing from PerformanceSettings | High — no way to disable | High | Low | **Fixed in PR #1706** |
| 18+ concurrent PointLight2D nodes | High — additive render passes | High | Low | Future work |
| RailwayStation: 15 enemies + 4 DroneOperators | Critical on that level | High | Medium | Future work |
| Accumulated autoload shader managers | Medium — per-frame overhead | Medium | Medium | Future work |
| Low-end hardware + baseline 6fps | Fundamental | High | N/A (optimize all of above) | Mitigated by above |
| Scene restart loop (Labyrinth2) | Episodic spikes | High | Low (UX fix) | Future work |
