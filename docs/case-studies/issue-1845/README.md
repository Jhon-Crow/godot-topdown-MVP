## Issue 1845: muzzle flashes are too dim on Labyrinth

Issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1845
PR: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1846

### Summary

The muzzle flash logic was spawning correctly, but on `LabyrinthLevel` the flash light was too dim compared with other levels. Owner feedback clarified that the desired result is not an extra bright sprite at the weapon barrel, but a stronger floor/wall light that visibly flashes walls and casts clear shadows through existing `LightOccluder2D` geometry.

### Collected data

- `issue.json`: issue metadata and original report
- `comments.json`: issue comments at investigation time
- `game_log_20260416_013506.txt`: owner-provided runtime log
- `game_log_20260416_021858.txt`: owner-provided follow-up runtime log from PR feedback

### Timeline

1. 2026-04-15: issue #1845 opened describing correct flash logic but poor floor visibility on Labyrinth.
2. Runtime log confirms the scene loaded was `LabyrinthLevel`, with standard muzzle flash support active and particles enabled.
3. Code inspection showed `MuzzleFlash.tscn` depended on:
   - a very small `GPUParticles2D` burst
   - a shadowed `PointLight2D`
4. Labyrinth inspection showed a very dark flat floor:
   - `Environment/Floor` is a `ColorRect` with `Color(0.15, 0.14, 0.13, 1)`
   - the level also uses cold ambient room lighting, reducing the contrast of short warm flashes
5. 2026-04-15: an initial draft added an additive `Sprite2D` flare so the muzzle itself remained readable on the floor.
6. 2026-04-15: owner feedback rejected the sprite-heavy result and requested the original wall-respecting light behavior with a brighter floor/wall flash and clear shadows.

### Root cause

The muzzle flash was already using the correct shadow-enabled light approach, but its peak energy and radius were tuned too low for the dark Labyrinth floor and wall lighting. A separate additive sprite improves local barrel visibility but bypasses the user's actual target: environmental illumination and shadow readability.

### Fix

The final fix keeps the original `GPUParticles2D` plus shadow-enabled `PointLight2D` structure and removes the additive sprite draft. It raises muzzle flash light energy from `4.5` to `8.0`, increases `PointLight2D.texture_scale` from `4.5` to `6.0`, and slightly strengthens the warm light gradient so the flash is visible on the Labyrinth floor/walls while still respecting wall occlusion and casting shadows.

### Verification strategy

- Updated unit coverage for the brighter light start energy in `tests/unit/test_muzzle_flash.gd`
- Preserved existing duration, particles, shadow-enabled light, and light fade behavior
- Kept the change local to the muzzle flash effect rather than retuning Labyrinth lighting globally
