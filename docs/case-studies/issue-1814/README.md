# Case Study: Issue #1814 - Enemies get stuck in PURSUING instead of FLANKING

## Issue Summary

**Issue:** [#1814](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1814)  
**PR:** [#1840](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1840)

The reported behavior was that enemies reached a PURSUING fallback state, visibly saw the player, but still oscillated in place instead of switching into FLANKING. The owner explicitly noted that FLANKING appeared to never activate, while SEARCHING, PURSUING, and COMBAT still worked.

The issue bundle for this case study contains five attached gameplay logs:

- `game_log_20260411_164253.txt`
- `game_log_20260411_164631.txt`
- `game_log_20260411_170145.txt`
- `game_log_20260413_211243.txt`
- `game_log_20260415_231752.txt`

## Evidence From Logs

The April 15, 2026 owner feedback confirmed the first fix was incomplete: the latest build still reproduced the bug and the attached `game_log_20260415_231752.txt` was provided as fresh evidence.

The attached logs consistently show long PURSUING stretches with repeated corner checks, but no successful FLANKING transitions during the stuck scenarios that matter for this issue.

Representative evidence from `game_log_20260413_211243.txt`:

```text
[21:12:58] [ENEMY] [Enemy1] State: COMBAT -> PURSUING
[21:12:58] [ENEMY] [Enemy2] State: COMBAT -> PURSUING
[21:12:58] [ENEMY] [Enemy3] State: COMBAT -> PURSUING
[21:12:58] [ENEMY] [Enemy4] State: COMBAT -> PURSUING
```

This is followed by a long stream of entries like:

```text
[21:12:59] [ENEMY] [Enemy1] PURSUING corner check: angle 138.2°
[21:13:00] [ENEMY] [Enemy2] PURSUING corner check: angle 2.8°
[21:13:04] [ENEMY] [Enemy4] PURSUING corner check: angle 18.5°
```

The pattern indicates that enemies are actively updating movement and visibility logic, but remain trapped in pursuit fallback behavior instead of escalating into FLANKING when pursuit cover is exhausted.

The new April 15 log also showed that FLANKING still existed elsewhere in the build, for example:

```text
[23:17:56] [ENEMY] [ContainerYardB_Machete] FLANKING started: target=(390.9296, 3840.453), side=right, pos=(363.6242, 3172.657)
```

That detail matters: it proves the state was not globally broken. The remaining problem had to be in the specific transition and target-selection logic used by the stuck enemies.

## Timeline Reconstruction

1. Enemy enters `COMBAT`.
2. Enemy loses a viable firing lane and transitions into `PURSUING`.
3. Enemy reaches or waits at pursuit cover.
4. No next pursuit cover can be found.
5. Player is still visible, but `_can_hit_target_from_current_position()` remains false.
6. Existing code starts approach fallback and returns early.
7. Even after the first patch added a flanking attempt here, flank target validation still rejected many tactically valid routes because it demanded a direct clear path from the enemy to the flank point.
8. The enemy therefore stayed in PURSUING/approach behavior and oscillated instead of committing to a nav-routed flank around obstacles.

## Root Cause

The full bug had two layers inside [scripts/objects/enemy.gd](/tmp/gh-issue-solver-1776281031188/scripts/objects/enemy.gd).

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

## Fix Implemented

The final fix has two parts:

1. The PURSUING fallback now attempts FLANKING before falling back to direct approach/combat:

- in the visible-target fallback branch, the enemy now tries `_transition_to_flanking()` after entering approach mode
- in the no-visible-target fallback branch, the code only returns early if `_transition_to_flanking()` actually succeeds
- otherwise it continues to the final COMBAT fallback as intended

2. Flank-side selection now validates navmesh-reachable flank targets instead of requiring a direct unobstructed line from the current enemy position to the flank point:

- candidate flank positions are snapped to navmesh first
- validation now checks whether the navigation path is reasonable
- LOS from the flank point to the player is still required
- direct current-position-to-flank ray clearance is no longer used to reject routes that intentionally go around walls

This preserves existing behavior while restoring the missing FLANKING path for the tactical case described in the issue.

## Regression Coverage

Added regression tests in [tests/unit/test_enemy.gd](/tmp/gh-issue-solver-1776281031188/tests/unit/test_enemy.gd:798):

- `test_should_flank_even_without_cover_when_player_visible`
- `test_pursuit_fallback_prefers_flanking_when_visible_target_is_still_unhittable`
- `test_choose_best_flank_side_accepts_nav_reachable_route_around_wall`

The second test directly models the issue path:

1. Player remains visible.
2. Pursuit cover fallback is reached.
3. Flanking is available.
4. Enemy should enter `FLANKING` instead of dropping straight into combat-only fallback.

## Conclusion

This issue was not a broad GOAP failure. The final root cause was a combination of:

- a PURSUING fallback transition gap
- overly strict flank target validation that rejected nav-routed flank paths around walls

The updated fix restores the intended FLANKING transition and aligns flank target selection with the actual purpose of the FLANKING state.
