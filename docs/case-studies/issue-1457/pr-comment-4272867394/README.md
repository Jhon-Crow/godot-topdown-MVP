# Case Study Addendum: PR #1856 Follow-up (comment 4272867394)

Owner report (2026-04-18): after the PR #1856 fix, enemies appeared to get
stuck in walls more often and to stand still in `COMBAT` state. Attached log:
`game_log_20260418_082842.txt` (≈2,952 lines, session 08:28:42-08:29:54).

## Reconstructed Timeline

| Time | Event |
| --- | --- |
| 08:28:42 | Session start. `ExperimentalSettings` logs `Global stuck max time: 20.0s`. |
| 08:28:54 | First enemy reaches `COMBAT`. |
| 08:29:19 | Grenadier and Enemy6 spawn around `(1700, 350)` and `(1950, 450)`. |
| 08:29:29 | Grenadier enters `COMBAT`, picks cover at `(1447, 356)`. |
| 08:29:30 | Enemy6 enters `COMBAT`, picks cover at `(1847, 823)` (387 px away). |
| 08:29:31 | Both transition `COMBAT -> PURSUING`. Neither ever regains LOS. |
| 08:29:36 | Grenadier dies without firing a single round. |
| 08:29:40-44 | Enemy8 oscillates inside ~200 px box at `~(1720, 1438)`, log repeatedly prints `Player vulnerable (ammo_empty) but cannot attack: close=true (dist=348), can_see=false`. |
| 08:29:49 | Enemy8 transitions to `SEEKING_COVER` without ever recovering. |
| 08:29:54 | Log ends. |

## Diagnostic Gap

`game_log_20260418_082842.txt` contains **zero** of the PR #1856 debug strings:

- no `GLOBAL STUCK: pos=... State: PURSUING/FLANKING/SEEKING_COVER -> SEARCHING`
- no `Machete COMBAT stuck (...s)`
- no repath-skip entries

Because the stuck detector (see `scripts/objects/enemy.gd:857`) only runs when
`_current_state in [PURSUING, FLANKING, SEEKING_COVER]`, an enemy that stalls
inside `COMBAT` never triggers the recovery transition to `SEARCHING` and never
writes a diagnostic line. The owner's observation ("стоят на месте в COMBAT")
is therefore invisible to the existing telemetry.

## Root Causes of the Regression

### RC-A: COMBAT stall is not recovered

`_process_combat_state` (`scripts/objects/enemy.gd:1384-1602`) has three
phases that can produce near-zero velocity:

- *exposed* phase: `velocity = Vector2.ZERO` while firing (line 1497);
- *seek clear shot* phase with no sidestep: `velocity = Vector2.ZERO` (line 1493);
- *approach* phase: `velocity = direction_to_player * combat_move_speed`
  with `_apply_wall_avoidance()`. When the player is behind a wall corner and
  the approach direction points into the wall, the one-sided wall-avoidance
  raycast only redirects along the local normal; the body rubs along the wall
  surface indefinitely.

Enemy8's log pattern (inside a 200 px box for ≥4 s, `can_see=false`, `close=true`)
matches the approach-rub scenario exactly.

### RC-B: Cached navigation target persists across state transitions

`_get_nav_direction_to()` (`scripts/objects/enemy.gd:4679-4686`) caches
`_nav_target_cache` and skips repath if the new target moved less than
`NAV_TARGET_REPATH_DISTANCE = 24 px`. `_transition_to_combat`, `_transition_to_pursuing`,
`_transition_to_flanking`, `_transition_to_seeking_cover`, and
`_transition_to_searching` do **not** reset `_nav_has_target`, so:

- a cached cover-point target from a previous state stays authoritative
  on entry to the new state;
- the first frame after the transition reads the stale `NavigationAgent2D`
  path instead of recomputing for the new intent.

Only `_reset()` (line 4420) clears `_nav_has_target`. Between two resets
an enemy can re-use a stale cached target for its entire session.

### RC-C: `_reset()` seeds `_global_stuck_last_position = Vector2.ZERO`

On the first tick after reset, `global_position.distance_to(Vector2.ZERO)`
is very large, so the stuck detector takes the "making progress" branch
(line 885-888) and silently masks one tick of stall telemetry. This is a
minor paper-cut but still hides the very first sample.

### RC-D: `MOTION_MODE_FLOATING + wall_min_slide_angle = 0.0` turns walls into frictionless rails

The PR #1856 motion-mode change makes shallow wall contact slide instead of
catching. When the approach direction is persistently into the wall, the
body never zeroes velocity on collision. The `_global_stuck_last_position`
distance can still creep past the 30 px threshold every few seconds,
resetting the stuck timer before it fires. Combined with RC-A, the enemy
grinds along the wall invisibly.

## Proposed Fix (planned for this PR iteration)

1. **Reset the nav target cache on every AI state transition** that moves
   the enemy (`COMBAT`, `PURSUING`, `FLANKING`, `SEEKING_COVER`, `SEARCHING`),
   so each state recomputes its path once on entry and does not re-use a
   stale cover target.
2. **Add a COMBAT approach stall recovery** analogous to the existing
   machete stuck detector: if the enemy is in `COMBAT` approach/clear-shot
   phase without LOS and moves less than 30 px for 2.0 s, transition to
   `PURSUING`. Emit a `COMBAT stall` log line for diagnostics.
3. **Fix `_reset()`** to seed `_global_stuck_last_position = global_position`
   instead of `Vector2.ZERO`.

These are small, additive changes. None of them revert the PR #1856 motion
mode or nav cache, and none of them touch `_apply_wall_avoidance()` (the
failed approach from PR #1557).
