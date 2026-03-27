# Case Study: Issue #1585 — Rain, Snow, and Water Waves Not Stopping During Last Chance Time Freeze

## Issue Summary

**Reporter:** Jhon-Crow
**Title:** update осадки (update precipitation)
**Description:** Rain, snow, and water waves (water body) must stop when time stops (e.g. during a special last chance).

After the initial fix was shipped (PR #1592), the reporter identified two remaining defects:
1. **Snow and rain simply disappear** (должны останавливаться в одном положении — they should stop in one position, not vanish).
2. **Water waves did not stop** at all.

---

## Evidence

**Game log:** `game_log_20260326_224801.txt`
**Build:** Release/exported build, Windows, Godot 4.3-stable
**Difficulty:** Hard

---

## Timeline of Events (from game log)

| Time | Event |
|------|-------|
| 22:48:01 | Game started, LabyrinthLevel loaded |
| 22:48:03 | DocksLevel loaded — RainEffect started |
| 22:48:13 | Last chance triggered (grenade explosion, 2s freeze) |
| 22:48:13 | `[RainEffect] Rain paused (time stopped)` — rain DISAPPEARED |
| 22:48:13 | `[LastChance] Precipitation paused: RainEffect` |
| 22:48:15 | Last chance ended — rain resumed |
| 22:48:21 | BeachLevel loaded |
| 22:48:28 | Last chance triggered (grenade explosion, 2s freeze) |
| 22:48:28 | `[LastChance] Froze all nodes` — **NO "Precipitation paused: Water" logged** |
| 22:48:30 | Last chance ended — **NO "Precipitation resumed: Water" logged** |
| 22:48:42 | SnowLevel loaded — SnowEffect started |
| 22:48:47 | Last chance triggered — snow DISAPPEARED |
| 22:48:49 | Last chance ended — snow resumed |

The water waves in BeachLevel never stopped during any of the freeze events.

---

## Root Cause Analysis

### Bug 1: Snow and Rain Disappear Instead of Freezing in Place

**Root cause:** `RainEffect.set_time_stopped(true)` and `SnowEffect.set_time_stopped(true)` called `emitting = false` on the `GPUParticles2D` nodes. In Godot 4, setting `GPUParticles2D.emitting = false` **immediately clears all active particles from the GPU buffer**, causing them to vanish. This is not a "pause" — it is a hard stop.

**Expected behavior:** Existing particles should remain visible and frozen in place. New particles should not spawn.

**Fix:** Use `process_mode = PROCESS_MODE_DISABLED` on the `GPUParticles2D` nodes instead of setting `emitting = false`. When processing is disabled, the GPU particle simulation is paused: existing particles stay visible at their last positions, and no new particles are spawned. On resume, process_mode is restored to `PROCESS_MODE_INHERIT` and `emitting` is set appropriately.

### Bug 2: Water Waves Did Not Stop

**Root cause:** `_set_precipitation_time_stopped` in `LastChanceEffectsManager` used `find_children("*", "", true, false)` + a script resource path check to find `WaterBody` nodes:

```gdscript
var path: String = script.resource_path.to_lower()
if "rain_effect" in path or "snow_effect" in path or "water_body" in path:
```

In an **exported (non-debug) Godot 4 build**, GDScript files are compiled into binary format and their `Script.resource_path` property returns an **empty string** (`""`). Therefore `"water_body" in ""` evaluates to `false`, and the WaterBody node was silently skipped.

This explains why the log shows NO "Precipitation paused: Water" entry for BeachLevel, despite the Water/WaterBody node being present in the scene.

Note: RainEffect and SnowEffect were affected by the *same* script-path lookup problem in theory, but since the log *does* show them being found, they may have been found by an alternative path or the behavior differs per platform. Regardless, the script-path approach is fragile.

**Fix:** All three effect types (`RainEffect`, `SnowEffect`, `WaterBody`) now call `add_to_group("precipitation_effects")` in `_ready()`. `LastChanceEffectsManager._set_precipitation_time_stopped` uses `get_tree().get_nodes_in_group("precipitation_effects")` instead of `find_children`. Group membership is stored in the scene tree and does not depend on script resource paths — it works correctly in both debug and exported builds.

---

## Additional Factors

- `WaterBody` extends `Area2D`. The `_freeze_node_except_player` function processes `Area2D` nodes by setting `process_mode = PROCESS_MODE_DISABLED`, which means the WaterBody's `_process` is paused by the general freeze. However, the shader animation continues because it runs entirely on the GPU and is unaffected by GDScript process_mode. Only explicit shader parameter writes (`set_shader_parameter("wave_speed", 0.0)`) can stop the GPU-driven animation.

- For RainEffect/SnowEffect, both are `Node2D` nodes. The general freeze code does NOT disable `Node2D` containers (only StaticBody2D, CharacterBody2D, RigidBody2D, and Area2D are disabled). So the particle nodes kept running, explaining why particles continued to appear momentarily before being stopped by `emitting = false`. With the new `PROCESS_MODE_DISABLED` approach, the particles freeze visually.

---

## Changes Made

| File | Change |
|------|--------|
| `scripts/effects/rain_effect.gd` | `set_time_stopped`: use `PROCESS_MODE_DISABLED/INHERIT` on `_streaks`/`_splashes` instead of `emitting = false`; `_ready`: `add_to_group("precipitation_effects")` |
| `scripts/effects/snow_effect.gd` | `set_time_stopped`: use `PROCESS_MODE_DISABLED/INHERIT` on `_flakes_large`/`_flakes_small` instead of `emitting = false`; `_ready`: `add_to_group("precipitation_effects")` |
| `scripts/objects/water_body.gd` | `_ready`: `add_to_group("precipitation_effects")` |
| `scripts/autoload/last_chance_effects_manager.gd` | `_set_precipitation_time_stopped`: replaced `find_children` + script path check with `get_tree().get_nodes_in_group("precipitation_effects")` |

---

## References

- [Godot 4 docs: GPUParticles2D.emitting](https://docs.godotengine.org/en/stable/classes/class_gpuparticles2d.html#class-gpuparticles2d-property-emitting) — "If true, particles are being emitted." Setting to false clears existing particles.
- [Godot 4 docs: Node.process_mode](https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-property-process_mode) — `PROCESS_MODE_DISABLED` stops all processing including GPU particle simulation.
- [Godot 4 export docs](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html) — Exported scripts are compiled; `resource_path` may return empty string.
- Issue #1585: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1585
- PR #1592: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1592
