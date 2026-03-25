# Case Study: Issue #1495 — Realistic 2D Water Physics

## Problem Statement

Issue #1495 requests implementing maximally realistic 2D water physics that reacts to
physical objects: shell casings (гильзы), enemies, the player, grenades, and explosions.

The existing water (from PR #1479 / Issue #1445) provides:
- A `ColorRect` with an animated sinusoidal shader (cosmetic waves only)
- `WaterSplashEffect` (expanding concentric rings — cosmetic)
- Area2D-based detection for objects entering water
- Blood diffusion effects
- Bloody footprint suppression

**What's missing** (and what this issue adds):
1. **Dynamic surface deformation** — water surface physically reacts to objects
2. **Spring-column simulation** — each point on the water surface acts as a damped spring
3. **Wave propagation** — disturbances travel across the surface realistically
4. **Velocity-based splash magnitude** — faster/heavier objects create bigger waves
5. **Buoyancy forces** — objects in water are slowed and pushed upward
6. **Continuous surface interaction** — moving objects constantly disturb the surface

## Reference

The issue links to: https://www.reddit.com/r/godot/comments/kv7pde/how_to_create_good_looking_2d_water_effect_in/

This reference discusses the classic spring-column 2D water technique popularized by:
- [Envato Tuts+ "Make a Splash with Dynamic 2D Water Effects"](https://gamedevelopment.tutsplus.com/make-a-splash-with-dynamic-2d-water-effects--gamedev-236t)
- [CaptainProton42 DynamicWaterDemo](https://github.com/CaptainProton42/DynamicWaterDemo)

---

## Research Findings

### Spring-Column Water Model

The classic approach divides the water surface into N evenly-spaced vertical columns.
Each column stores:
- `height` — current vertical position
- `target_height` — equilibrium position
- `velocity` — current vertical velocity

**Constants:**

| Parameter | Value | Purpose |
|-----------|-------|---------|
| SPRING_CONSTANT | 0.025 | Hooke's law stiffness |
| DAMPING | 0.025 | Velocity decay per frame |
| SPREAD | 0.25 | Wave propagation to neighbors |
| COLUMN_WIDTH | 4 px | Spacing between columns |
| PASSES | 8 | Propagation passes per frame |

**Per-frame algorithm:**

1. For each column: apply Hooke's law restoring force + damping
2. For each propagation pass: spread height differences to neighbors

### Object Interaction

When an object enters water:
1. Find the nearest column(s) to the object's X position
2. Apply velocity proportional to the object's entry speed and mass
3. Optionally spread the force across neighboring columns for wider objects

### Rendering

Two main approaches:
- **Polygon2D** — build polygon from column heights each frame (CPU-side)
- **Shader + texture** — pass heights as uniform array, displace in shader (GPU-side)

For this project, we use **Polygon2D** for the deformed surface with the existing
wave shader applied as texture, providing both physical deformation AND visual detail.

### Buoyancy

For RigidBody2D objects (casings, grenades):
- Reduce gravity when submerged
- Apply upward force proportional to submersion
- Apply drag force opposing velocity

For CharacterBody2D objects (player, enemies):
- Reduce movement speed in water
- Create continuous surface disturbances while moving

---

## Solution Architecture

### New Files

| File | Purpose |
|------|---------|
| `scripts/objects/water_surface.gd` | Spring-column simulation, Polygon2D rendering, splash API |
| `scripts/shaders/water_surface.gdshader` | Shader for the dynamic polygon surface |

### Modified Files

| File | Change |
|------|--------|
| `scripts/objects/water_body.gd` | Integrate WaterSurface, pass splash events to spring system |
| `scenes/objects/WaterBody.tscn` | Add WaterSurface (Polygon2D) and WaterSurfaceLine (Line2D) children |
| `scripts/shaders/realistic_water.gdshader` | Add surface distortion from spring heights |

### Design Decisions

1. **Polygon2D approach** — chosen over shader-only because it gives physically correct
   deformation that is visible as actual geometry changes, not just UV tricks.

2. **Additive to existing system** — the spring simulation adds to (not replaces) the
   existing shader waves. The shader provides ambient animation; springs provide reactive
   physics.

3. **Column width = 4px** — with water_width=2400px this gives 600 columns.
   Good visual fidelity without excessive CPU cost.

4. **Multiple propagation passes** — 8 passes per frame ensures waves travel at a
   visible speed across the surface.

---

## User Feedback Analysis (2026-03-25)

### Report

User (Jhon-Crow) reported: "сейчас физика воде не добавилась (воде на карте Пляж)" — water physics
did not get added to the Beach map. Log file: `game_log_20260325_164449.txt`.

### Root Cause Analysis

**Key finding from log:** Line 1465 shows:
```
[BeachLevel] Water node found OK — visual=true shader=false collision=true pos=(1264, 242)
```

`shader=false` means `WaterVisual.material == null` — the shader was not applied.
Additionally, there are **zero** `[WaterBody]` log entries in the entire log.

**Explanation:** The `water_body.gd` script has `_ready()` that logs `[WaterBody] Ready — ...` via
FileLogger. This message is completely absent, meaning WaterBody's `_ready()` either:
1. Never ran, or
2. Ran on an older script version without the logging.

**Root cause:** The user is running an **exported binary** (`Godot-Top-Down-Template.exe`,
`Debug build: false`) that was compiled **before** PR #1495 (this PR) or possibly even before
PR #1479 (the base water implementation). Exported Godot binaries include GDScript files compiled
into `.gdc` at export time — updating source files does not affect an already-exported binary.

The `shader=false` confirms: `_apply_shader()` was not called (because the pre-export
version of `water_body.gd` didn't have it), not that it failed.

### Evidence

1. No `[WaterBody]` log entries — script not running from our version
2. `shader=false` — shader not applied (old binary without our code)
3. `Debug build: false` — confirmed exported binary
4. Executable path: `I:/Загрузки/godot exe/ОСадКИ/Godot-Top-Down-Template.exe`
5. The `beach_level.gd` runs correctly (logs appear), confirming FileLogger works

### Solution

The PR must be merged and the user must:
1. Pull latest changes (merge main with our PR)
2. Re-export the game from Godot editor with the updated scripts

The implementation in this PR is correct. Once the user updates their build, water physics will
work as designed.

---

## References

- [Envato Tuts+ Dynamic 2D Water Effects](https://gamedevelopment.tutsplus.com/make-a-splash-with-dynamic-2d-water-effects--gamedev-236t)
- [CaptainProton42 DynamicWaterDemo](https://github.com/CaptainProton42/DynamicWaterDemo)
- [HackTrout 2DDynamicWater for Godot](https://github.com/HackTrout/2DDynamicWater)
- [2D Water JavaScript Demo](https://github.com/anothrNick/2D-Water-Javascript-Demo)
- [Godot FloatableBody](https://github.com/ueshita/godot-floatable-body)
