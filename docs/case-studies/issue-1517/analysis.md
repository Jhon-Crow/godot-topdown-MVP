# Case Study: Issue #1517 — Stress Benchmark Analysis

## Benchmark File

`stress_benchmark_20260326_064851.txt` (attached to issue #1517)

Run on: 2026-03-26 06:48:51
Tool: `_run_stress_benchmark()` in `scripts/ui/performance_menu.gd` (Issue #1504)
Configuration: 30 particles, 20 lights, 20 enemies, 2.0 s sample per half-step

---

## Raw Results

| Step | Subsystem | Enabled FPS | Disabled FPS | Delta |
|------|-----------|-------------|--------------|-------|
| 1/4 | Particles (30 GPUParticles2D) | 42.1 | 30.0 | **−12.1** |
| 2/4 | Explosion Lights (20 PointLight2D) | 47.4 | 56.0 | **+8.6** |
| 3/4 | AI (20 enemies) | 29.4 | 38.8 | **+9.4** |
| 4/4 | Combined (particles + lights + enemies) | 24.4 | 21.3 | **−3.1** |

Convention in log: `delta = disabled_fps − enabled_fps` (positive means disabling **helped** FPS, i.e. that subsystem has a real cost; negative means disabling **hurt** FPS, which is anomalous).

---

## Analysis per Subsystem

### Step 1 — Particles: anomalous negative delta

**Result:** `delta = −12.1` (FPS *dropped* after "disabling" particles)

**Root cause — particles toggle does not affect already-spawned nodes.**

The stress benchmark:
1. Spawns 30 `GPUParticles2D` nodes via `_spawn_stress_particles()` → nodes added to scene tree, emitting = true.
2. Samples FPS with particles **enabled** → 42.1 FPS.
3. Calls `perf_settings.set_particles_enabled(false)`.
4. Samples FPS with particles supposedly **disabled** → 30.0 FPS.
5. Cleans up the 30 nodes.

The `set_particles_enabled(false)` flag in `PerformanceSettings` guards future particle creation (checked at the moment an effect is triggered, e.g. in `explosion_effect.gd` or similar). It does **not** retroactively stop already-live `GPUParticles2D` nodes that are already emitting in the scene tree. All 30 particles continue to emit throughout the "disabled" measurement window.

The FPS difference is therefore not caused by the toggle at all — it is measurement noise and warmup variance over consecutive 2-second windows. The real GPU cost of 30 GPUParticles2D is not isolated by this measurement.

**Conclusion:** The particles delta is **invalid**. The "disabled" sample is not a true baseline.

---

### Step 2 — Explosion Lights: valid result, 8.6 FPS cost

**Result:** `delta = +8.6` (disabling lights freed 8.6 FPS)

The stress benchmark explicitly sets `ln.visible = false` on each spawned `PointLight2D` node before the "disabled" sample:

```gdscript
perf_settings.set_explosion_lights_enabled(false)
for ln in light_nodes:
    if is_instance_valid(ln):
        ln.visible = false
var fps_lights_off := await _sample_fps(STRESS_SAMPLE_DURATION)
```

Setting `visible = false` removes the light from Godot's 2D render pipeline — shadow maps are not recalculated and draw calls are skipped. This is a valid disable path.

**Conclusion:** The lights result is **valid**. 20 `PointLight2D` nodes without a texture cost ~8.6 FPS at this scene complexity. In production, each explosion light uses a texture and may have shadow casting enabled, which would make the cost higher. This validates the performance concern and confirms the explosion lights toggle is effective.

---

### Step 3 — AI: valid result, 9.4 FPS cost

**Result:** `delta = +9.4` (disabling AI freed 9.4 FPS)

The benchmark calls `perf_settings.set_ai_enabled(false)`, which is checked at the top of each enemy's `_process` / `_physics_process` tick via `filter_ai_state()` in `performance_settings.gd`. When the flag is false, enemies skip their entire GOAP state machine and navigation updates.

The 20 spawned enemies plus their nav agents and collision bodies remain in the tree — only the per-frame CPU work is suppressed. This cleanly isolates the AI processing cost.

**Conclusion:** The AI result is **valid**. 20 simultaneously active enemies (exceeding the in-game cap of 12 in `arena_level.gd`) cost ~9.4 FPS. This is a significant CPU bottleneck at scale and confirms that the AI toggle delivers a measurable optimization.

---

### Step 4 — Combined: anomalous negative delta

**Result:** `delta = −3.1` (FPS *dropped* after "disabling" everything)

This is the same root cause as Step 1. In the combined step, `_spawn_stress_particles()` is called again, spawning 30 more `GPUParticles2D` nodes. When `set_particles_enabled(false)` is subsequently called, those nodes keep emitting. The "disabled" baseline therefore still bears the full GPU cost of 30 active particle systems, making it heavier than expected and producing a spurious negative delta.

The AI and lights disabling *do* work correctly in this step (same mechanism as Steps 2–3), but their savings are offset by the unresponsive particle load.

**Conclusion:** The combined delta is **invalid** for the same reason as Step 1. The measured result cannot be used to draw conclusions about the aggregate cost of all three subsystems together.

---

## Summary Table

| Subsystem | Delta valid? | Measured cost | Conclusion |
|-----------|-------------|---------------|------------|
| Particles | **No** — toggle does not stop already-spawned nodes | Unknown (measurement broken) | Fix needed in benchmark |
| Explosion Lights | **Yes** | ~8.6 FPS / 20 lights | Real cost confirmed; toggle works |
| AI (20 enemies) | **Yes** | ~9.4 FPS / 20 enemies | Real cost confirmed; toggle works |
| Combined | **No** — same particle issue | Unknown | Fix needed in benchmark |

---

## Baseline FPS Context

The enabled FPS values across steps tell a story even without valid deltas:

| Step | Enabled FPS | Active load |
|------|------------|-------------|
| 1 (particles only) | 42.1 | 30 particle emitters |
| 2 (lights only) | 47.4 | 20 PointLight2D |
| 3 (AI only) | 29.4 | 20 enemies |
| 4 (all combined) | 24.4 | particles + lights + enemies |

AI alone drops FPS to 29.4 — more aggressively than lights (47.4) or particles (42.1) in isolation. The combined load of 24.4 FPS is below 30 FPS, which represents a real performance cliff for target hardware.

---

## Recommended Fix for the Benchmark

The particle stress step should stop already-spawned nodes before sampling the "disabled" window. The correct approach is to call `p.emitting = false` on each spawned `GPUParticles2D` node directly, rather than relying on the `PerformanceSettings` toggle (which only controls future instantiation):

```gdscript
# After calling set_particles_enabled(false):
for p in particle_nodes:
    if is_instance_valid(p):
        p.emitting = false   # stop the already-live emitter
var fps_particles_off := await _sample_fps(STRESS_SAMPLE_DURATION)
```

Apply the same fix to the combined step for the `combo_particles` nodes.

This will make Steps 1 and 4 produce valid, positive deltas consistent with the lights and AI measurements.

---

## Actionable Recommendations

1. **Fix the stress benchmark** (see above) so particle and combined deltas are meaningful.
   - File: `scripts/ui/performance_menu.gd`, steps 1 and 4 of `_run_stress_benchmark()`.

2. **AI is the primary CPU bottleneck.** At 20 enemies the game is below 30 FPS. The in-game cap of 12 enemies (`MAX_CONCURRENT_ENEMIES` in `arena_level.gd`) partially mitigates this, but harder difficulty levels or open arenas may approach the threshold.
   - Consider per-state AI disabling for the cheapest states first (IDLE patrol has a high toggle cost relative to its gameplay value).

3. **Lights are the primary GPU bottleneck** among the confirmed measurements (8.6 FPS / 20 lights). In production, textures and shadow casting will increase this cost further.
   - The existing toggle (`set_explosion_lights_enabled`) is confirmed effective.

4. **Re-run the benchmark after the fix** to get valid particle cost data and a true combined baseline.
