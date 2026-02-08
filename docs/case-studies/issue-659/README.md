# Case Study: Issue #659 — Fix Revolver Reloading

## Issue Summary

Two bugs were reported in the revolver cylinder reload mechanics introduced in PR #634 (Issue #626):

1. **Multiple cartridges loaded per drag**: When dragging RMB upward in a single continuous motion, multiple rounds would load instead of just one per slot.
2. **Ejected casings freeze at spawn**: When the cylinder is opened (R key), spent casings spawn but remain motionless until the player walks into them.

## Timeline

- **PR #634** (merged): Implemented multi-step cylinder reload for the RSh-12 Revolver.
- **Issue #659** (reported): Two bugs discovered during gameplay testing.
- **This fix**: Addresses both bugs with targeted changes to `Scripts/Weapons/Revolver.cs`.

## Root Cause Analysis

### Bug 1: Multiple Cartridges Per Drag

**Location**: `Revolver.HandleDragGestures()` (Revolver.cs)

**Root Cause**: The original drag gesture handler used a "continuous gesture" pattern — after a successful cartridge insertion, it reset `_dragStartPosition = currentPosition`, allowing the very next frame's mouse movement to start accumulating toward the 30px `MinDragDistance` threshold again. Since the player's mouse was still moving upward, within a few frames the threshold was exceeded again, inserting another cartridge. This chain continued for as long as the mouse moved upward, loading the entire cylinder in a single drag motion.

**Evidence from game log**: The log shows cylinder open → cylinder close transitions without intermediate cartridge insertion logs, suggesting rapid multi-loading occurred faster than the logging could capture distinct events.

**Fix**: Added `_cartridgeInsertionBlocked` flag. After a cartridge is inserted via drag gesture, all further insertions are blocked until RMB is released. The player must release and re-press RMB for each cartridge, matching the intended "one cartridge per deliberate gesture" design from Issue #626.

### Bug 2: Ejected Casings Freeze

**Location**: `Revolver.SpawnEjectedCasings()` (Revolver.cs)

**Root Cause**: The original code set `LinearVelocity` on the `RigidBody2D` casing *before* calling `AddChild()`. In Godot 4, the physics server creates and registers a body when it enters the scene tree. Setting `LinearVelocity` before registration can cause the velocity to be discarded during physics initialization. The casings would spawn at the correct position but with zero effective velocity.

When the player moved near the casings, the `CasingPusher` Area2D (on the Player node) would detect the casings and call `receive_kick()`, which applied an impulse and re-enabled physics processing — making them suddenly start moving.

**Reference**: [Godot documentation on RigidBody2D](https://docs.godotengine.org/en/stable/classes/class_rigidbody2d.html) states: "Setting a RigidBody2D's physical properties, such as position or linear_velocity directly will not work correctly, and the physics engine controls these values."

**Fix**: Reordered operations — `AddChild()` first, then `GlobalPosition` assignment and `ApplyCentralImpulse()` instead of `LinearVelocity`. This ensures the physics server has registered the body before any physics operations are applied.

## Changes Made

### `Scripts/Weapons/Revolver.cs`

1. **New field**: `_cartridgeInsertionBlocked` — blocks cartridge insertion until RMB is released.
2. **Modified `HandleDragGestures()`**: After successful insertion, sets `_cartridgeInsertionBlocked = true`. Resets to `false` on RMB release or when cylinder is no longer open. Removed the mid-drag position reset that caused chain-loading.
3. **Modified `SpawnEjectedCasings()`**: Reordered to `AddChild()` first, then set position and apply impulse via `ApplyCentralImpulse()` instead of `LinearVelocity`.

### `tests/unit/test_revolver_reload.gd`

Added `MockDragGestureHandler` class and 3 regression tests:
- `test_issue_659_single_cartridge_per_drag`: Verifies continuous drag only loads 1 round.
- `test_issue_659_second_cartridge_after_rmb_release`: Verifies RMB release unblocks insertion.
- `test_issue_659_five_separate_drags_for_full_reload`: Verifies 5 drags → 5 rounds.

## Data Files

- `game_log_20260208_180057.txt` — Original game log attached to the issue, showing revolver gameplay session.
