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
- `game_log_20260415_231752.txt`
- `game_log_20260415_235021.txt`
- `game_log_20260416_002256.txt`
- `game_log_20260416_002352.txt`
- `game_log_20260416_011440.txt`
- `game_log_20260416_022352.txt`
- `game_log_20260416_024953.txt`
- `game_log_20260416_035146.txt`
- `game_log_20260416_100704.txt`
- `game_log_20260416_103037.txt`
- `game_log_20260416_193750.txt`
- `game_log_20260416_223640.txt`

The issue screenshots were also preserved under `images/`:

- `images/issue-1814-screenshot-1.png`
- `images/issue-1814-screenshot-2.png`
- `images/issue-1814-screenshot-3.png`

## Evidence From Logs

The April 15-16, 2026 owner feedback confirmed the previous fixes were still incomplete: the latest build still reproduced the bug, and the owner attached `game_log_20260415_231752.txt`, `game_log_20260416_022352.txt`, and `game_log_20260416_024953.txt` as fresh evidence.

The newest logs show that the bug evolved after the earlier fixes. FLANKING is no longer globally unreachable, but on the Building map enemies still fall back into short PURSUING/COMBAT loops and sometimes report that the chosen flank target is invalid or unreachable.

Representative evidence from `game_log_20260416_024953.txt`:

```text
[02:50:05] [ENEMY] [Enemy4] State: COMBAT -> PURSUING
[02:50:05] [ENEMY] [Enemy3] State: COMBAT -> PURSUING
[02:50:05] [ENEMY] [Enemy7] State: COMBAT -> PURSUING
[02:50:05] [ENEMY] [Enemy10] State: COMBAT -> PURSUING
[02:50:05] [ENEMY] [Enemy1] State: COMBAT -> PURSUING
```

That same session proves the global transition path exists, because `Enemy7` does enter `FLANKING` multiple times:

```text
[02:50:08] [ENEMY] [Enemy7] State: PURSUING -> FLANKING
[02:50:08] [ENEMY] [Enemy7] State: FLANKING -> COMBAT
[02:50:10] [ENEMY] [Enemy7] State: PURSUING -> FLANKING
[02:50:10] [ENEMY] [Enemy7] State: FLANKING -> COMBAT
```

But later in the same Building-map encounter the logs still show flank rejection:

```text
[02:50:35] [ENEMY] [Enemy10] Warning: No valid flank position (both sides behind walls)
[02:50:35] [ENEMY] [Enemy10] Flank target unreachable via navigation, skipping flanking: target=(959.9999, 804.5465) pos=(1065.498, 1069.021)
[02:50:35] [ENEMY] [Enemy7] Warning: No valid flank position (both sides behind walls)
[02:50:35] [ENEMY] [Enemy7] Flank target unreachable via navigation, skipping flanking: target=(1155.836, 922.8585) pos=(1426.545, 824.067)
```

The pattern indicates that the remaining failure is no longer "cannot enter FLANKING at all." Instead, Building-room geometry can still cause flank target selection to collapse back into pursuit-oriented doorway routing, after which the enemy immediately abandons the flank or rejects it as unreachable.

The later `game_log_20260416_103037.txt` confirms a more specific remaining failure. `Enemy7` enters `FLANKING` once, but most enemies stay in `PURSUING` and repeatedly run corner checks. The closest-cover case still waits for pursuit cover selection before flanking, so Building's authored/path fallback can keep feeding more pursuit waypoints and delay the close-cover flank that the owner expects.

The latest owner feedback on April 16, 2026 attached `game_log_20260416_193750.txt` and narrowed the symptom further: on Building, enemies that entered `FLANKING` were observed mostly off-screen or roughly 800px+ away, while nearer visible enemies stayed in `PURSUING`. The log supports that shape:

```text
[19:38:12] [ENEMY] [Enemy7] FLANKING started: target=(1103.39, 546.6495), side=left, pos=(1425.273, 842.1158)
[19:38:44] [ENEMY] [Grenadier] FLANKING started: target=(500.2328, 1676), side=right, pos=(1412.067, 575.9337)
[19:38:58] [ENEMY] [Enemy7] FLANKING started: target=(610.0448, 670.3342), side=left, pos=(1412.745, 974.1956)
[19:39:01] [ENEMY] [Enemy8] FLANKING started: target=(555.6368, 976), side=right, pos=(1412.065, 968.516)
```

