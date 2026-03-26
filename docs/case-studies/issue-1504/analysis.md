# Case Study: Issue #1504 — Update Benchmark (Extreme Loads)

## Problem Statement

The existing benchmark in the Performance tab (introduced in Issue #1497) measures FPS while
**disabling** one subsystem at a time.  This passive approach has a significant blind spot:
if the game is running with few enemies and little action, the numbers will look healthy even
on a slow machine.  The issue requests that the benchmark apply **extreme loads** for each
parameter so that problems are clearly visible.

> *"бэнчмарк должен давать экстримальные нагрузки по каждому параметру, чтоб были явно видны
> проблемы (например запускать тестовые сцены или сценарии)"*
>
> Translation: "the benchmark should apply extreme loads for each parameter so that problems
> are clearly visible (e.g. run test scenes or scenarios)"

## Root Cause Analysis

### Current benchmark (Issue #1497) limitations

| Step | What it does | What it misses |
|------|-------------|----------------|
| Baseline | Samples FPS as-is | May have 0 enemies, no shooting |
| Particles disabled | Toggles flag, samples FPS | Particles may not even be firing |
| AI disabled | Toggles flag, samples FPS | AI may not be doing anything costly |
| ... | | |

The measurement window is 3 seconds of **whatever is currently happening** in the game. If the
player is standing idle in the menu, the FPS impact of disabling particles is essentially zero —
because there are no particles to measure.

### Required approach — stress-then-measure

For each subsystem we must:
1. **Apply extreme load** on that subsystem (spawn many enemies, fire many projectiles, etc.)
2. **Sample FPS** under that load (subsystem enabled)
3. **Disable** the subsystem
4. **Sample FPS** again (subsystem disabled under the same load)
5. Calculate the **delta** — this is the true cost of that subsystem

## Research: Known Performance Bottlenecks in Godot Top-Down Games

### GPU Bottlenecks
- **GPUParticles2D** — Each active particle system issues a GPU draw call.  The more particles
  active simultaneously (e.g. muzzle flash × N enemies + impact sparks), the higher the GPU load.
  Known Godot 4 recommendation: reduce particle lifetime and `amount` before shipping.
- **PointLight2D / explosion lights** — Dynamic lights require full-scene shadow re-rendering
  per light.  This is documented as a major bottleneck in Godot's 2D rendering pipeline
  (Godot docs: "PointLight2D is expensive, especially with shadows enabled").
- **Blood decals (Sprite2D)** — Each decal adds a draw call and grows the node count over time.

### CPU Bottlenecks
- **Enemy AI** — Pathfinding (`NavigationAgent2D`) is the most expensive part; each
  `_physics_process` tick for a searching/pursuing enemy calls the nav server.
- **Collision detection** — More enemies = more physics bodies = more collision pair tests.
- **Bullet physics** — Each bullet is an `Area2D` or `CharacterBody2D` iterating overlaps.

### Existing game data
- `MAX_CONCURRENT_ENEMIES: int = 12` in `arena_level.gd` — the current hard cap.
- Enemy types expose `weapon_type`, `min_health`, `max_health`, `enable_cover`,
  `enable_flanking`, `is_grenadier`, `is_teleporter`, `has_force_field`.
- Benchmarking at 20–30 enemies is a realistic worst-case for this game's design.

## Proposed Solution

### Design

Add a **Stress Benchmark** mode alongside the existing passive benchmark.  The stress benchmark:

1. Spawns a configurable number of stress enemies at the centre of the viewport
   (no level scene needed — just physics bodies with AI scripts).
2. For each subsystem:
   a. Enables the subsystem.
   b. Runs the stress scenario for `STRESS_SAMPLE_DURATION` seconds and records FPS.
   c. Disables the subsystem.
   d. Runs the same stress scenario and records FPS.
   e. Cleans up spawned objects.
3. Logs the `enabled_fps`, `disabled_fps`, and `delta_fps` for each subsystem.
4. Restores all settings to their pre-benchmark values when done.

### Key parameters

| Constant | Value | Rationale |
|----------|-------|-----------|
| `STRESS_ENEMY_COUNT` | 20 | Exceeds the arena cap (12), creates visible AI load |
| `STRESS_SAMPLE_DURATION` | 2.0 s | Shorter than passive benchmark — enemies are actively busy |
| `STRESS_BURST_PROJECTILES` | 50 | Fire 50 bullets at once to stress particles + collision |

### Components affected
- `scripts/ui/performance_menu.gd` — main benchmark logic (new `_run_stress_benchmark` coroutine)
- `scenes/ui/PerformanceMenu.tscn` — add "Stress Benchmark" button node
- `tests/unit/test_performance_menu.gd` — new test cases for stress benchmark logic

## Alternative Approaches Considered

### Option A: Load a test scene
Launch an existing level (e.g. `ArenaLevel.tscn`) in the background.  **Rejected** because it
requires scene transitions, breaks the current menu context, and adds complexity without clear
benefit over spawning lightweight stress actors.

### Option B: Existing external libraries
- **Godot Benchmark Plugin** — community plugin for FPS/memory logging.  Overkill for this use-case.
- **GDUnit4** — test framework, not a runtime performance tool.
The existing in-game log approach (FileAccess) is already well-suited.

### Option C (chosen): Inline stress spawning
Spawn dummy `Node2D` nodes with particle/light/AI simulation directly inside the benchmark
coroutine, without needing a full scene change.  Results appear in the same log file.

## Implementation Plan

1. Add `const STRESS_ENEMY_COUNT`, `STRESS_SAMPLE_DURATION`, `STRESS_BURST_PROJECTILES` to
   `performance_menu.gd`.
2. Add helper `_create_stress_particles() -> Array` that instantiates N GPUParticles2D nodes
   and attaches them as children of the menu (removed after each step).
3. Add helper `_create_stress_lights() -> Array` that instantiates N PointLight2D nodes.
4. Add helper `_create_stress_enemies() -> Array` that loads `Enemy.tscn` and spawns N enemies
   at random positions within the viewport (using `set("destroy_on_death", true)`).
5. Rewrite `_run_benchmark` (or add `_run_stress_benchmark`) to:
   - For each subsystem: spawn stressors, measure enabled FPS, disable, measure disabled FPS,
     clean up, log delta.
6. Wire up a new "Stress Benchmark" button in `PerformanceMenu.tscn`.
7. Add unit tests for the new logic in `test_performance_menu.gd`.
