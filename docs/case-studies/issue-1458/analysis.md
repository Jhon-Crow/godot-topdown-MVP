# Issue #1458: SEARCHING State Performance Drop (30 FPS loss)

## Problem

When all enemies enter the SEARCHING state simultaneously, the game drops from ~60 FPS to ~27-29 FPS. The issue was reported with 20 enemies on a large map (warehouse/docks level).

## Root Cause Analysis (Round 2 — March 2026)

After the initial fixes (oscillation prevention, nav target caching, redirect guard), the owner reported the FPS drop **persisted**. Screenshots showed:
- Dense overlapping grids of orange waypoints around containers
- Long diagonal yellow lines crossing the entire map
- Multiple enemies clustered with redundant overlapping waypoint networks

Analysis of `game_log_20260325_031409.txt` (111,918 lines) revealed:

### Primary Bottleneck: Timeout Log Spam (97,860 entries)

The `_search_state_timer >= SEARCH_MAX_DURATION` check fires every physics frame once the 30s timeout is reached. When IDLE is disabled, `_transition_to_idle()` redirects back to SEARCHING via the `_current_state != AIState.SEARCHING` guard, which correctly prevents waypoint regeneration — but **does not reset the timer**. So the timeout condition continues to fire every frame, logging "SEARCHING timeout after X.Xs" with an ever-incrementing timer (30.0s → 52.6s). With 20 enemies, this produced:
- **97,860 log file writes** in ~8 minutes
- **97,860 `_transition_to_idle()` calls** (each doing a `get_node_or_null()` lookup)

### Secondary Bottleneck: Expanding Square Spiral Algorithm

The `_generate_search_waypoints()` function used an expanding square spiral:
```
while iters < 100:
    NavigationServer2D.map_get_closest_point(nav_map, next_pos)  # Up to 100 calls
```
Problems:
- **Up to 100 `map_get_closest_point()` calls per generation** per enemy
- **Mechanical grid patterns** visible as overlapping debug lines
- **Waypoints at fixed 75px spacing** created identical grids for nearby enemies
- **Max radius of 2000px** caused paths to cross the entire map (visible as long diagonal yellow lines in screenshots)
- With 20 enemies, each generation batch = up to 2,000 NavigationServer queries

### Tertiary Bottleneck: Excessive Ring Expansion

When all spiral waypoints were visited, `_search_radius` expanded by 75px and regenerated. With `SEARCH_MAX_RADIUS = 2000` and `SEARCH_INITIAL_RADIUS = 100`, this allowed 25+ expansion rounds, each generating another 100 nav queries.

## Quantified Impact

| Metric | Before (Round 1) | After Round 1 | After Round 2 |
|--------|------------------|---------------|---------------|
| Timeout log writes (8 min, 20 enemies) | 0 (timeout worked) | 97,860 (loop bug) | 20 (once per enemy) |
| Nav calls per waypoint generation | 100 (spiral) | 100 (unchanged) | ~10 (random-radius) |
| Max waypoints per batch | 20 | 20 | 5 |
| Max search radius | 2000px | 2000px | 600px |
| Radius expansion steps to max | 25 | 25 | ~5 |
| Visual path quality | Mechanical grid | Mechanical grid | Natural random spread |

## Solution (Round 2)

### Fix 1: Replace spiral with random-radius waypoint generation
Replaced the expanding square spiral (`_search_direction`, `_search_leg_length`, etc.) with random point generation:
- Generate `SEARCH_WAYPOINT_COUNT` (5) random points within `_search_radius` of `_search_center`
- Each point is a random angle + random distance (30%-100% of radius)
- Snap to navmesh using `map_get_closest_point()`, reject if too far (>50px)
- **Max ~10 nav calls per batch** vs 100 in the spiral
- Points are naturally spread, no mechanical grid patterns

### Fix 2: Reduce max search radius
Reduced `SEARCH_MAX_RADIUS` from 2000 to 600. Enemies now search locally near the last known player position instead of expanding across the entire map. This also reduces the number of expansion rounds from 25 to ~5.

### Fix 3: Throttle timeout log
Added `_search_timeout_logged` flag — the "SEARCHING timeout" message logs once per search session instead of every physics frame. This eliminated 97,860 redundant log writes.

### Fix 4: Increased initial radius
Changed `SEARCH_INITIAL_RADIUS` from 100 to 150 and `SEARCH_RADIUS_EXPANSION` from 75 to 100. Random points need a larger radius to find navigable positions that aren't clustered together.

## Fixes Retained from Round 1

- **SEARCH_MIN_TIME_BEFORE_COMBAT (0.3s)**: Prevents rapid SEARCHING↔COMBAT oscillation
- **Nav target caching**: `_search_last_nav_target` prevents redundant `target_position` updates
- **Redirect chain guard**: `_current_state != AIState.SEARCHING` check in `_transition_to_idle()`
- **Combat log throttle**: "Player spotted" logged once per session

## Research: Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| `map_get_random_point()` | Cheapest, guaranteed valid | Added in Godot 4.4 (project uses 4.3) | Incompatible |
| Predefined `Path2D` waypoints | Zero runtime cost | Requires level designer work, rigid | Already supported via `SearchPathWaypoints` |
| Random-radius + snap to navmesh | Low nav calls (~10), natural paths | Rejection sampling may miss some points | **Chosen** |
| Probability/Markov chain | Most intelligent search | High complexity, needs graph infrastructure | Overkill |

## References

- Godot docs: [Optimizing Navigation Performance](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_optimizing_performance.html)
- Godot docs: [NavigationServer2D](https://docs.godotengine.org/en/stable/classes/class_navigationserver2d.html)
- Godot Forum: [Nav Agent tanks my fps](https://forum.godotengine.org/t/nav-agent-tanks-my-fps/115578)
- Issue #1186: PerformanceSettings state redirect chain
- Issue #322: SEARCHING state implementation
- Issue #330: Engaged enemies search indefinitely
- Issue #405: Search continues indefinitely after engagement
- Issue #1225: Predefined search path waypoints
