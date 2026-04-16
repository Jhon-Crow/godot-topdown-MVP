## Issue 1845: muzzle flashes are too dim on Labyrinth Complex

Issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1845
PR: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1846

### Summary

The muzzle flash logic was spawning correctly, but on `Labyrinth2Level` (`Labyrinth Complex`) the flash light was visible on dynamic objects such as particles, blood, and shell casings while the map floor itself did not brighten. Owner feedback clarified that the desired result is not an extra bright sprite at the weapon barrel, but a stronger floor/wall light that visibly flashes the environment and casts clear shadows through existing `LightOccluder2D` geometry.

### Collected data

- `issue.json`: issue metadata and original report
- `comments.json`: issue comments at investigation time
- `game_log_20260416_013506.txt`: owner-provided runtime log
- `game_log_20260416_021858.txt`: owner-provided follow-up runtime log from PR feedback
- `game_log_20260416_231945.txt`: owner-provided follow-up runtime log confirming the remaining problem on `Labyrinth Complex`

### Timeline

1. 2026-04-15: issue #1845 opened describing correct flash logic but poor floor visibility on Labyrinth.
2. Runtime logs confirmed the issue on Labyrinth-family scenes, with standard muzzle flash support active and particles enabled.
3. Code inspection showed `MuzzleFlash.tscn` depended on:
   - a very small `GPUParticles2D` burst
   - a shadowed `PointLight2D`
4. Labyrinth-family inspection showed dark flat floors and warm/cold room lighting that reduce the contrast of short warm flashes.
5. 2026-04-15: an initial draft added an additive `Sprite2D` flare so the muzzle itself remained readable on the floor.
6. 2026-04-15: owner feedback rejected the sprite-heavy result and requested the original wall-respecting light behavior with a brighter floor/wall flash and clear shadows.
7. 2026-04-16: owner feedback clarified that `Labyrinth Complex` still showed flash response on particles, blood, and shell casings, but not on the map floor.
8. Code inspection showed `Labyrinth2Level.tscn` used `Environment/Floor` as a `ColorRect`, while the desired behavior requires light-reactive world geometry under `PointLight2D`.

### Root cause

The muzzle flash was already using the correct shadow-enabled light approach. The remaining `Labyrinth Complex` failure was not primarily energy: dynamic objects responded to the light, but the floor was a `ColorRect`, so it behaved like a flat UI/control surface instead of light-reactive world geometry. Raising energy made lit objects brighter but could not make that floor surface participate in `PointLight2D` illumination.

### Fix

The final fix keeps the original `GPUParticles2D` plus shadow-enabled `PointLight2D` structure and removes the additive sprite draft. It raises muzzle flash light energy from `4.5` to `8.0`, increases `PointLight2D.texture_scale` from `4.5` to `6.0`, slightly strengthens the warm light gradient, and changes `Labyrinth2Level.tscn` `Environment/Floor` from `ColorRect` to a same-bounds, same-color `Polygon2D` so the Complex floor can receive the muzzle flash light while wall occluders still cast shadows.

### Verification strategy

- Updated unit coverage for the brighter light start energy in `tests/unit/test_muzzle_flash.gd`
- Added regression coverage that `Labyrinth Complex` floor uses light-reactive `Polygon2D` geometry while preserving bounds and color in `tests/unit/test_labyrinth2_level.gd`
- Preserved existing duration, particles, shadow-enabled light, and light fade behavior
- Kept the effect changes local to the muzzle flash and changed only the problematic Complex floor rendering primitive