In the same log, near/on-screen enemies repeatedly stayed in `PURSUING` and performed corner checks until they eventually fell back to `COMBAT`. A quick count showed roughly 50 `-> PURSUING` transitions and 896 corner-check entries, but only four `FLANKING started` entries. That is consistent with a flanking admission rule that was reachable, but not being evaluated early enough for enemies that already had a pursuit cover target or were already in the pursuit-cover movement branch.

The newest owner feedback on April 16, 2026 attached `game_log_20260416_223640.txt` and reported two remaining symptoms: enemies still did not visibly flank, and while `PURSUING` they moved farther away from the player instead of approaching. The log shows why `FLANKING` still looked broken even though the transition technically happened. It contains 15 `FLANKING started` entries, but 12 `State: FLANKING -> COMBAT` exits and one timeout. Many exits happen in the same timestamp bucket as the start:

```text
[22:37:04] [ENEMY] [Enemy3] PURSUING: visible target within 900px but unhittable, attempting FLANKING before pursuit cover
[22:37:04] [ENEMY] [Enemy3] FLANKING started: target=(681.4048, 710.5581), side=left, pos=(643.1943, 917.3452)
[22:37:04] [ENEMY] [Enemy3] State: PURSUING -> FLANKING
[22:37:04] [ENEMY] [Enemy3] State: FLANKING -> COMBAT
[22:39:57] [ENEMY] [Enemy4] FLANKING started: target=(800.9203, 457.0093), side=right, pos=(503.9913, 743.0674)
[22:39:57] [ENEMY] [Enemy4] State: FLANKING -> COMBAT
```

That confirmed a new priority bug: a one-frame `FLANKING` state satisfied log-based transition checks, but did not produce a committed flank maneuver on screen. The same log still had 49 `COMBAT -> PURSUING` transitions and 786 `PURSUING corner check` entries, supporting the owner's observation that the remaining live behavior was still dominated by pursuit oscillation.

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
11. After that fix, the Building-map owner logs still showed a narrower problem: flank targets were being snapped through `_combat_waypoint(...)`, which is authored for forward progress through doors and corridors rather than lateral movement around the player.
12. That waypoint snap could pull the flank destination back into the same doorway/corridor pursuit loop, making the "flank" either collapse immediately to COMBAT or fail navigation validation altogether.
13. The latest Building log then showed that flanking could start once, but the dominant behavior was still `PURSUING` corner oscillation.
14. The remaining ordering bug was that close hidden/unhittable targets only reached flanking after pursuit-cover selection failed, but Building often continues to provide pursuit waypoints.
15. The `game_log_20260416_193750.txt` feedback showed the final distance/ordering mismatch: the flanking-priority check was tied to `CLOSE_COMBAT_DISTANCE` and placed after existing pursuit-cover movement, so visible on-screen enemies outside 400px or already assigned to cover could keep pursuing instead of immediately trying `FLANKING`.
16. The `game_log_20260416_223640.txt` feedback showed that the flanking transition could now fire, but it frequently collapsed back to `COMBAT` before any meaningful flank movement, while fallback pursuit waypoints could still choose local anchors that increased distance to a far player.

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

Fifth layer, revealed by the later April 16 Building-map owner logs after the LOS fix:

- `_calculate_flank_position()` still ran the geometric flank point through `_combat_waypoint(...)`
- those combat-path anchors are intentionally authored for pursuit and room-to-room forward progress
- on Building, that could redirect a lateral flank destination back toward the same doorway or corridor the enemy was already using for PURSUING
- the result was a fake "flank" target that either re-entered the same oscillation loop or became invalid when checked as a true flank route

The April 16, 2026 Building reports therefore showed that flanking was partially restored but still not robust on maps whose authored combat waypoints bias strongly toward doorway traversal.

Sixth layer, revealed by `game_log_20260416_103037.txt`:

- the owner scenario is close-cover combat, where `FLANKING` should win over `PURSUING`
- `_process_pursuing_state()` still called `_find_pursuit_cover_toward_player()` before trying a close-cover flank
- on Building, pursuit cover and path waypoints are plentiful enough to keep enemies in pursuit/corner-check movement even though the player is already close and not hittable
- the corrected priority started as: if the target is close and cannot be hit from the current position, try `FLANKING` before selecting another pursuit cover

