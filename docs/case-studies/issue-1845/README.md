## Issue 1845: muzzle flashes are barely visible on Labyrinth floor

Issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1845
PR: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1846

### Summary

The muzzle flash logic was spawning correctly, but on `LabyrinthLevel` the effect was hard to read against the flat dark floor. It remained visible on enemies and blood because those sprite surfaces provide stronger local contrast than the floor `ColorRect`.

### Collected data

- `issue.json`: issue metadata and original report
- `comments.json`: issue comments at investigation time
- `game_log_20260416_013506.txt`: owner-provided runtime log

### Timeline

1. 2026-04-15: issue #1845 opened describing correct flash logic but poor floor visibility on Labyrinth.
2. Runtime log confirms the scene loaded was `LabyrinthLevel`, with standard muzzle flash support active and particles enabled.
3. Code inspection showed `MuzzleFlash.tscn` depended on:
   - a very small `GPUParticles2D` burst
   - a shadowed `PointLight2D`
4. Labyrinth inspection showed a very dark flat floor:
   - `Environment/Floor` is a `ColorRect` with `Color(0.15, 0.14, 0.13, 1)`
   - the level also uses cold ambient room lighting, reducing the contrast of short warm flashes

### Root cause

The muzzle flash was effectively light-only. That works better on walls and sprites with texture or silhouette contrast, but reads poorly on a dark uniform floor. The light was not wrong; it simply did not provide enough visible screen-space flare on that specific background.

### Fix

The fix keeps the existing wall-respecting `PointLight2D`, but adds a short-lived additive `Sprite2D` flare in the muzzle direction. This gives the flash a visible emissive shape on flat floor surfaces without removing wall occlusion from the actual light.

### Verification strategy

- Added unit coverage for the new sprite fade path in `tests/unit/test_muzzle_flash.gd`
- Preserved existing duration and light fade behavior
- Kept the change local to the muzzle flash effect rather than retuning Labyrinth lighting globally
