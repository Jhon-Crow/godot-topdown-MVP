# Case Study: Issue #1458 — Search State Pathfinding Performance Drop

## Summary

When all enemies enter the SEARCHING state simultaneously, game FPS drops by ~30 fps (from ~57 to ~21-27 fps). The root cause is that every enemy in SEARCHING state triggers a full NavigationServer2D path recalculation **every physics frame** by setting `_nav_agent.target_position` unconditionally.

## Timeline of Events

1. **2026-03-24 20:26:43** — Game starts on LabyrinthLevel with 5 enemies, all in initial SEARCHING state.
2. **2026-03-24 20:26:46** — First FPS drop to 27 fps. All 5 enemies expand search rings simultaneously (`r=175 wps=8`).
3. **2026-03-24 20:26:54** — Level changes to map with 20 enemies, all spawning in SEARCHING state.
4. **2026-03-24 20:27:00** — FPS drops to 29 fps with 20 enemies searching.
5. **2026-03-24 20:27:28** — Worst FPS drop to **21 fps** — all enemies expanding search rings at the same time.
6. **2026-03-24 20:27:29** — 12 enemies simultaneously expand outer rings (`r=175 wps=8`).

## Root Cause Analysis

### Primary Bottleneck: Per-Frame NavigationServer2D Path Queries

In `_process_searching_state()` (enemy.gd:2408), every searching enemy executes:
```gdscript
_nav_agent.target_position = target_waypoint  # Every physics frame!
```

In Godot 4, setting `target_position` on a NavigationAgent2D triggers a new path query to the NavigationServer2D. With 20 enemies all in SEARCHING state at 60 fps physics:
- **20 enemies x 60 fps = 1,200 path queries/second**

This is the dominant performance cost. Other states (like COMBAT, PURSUING) also set `target_position` per-frame, but those states typically have fewer simultaneous enemies.

### Secondary Bottleneck: Simultaneous Search Ring Expansion

All enemies expand their search radius at roughly the same time because they all start searching simultaneously. Each expansion calls `_generate_search_waypoints()`, which calls `_is_waypoint_navigable()` (a `NavigationServer2D.map_get_closest_point()` call) up to 100 times per enemy.

### Tertiary Bottleneck: String-Based Zone Key Generation

`_get_zone_key()` used `"%d,%d" % [...]` string formatting for every zone check. String formatting allocates new String objects on every call, creating GC pressure.

## Evidence from Game Logs

Key correlations between FPS drops and search activity (from `game_log_20260324_202643.txt`):

| Timestamp  | FPS  | Searching Enemies | Event                          |
|------------|------|-------------------|--------------------------------|
| 20:26:46   | 27   | 5                 | All 5 expand ring r=175        |
| 20:27:00   | 29   | ~17               | Multiple expand rings          |
| 20:27:06   | 29   | ~15               | Continued expansion            |
| 20:27:12   | 29   | ~13               | Expansion at r=250             |
| 20:27:18   | 29   | ~12               | Sustained searching            |
| 20:27:24   | 29   | ~10               | Sustained searching            |
| 20:27:28   | **21** | 20              | **All enemies re-expand r=175**|
| 20:27:29   | -    | 12                | 12 simultaneous expansions     |

## Solution

### Fix 1: Stagger Nav Target Updates Across Frames (Primary)

Inspired by the existing `VISION_CHECK_INTERVAL` pattern (Issue #883), we stagger NavigationAgent2D path queries across frames using `SEARCH_NAV_UPDATE_INTERVAL = 3`:

```gdscript
# Issue #1458: Only update nav target on staggered frames or when target changed
_search_nav_frame_counter += 1
var is_nav_update_frame := (_search_nav_frame_counter % SEARCH_NAV_UPDATE_INTERVAL) == _search_nav_frame_offset
var target_changed := _search_cached_nav_target.distance_squared_to(target_waypoint) > 1.0
if is_nav_update_frame or target_changed:
    _search_cached_nav_target = target_waypoint
    _nav_agent.target_position = target_waypoint
```

**Impact**: Reduces path queries from 20/frame to ~7/frame (3x reduction). Each enemy still gets smooth updates at ~20 fps (every 3rd frame at 60 fps physics), which is sufficient for the slow search movement speed (0.7x move_speed).

The `_search_nav_frame_offset` is set from `get_instance_id() % SEARCH_NAV_UPDATE_INTERVAL` in `_ready()`, ensuring enemies are evenly distributed across frames (same pattern as vision check staggering).

### Fix 2: Integer Zone Keys Instead of String Formatting

Replaced string-based zone keys with integer hashing:

```gdscript
# Before (allocates String every call):
func _get_zone_key(pos: Vector2) -> String:
    return "%d,%d" % [int(pos.x / SNAP) * int(SNAP), int(pos.y / SNAP) * int(SNAP)]

# After (no allocation, integer arithmetic only):
func _get_zone_key(pos: Vector2) -> int:
    var gx := int(pos.x / SEARCH_ZONE_SNAP_SIZE)
    var gy := int(pos.y / SEARCH_ZONE_SNAP_SIZE)
    return gx * 100003 + gy  # large prime to avoid collisions
```

**Impact**: Eliminates String allocations in hot path. Dictionary lookups with int keys are also faster than String keys.

## Expected Performance Improvement

| Metric                    | Before          | After           | Improvement |
|---------------------------|-----------------|-----------------|-------------|
| Nav queries/frame (20 enemies) | 20         | ~7              | ~3x fewer   |
| Zone key allocation       | String per call | int (no alloc)  | No GC       |
| Estimated FPS with 20 enemies | 21-29 fps  | ~45-55 fps      | +15-25 fps  |

## References

- [Godot Forum: How to optimize multiple pathfinding](https://forum.godotengine.org/t/how-to-optimize-multiple-pathfinding-optimizing-a-huge-number-of-enemies/50709) — Recommends staggering updates and chunking
- [Godot Forum: Large amounts of NavigationAgents](https://godotforums.org/d/31934-how-to-handle-large-amounts-of-navigationagents-pathfinding) — Performance degrades with many simultaneous agents
- [Godot Docs: Optimizing Navigation Performance](https://docs.godotengine.org/en/latest/tutorials/navigation/navigation_optimizing_performance.html) — Official guidance
- Issue #883 in this repo — Vision check stagger pattern (prior art for frame distribution)
- Issue #1289 in this repo — `path_desired_distance` optimization for PURSUING state

## Files Changed

- `scripts/objects/enemy.gd` — Core optimization (stagger nav updates, integer zone keys)
- `tests/unit/test_enemy.gd` — Regression tests for optimization constants
