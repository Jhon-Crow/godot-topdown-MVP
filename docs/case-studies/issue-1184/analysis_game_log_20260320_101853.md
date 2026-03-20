# Analysis: game_log_20260320_101853.txt

## Session Summary

| Field | Value |
|---|---|
| Date | 2026-03-20 10:18:53 |
| Reported issue | FPS capped at 30 on BuildingLevel with all enemies in IDLE |
| Level | BuildingLevel (10 enemies) |
| FPS counter enabled | Yes |

## Timeline Reconstruction

| Time | Event |
|---|---|
| 10:18:53 | Game starts on LabyrinthLevel (5 enemies) |
| 10:18:55 | FPS drop: 2fps (shader warmup spike — pre-existing issue #343) |
| 10:18:55–10:19:08 | LabyrinthLevel runs at stable 60fps (frame 60 per 1.0s confirmed) |
| 10:19:08–10:19:11 | Scene transition to LabyrinthLevel (fresh load after PersistManager) |
| 10:19:11–10:20:47 | LabyrinthLevel 5 enemies — stable 60fps |
| 10:20:47 | Transition to BuildingLevel (10 enemies) |
| 10:20:48 | **FPS drop: 25fps** (BuildingLevel spawn, all enemies IDLE) |
| 10:20:51–10:20:52 | **FPS drops: 29fps** (enemies still in IDLE/PATROL) |
| 10:20:47–10:21:07 | BuildingLevel sustained low FPS with enemies in IDLE |

## Root Causes Found (3 new bottlenecks)

### 1. `_apply_separation_force()` — O(N²) every frame
- Calls `get_tree().get_nodes_in_group("enemies")` every physics frame
- With 10 enemies: 10 array allocations + 100 iterations per frame
- At 60fps: 6000 iterations/sec just for separation
- This runs even when all enemies are IDLE (velocity=0, so force is applied but wasted)
- **Fix**: Run only every 3rd frame per enemy (staggered by `get_instance_id() % 3`)

### 2. `get_node_or_null("/root/PerformanceSettings")` — every physics frame
- Called in `_physics_process()` for every alive enemy, every frame
- Autoload dictionary lookup × 10 enemies × 60fps = 600 calls/sec
- **Fix**: Cache in `_ready()` as `_perf_settings_node`

### 3. `_detect_perpendicular_opening()` — P4↔P3 oscillation
- Patrol enemy (Enemy7) continuously triggers P4:velocity → P3:corner → P4:velocity → ...
- Each trigger: 2 raycasts (perpendicular check left and right)
- Enemy7 was generating 50+ ROT_CHANGE log entries per second
- After corner check timer expires (0.3s), it immediately detects opening again
- **Fix**: Add `_corner_check_cooldown` — after a corner check completes, block re-trigger for 0.3s

## Evidence from Log

```
[10:20:48] [WARN] [FPS] Drop detected: 25 fps (threshold: 30)
[10:20:52] [WARN] [FPS] Drop detected: 29 fps (threshold: 30)
[10:20:55] [WARN] [FPS] Drop detected: 29 fps (threshold: 30)
```

Recording frames confirm 60fps normally, but FPS counter shows 25-29 on BuildingLevel idle.
Enemy7 (PATROL) generated massive ROT_CHANGE spam:
```
[10:20:49] Enemy7 ROT_CHANGE: none -> P3:corner
[10:20:49] Enemy7 ROT_CHANGE: P3:corner -> P4:velocity
[10:20:49] Enemy7 ROT_CHANGE: P4:velocity -> P3:corner
... (repeated dozens of times per second)
```

## Fixes Applied

| # | Fix | File | Impact |
|---|---|---|---|
| 1 | Cache `PerformanceSettings` node in `_ready()` | enemy.gd:367,758 | Eliminates 600 dict lookups/sec |
| 2 | Throttle `_apply_separation_force()` to every 3rd frame | enemy.gd:858 | Reduces O(N²) by 66% |
| 3 | Add `_corner_check_cooldown` to prevent P4↔P3 oscillation | enemy.gd:4105-4107 | Eliminates continuous raycasting |
