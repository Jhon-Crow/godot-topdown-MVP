# Case Study: Issue #612 - Enemies Stuck/Jittering Against Walls

## Problem Description

Enemies sometimes get stuck and lag against walls, jerking in different directions
(Russian: "враги иногда упираются и лагают в стену, дёргаются в разные стороны").

## Game Log Analysis

Game log `logs/game_log_20260207_223120.txt` (9164 lines, 2 min gameplay) reveals:

### GLOBAL STUCK Events (3 total)

| Time | Enemy | Position | Previous State | Duration |
|------|-------|----------|----------------|----------|
| 22:31:46 | Enemy4 | (548.07, 971.19) | PURSUING | 4.0s |
| 22:32:25 | Enemy4 | (887.93, 710.00) | FLANKING | 4.0s |
| 22:32:30 | Enemy7 | (1422.05, 825.04) | PURSUING | 4.0s |

### Wall Trap at ~(886, 710)

5 stuck events at nearly identical positions within 6 seconds involving 4 different enemies:
- Enemy1 at (886.08, 717.24), Enemy3 at (887.72, 709.31), Enemy2 at (886.53, 718.08),
  Enemy1 at (886.49, 708.37), Enemy4 at (887.93, 710.00)

### "Both Sides Behind Walls" Warnings: 23 occurrences

Every time this warning appeared, the enemy proceeded to flank anyway, guaranteeing
it would press into a wall and get stuck.

## Root Cause Analysis

### Root Cause 1: FLANKING Proceeds When Both Sides Are Behind Walls

`_choose_best_flank_side()` detects that both flank positions are behind walls (23
warnings in a 2-minute session), but the function falls through to a default "pick
the closer side" behavior. The enemy then pathfinds toward a position it already knows
is blocked, gets stuck against the wall, and triggers the 2s/4s stuck detection timeout.

This is the **primary cause** of the stuck/jitter behavior. The FLANKING stuck detection
is reactive (2-5 seconds) rather than preventive, allowing significant visible jitter.

### Root Cause 2: Double `move_and_slide()` Calls

SEARCHING and EVADING_GRENADE states call `move_and_slide()` internally, but
`_physics_process()` calls it again at the end. This means enemies in these states
get movement applied **twice per physics frame**, amplifying any direction oscillation
near walls.

### Root Cause 3: Missing Wall Avoidance in Some States

SEARCHING and EVADING_GRENADE states move enemies using raw navigation direction
without `_apply_wall_avoidance()`. Tight corners between navigation mesh and collision
geometry cause enemies to press into walls.

### Root Cause 4: Center Raycast Bias

The center/forward raycast (index 0) was grouped with left-side raycasts (indices 0-3),
always steering right on head-on wall contact. This creates asymmetric avoidance that
oscillates when the enemy approaches a wall at varying angles.

### Root Cause 5: No Avoidance Smoothing

Wall avoidance direction changes instantly each frame. When raycasts flicker between
frames (e.g., near corners), this produces visible jitter.

## Solution

### Fix 1: Abort Flanking When Both Sides Are Behind Walls

When `_choose_best_flank_side()` determines that neither side (at full or reduced
distance) has a valid path with LOS to the player, return NAN to signal failure.
`_transition_to_flanking()` checks for NAN and aborts, incrementing the fail counter
and setting the cooldown. The enemy falls back to COMBAT or PURSUING instead of
pressing into a wall.

### Fix 2: Remove Duplicate `move_and_slide()` Calls

Remove `move_and_slide()` and `_push_casings()` from SEARCHING and EVADING_GRENADE
state handlers. Let the centralized `move_and_slide()` in `_physics_process()` handle
all movement (consistent with every other state).

### Fix 3: Add Wall Avoidance to SEARCHING and EVADING_GRENADE

Apply `_apply_wall_avoidance()` to movement direction in both states.

### Fix 4: Center Raycast Uses Collision Normal

When the forward raycast (index 0) hits a wall, use the collision normal (pointing
away from surface) instead of a fixed perpendicular direction. This provides stable,
physically correct avoidance for head-on wall approaches.

### Fix 5: Smoothed Avoidance Direction

Interpolate `_last_wall_avoidance` via `lerp(0.4)` to dampen frame-to-frame direction
changes when wall avoidance is active. Reset to zero when no wall is detected.

## Game Log Analysis: Second Round (game_log_20260208_152148.txt)

Game log `logs/game_log_20260208_152148.txt` (2007 lines, ~70s gameplay) reveals:

### Previous Fix Validation

The flanking abort fix from Round 1 is working — "Flanking aborted: both sides behind walls (Issue #612)" messages appear 18+ times, confirming enemies no longer blindly walk into known-blocked flank positions.

### New Issues Identified

**1. PURSUING state walks into walls when player is behind a wall (Primary Issue)**

Enemies in PURSUING continuously pathfind toward a player behind a wall:
- Enemy2, Enemy3, Enemy4 reach the wall and get stuck
- Navigation path ends at the wall edge (target unreachable)
- `_move_to_target_nav` returns `Vector2.ZERO`, enemy stops
- GLOBAL STUCK timer fires after 4.0 seconds — too slow

