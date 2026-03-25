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

## Solution (Round 2) — Random-Radius Approach

Replaced expanding square spiral with random-radius waypoint generation. Reduced max radius from 2000→600, throttled timeout log, cached nav targets. This reduced nav calls from 100 to ~10 per batch.

**Result**: FPS drop persisted — random waypoints still caused 30 FPS loss with 20 enemies. Paths looked random/illogical, duplicated between enemies.

## Root Cause Analysis (Round 3 — March 2026)

After round 2 fixes, owner reported:
- **FPS drop still 30 fps** (game_log_20260325_034754.txt: FPS drops to 16-29)
- **Paths look illogical** — random waypoints don't correspond to where the player could actually be hiding
- **Paths duplicate between enemies** — each enemy independently generates waypoints

Analysis of game_log_20260325_034754.txt (2,679 lines):
- FPS drops logged at 03:47:56 (17fps), 03:49:25 (16fps), and sustained 28-29fps from 03:49:29 onwards
- All 5 enemies simultaneously expanding outer rings, generating overlapping waypoint sets
- Corner check entries show constant scanning without purposeful direction
- The random-radius approach generates points without considering where the player could actually be hiding

### Core Problem: Per-frame cost of search management
Even with fewer nav calls per generation, the _process_searching_state function runs every physics frame for every enemy. With random waypoints, enemies wander aimlessly, frequently hitting expansion triggers that regenerate waypoints, causing repeated NavigationServer calls.

## Solution (Round 3) — Cover-Inspection Approach

Complete redesign based on owner's feedback: instead of random/spiral waypoints, use a **ray-based obstacle inspection system** similar to the existing cover-finding mechanism.

### How it works:
1. **Ray casting from search center**: Cast 36 rays (10° apart) from the last known player position outward to find obstacles
2. **Compute inspection points**: Each obstacle hit generates a point 45px past the obstacle edge (where the player could be hiding)
3. **Snap to navmesh**: Points are validated and snapped to the navigation mesh
4. **Deduplicate**: Points within 50px of each other are merged
5. **Enemies inspect points**: Each enemy picks the nearest uninspected point and walks there
6. **FOV clearing**: When an inspection point is within 60px of any enemy AND within their FOV cone, it's marked as "inspected" (no raycasts needed — pure math)
7. **Cross-enemy sync**: Cleared flags are shared between all searching enemies

### Performance characteristics:
- **One-time cost**: 36 raycasts + ~36 nav snaps at search start = ~72 calls total (not per frame)
- **Per-frame cost**: Simple distance + angle check for FOV clearing (no raycasts, no nav calls)
- **No expanding radius**: All inspection points generated upfront
- **No per-frame waypoint regeneration**: Points are pre-computed, enemies just walk to them

### Debug visualization:
- Green circles: uninspected points (potential hiding spots)
- Gray circles: inspected/cleared points
- Yellow line: enemy → assigned target

## Quantified Impact

| Metric | Round 1 (spiral) | Round 2 (random) | Round 3 (cover-inspect) |
|--------|-------------------|-------------------|-------------------------|
| Nav calls at search start | 100+ per enemy | ~10 per enemy | ~72 total (once) |
| Nav calls per frame | 0 (cached) | 0 (cached) | 0 |
| Per-frame raycast cost | 0 | 0 | 0 (pure math FOV check) |
| Waypoint regeneration | Every expansion | Every expansion | Never (one-shot) |
| Path logic | Mechanical grid | Random aimless | Purposeful obstacle inspection |
| Cross-enemy coordination | None | None | Shared inspection flags |
| Max search radius | 2000px | 600px | 800px (ray distance) |

## Fixes Retained from Earlier Rounds

- **SEARCH_MIN_TIME_BEFORE_COMBAT (0.3s)**: Prevents rapid SEARCHING↔COMBAT oscillation
- **Nav target caching**: `_search_last_nav_target` prevents redundant `target_position` updates
- **Redirect chain guard**: `_current_state != AIState.SEARCHING` check in `_transition_to_idle()`
- **Combat/timeout log throttle**: Logged once per session

## Research: Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| Random-radius + snap | Simple, low nav calls | Random aimless paths, still causes FPS drop | Round 2 (failed) |
| Predefined `Path2D` waypoints | Zero runtime cost | Requires level designer work, rigid | Supported as fallback |
| **Cover-inspection (ray-based)** | **Purposeful paths, shared state, one-shot cost** | **Requires obstacle geometry** | **Chosen (Round 3)** |
| `map_get_random_point()` | Cheapest, guaranteed valid | Added in Godot 4.4 (project uses 4.3) | Incompatible |
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
