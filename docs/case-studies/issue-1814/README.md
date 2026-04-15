# Case Study: Issue #1814 - Enemies get stuck in PURSUING instead of FLANKING

## Issue Summary

**Issue:** [#1814](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1814)  
**PR:** [#1840](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1840)

The reported behavior was that enemies reached a PURSUING fallback state, visibly saw the player, but still oscillated in place instead of switching into FLANKING. The owner explicitly noted that FLANKING appeared to never activate, while SEARCHING, PURSUING, and COMBAT still worked.

The issue bundle for this case study contains the original attached gameplay logs plus the owner's later repro logs:

- `game_log_20260411_164253.txt`
- `game_log_20260411_164631.txt`
- `game_log_20260411_170145.txt`
- `game_log_20260413_211243.txt`
- `game_log_20260415_235021.txt`
- `game_log_20260416_002256.txt`
- `game_log_20260416_002352.txt`

## Evidence From Logs

The April 15-16, 2026 owner feedback confirmed the previous fixes were still incomplete: the latest build still reproduced the bug, and the owner attached `game_log_20260415_235021.txt`, `game_log_20260416_002256.txt`, and `game_log_20260416_002352.txt` as fresh evidence.

The newest logs consistently show long PURSUING stretches with repeated corner checks, but no successful FLANKING transitions during the stuck scenarios that matter for this issue.

Representative evidence from `game_log_20260416_002256.txt`:

```text
[00:23:03] [ENEMY] [Enemy3] State: COMBAT -> PURSUING
[00:23:03] [ENEMY] [Enemy4] State: COMBAT -> PURSUING
[00:23:03] [ENEMY] [Enemy7] State: COMBAT -> PURSUING
[00:23:03] [ENEMY] [Enemy8] State: COMBAT -> PURSUING
[00:23:03] [ENEMY] [Enemy10] State: COMBAT -> PURSUING
```

This is followed by a long stream of entries like:

```text
[00:23:05] [ENEMY] [Enemy8] PURSUING corner check: angle -34.6°
[00:23:07] [ENEMY] [Enemy7] PURSUING corner check: angle -177.1°
[00:23:21] [ENEMY] [Enemy2] PURSUING corner check: angle 52.3°
[00:23:38] [ENEMY] [Enemy1] PURSUING corner check: angle -45.4°
```

The same log also shows repeated returns to combat without any `FLANKING` transition in between:

```text
[00:23:08] [ENEMY] [Enemy4] State: PURSUING -> COMBAT
[00:23:09] [ENEMY] [Enemy3] State: PURSUING -> COMBAT
[00:23:21] [ENEMY] [Enemy2] State: PURSUING -> COMBAT
[00:23:22] [ENEMY] [Enemy1] State: PURSUING -> COMBAT
```

The pattern indicates that enemies are actively updating movement and visibility logic, but remain trapped in pursuit fallback behavior instead of escalating into FLANKING when the player is close behind cover.

## Timeline Reconstruction

1. Enemy enters `COMBAT`.
2. Enemy loses a viable firing lane and transitions into `PURSUING`.
3. Enemy reaches or waits at pursuit cover.
4. No next pursuit cover can be found.
5. Player is still visible, but `_can_hit_target_from_current_position()` remains false.
6. Existing code starts approach fallback and returns early.
7. Even after the first patch added a flanking attempt here, flank target validation still rejected many tactically valid routes because it demanded a direct clear path from the enemy to the flank point.
8. After that was fixed, flank-side selection still required the final flank destination to already have LOS to the player.
9. In close-range "player just moved behind cover" encounters, both candidate flank destinations can legitimately fail that LOS test even though one side is nav-reachable and tactically correct.
10. The enemy therefore stayed in PURSUING/approach behavior and oscillated instead of committing to a nav-routed flank around obstacles.

## Root Cause

The full bug had multiple layers inside [scripts/objects/enemy.gd](/tmp/gh-issue-solver-1776288462582/scripts/objects/enemy.gd).

First layer, inside the PURSUING fallback branch:

- when pursuit cover ran out and the target was still visible but unhittable, the code set `_pursuit_approaching = true`
- then it returned immediately
- `_transition_to_flanking()` was either never attempted in that visible-target fallback path, or its result was ignored in the no-visible-target fallback path

That made FLANKING effectively unreachable in one of the exact scenarios described by the issue: visible player, no viable shot, no next pursuit cover.

Second layer, inside flank target selection:

- `_choose_best_flank_side()` validated candidate flank positions with `_has_clear_path_to(...)`
- that required a direct ray-clear line from the enemy to the final flank point
- but FLANKING is explicitly a navigation maneuver that is supposed to move cover-to-cover around walls
- as a result, valid navmesh flank routes were rejected before FLANKING could start

This is why the maintainer still saw no flanking in the reported encounters even after the first transition fix landed.

Third layer, inside nav-reachability validation for flank targets:

- the follow-up helper tried to validate flank targets by mutating `NavigationAgent2D.target_position`
- it then trusted `is_navigation_finished()` and `distance_to_target()` as a proxy for reachability
- that makes validation depend on transient agent state instead of the navigation map itself
- in live encounters this can reject or wobble on valid routes even when the navmesh contains a path

Fourth layer, revealed by the April 16 owner logs after the nav-path fix:

- `_choose_best_flank_side()` still treated LOS from the final flank point to the player as mandatory
- if both candidate sides were nav-reachable but neither destination yet had LOS because the player was close behind cover, the function still rejected both tactical sides
- that suppressed `FLANKING` exactly in the scenario the owner described and pushed enemies back into `PURSUING`

The April 16, 2026 owner report arrived after the earlier fixes and showed that the stuck encounter still reproduced in the latest build. That pointed to the flank-side LOS gate as the next remaining false-negative source.

## Fix Implemented

The final fix has four parts:

1. The PURSUING fallback now attempts FLANKING before falling back to direct approach/combat:

- in the visible-target fallback branch, the enemy now tries `_transition_to_flanking()` after entering approach mode
- in the no-visible-target fallback branch, the code only returns early if `_transition_to_flanking()` actually succeeds
- otherwise it continues to the final COMBAT fallback as intended

2. Flank-side selection now validates navmesh-reachable flank targets instead of requiring a direct unobstructed line from the current enemy position to the flank point:

- candidate flank positions are snapped to navmesh first
- validation now checks whether the navigation path is reasonable
- LOS from the flank point to the player is still preferred
- direct current-position-to-flank ray clearance is no longer used to reject routes that intentionally go around walls

3. Reachability validation now queries the navigation map path directly instead of depending on mutable `NavigationAgent2D` runtime state:

- flank validation uses `NavigationServer2D.map_get_path(...)` to ask whether a route actually exists
- path length is measured from the returned path segments
- the previous `target_position` / `distance_to_target()` probe is no longer used for flank admission
- this makes flank startup deterministic for the same geometry and removes one more runtime-only rejection path

4. Flank-side selection no longer treats immediate LOS at the final flank destination as mandatory for entering `FLANKING`:

- sides whose final destination already has LOS are still preferred first
- when neither side has immediate LOS, the code now falls back to a nav-reachable side instead of rejecting flanking entirely
- this aligns behavior with the owner's expectation that nearby enemies should flank around cover rather than keep "pursuing" a target who is already close

This preserves existing behavior while restoring the missing FLANKING path for the tactical case described in the issue.

## Regression Coverage

Added regression tests in [tests/unit/test_enemy.gd](/tmp/gh-issue-solver-1776288462582/tests/unit/test_enemy.gd:848):

- `test_should_flank_even_without_cover_when_player_visible`
- `test_pursuit_fallback_prefers_flanking_when_visible_target_is_still_unhittable`
- `test_choose_best_flank_side_accepts_nav_reachable_route_around_wall`
- `test_choose_best_flank_side_allows_nav_reachable_side_without_immediate_los`
- `test_navigation_target_reasonable_accepts_real_path_distance`
- `test_navigation_target_reasonable_rejects_missing_path`

The second test directly models the issue path:

1. Player remains visible.
2. Pursuit cover fallback is reached.
3. Flanking is available.
4. Enemy should enter `FLANKING` instead of dropping straight into combat-only fallback.

## Conclusion

This issue was not a broad GOAP failure. The final root cause was a combination of:

- a PURSUING fallback transition gap
- overly strict flank target validation that rejected nav-routed flank paths around walls
- an extra LOS-only flank admission rule that suppressed `FLANKING` exactly when the player was close behind cover

The updated fix restores the intended FLANKING transition and aligns flank target selection with the actual purpose of the FLANKING state.
