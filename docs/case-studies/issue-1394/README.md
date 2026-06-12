# Case Study: Top-Down Rain Precipitation Effect (Issue #1394)

## Problem Statement

The Docks level needed a weather precipitation system that:
1. Adds atmospheric top-down rain visual effect (HM2-style)
2. Continuous rain — always active while outdoors
3. Excludes rain from indoor areas (WarehouseA, WarehouseB)
4. Is reusable for other maps and future precipitation types

---

## Timeline / Sequence of Events

### 2026-03-24 — Iteration 1: Rain Not Visible

**Evidence:** `game_log_20260324_075210.txt`
- Log shows `[DocksLevel] Rain precipitation setup with 2 exclusion zones` but **no `[RainEffect]` log lines**
- Session lasted only ~47 seconds (07:52:10 to ~07:53:00)

**Root causes:**
1. Rain start delay was 30–90 seconds — the session ended before rain ever triggered
2. No `[RainEffect]` logging → impossible to verify if rain fired at all
3. Particle opacity was 0.35 alpha with only 120 particles — too subtle to notice

**Fix applied:** Reduced delay to 5s, increased particle count to 200, increased opacity to 0.5, added logging

---

### 2026-03-24 — Iteration 2: Rain Visible But Looks Wrong (Side-View)

**Evidence:** `game_log_20260324_090934.txt`
- `[RainEffect] Scheduled first rain episode in 5.0 seconds` — rain now starts
- `[RainEffect] Rain episode STARTED (duration: 34.9 seconds, emitting: true)` — rain fires

**User feedback:** Rain started too quickly for episodic play; looked like **side-view rain** (streaks falling straight down), not top-down

**Root cause:** Fixed `direction = Vector3(0, 1, 0)` made every streak move straight downward — this looks like a side-scrolling game, not top-down

**Fix applied:** Added diagonal direction (HM2 reference requested), added two-layer system (streaks + splashes)

---

### 2026-03-24 — Iterations 3–5: HM2-Style Two-Layer Rain — Splash Misalignment

**Evidence:** `game_log_20260324_130348.txt`
- Rain starts and stops properly (episodic mode): `Rain episode STARTED (duration: 23.9s)` → `Rain episode STOPPED`

**User feedback:** Splash rings do not appear where streaks land — two disconnected particle areas visible

**Root cause:** `RainSplashes` position was `Vector2(0, 180)` calculated for old diagonal trajectory. After trajectory changes, the offset was stale.

**Fix applied:** Synchronized emission areas; matched splash position to streak travel distance

---

### 2026-03-24 — Iteration 6: Continuous Rain

**Evidence:** `game_log_20260324_142031.txt`
- `[RainEffect] Rain started (continuous mode)` — episodic system replaced

**User feedback:** Rain should never stop — always continuous outdoors

**Fix applied:** Removed episodic timer system entirely; rain emits from `_ready()` forever

---

### 2026-03-25 — Iteration 7: Fish-Eye Radial Perspective (radial_velocity)

**Evidence:** `game_log_20260325_125244.txt`
- `[RainEffect] Rain started (continuous mode)` — rain works

**Context:** All previous iterations used fixed `direction` vectors (e.g., `Vector3(0.4, 1, 0)`). The user liked the appearance of the screen-filling rain but wanted a top-down perspective feel similar to HM2.

**Approach:** Replaced `direction + initial_velocity` with `radial_velocity = 80–140 px/s`. Each particle spawns at a random point on the full screen and moves outward from the emitter center (`Vector2(640, 360)`). With `particle_flag_align_y = true`, each streak auto-rotates to face its velocity direction. Result: center streaks point nearly straight, edge streaks angle outward — a fish-eye perspective illusion.

**User feedback (2026-03-25):** Liked the visual, but **streaks appear to be flying away/going upward** instead of falling. Also splashes still don't align with streak endpoints.

---

### 2026-03-25 — Iteration 8: Fix Direction (Wrong Approach)

**Evidence:** `game_log_20260326_094619.txt` (tested on 2026-03-26)
- `[RainEffect] Rain started (continuous mode)` — works

**Approach:** Replaced `radial_velocity` with fixed `direction = Vector3(0.4, 0.9, 0)` at 180–240 px/s (diagonal down-right). Also moved `RainSplashes` to `position = Vector2(653, 388)` as a co-location attempt.

**User feedback (2026-03-26):** "All wrong again. Revert to commit `123cde9a` (the radial_velocity version) but invert the direction of streaks."

