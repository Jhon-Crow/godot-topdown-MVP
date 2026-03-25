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

## Solution Iterations

### Iteration 1 (Reverted): Stagger Nav Updates Per-Enemy

The first approach staggered NavigationAgent2D path queries across frames using `SEARCH_NAV_UPDATE_INTERVAL = 3`, reducing queries from 20/frame to ~7/frame. However, **this was insufficient** — FPS still dropped to 19-20 fps (log `game_log_20260325_140936.txt` shows sustained 20 fps from 14:10:05 to 14:10:29). Each enemy still independently generated its own spiral waypoints and computed its own paths.

### Iteration 2 (Reverted): SharedSearchPath — One Path For All Searchers

The owner requested: *"сделай чтоб для всех участников поиска создавался один путь поиска"* (create one search path for all search participants).

**Architecture**: `SharedSearchPath` autoload generated ONE shared set of waypoints with a claim system. All searching enemies claimed the nearest unclaimed waypoint from this shared pool.

**Outcome**: **FPS dropped further** (worse than before). Feedback: *"просадка fps ещё больше стала"* (FPS drop became even larger). The claim system, centralized zone tracking, spiral generation, and per-frame claim lookups added overhead rather than reducing it.

**Root cause of failure**: The centralized approach introduced new per-frame overhead (claim lookups, zone dictionary access, spiral generation on expansion) that outweighed the savings from shared waypoints. The real problem is simply having too many enemies in SEARCHING state at all.

### Iteration 3 (Current): Slot Limiter — Maximum 2 Simultaneous Searchers

The owner requested: *"используй самый простой и оптимальный способ реализовать поиск. (например чтоб 1-2 врага максимум учавствовали в поиске) в общем делай максимально оптимизированный вариант"* (use the simplest/most optimal way — max 1-2 enemies searching).

**Architecture**: `SharedSearchPath` autoload is replaced with a minimal slot limiter (42 lines). Max `MAX_SEARCHERS = 2` enemies can hold SEARCHING slots at any time. Excess enemies trying to enter SEARCHING go to IDLE instead.

```gdscript
# SharedSearchPath autoload — minimal slot limiter
const MAX_SEARCHERS: int = 2
func try_acquire(enemy_id: int) -> bool  # true = slot granted, false = go IDLE
func release(enemy_id: int) -> void       # free slot on SEARCHING exit/death/tree exit
func get_active_count() -> int
func is_active(enemy_id: int) -> bool
```

**Per-enemy search logic is fully preserved** (spiral waypoints, predefined paths, zone tracking, stagger) — it works fine for 1-2 enemies.

**Key insight**: With only 2 searchers active, total nav queries drop from 20/frame to ≤2/frame — a 10x reduction, regardless of stagger. This is the simplest possible approach with maximum effect.

## Evidence from Game Logs

### Log 1: game_log_20260324_202643.txt (Pre-fix baseline)

| Timestamp  | FPS  | Searching Enemies | Event                          |
|------------|------|-------------------|--------------------------------|
| 20:27:00   | 29   | ~17               | Multiple expand rings          |
| 20:27:28   | **21** | 20              | **All enemies re-expand r=175**|

### Log 2: game_log_20260325_140936.txt (After stagger-only fix — insufficient)

| Timestamp  | FPS  | Event                                            |
|------------|------|--------------------------------------------------|
| 14:10:02   | 29   | First drop — enemies enter SEARCHING              |
| 14:10:05   | 22   | 20 enemies searching with staggered nav (interval=3) |
| 14:10:07   | 19   | Sustained searching — **still too many queries**  |
| 14:10:10-29| **19-20** | 20 seconds of sustained 20fps — stagger alone is not enough |

## Expected Performance Improvement (Slot Limiter)

| Metric                          | Before (per-enemy) | Stagger-only | Shared Path (iter 2) | **Slot Limiter (iter 3)** |
|---------------------------------|---------------------|--------------|----------------------|---------------------------|
| Active searchers                | 20                  | 20           | 20                   | **2**                     |
| Waypoint generators             | 20                  | 20           | 1 (but heavier)      | **2** (lightweight)       |
| Nav queries/frame               | 20                  | ~7           | ~3 (but more overhead) | **≤2**                  |
| NavigationServer2D checks/expansion | 20x100=2000    | 2000         | 100                  | **2x100=200**             |
| SharedSearchPath overhead/frame | 0                   | 0            | high (claims+zones)  | **minimal (dict lookup)** |
| enemy.gd lines                  | 4999                | 4999         | 4887                 | **5000**                  |

## References

- [Godot Forum: How to optimize multiple pathfinding](https://forum.godotengine.org/t/how-to-optimize-multiple-pathfinding-optimizing-a-huge-number-of-enemies/50709) — Recommends staggering updates and chunking
- [Godot Forum: Large amounts of NavigationAgents](https://godotforums.org/d/31934-how-to-handle-large-amounts-of-navigationagents-pathfinding) — Performance degrades with many simultaneous agents
- [Godot Docs: Optimizing Navigation Performance](https://docs.godotengine.org/en/latest/tutorials/navigation/navigation_optimizing_performance.html) — Official guidance
- Issue #883 in this repo — Vision check stagger pattern (prior art for frame distribution)
- Issue #1289 in this repo — `path_desired_distance` optimization for PURSUING state

## Files Changed

- `scripts/autoload/shared_search_path.gd` — New SharedSearchPath autoload (centralized waypoint generation, claim system)
- `scripts/objects/enemy.gd` — Removed per-enemy search code, delegate to SharedSearchPath (-112 lines)
- `project.godot` — Register SharedSearchPath autoload
- `tests/unit/test_shared_search_path.gd` — Unit tests for shared search path system
