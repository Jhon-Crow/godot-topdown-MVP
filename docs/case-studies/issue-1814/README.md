# Case Study: Issue #1814 - Enemies get stuck in PURSUING instead of FLANKING

## Issue Summary

**Issue:** [#1814](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1814)  
**PR:** [#1840](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1840)

The reported behavior was that enemies reached a PURSUING fallback state, visibly saw the player, but still oscillated in place instead of switching into FLANKING. The owner explicitly noted that FLANKING appeared to never activate, while SEARCHING, PURSUING, and COMBAT still worked.

The issue bundle for this case study contains four attached gameplay logs:

- `game_log_20260411_164253.txt`
- `game_log_20260411_164631.txt`
- `game_log_20260411_170145.txt`
- `game_log_20260413_211243.txt`

## Evidence From Logs

The attached logs consistently show long PURSUING stretches with repeated corner checks, but no successful FLANKING transitions during the stuck scenarios.

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

## Timeline Reconstruction

1. Enemy enters `COMBAT`.
2. Enemy loses a viable firing lane and transitions into `PURSUING`.
3. Enemy reaches or waits at pursuit cover.
4. No next pursuit cover can be found.
5. Player is still visible, but `_can_hit_target_from_current_position()` remains false.
6. Existing code starts approach fallback and returns early.
7. Because that branch returned before a successful flank transition, the enemy keeps oscillating between pursuit fallback movement and combat re-evaluation.

## Root Cause

The bug was inside the PURSUING fallback branch in [scripts/objects/enemy.gd](/tmp/gh-issue-solver-1776281031188/scripts/objects/enemy.gd:2153).

Before the fix:

- when pursuit cover ran out and the target was still visible but unhittable, the code set `_pursuit_approaching = true`
- then it returned immediately
- `_transition_to_flanking()` was either never attempted in that visible-target fallback path, or its result was ignored in the no-visible-target fallback path

That made FLANKING effectively unreachable in one of the exact scenarios described by the issue: visible player, no viable shot, no next pursuit cover.

## Fix Implemented

The PURSUING fallback now attempts FLANKING before falling back to direct approach/combat:

- in the visible-target fallback branch, the enemy now tries `_transition_to_flanking()` after entering approach mode
- in the no-visible-target fallback branch, the code only returns early if `_transition_to_flanking()` actually succeeds
- otherwise it continues to the final COMBAT fallback as intended

This preserves existing behavior while restoring the missing FLANKING path.

## Regression Coverage

Added regression tests in [tests/unit/test_enemy.gd](/tmp/gh-issue-solver-1776281031188/tests/unit/test_enemy.gd:798):

- `test_should_flank_even_without_cover_when_player_visible`
- `test_pursuit_fallback_prefers_flanking_when_visible_target_is_still_unhittable`

The second test directly models the issue path:

1. Player remains visible.
2. Pursuit cover fallback is reached.
3. Flanking is available.
4. Enemy should enter `FLANKING` instead of dropping straight into combat-only fallback.

## Conclusion

This issue was not a broad GOAP failure. The core problem was a narrow state-machine gap in the PURSUING fallback path that prevented FLANKING from being chosen when it should have been the preferred tactical continuation. The fix restores that transition and adds regression coverage for the exact failure mode captured in the logs.
