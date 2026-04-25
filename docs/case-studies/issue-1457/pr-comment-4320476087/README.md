# Issue #1457 PR Comment 4320476087 Follow-up

Owner report: 2026-04-25 20:19:21 UTC, PR #1856 comment 4320476087.

Original note: enemies in `PURSUING` and `SEARCHING` walk into walls.

Downloaded artifact:

- `game_log_20260425_231741.txt` from `https://github.com/user-attachments/files/27089498/game_log_20260425_231741.txt`

## Timeline Reconstructed From Log

- 23:17:41: session starts on Windows, Godot 4.3-stable, logging enabled. Experimental settings report `Global stuck max time: 20.0s`.
- 23:18:26: multiple enemies hit the new PR #1856 hard cap in `PURSUING` and emit `GLOBAL STUCK ... for 4.0s ... State: PURSUING -> SEARCHING`.
- 23:18:26-23:18:28: those enemies enter spiral `SEARCHING` from the last known player position.
- 23:18:31: only one enemy emits `SEARCHING: Stuck at wp 0, skipping`; other searching enemies continue without a global no-progress recovery marker.
- Later frames show repeated combat/flanking/pursuit churn near wall-heavy cover positions, confirming that the previous fix recovered from one stuck state but did not fully stabilize the handoff into search movement.

## Root Cause

The 2026-04-20 fix worked for `PURSUING`: despite the user's debug setting of 20 seconds, the log proves `PURSUING` wall catches recover in 4 seconds.

The remaining gap is `SEARCHING`:

- The shared global no-progress detector only covered `PURSUING`, `FLANKING`, and `SEEKING_COVER`, so `SEARCHING` did not get the same hard cap after stuck pursuit handed off into search.
- `_process_searching_state()` wrote `_nav_agent.target_position = target_waypoint` every physics frame instead of using `_get_nav_direction_to()`. That bypassed the issue #1457 target cache, allowing path churn during search waypoint movement.
- The local `SEARCHING: Stuck at wp` detector can skip a waypoint, but it does not reset the larger movement context or recover from cases where repeated waypoint skips keep the enemy pressed into wall geometry.

## Implemented Follow-up

- Include `AIState.SEARCHING` in the shared navigation movement stuck detector and hard cap.
- Keep `SEARCHING` recovery capped by `NAV_MOVEMENT_STUCK_MAX_TIME`, independent of the debug `Global stuck max time` setting.
- Route search waypoint movement through `_get_nav_direction_to(target_waypoint)` so it reuses the NavigationAgent target cache instead of assigning `target_position` every frame.
- Add regression tests covering `SEARCHING` hard-cap inclusion and cached waypoint navigation.

## Verification Targets

- `tests/unit/test_enemy_navigation_issue_1457.gd::test_nav_movement_stuck_recovery_has_hard_cap_issue_1457`
- `tests/unit/test_enemy_navigation_issue_1457.gd::test_searching_uses_shared_nav_target_cache_issue_1457`
