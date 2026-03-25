# Case Study: Issue #1487 — Optimize Dust Particles (30 FPS Loss)

## Summary

**Issue**: Dust particles cause ~30 FPS loss during sustained fire at walls.
**Author report**: "оптимизируй частицы пыли (сейчас потеря 30fps)" — Optimize dust particles (currently losing 30 FPS).
**Linked hint**: Reddit post on Godot physics/particle optimization.

---

## Data Collected

### Log File

`game_log_20260325_050601.txt` — released build, Windows, Godot 4.3-stable, LabyrinthLevel.

| Time | Event |
|------|-------|
| 05:06:01 | Game start. Dust pool initialized: 16 effects pre-created. `wall_hit_particles: true`. |
| 05:06:03 | **FPS drop: 28 fps** (threshold: 30). Level LabyrinthLevel, 5 enemies. Very early — likely scene load + cinema shader. |
| 05:06:28 | **FPS drop: 29 fps**. Level with 10 enemies. Active gameplay (ReplayManager recording frames). |
| 05:06:32 | **FPS drop: 29 fps**. Still 10 enemies, active gameplay. |

Key settings from log:
- `particles_enabled: true` (PerformanceSettings)
- `wall_hit_particles: true` (GameplaySettings)
- `FPS drop logging: true` (ExperimentalSettings)
- `blood_decals scheduled: 15–30 per hit` (blood system active)
- Released build (not debug) — so `_debug_effects` is OFF, `print()` spam not a factor.

---

## Root Cause Analysis

### Current DustEffect Parameters (scenes/effects/DustEffect.tscn)

```
amount = 25
lifetime = 2.5s
cleanup_delay = 1.0s  (total pool return: 3.5s)
explosiveness = 0.85
```

### Calculation: Active Particles at Sustained Fire

| Weapon | Fire rate | Active effects at once | Active particles |
|--------|-----------|----------------------|-----------------|
| Mini UZI | ~15/sec | 15 × 2.5 = 37.5 → capped at 16 | 16 × 25 = **400** |
| AK+GL | ~7/sec | 7 × 2.5 = 17.5 → capped at 16 | 16 × 25 = **400** |
| Shotgun | ~1.5/sec | 1.5 × 2.5 = 3.75 | ~4 × 25 = **100** |

With the pool cap at 16 and 25 particles each: **400 active GPU particles** from dust alone during sustained rapid fire. Each GPUParticles2D node runs a particle simulation step every frame on the GPU, and the CPU must issue draw calls for each visible node. 16 nodes × per-node overhead = measurable GPU/CPU cost.

### Key Performance Bottlenecks Identified

1. **Too many particles per effect** (`amount=25`): Each wall hit spawns 25 GPU particles. At max concurrency (16 effects), this is 400 simultaneous particles from dust alone, plus blood, sparks, and other effects.

2. **Too long lifetime** (`lifetime=2.5s`): Each dust cloud persists for 2.5 seconds. This means old dust clouds overlap with new ones during sustained fire, keeping many effects alive simultaneously.

3. **No fixed_fps on particles**: Without `fixed_fps` set, GPUParticles2D simulates at the game's full framerate (typically 60 FPS). Dust particles don't need sub-frame precision — they can be simulated at 15–20 FPS with no visible quality loss.

4. **No per-quality-level control**: Players on low-end hardware have no option to reduce dust quality short of disabling it entirely. A "half quality" option would help significantly.

5. **Pool size matches concurrent limit** (both 16): When all 16 pool slots are in use, new effects are silently dropped. During rapid fire with AK+GL (7 shots/sec × 2.5s = 17 desired active), about one effect per 2 seconds gets dropped. This is fine from a visual standpoint but means the limit is already tight — the visual quality loss from adding more effects would exceed the FPS benefit.

---

## Research: Godot GPUParticles2D Optimization Techniques

### 1. Reduce `amount` (particle count)

