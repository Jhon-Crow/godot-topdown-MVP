# Case Study: Issue #612 - Enemies Stuck/Jittering Against Walls

## Problem Description

Enemies sometimes get stuck and lag against walls, jerking in different directions
(Russian: "враги иногда упираются и лагают в стену, дёргаются в разные стороны").

## Root Cause Analysis

### Root Cause 1: Double `move_and_slide()` Calls

The main `_physics_process()` calls `move_and_slide()` at line 907 after all state
processing. However, two states also call `move_and_slide()` internally:

- **SEARCHING state** (line 2276): `velocity = dir * move_speed * 0.7; move_and_slide()`
- **EVADING_GRENADE state** (lines 2334, 2338): `move_and_slide()`

This means enemies in these states get `move_and_slide()` applied **twice per physics
frame** - once inside the state and once at the end of `_physics_process()`. The second
call uses the velocity that was already consumed/modified by the first `move_and_slide()`,
causing unpredictable movement and jitter, especially near walls where slide calculations
compound.

### Root Cause 2: Wall Avoidance Oscillation (Opposing Forces)

The `_check_wall_ahead()` function uses 8 raycasts to detect walls. When an enemy
approaches a wall head-on:

1. The center raycast (index 0) hits the wall
2. Left-side raycasts (indices 1-3) detect the wall and push RIGHT (via perpendicular)
3. Right-side raycasts (indices 4-6) detect the wall and push LEFT (via -perpendicular)

When both sides detect a wall simultaneously (e.g., at a flat wall or concave corner),
the avoidance forces partially cancel each other out. On consecutive frames, slight
position changes cause different raycasts to fire, producing oscillating avoidance
directions - visible as jittering.

The current `_check_wall_ahead()` treats index 0 (center/forward) as a left-side raycast
(`i <= 3`), but the center raycast should use the collision normal directly rather than
pushing to one side.

### Root Cause 3: Missing Wall Avoidance in Some States

The SEARCHING state (line 2276) and EVADING_GRENADE state (lines 2333-2338) move
enemies directly using navigation direction without applying `_apply_wall_avoidance()`.
While NavigationAgent2D provides pathfinding around obstacles, tight corners and small
offsets between navigation mesh and collision geometry can still cause enemies to press
into walls.

### Root Cause 4: No Velocity Smoothing

Velocity is set directly each frame (`velocity = direction * speed`) without any temporal
smoothing or damping. When wall avoidance produces different directions on consecutive
frames, this causes instant velocity changes visible as jitter.

## Solution

### Fix 1: Eliminate Double `move_and_slide()` Calls

Remove the `move_and_slide()` and `_push_casings()` calls from inside SEARCHING and
EVADING_GRENADE states. Instead, set velocity and let the centralized `move_and_slide()`
at line 907 handle movement. This is consistent with how all other states work.

### Fix 2: Fix Wall Avoidance for Head-On Collisions

When the center/forward raycast (index 0) hits a wall, use the collision normal as the
avoidance direction instead of pushing to one side. The collision normal naturally points
away from the wall surface, providing the correct escape direction.

### Fix 3: Add Wall Avoidance to SEARCHING and EVADING_GRENADE States

Apply `_apply_wall_avoidance()` to the movement direction in these states, consistent
with all other movement states.

### Fix 4: Add Velocity Smoothing for Wall Avoidance

Smoothly interpolate between the current and desired velocity when wall avoidance is
active. This prevents instant direction changes and eliminates visible jitter.

## Online Research

The following known issues in the Godot community are related:

- [NavigationAgent2D gets stuck on corners](https://forum.godotengine.org/t/navigationagent2d-keeps-geting-stuck-on-corners/126027) - Navigation mesh needs offset from collision geometry
- [NavigationAgent2D path jitters erratically](https://forum.godotengine.org/t/navigationagent2d-path-jitters-erratically/116932) - Don't query path every physics frame
- [CharacterBody2D stuck on wall](https://forum.godotengine.org/t/characterbody2d-gets-stuck-on-a-wall-staticbody2d/54435) - Known Godot physics issue
- [move_and_slide causes jitter at corners](https://github.com/godotengine/godot/issues/32182) - Engine-level issue with corner collisions
- [Steering behaviors for Godot 4](https://github.com/konbel/steering-behaviors-godot-4) - Reference for wall avoidance patterns
- [GDQuest Steering AI Framework](https://github.com/GDQuest/godot-steering-ai-framework) - Production-quality steering behaviors

## Existing Solutions in Codebase

The codebase already has some stuck detection mechanisms:

1. **Global stuck detection** (Issue #367): Detects enemies stuck for 4s in PURSUING/FLANKING
2. **Flank stuck detection**: Detects stuck for 2s during FLANKING
3. **Search stuck detection**: Detects stuck for 2s during SEARCHING

These are reactive (detect-and-recover) rather than preventive. This fix addresses the
root cause to prevent the jittering from occurring in the first place.

## Files Modified

- `scripts/objects/enemy.gd` - Main enemy AI script
- `tests/unit/test_enemy.gd` - Unit tests for wall avoidance fixes
