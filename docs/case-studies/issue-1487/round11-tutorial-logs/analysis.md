# Round 11 Log Analysis — Tutorial / BuildingLevel Benchmark Session
**Session date:** 2026-03-27
**Log files:** game_log_20260327_111028.txt, benchmark_log_20260327_111211.txt, stress_benchmark_20260327_111149.txt
**Platform:** Windows (Godot 4.3-stable, release build)
**Executable path:** `I:/Загрузки/godot exe/оптимизация/`

---

## Session Timeline

The game session covered three distinct maps in sequence:

1. **LabyrinthLevel** — initial scene at startup (briefly visited, never played)
2. **Tutorial** (res://scenes/levels/csharp/TestTier.tscn) — loaded after PersistManager redirected to last-played level. Player had no enemies, AI was disabled manually during this phase. Infinite grenades were enabled.
3. **BuildingLevel** (res://scenes/levels/BuildingLevel.tscn) — main combat map, 10 enemies. Both the stress benchmark and the standard benchmark ran here.

The stress benchmark ran first (~11:11:49–11:12:08), then the standard benchmark (~11:12:11–11:13:05), after which the game continued recording for a full 300-second replay.

---

## FPS Drops Detected

All FPS drops were logged with threshold 30 fps. There were **5 drop events** total:

| Timestamp    | Map           | FPS | Context |
|--------------|---------------|-----|---------|
| 11:10:34     | Tutorial      | 1   | Scene transition / particle shader warmup completing (4526 ms warmup finished at 11:10:33, background scene load in progress) |
| 11:10:52     | Tutorial      | 28  | Player fired explosion + gunshot (MiniUzi), no enemies present |
| 11:11:17     | BuildingLevel | 23  | Immediately after scene load + navmesh bake, 10 enemies active (player_valid=True) |
| 11:11:24     | BuildingLevel | 23  | Player ran out of ammo; all 10 enemies simultaneously received ammo-empty event + reload-start events |
| 11:11:32     | BuildingLevel | 22  | Second reload cycle — same 10-enemy broadcast pattern |
| 11:11:40     | BuildingLevel | 27  | Third ammo depletion broadcast to all 10 enemies |

### Root cause observations

- The **1 fps drop at 11:10:34** is a known startup artefact: particle shader warmup (7 effects, 4526 ms) was completing simultaneously with a background scene load.
- The **Tutorial drops** (28 fps) occurred while firing weapons with no enemies; likely explosion particle and sound propagation overhead with zero listeners.
- The **BuildingLevel drops (22–27 fps)** correlate directly with the pattern of all 10 enemies simultaneously processing player-state change signals (ammo empty / reloading). Each reload cycle generated 20 `[ENEMY]` log entries in rapid succession (10 × ammo-empty + 10 × reload-state). This is the same signal-broadcast cost identified in earlier rounds.

---

## Benchmark Results (benchmark_log_20260327_111211.txt)

**Map:** BuildingLevel, 10 enemies (from game log context)
**Baseline (all enabled):** avg=45.9, min=30.0, max=55.0

| Step | Subsystem disabled | Avg FPS | Min | Max | Delta vs baseline |
|------|--------------------|---------|-----|-----|-------------------|
| 1 | Baseline (all enabled) | 45.9 | 30.0 | 55.0 | — |
| 2 | Particles | 55.1 | 51.0 | 58.0 | +9.2 |
| 3 | Blood Decals | 54.4 | 54.0 | 57.0 | +8.5 |
| 4 | Screen Shake | 56.4 | 54.0 | 57.0 | +10.5 |
| 5 | Explosion Lights | 55.0 | 52.0 | 56.0 | +9.1 |
| 6 | Wall Hit Particles | 53.2 | 48.0 | 57.0 | +7.3 |
| 7 | AI (all states) | 56.9 | 53.0 | 59.0 | +11.0 |
| 8 | AI:IDLE | 56.2 | 53.0 | 58.0 | +10.3 |
| 9 | AI:COMBAT | 56.7 | 54.0 | 58.0 | +10.8 |
| 10 | AI:SEEKING_COVER | 55.5 | 53.0 | 58.0 | +9.6 |
| 11 | AI:IN_COVER | 55.6 | 54.0 | 58.0 | +9.7 |
| 12 | AI:FLANKING | 55.7 | 53.0 | 58.0 | +9.8 |
| 13 | AI:SUPPRESSED | 53.7 | 41.0 | 57.0 | +7.8 |
| 14 | AI:RETREATING | 40.3 | 38.0 | 43.0 | −5.6 (regression) |
| 15 | AI:PURSUING | 50.6 | 43.0 | 54.0 | +4.7 |
| 16 | AI:ASSAULT | 55.3 | 53.0 | 57.0 | +9.4 |
| 17 | AI:SEARCHING | 55.4 | 52.0 | 57.0 | +9.5 |

### Key findings

- **Disabling AI entirely (step 7)** gives the largest single gain: +11 fps avg, bringing min to 53 fps.
- **AI:RETREATING (step 14)** is the worst-performing individual state: avg drops to 40.3 fps, min 38 fps, even lower than the all-enabled baseline. This is a significant regression — disabling RETREATING makes things worse. This state may be triggering expensive fallback logic or pathfinding when it is suppressed.
- **Particles (step 2) and Screen Shake (step 4)** each contribute ~9–10 fps individually.
- All other visual subsystems (blood decals, explosion lights, wall hit particles) each cost 7–9 fps.
- The min=30.0 in the baseline step is right at the threshold, explaining the 22–27 fps drops observed in the game log when 10 enemies were active.

---

## Stress Benchmark Results (stress_benchmark_20260327_111149.txt)

**Issue referenced:** #1504
**Stress load:** 30 GPUParticles2D, 20 PointLight2D, 20 enemies

| Subsystem | Enabled FPS | Disabled FPS | Delta (cost) |
|-----------|-------------|--------------|--------------|
| Particles (30 GPUParticles2D) | 28.3 | 37.7 | 9.4 |
| Explosion Lights (20 PointLight2D) | 46.5 | 51.7 | 5.2 |
| AI (20 enemies) | 36.3 | 43.4 | 7.1 |
| Combined (particles + lights + 20 enemies) | 8.8 | 21.2 | 12.5 |

### Key findings

- Under heavy stress (30 particles active), FPS drops to 28.3 — below the 30 fps threshold even without lights or AI.
- 20 enemies (AI) costs 7.1 fps, which is proportionally consistent with the standard benchmark.
- The **combined stress test hits 8.8 fps** enabled vs 21.2 fps disabled — a 12.5 fps delta, but even with all disabled the combined overhead leaves only 21 fps, indicating multiplicative rendering cost when all three systems overlap.
- This confirms particles are the most expensive single subsystem under stress, exceeding AI cost at high counts.

---

## Errors and Warnings

| Timestamp | Level | Source | Message |
|-----------|-------|--------|---------|
| 11:10:34 | WARN | FPS | Drop detected: 1 fps (threshold: 30) — startup/warmup artefact |
| 11:10:32 | INFO (error text) | SceneLoader | `ERROR: Invalid resource (falling back to sync): res://scenes/levels/csharp/TestTier.tscn` — async load failed, sync fallback used |
| 11:10:52 | WARN | FPS | Drop detected: 28 fps |
| 11:11:17 | WARN | FPS | Drop detected: 23 fps |
| 11:11:24 | WARN | FPS | Drop detected: 23 fps |
| 11:11:32 | WARN | FPS | Drop detected: 22 fps |
| 11:11:40 | WARN | FPS | Drop detected: 27 fps |

No ERROR-level entries aside from the SceneLoader async fallback. No crashes.

The `SceneLoader ERROR` for `TestTier.tscn` (Tutorial) is a known pattern where C# resource async-loading fails and falls back to sync. It is not fatal but may contribute to the 1 fps spike at 11:10:34 since sync loading blocks the main thread.

---

## Comparison with Round 10

Round 10 confirmed the BuildingLevel fix. Round 11 replicates the same session flow:
- BuildingLevel continues to be the primary performance concern with 10 enemies.
- The 22–27 fps drops in BuildingLevel match the pattern from earlier rounds and are caused by simultaneous enemy signal broadcasts on player ammo/reload state changes, not a regression.
- **New finding this round:** AI:RETREATING disabling causes a performance regression (avg 40.3 vs 45.9 baseline). This was not highlighted in previous rounds and warrants investigation — the RETREATING guard code may be running more expensive logic when that state is blocked.
- The Tutorial scene itself is lightweight (no enemies), and the single 28 fps drop there is from explosion + particle overhead with no AI.

---

## Summary

The Round 11 session is a multi-part benchmark run on BuildingLevel with 10 enemies. Performance is broadly consistent with Round 10:

- **Baseline avg: ~46 fps**, dropping to 22–27 fps during active 10-enemy + reload broadcast events.
- **Biggest performance wins:** disabling AI entirely (+11 fps), particles (+9 fps), or screen shake (+10 fps).
- **Anomaly requiring investigation:** AI:RETREATING disabled makes performance worse (avg 40.3, min 38) — this is a regression relative to baseline.
- **Stress test** confirms particles at high counts are the most expensive single subsystem (9.4 fps cost at 30 active), and combined load at extreme stress (particles + lights + 20 enemies) tanks to 8.8 fps.
- **One non-fatal error:** Tutorial scene async load failure causing sync fallback and a 1-frame FPS spike.
