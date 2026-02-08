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
- `docs/case-studies/issue-612/logs/game_log_20260207_223120.txt` - User-provided game log