**Source**: Godot docs — [Particles optimization](https://docs.godotengine.org/en/stable/tutorials/performance/gpu_optimization.html#particles)

Reducing `amount` is the single most impactful change. GPU particle simulation cost scales linearly with particle count per node. For a dust puff at wall-hit distance (small effect), 8–12 particles are visually sufficient.

**Before**: `amount = 25` → 400 particles at max concurrency
**After**: `amount = 12` → 192 particles at max concurrency (−52%)

### 2. Reduce `lifetime`

Shorter lifetime = fewer simultaneously active effects. A dust puff dissipates naturally in ~1s in gameplay — 2.5s is longer than needed. Reducing to 1.2s makes effects snappier and reduces concurrent effect count.

**Before**: `lifetime = 2.5s`, concurrent at 15 shots/sec = 37.5 → capped 16
**After**: `lifetime = 1.2s`, concurrent at 15 shots/sec = 18 → capped 8

### 3. Use `fixed_fps`

**Source**: [Godot docs — GPUParticles2D fixed_fps](https://docs.godotengine.org/en/stable/classes/class_gpuparticles2d.html#class-gpuparticles2d-property-fixed-fps)

`fixed_fps = 15` causes the particle simulation to run at 15 Hz instead of 60 Hz. The GPU still renders particles at full framerate (interpolating between simulation steps), but the simulation cost drops ~75%. For dust, 15 FPS simulation is imperceptible.

### 4. Reduce `MAX_CONCURRENT_DUST_EFFECTS`

With the optimized parameters (`lifetime=1.2s`), the natural concurrency at 15 shots/sec is only 18. Reducing the cap from 16 to 8 further bounds GPU work while keeping visuals dense enough.

### 5. Add Quality Setting (Full / Half / Off)

Rather than a single binary toggle, a 3-level quality setting allows users to:
- **Full**: default behavior (optimized parameters)
- **Half**: `amount_ratio = 0.5` halves the active particle count at runtime
- **Off**: no dust spawned (existing behavior from `wall_hit_particles_enabled`)

This is implemented via `amount_ratio` on the `GPUParticles2D` node, which is a built-in property that scales the active particle count without modifying the scene resource.

### 6. Reddit Post Tips (r/godot — Godot physics/particle optimization)

The linked Reddit post covers physics object optimization tips relevant to this issue:

- **Object pooling**: Pre-allocate objects instead of instantiating/freeing at runtime. Already implemented for dust (Issue #1145).
- **Limit concurrent instances**: Cap the number of simultaneously active effects. Already implemented.
- **Reduce simulation cost**: Use `fixed_fps` to reduce how often the GPU runs the particle simulation shader. **Not yet applied to dust.**
- **Visibility culling**: Set `visibility_rect` so particles outside the camera are skipped. For a top-down game where the camera follows the player, most dust is visible — marginal benefit.
- **Simpler particle materials**: Fewer `ParticleProcessMaterial` parameters = less shader complexity. Current dust material is already simple (no color curves, no attractors).

---

## Proposed Solutions

### Solution 1: Optimize DustEffect.tscn Parameters (PRIMARY — implement)

Reduce particle count and lifetime directly in the scene file:

| Parameter | Before | After | Reason |
|-----------|--------|-------|--------|
| `amount` | 25 | 12 | Sufficient for small dust puff; −52% particles |
| `lifetime` | 2.5s | 1.2s | Dust dissipates faster; reduces concurrent count |
| `cleanup_delay` | 1.0s | 0.5s | Proportional to shorter lifetime |
| `fixed_fps` | *(not set)* | 15 | Simulate at 15 Hz; imperceptible for dust |

**Expected impact**: Reduces max concurrent GPU particles from 400 to ~96 (−76%).

### Solution 2: Reduce MAX_CONCURRENT_DUST_EFFECTS (implement)

With `lifetime=1.2s` at 15 shots/sec, natural concurrency is 18. Cap at 8 keeps GPU load bounded while keeping the effect visually dense.

| Constant | Before | After |
|----------|--------|-------|
| `MAX_CONCURRENT_DUST_EFFECTS` | 16 | 8 |
| `DUST_EFFECT_POOL_SIZE` | 16 | 8 |

### Solution 3: Dust Quality Setting in Optimization Menu (implement)

Add `dust_quality` (0=Full, 1=Half, 2=Off) to `GameplaySettings` and expose it as an `OptionButton` in `OptimizationMenu`.

**Important**: Godot docs explicitly state that `amount_ratio` has **no GPU performance benefit** — the engine still allocates and simulates the full `amount` regardless of `amount_ratio`. The only correct way to reduce GPU particle cost is to reduce `amount` (done in Solution 1) or skip spawning the effect node entirely.

Therefore the `spawn_dust_effect()` function implements Half mode by **skipping every other spawn** (50% fewer nodes) rather than adjusting `amount_ratio`.

| Quality | Spawn behavior | Active nodes | Active particles |
|---------|---------------|--------------|-----------------|
| Full (0) | All spawns | up to 8 | up to 96 |
| Half (1) | Skip every other | up to 4 | up to 48 |
| Off (2) | No spawns | 0 | 0 |

This replaces the existing binary `wall_hit_particles_enabled` toggle with a 3-level choice, while keeping backward compatibility (Off = same as old "disabled").

### Solution 4: Existing Component — `visibility_rect` (not implemented, marginal benefit)

Setting `visibility_rect` on GPUParticles2D allows Godot to skip rendering particles outside the viewport. For a top-down game, most dust is near the player and thus visible. Marginal benefit; not prioritized.

### Solution 5: CPUParticles2D as Fallback (not implemented, different trade-off)

`CPUParticles2D` runs simulation on the CPU, offloading the GPU. On GPU-limited hardware, this could help; on CPU-limited hardware, it would hurt. Not recommended as a general optimization.

---

## Implementation Plan

1. **DustEffect.tscn**: Set `amount=12`, `lifetime=1.2`, add `fixed_fps=15`.
2. **impact_effects_manager.gd**: Reduce `MAX_CONCURRENT_DUST_EFFECTS` to 8, `DUST_EFFECT_POOL_SIZE` to 8. Update `return_delay` to use `effect.lifetime + 0.5`.
3. **gameplay_settings.gd**: Add `dust_quality: int = 0` (0=Full, 1=Half, 2=Off). Add getter/setter with persistence.
4. **impact_effects_manager.gd — spawn_dust_effect()**: Read `dust_quality` from `GameplaySettings`. If 2 (Off), return early. If 1 (Half), set `amount_ratio = 0.5`. If 0 (Full), set `amount_ratio = effect_scale`.
5. **OptimizationMenu.tscn + optimization_menu.gd**: Replace `WallHitParticlesCheckbox` with `DustQualityOption` (OptionButton: Full / Half / Off). Remove the old toggle.

---

## Expected Results

| Scenario | Before | After |
|----------|--------|-------|
| Max concurrent particles (rapid fire) | ~400 | ~96 (Full) / ~48 (Half) / 0 (Off) |
| Effect lifetime on screen | 2.5s | 1.2s |
| Particle simulation cost | 60 Hz | 15 Hz |
| FPS at sustained AK fire (estimated) | 28–29 fps | 45–55 fps |