---

### 2026-03-26 — Iteration 9: Inverted Radial Velocity (Current Fix)

**Root cause identified:** In Godot 4, `radial_velocity > 0` pushes particles **away from the emitter center** (outward). This caused particles to appear to fly away from the camera in all directions. The user's description of streaks "going upward" (for particles above center) is exactly this behavior.

**Fix:** Revert scene to commit `123cde9a` exactly, but set `radial_velocity` to **negative values** (`-140` to `-80`). Negative `radial_velocity` in Godot pulls particles **toward the emitter center** — inward convergence. Combined with `particle_flag_align_y = true` and `BOX` emission across the full screen:
- Particles spawn at random screen positions
- All converge toward `Vector2(640, 360)` (screen center)
- Each streak auto-rotates to face its movement direction
- Visual result: streaks fall "toward" the camera focal point — simulating top-down rain perspective

Also restored splash emitter to `position = Vector2(640, 360)` (co-located with streaks, same as commit `123cde9a`).

---

## Root Cause Analysis

### Why Every Fixed-Direction Attempt Failed

| Attempt | Direction | Problem |
|---------|-----------|---------|
| `Vector3(0, 1, 0)` | Straight down | Side-view appearance |
| `Vector3(0.5, 1, 0)` | Diagonal | Still side-view (uniform direction everywhere) |
| `Vector3(0.4, 0.9, 0)` | Diagonal | Still side-view (uniform direction everywhere) |
| `radial_velocity = +80–140` | Outward from center | Rain "flies away" (upward for top particles) |
| `radial_velocity = -80–140` | **Inward to center** | **Top-down perspective (current fix)** |

### The Physics of Top-Down Rain

In real top-down perspective:
- Raindrops fall toward the camera (along the optical axis)
- From the camera's view, they appear to converge toward the center of the lens
- Near the edges of the frame, this convergence creates an inward-angling effect

Negative `radial_velocity` in a screen-space particle system with `BOX` emission replicates this: particles at screen edges travel toward center, particles close to center move nearly straight (low radial distance → low velocity component).

### External Research: What HM2-Style Rain Actually Is

Research into Hotline Miami 2's rain and top-down rain implementations reveals:

**For a flat 2D top-down art style** (which is what this game uses), all published implementations use **uniform diagonal streaks** (all same direction), not radial/fish-eye streaks. The convergence effect would only be physically meaningful for a 3D perspective camera looking down.

**However:** The user explicitly confirmed they liked the fish-eye radial look from commit `123cde9a` and only wanted the direction inverted — so negative `radial_velocity` is correct per user preference, regardless of physical accuracy.

