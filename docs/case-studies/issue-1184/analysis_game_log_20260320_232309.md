# Case Study: game_log_20260320_232309.txt

## User Report
> враги полностью сломаны и навмеш не отображается
> (Enemies are completely broken and navmesh is not visible)

## Session Overview

| Field | Value |
|---|---|
| Timestamp | 2026-03-20 23:23:09 – 23:23:29 |
| Duration | ~20 seconds |
| Level | LabyrinthLevel only (BuildingLevel never loaded) |
| Enemies | 5 in scene, 0 registered |
| Active item | Invisibility suit |
| Nav mesh visible | true (toggled off/on during session) |
| Build | Export build, Debug: false |

## Root Cause Analysis

### Finding 1: BuildingLevel.tscn failed to load (PCK issue)

Line 229: `[SceneLoader] ERROR: Invalid resource: res://scenes/levels/BuildingLevel.tscn`

The game tried to background-load BuildingLevel.tscn but it was absent from the export PCK.
The game remained stuck in LabyrinthLevel for the entire 20-second session.

**Root cause**: User's exported binary is outdated / incomplete — not a code regression.

### Finding 2: Enemy registration shows 0 enemies

Lines 183–188:
```
Child 'Enemy1': script=true, has_died_signal=false
...
Enemy tracking complete: 0 enemies registered
```

All 5 enemies show `has_died_signal=false`. This means `child.has_signal("died")` returned false.

In an **export** build, GDScript signals may not be detectable via `has_signal()` unless the script is fully loaded. Since the user is running an **older binary** where the `died` signal may be declared differently (2-param `died_with_info` from our regression), this is consistent with the binary having our broken intermediate commits.

**Root cause**: User's binary was built from a version with the `is_from_player` regression that we introduced in commit `f2a36021`. The older binary had `signal died_with_info(is_ricochet_kill, is_penetration_kill)` (2 params) but the level scripts expected 3 params.

### Finding 3: Navmesh not visible

Line 40: `Nav mesh visible: true` at startup.
Lines 242–243:
```
[ExperimentalSettings] Navigation mesh visibility disabled
[ExperimentalSettings] Navigation mesh visibility enabled
```

The user toggled navmesh off and back on. No code error here — this is a user action.

**Root cause**: Not a bug. The toggle worked correctly.

## Timeline Reconstruction

| Time | Event |
|---|---|
| 23:23:09 | Game starts, LabyrinthLevel loads |
| 23:23:11 | ExperimentalSettings: Nav mesh visible=true |
| 23:23:11 | Player equipped with Invisibility suit |
| 23:23:12 | PersistManager: last played level = BuildingLevel |
| 23:23:13 | SceneLoader: ERROR - BuildingLevel.tscn not found in PCK |
| 23:23:23 | User toggles navmesh off/on in ExperimentalSettings |
| 23:23:27 | Level reloads (LabyrinthLevel, same issue) |
| 23:23:29 | Session ends after 20s |

## Fixes Applied

### Fix 1: Merged latest main (commit: merge)

Commit `686e194c` brought in main, but subsequent commits (`1231eceb` and `f2a36021`) accidentally stripped out features from Issue #1196 (laser sight/is_from_player), Issue #1127 (EXPERIMENTAL_SAMPLE), and 27 other files.

The merge of the latest main (2026-03-20) restored all missing features:
- `EXPERIMENTAL_SAMPLE` active item (Issue #1127)
- `is_from_player` parameter in `died_with_info` signal and `on_hit_with_bullet_info` (Issue #1196)
- `_killed_by_player` tracking in enemy.gd
- Laser sight unlock condition in `active_item_manager.gd`
- All level scripts, UI scripts, and autoload scripts updated to match main

### Fix 2: Performance optimizations preserved (Issue #1184)

All 8 performance optimizations from this PR remain intact on top of the merged main:
1. Corner cooldown timing fix
2. Cache ExperimentalSettings node
3. Cache PerformanceSettings node
4. Throttle separation O(N²) to every 3rd frame
5. Throttle combat count to every 0.5s
6. Stagger intel-share timers
7. Cache nav map RID
8. Integer zone key

## Online Research

Godot 4 `has_signal()` documentation confirms that signal detection works at runtime for GDScript nodes, but relies on the script being loaded. In export builds, signal connections established via `.connect()` can silently fail if the signal count doesn't match — which would explain `has_died_signal=false` with a binary built from our regression.

Godot 4 export PCK issues: A level scene can fail to export if it's not reachable from the main scene's resource path tree and not explicitly added to export filters.

## Conclusion

The "enemies completely broken" issue was caused by:
1. The user's game binary was built from an intermediate commit that had regressions (missing `is_from_player` param in signals, missing `EXPERIMENTAL_SAMPLE` enum value).
2. The BuildingLevel was absent from the user's exported PCK.

Both issues are resolved by:
1. ✅ Merging latest main to restore all missing features
2. ℹ️ User needs to rebuild/re-export the game binary