Seventh layer, revealed by `game_log_20260416_193750.txt`:

- the owner observed that enemies entering `FLANKING` were mostly off-screen or around 800px+ away
- the previous close-cover check used `CLOSE_COMBAT_DISTANCE` (400px), which is a shooting/combat threshold, not a good tactical-flank admission distance for Building interiors
- `_process_pursuing_state()` still evaluated that check after branches that return early while moving toward existing pursuit cover
- therefore near visible enemies could keep consuming current pursuit-cover/corner-check behavior, while farther enemies only reached `FLANKING` later through no-cover fallback paths

The corrected priority is: when a target is visible, inside a screen-scale flanking-priority range, and not hittable from the current position, attempt `FLANKING` before any pursuit-cover movement or cover search.

Eighth layer, revealed by `game_log_20260416_223640.txt`:

- `_process_flanking_state()` allowed `FLANKING -> COMBAT` as soon as a target became hittable
- because this check ran immediately after entering `FLANKING`, the enemy could leave the state before moving toward the flank target
- Building's pre-authored attacking waypoint fallback also kept a nearest-local fallback for corner escape
- that fallback was valid for enemies already very close to the target, but for normal `PURSUING` it could select a nearby waypoint that was farther from the player
- this matched the owner report: the state was technically present in logs, but not visible as a real flank, and pursuit could move away instead of closing distance

## External Navigation Notes

Official Godot navigation documentation reinforces the separation used in the fix:

- `NavigationAgent2D.get_next_path_position()` is intended to be called every physics frame while following an agent path, because it updates the agent's internal path logic: https://docs.godotengine.org/en/4.4/classes/class_navigationagent2d.html
- `NavigationServer2D.map_get_path(...)` directly queries a map path and is suitable for validating whether a route exists without mutating the live `NavigationAgent2D` target state: https://docs.godotengine.org/en/4.1/classes/class_navigationserver2d.html

That supports keeping runtime movement on the agent while using `NavigationServer2D` inside the flank helper for deterministic route validation.

## Fix Implemented

The final fix has seven parts:

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

5. Flank target generation no longer snaps through generic combat-path waypoints:

- `_calculate_flank_position()` now keeps the geometric lateral flank endpoint and only snaps it to the navmesh
- it no longer reuses `_combat_waypoint(...)` anchors that were authored for pursuit progress through rooms and corridors
- this prevents Building-map flank targets from collapsing back into the same doorway/corridor loop seen in the owner's latest logs

6. PURSUING now gives close hidden/unhittable targets a flanking opportunity before selecting another pursuit cover:

- `_should_flank_close_hidden_target()` checks that a player target exists, flanking is available, the target is inside `CLOSE_COMBAT_DISTANCE`, and the enemy still cannot hit from the current position
- `_process_pursuing_state()` calls that check before `_find_pursuit_cover_toward_player()`
- this prevents Building's pursuit waypoint fallback from starving the close-cover flanking transition

7. PURSUING now prioritizes visible, on-screen, unhittable targets before any pursuit-cover branch can return:

- `_should_prioritize_flanking_target()` requires an actual visible player/companion target, available flanking, target distance within `PURSUIT_FLANK_PRIORITY_DISTANCE` (900px), and no current firing lane
- `_process_pursuing_state()` calls this immediately after the "can see and can hit" COMBAT transition check
- this lets on-screen Building enemies attempt `FLANKING` before continuing existing pursuit cover, waiting at cover, or choosing another pursuit waypoint
- flank-side and flank-target calculations were moved into `EnemyFlankNavigationHelper`, keeping `enemy.gd` below the CI 5000-line architecture limit

8. FLANKING now requires a small movement/time commitment before it can collapse to COMBAT:

- `_process_flanking_state()` now tracks the entry position for each flank attempt
- early `FLANKING -> COMBAT` is allowed only after `FLANK_MIN_COMMIT_TIME` or `FLANK_MIN_COMMIT_DISTANCE`
- this preserves legitimate combat exit once a flank has started, but prevents one-frame flanking that is invisible to players