**2. COMBAT ↔ PURSUING rapid cycling**

At wall edges, multi-point visibility check `_can_see_player` flickers:
- PURSUING → COMBAT (after 0.3s) when partial visibility + can_hit
- COMBAT → PURSUING (after 0.5s) when visibility drops
- Creates 1-2 second loops: `PURSUING -> COMBAT -> PURSUING -> COMBAT -> ...`
- Enemies appear indecisive, standing at walls

**3. Flank abort → PURSUING → wall loop**

After flanking is aborted (both sides behind walls), enemy transitions to PURSUING:
- PURSUING can't find cover → tries flanking → abort → PURSUING → repeat
- Enemy walks into wall each cycle before flanking cooldown triggers

### Timeline: Enemy2 Wall-Blocked Pursuit (15:22:04 - 15:22:56)

| Time | Event | Position |
|------|-------|----------|
| 15:22:04 | Flanking aborted: both sides behind walls | ~(880, 600) |
| 15:22:05 | PURSUING corner check: stays near wall | ~(880, 600) |
| 15:22:05 | State: PURSUING → COMBAT (visibility flicker) | ~(880, 600) |
| 15:22:06 | State: COMBAT → PURSUING | ~(880, 600) |
| 15:22:07-13 | Repeated PURSUING corner checks (stuck at wall) | ~(880, 600) |
| 15:22:13 | Flanking aborted again | ~(880, 600) |
| 15:22:35 | FLANKING started (cooldown expired) → eventually timeout at 5s | ~(888, 880) |
| 15:22:40 | FLANKING timeout | ~(888, 880) |
| 15:22:49-56 | More FLANKING/PURSUING cycles at same wall | ~(888, 900) |

**Total wall-blocked time: ~52 seconds for a single enemy.**

## Root Cause Analysis: Round 2

### Root Cause 6: No "Unreachable Player" Detection in PURSUING

When navigation reaches the wall (target behind wall), `is_navigation_finished()` returns true and the enemy stops moving. There's no mechanism to detect "I'm at a wall and can't reach the player" faster than the 4-second GLOBAL STUCK timer.

### Root Cause 7: Flank Abort Loops Back to PURSUING

After flanking is aborted due to both sides being behind walls, the fallback goes to COMBAT or PURSUING. Both states will attempt flanking again after cooldown, creating an infinite loop.

## Solution: Round 2

### Fix 6: Wall-Blocked Pursuit Detection (2-second timer)

Added `_wall_blocked_pursuit_timer` that accumulates when the enemy is in PURSUING without making navigation progress (< 15px movement). After 2 seconds, if:
- `_can_see_player = true` but `_can_hit_player = false` (player behind wall), OR
- Navigation is finished but player is not visible (target unreachable)

...the enemy transitions to SEARCHING instead of waiting for the 4-second GLOBAL STUCK timer.

The timer persists across COMBAT ↔ PURSUING cycles (not reset on state transitions), so rapid cycling still accumulates toward the threshold.

### Fix 7: Flank Fail Escalation to SEARCHING

When `_flank_fail_count >= FLANK_FAIL_MAX_COUNT` (2 failures), the flank abort now transitions to SEARCHING instead of PURSUING/COMBAT. This breaks the loop:

Before: `PURSUING → flank abort → PURSUING → wall → COMBAT → PURSUING → flank abort → ...`
After: `PURSUING → flank abort → PURSUING → flank abort → SEARCHING (explores elsewhere)`

### Fix 8: COMBAT Clear-Shot Timeout Uses SEARCHING Fallback

When COMBAT state times out finding a clear shot and flanking is exhausted (`_flank_fail_count >= FLANK_FAIL_MAX_COUNT`), transition to SEARCHING instead of PURSUING.

## Online Research

- [NavigationAgent2D gets stuck on corners](https://forum.godotengine.org/t/navigationagent2d-keeps-geting-stuck-on-corners/126027)
- [NavigationAgent2D path jitters erratically](https://forum.godotengine.org/t/navigationagent2d-path-jitters-erratically/116932)
- [CharacterBody2D stuck on wall](https://forum.godotengine.org/t/characterbody2d-gets-stuck-on-a-wall-staticbody2d/54435)
- [move_and_slide causes jitter at corners](https://github.com/godotengine/godot/issues/32182)
- [Steering behaviors for Godot 4](https://github.com/konbel/steering-behaviors-godot-4)
- [GDQuest Steering AI Framework](https://github.com/GDQuest/godot-steering-ai-framework)

## Files Modified

- `scripts/objects/enemy.gd` - Main enemy AI script
- `tests/unit/test_wall_avoidance.gd` - Unit tests for wall avoidance fixes
- `docs/case-studies/issue-612/logs/game_log_20260207_223120.txt` - User-provided game log (Round 1)
- `docs/case-studies/issue-612/logs/game_log_20260208_152148.txt` - User-provided game log (Round 2)
