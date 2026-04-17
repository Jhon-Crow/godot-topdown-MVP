# Issue #1816 Case Study

## Issue Summary

- GitHub issue: `#1816 fix перемещение врагов`
- Reported on April 15, 2026 in `Jhon-Crow/godot-topdown-MVP`
- User report: enemies almost stop moving in passages, likely due to wall interaction and enemies blocking each other
- Attached evidence collected locally:
  - `docs/case-studies/issue-1816/issue-1816.png`
  - `docs/case-studies/issue-1816/raw/game_log_20260417_041936.txt`
  - `game_log_20260411_165829.txt` attachment was referenced in the issue, but the authenticated download did not complete in this workspace

## Follow-Up Feedback Data

Owner feedback on April 17, 2026 said that visible movement changes were not apparent,
especially on the `Здание` / `BuildingLevel` map. The attached runtime log was downloaded
to `raw/game_log_20260417_041936.txt`.

### Runtime Timeline From `game_log_20260417_041936.txt`

- `04:19:36`: game log started from a Windows exported build using Godot `4.3-stable`
- `04:19:37`: `ExperimentalSettings` initialized with logging enabled and `Global stuck max time: 20.0s`
- `04:19:43`: scene load switched to `res://scenes/levels/BuildingLevel.tscn`
- `04:19:43`: `BuildingLevel` enemy set initialized
- `04:20:31` through `04:21:25`: frequent `ROT_CHANGE` messages alternate between
  `P4:velocity` and `P3:corner` for several enemies, which indicates movement/corner
  steering jitter rather than tactical-yield logging
- No `GLOBAL STUCK` entries appear in the captured run

### New Observation

The runtime settings in the provided log override enemy global stuck recovery to `20.0s`
while the code-level fallback constant is `4.0s`. If an enemy makes very small movements
or repeatedly jitters near corridor corners, the player can observe it as nearly stopped
for a long time before the global stuck recovery transitions it to searching. This explains
why the first tactical-yield-only fix could look unchanged on `BuildingLevel`: the evidence
does not show tactical yielding, but it does show corner/velocity oscillation and a long
stuck recovery window.

## CI Data Collected

- `ci-logs/run-gut-tests-24485543753.log`
  - Run created: `2026-04-16T00:32:42Z`
  - Head SHA: `8941992b9dea95922d6b8d69c272f1fe9451e93e`
  - Conclusion: cancelled
  - Relevant branch-introduced compile errors:
    - `scripts/components/tactical_movement_component.gd:163`
    - `scripts/components/tactical_movement_component.gd:164`
  - Godot treated inferred `Variant` warnings as parse errors during import. The fix
    now uses explicit `Node2D`, `Vector2`, and `float` annotations in that block.

## Repository Data Collected

### Relevant Existing Systems

- `scripts/objects/enemy.gd`
  - Uses `NavigationAgent2D` for pathing
  - Uses ORCA avoidance through `velocity_computed`
  - Uses separation steering to reduce overlap
  - Uses corner escape logic based on `get_slide_collision()`
- `scripts/components/tactical_movement_component.gd`
  - Coordinates yielding in narrow passages so one enemy can pass first
- `tests/unit/test_tactical_movement_component.gd`
  - Focused unit tests for tactical yielding state and constants

### Relevant Prior Issues In This Repo

- `docs/case-studies/issue-1107/case-study.md`
  - Prior wall-corner sticking bug in enemy navigation
- `docs/case-studies/issue-1249/analysis.md`
  - Prior narrow-passage ally-blocking and queueing problem
- `docs/case-studies/issue-1289/case-study.md`
  - Path conflicts in constrained spaces
- `docs/case-studies/issue-1226/README.md`
  - Navigation architecture notes for levels using `NavigationAgent2D`

## Root Cause Analysis For #1816

The current issue aligns most closely with the narrow-passage coordination logic from issue `#1249`.

### Observed Risk In Current Code

`TacticalMovementComponent._is_ally_blocking_path()` previously treated any enemy hit by the forward ray as a blocker. In tight geometry this is too broad:

- an ally slightly off to the side can still be hit by the ray
- the yielding enemy then stops even though the forward lane is still usable
- repeated false-positive yielding combines with wall collisions and ORCA dead zones to make enemies appear frozen in passages

### Why This Matches The Report

- The issue report explicitly mentions enemies blocking each other in passages
- The code already contains fixes for wall rubbing and corner sticking, so the remaining likely failure is coordination in shared corridors
- The existing tactical yielding system is designed for this class of problem, which makes false-positive yield detection a high-probability regression point

## Fix Implemented

Updated `scripts/components/tactical_movement_component.gd`:

- ally blockers must now be in front of the enemy
- ally blockers must also be within the same forward lane using a lateral-offset check
- side-lane or intersection-adjacent allies no longer trigger yielding
- the lane decision is now isolated in `_is_position_in_forward_lane()` for deterministic
  regression coverage and to avoid depending on live physics ray hits in unit tests

Added regression coverage in `tests/unit/test_tactical_movement_component.gd`:

- verifies side-lane positions do not count as blockers
- verifies forward-lane positions still count as blockers
- verifies positions behind the enemy do not count as blockers

## Proposed Solutions Considered

### 1. Tighten tactical-yield detection

Status: implemented

Why:

- smallest targeted fix
- preserves existing ORCA, separation, and navigation behavior
- directly addresses false queuing in passages

### 2. Add stronger lane-aware queueing with waypoint ownership

Potential future enhancement:

- reserve passage segments or next-waypoint slots
- have only one enemy claim a corridor entrance at a time

Pros:

- robust for crowds in very narrow corridors

Cons:

- more stateful and invasive than needed for the reported regression

### 3. Replace local yielding with full crowd-simulation priority logic

Potential future enhancement:

- enrich ORCA/avoidance with explicit priorities or corridor rules

Pros:

- can scale better to large enemy groups

Cons:

- significantly more complex
- harder to validate in this codebase than a local tactical fix

## External Research And Useful Components

- RVO2 / ORCA reference implementation: `https://gamma.cs.unc.edu/RVO2/`
  - Relevant because the project already uses ORCA-style avoidance via Godot navigation avoidance
- Godot `NavigationAgent2D` documentation:
  - `https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_introduction_2d.html`
  - `https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationagents.html`
  - These pages were not directly retrievable from this environment due HTTP 403, but they remain the primary upstream references for the system already used in the codebase

## Verification Status

- Code change completed
- Regression tests added
- CI cancellation log downloaded and analyzed
- Local execution blocked in this workspace because no `godot` executable is installed on `PATH`

## Files Changed For The Fix

- `scripts/components/tactical_movement_component.gd`
- `tests/unit/test_tactical_movement_component.gd`