9. PURSUING waypoint fallback no longer moves away from distant targets:

- `CombatPathComponent` only uses a non-progress nearest fallback when the enemy is already very close to the target
- `PursuitComponent` filters passage-waypoint fallback candidates so they must reduce distance to the target
- this keeps `PURSUING` aligned with the owner expectation: if pursuit is active, enemies should approach the player rather than pick a local anchor farther away

This preserves existing behavior while restoring the missing FLANKING path for the tactical case described in the issue.

## Regression Coverage

Added regression tests in `tests/unit/test_enemy.gd`:

- `test_should_flank_even_without_cover_when_player_visible`
- `test_pursuit_fallback_prefers_flanking_when_visible_target_is_still_unhittable`
- `test_choose_best_flank_side_accepts_nav_reachable_route_around_wall`
- `test_choose_best_flank_side_allows_nav_reachable_side_without_immediate_los`
- `test_navigation_target_reasonable_accepts_real_path_distance`
- `test_navigation_target_reasonable_rejects_missing_path`
- `test_calculate_flank_target_keeps_geometric_flank_instead_of_combat_waypoint`
- `test_pursuit_prefers_flanking_for_close_hidden_building_target_before_more_cover`
- `test_pursuit_prefers_flanking_for_screen_distance_unhittable_building_target`
- `test_existing_pursuit_cover_does_not_starve_visible_unhittable_flanking`
- `test_pursuit_keeps_distant_hidden_target_in_pursuing`
- `test_pursuit_does_not_flank_when_close_target_is_hittable`
- `test_flanking_does_not_collapse_to_combat_before_commitment`
- `test_flanking_can_exit_to_combat_after_minimum_commit_time`
- `test_flanking_can_exit_to_combat_after_meaningful_movement`
- `test_attack_waypoint_selection_rejects_local_fallback_that_moves_away`

Added companion coverage in `tests/unit/test_combat_path_component.gd` and `tests/unit/test_pursuit_component.gd`:

- `test_attacking_rejects_fallback_that_moves_away_from_far_target`
- `test_passage_waypoint_fallback_rejects_waypoint_farther_from_target`
- `test_passage_waypoint_fallback_accepts_waypoint_closer_to_target`

The second test directly models the issue path:

1. Player remains visible.
2. Pursuit cover fallback is reached.
3. Flanking is available.
4. Enemy should enter `FLANKING` instead of dropping straight into combat-only fallback.

The new flank-target test covers the Building-specific regression:

1. Compute the geometric lateral flank endpoint from player/enemy positions.
2. Ensure flank targeting does not replace it with a generic combat-path anchor.
3. Preserve the lateral maneuver target that FLANKING actually needs.

## Verification

- `git diff --check`
- Architecture line-count check: `scripts/objects/enemy.gd` is 4938 lines, below the 5000-line CI limit.
- `dotnet build GodotTopDownTemplate.sln --configuration Debug` completed with 0 errors; existing nullable/unreachable-code warnings remain in unrelated C# files.
- Targeted GUT filter `flanking`: 11 tests, 11 passing.
- Targeted GUT filter `attacking_rejects_fallback`: 1 test, 1 passing.
- Targeted GUT filter `passage_waypoint_fallback`: 2 tests, 2 passing.
- GUT still emits existing import/autoload warnings in this workspace before and after the selected tests, but the filtered regression tests pass.

## Conclusion

This issue was not a broad GOAP failure. The final root cause was a combination of:

- a PURSUING fallback transition gap
- overly strict flank target validation that rejected nav-routed flank paths around walls
- an extra LOS-only flank admission rule that suppressed `FLANKING` exactly when the player was close behind cover
- a Building-map-specific flank target snap that redirected lateral flank destinations back onto pursuit-oriented combat waypoints
- a final state-priority ordering issue where Building pursuit-cover selection could starve close-cover flanking
- a distance/ordering mismatch where on-screen visible enemies outside 400px or already assigned to cover did not get the early flanking-priority decision
- a one-frame `FLANKING -> COMBAT` collapse that made successful transitions visually meaningless
- pursuit waypoint fallbacks that could still select local anchors farther from a distant player

The updated fix restores the intended FLANKING transition and aligns flank target selection with the actual purpose of the FLANKING state.
