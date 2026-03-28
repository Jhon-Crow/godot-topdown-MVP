# Root Cause Analysis — Issue #1627 (Snow interactions not visible)

## Source of investigation
Game log provided by owner: `game_log_20260328_084242.txt` (2026-03-28 08:42:42)

## Timeline of events

| Time | Event |
|------|-------|
| 08:42:42 | Game started — `Build info: not available (build_info.cfg not found)` |
| 08:42:51 | WinterForestLevel loaded |
| 08:42:51 | `[SnowEffect] Snow started` (existing snowfall particles — not our code) |
| 08:42:51 | `[BloodyFeet:Player]` / `[BloodyFeet:Clearing_*]` initialized — OLD code only |
| (never) | No `[WinterForestLevel]` entries in FileLogger |
| (never) | No `[SnowFeet:...]` entries |
| (never) | No `[SnowBloodAbsorption]` entries |

## Root Causes

### RC-1: Old binary (build predates our changes)
The log header says `Build info: not available (build_info.cfg not found)`. The
`build_info.cfg` in our branch has `branch="issue-1142-..."` — but the user's build
comes from a local executable (`I:/Загрузки/godot exe/ОСадКИ/Godot-Top-Down-Template.exe`)
that was exported **before** our changes were merged. The user needs to build a new
binary from the `issue-1627-b7e2d4ef93ef` branch to see any changes.

### RC-2: Blood absorption never triggered (critical bug)
`spawn_snow_blood_absorption()` existed on the level node but **nothing called it**
when blood landed on snow. `ImpactEffectsManager._schedule_delayed_decal()` always
spawns a regular `BloodDecal` — it had no snow-awareness.

**Fix:** Added `_try_spawn_snow_blood_absorption(scene, landing_pos)` to
`ImpactEffectsManager`. It checks if the landing position falls inside any node in
the `"snow_surface"` group (a `ColorRect` in WinterForestLevel.tscn). If yes, it
calls `scene.spawn_snow_blood_absorption(pos)` and returns early, skipping the
regular `BloodDecal` puddle.

### RC-3: Footprint and blood stain z_index = 0 (invisible on snow)
Both `SnowFootprint` and `SnowBloodAbsorption` set `z_index = 0` in `_ready()`,
same as the snow `ColorRect` background. On top of that, `SnowFeetComponent._spawn_footprint()`
overrode it back to `0` after instantiation, fighting `_ready()`.

**Fix:** Changed both effects to `z_index = 1`. Removed the override in the spawner.

### RC-4: SnowFeetComponent not logging to FileLogger by default
`debug_logging` defaults to `false`. The old `_log()` function skipped both print
AND FileLogger when `debug_logging` was false, so initialization of `SnowFeetComponent`
left no trace in the game log — making it impossible to confirm whether the component
was running at all.

**Fix:** Added `_log_always()` which always writes to FileLogger regardless of the
debug flag. Used for the `_ready()` init message. Future game logs will show
`[SnowFeet:Player]` and `[SnowFeet:EnemyName]` entries confirming setup.

### RC-5: `_setup_snow_interactions` missing diagnostic logging
Several paths (SnowBloodAbsorption missing, player null, etc.) only called
`push_warning()` which goes to the editor output — not to the FileLogger file.

**Fix:** Added `_log_to_file()` calls for every branch (success and failure) in
`_setup_snow_interactions()`.

## What to expect in next build's log

If the user builds from the `issue-1627-b7e2d4ef93ef` branch:

```
[08:xx:xx] [INFO] [WinterForestLevel] Setting up snow interactions (Issue #1627)...
[08:xx:xx] [INFO] [WinterForestLevel] SnowBloodAbsorption scene loaded
[08:xx:xx] [INFO] [WinterForestLevel] SnowFeetComponent added to Player
[08:xx:xx] [INFO] [WinterForestLevel] Player BloodyFeetComponent blood_steps_count reduced to 6 (snow map)
[08:xx:xx] [INFO] [WinterForestLevel] Snow interactions setup complete: N enemies equipped with SnowFeetComponent
[08:xx:xx] [INFO] [SnowFeet:Player] SnowFeetComponent ready on Player
[08:xx:xx] [INFO] [SnowFeet:Clearing_DroneOperator1] SnowFeetComponent ready on Clearing_DroneOperator1
...
```
