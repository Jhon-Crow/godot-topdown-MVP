# Issue #1458: SEARCHING State Performance Drop (30 FPS loss)

## Problem

When all enemies enter the SEARCHING state simultaneously, the game drops from ~60 FPS to ~27-29 FPS. The issue was reported with 20 enemies on a large map (warehouse level) where enemies start in SEARCHING state and immediately detect the player.

## Root Cause Analysis

### Primary Bottleneck: SEARCHING-COMBAT State Oscillation

Analysis of `game_log_20260324_202643.txt` (34,081 lines) revealed:
- **32,371 "SEARCHING: Player spotted! Transitioning to COMBAT" log entries** in ~10 seconds
- **Zero** "State: X -> Y" state change logs despite constant transition attempts
- Multiple enemies (WarehouseA_UZI2, ContainerYardB_Machete, OpenArea_Patrol1, etc.) logging "Player spotted!" every physics frame

The root cause is a rapid state oscillation cycle:

```
SEARCHING → _transition_to_combat()
    → COMBAT disabled or LOS lost on next frame
    → _transition_to_idle()
    → IDLE disabled
    → re-enter SEARCHING (with full waypoint regeneration)
    → Player still visible → repeat
```

This cycle occurs because:
1. `_process_searching_state()` checks `_can_see_player` every frame (line 2365)
2. `_transition_to_combat()` calls `_transition_to_idle()` when COMBAT is disabled (line 2662)
3. `_transition_to_idle()` redirects back to SEARCHING when IDLE is disabled (line 2653)
4. The redirect chain calls `_generate_search_waypoints()` which invokes `NavigationServer2D.map_get_closest_point()` up to 100 times

Even when states are enabled, the transition SEARCHING→COMBAT resets `_combat_state_timer = 0`, and COMBAT requires `COMBAT_MIN_DURATION_BEFORE_PURSUE` (0.5s) before allowing PURSUING transition. Vision checks run every 6 frames, so the enemy can briefly lose and regain LOS, causing rapid cycling.

### Secondary Bottleneck: Redundant Navigation Updates

In `_process_searching_state()`, line 2408 sets `_nav_agent.target_position = target_waypoint` every physics frame. In Godot's NavigationServer2D, setting `target_position` triggers an internal path query even when the target hasn't changed. With 20 enemies, this means 20 redundant path calculations per frame.

### Tertiary Bottleneck: Per-Frame File Logging

`_log_to_file("SEARCHING: Player spotted! Transitioning to COMBAT")` at line 2366 writes to disk every physics frame for every enemy that can see the player. With 20 enemies at 60 FPS, this is up to 1,200 file writes per second.

## Quantified Impact

| Metric | Before Fix | After Fix |
|--------|-----------|-----------|
| State transition attempts/sec (20 enemies) | ~1,200 | ~0 (after 0.3s cooldown) |
| Waypoint regenerations/sec (disabled states) | ~1,200 | 0 (guard added) |
| NavigationServer path queries/sec | ~1,200 (redundant) | ~20 (only on waypoint change) |
| File log writes/sec (search→combat) | ~1,200 | 1 per enemy per search session |

## Solution

Three targeted fixes in `scripts/objects/enemy.gd`:

### Fix 1: Minimum SEARCHING duration before COMBAT transition
Added `SEARCH_MIN_TIME_BEFORE_COMBAT = 0.3` seconds. The enemy must be in SEARCHING for at least 0.3s before transitioning to COMBAT when player is spotted. This prevents the rapid oscillation cycle while remaining short enough to not noticeably delay combat engagement.

### Fix 2: Navigation target caching
Added `_search_last_nav_target` to cache the last waypoint passed to `_nav_agent.target_position`. Only updates when the waypoint actually changes (distance > 1px), eliminating redundant path recalculations.

### Fix 3: _transition_to_idle redirect chain guard
Added a check `if _current_state != AIState.SEARCHING` before regenerating waypoints in the IDLE-disabled redirect path. When the enemy is already in SEARCHING and the redirect chain fires, it now returns immediately instead of clearing and regenerating all search waypoints.

### Fix 4: Log throttling
Added `_search_combat_transition_logged` flag to log "Player spotted! Transitioning to COMBAT" only once per search session instead of every frame.

## References

- Godot NavigationServer2D docs: setting `target_position` triggers internal path update
- Issue #1186: PerformanceSettings state redirect chain
- Issue #322: SEARCHING state implementation
- Issue #330: Engaged enemies search indefinitely
- Issue #1249: Tactical movement / stuck detection optimization