Sources:
- [Making rain in a top-down game (Unity forums)](https://forum.unity.com/threads/making-rain-in-a-top-down-game.532887/)
- [Simple top-down rain (GameMaker forums)](https://forum.gamemaker.io/index.php?threads%2Fsimple-pretty-performant-top-down-rain.36059%2F=)
- [Photorealistic Rendering of Rain Streaks — Garg & Nayar, Columbia CAVE](https://cave.cs.columbia.edu/old/publications/pdfs/Garg_TOG06.pdf)
- [How developers make perfect rain in games — PC Gamer](https://www.pcgamer.com/how-developers-make-perfect-rain-in-games/)

---

## Current Solution Architecture

### Rain Effect Layers

| Layer | Amount | Lifetime | Purpose |
|-------|--------|----------|---------|
| **RainStreaks** | 50 | 0.15s | Short radial dashes converging toward screen center |
| **RainSplashes** | 50 | 0.4s | Circular rings scattered across full screen |

### Key Parameters (Current State)

```
RainStreaks:
  radial_velocity_min = -140.0   # negative = inward/converging
  radial_velocity_max = -80.0
  particle_flag_align_y = true   # auto-rotate streak to face velocity
  emission_shape = BOX (640x360) # full screen coverage
  lifetime = 0.15s               # short streaks
  amount = 50

RainSplashes:
  spread = 180.0                 # omnidirectional minimal drift
  initial_velocity = 0–2 px/s   # nearly static rings
  emission_shape = BOX (640x360) # same area as streaks
  lifetime = 0.4s                # longer-lasting rings
  amount = 50
```

### Node Hierarchy

Rain lives inside a **CanvasLayer** (`RainCanvas`, layer 5) — renders in screen/viewport space, no per-frame camera repositioning needed.

```
RainEffect (Node2D)
└── RainCanvas (CanvasLayer, layer=5)
    ├── RainStreaks (GPUParticles2D)  position=(640,360)
    └── RainSplashes (GPUParticles2D) position=(640,360)
```

### Building Exclusion

WarehouseA and WarehouseB use Rect2 bounds checking in `rain_effect.gd`. Each frame the camera's world position is compared to registered exclusion zones; if inside, `emitting = false`.

---

## Collected Evidence

### Game Logs

| File | Date | Key Evidence |
|------|------|-------------|
| `game_log_20260324_075210.txt` | 2026-03-24 | No RainEffect logs → rain never started (delay too long) |
| `game_log_20260324_090934.txt` | 2026-03-24 | First successful rain start (episodic mode, 5s delay) |
| `game_log_20260324_130348.txt` | 2026-03-24 | Episodic start/stop working |
| `game_log_20260324_132947.txt` | 2026-03-24 | No rain log entries (version/scene mismatch) |
| `game_log_20260324_142031.txt` | 2026-03-24 | First continuous mode confirmed |
| `game_log_20260325_125244.txt` | 2026-03-25 | Radial velocity version (fish-eye, user liked visually) |
| `game_log_20260326_094619.txt` | 2026-03-26 | Fixed-direction version (user rejected, asked to revert) |

### Screenshots

| File | Shows |
|------|-------|
| `hm2-rain-reference.png` | Target HM2 rain style |
| `hm2-rain-reference-2.png` | Additional HM2 reference |
| `feedback-screenshot-2.png` | User feedback — splash misalignment |
| `feedback-screenshot-3.png` | User feedback — side-view appearance |
| `feedback-screenshot-latest.png` | Radial velocity version (user approved look, rejected direction) |
| `screenshot_diagonal_rain.png` | Diagonal streak attempt |
| `screenshot_side_view_rain_latest.png` | Side-view appearance |
| `screenshot_vertical_rain_feedback.png` | Vertical streak attempt |

---

## File Changes Summary

| File | Change Type | Description |
|------|------------|-------------|
| `scripts/effects/rain_effect.gd` | New | Rain controller with exclusion zones, continuous mode |
| `scenes/effects/RainEffect.tscn` | New | Two-layer GPUParticles2D rain scene |
| `scenes/levels/DocksLevel.tscn` | Modified | Added RainEffect instance |
| `scripts/levels/docks_level.gd` | Modified | Added `_setup_rain()` with WarehouseA/B exclusion zones |
| `tests/unit/test_rain_effect.gd` | New | Unit tests for exclusion zone logic and continuous rain |

## Testing

Unit tests cover:
- Continuous rain (always emitting from ready)
- Exclusion zone detection (add, clear, point-in-zone checks)
- Building enter/exit behavior (rain stops/resumes)
- Warehouse-specific zone coordinates
- Edge cases (boundary points, multiple zones)

## External References

- [Godot GPUParticles2D documentation](https://docs.godotengine.org/en/4.3/classes/class_gpuparticles2d.html)
- [Godot ParticleProcessMaterial — radial_velocity](https://docs.godotengine.org/en/4.3/classes/class_particleprocessmaterial.html#class-particleprocessmaterial-property-radial-velocity-min)
- [Making rain in a top-down game (Unity forums)](https://forum.unity.com/threads/making-rain-in-a-top-down-game.532887/)
- [Simple top-down rain (GameMaker forums)](https://forum.gamemaker.io/index.php?threads%2Fsimple-pretty-performant-top-down-rain.36059%2F=)
- [Hotline Miami 2 rain discussion (Steam Level Editor)](https://steamcommunity.com/app/274170/discussions/1/494632506578501542/)
- [Photorealistic Rendering of Rain Streaks — Garg & Nayar, Columbia CAVE](https://cave.cs.columbia.edu/old/publications/pdfs/Garg_TOG06.pdf)
- [Water drop 2a: Dynamic rain and its effects — Sébastien Lagarde](https://seblagarde.wordpress.com/2012/12/27/water-drop-2a-dynamic-rain-and-its-effects/)
- [How developers make perfect rain in games — PC Gamer](https://www.pcgamer.com/how-developers-make-perfect-rain-in-games/)

## Future Extensibility

- Any level can instance `RainEffect.tscn` and configure exclusion zones
- Different precipitation types (snow, hail) can be created by duplicating the scene with different particle materials
- Rain starts automatically — no configuration needed for basic use
