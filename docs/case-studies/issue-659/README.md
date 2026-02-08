# Case Study: Issue #659 — Fix Revolver Reloading

## Issue Summary

Multiple bugs were reported in the revolver cylinder reload mechanics introduced in PR #634 (Issue #626):

1. **Multiple cartridges loaded per drag** (v1): When dragging RMB upward in a single continuous motion, multiple rounds would load instead of just one per slot.
2. **Ejected casings freeze at spawn** (v1): When the cylinder is opened (R key), spent casings spawn but remain motionless until the player walks into them.
3. **Cartridges load into same slot without rotation** (v2): After inserting one cartridge, the player can insert more without scrolling (rotating the cylinder), loading all cartridges into the same chamber.
4. **Casings eject on every open/close** (v2): Opening and closing the cylinder repeatedly ejects casings every time, even when no rounds were fired between opens.

## Timeline

- **PR #634** (merged): Implemented multi-step cylinder reload for the RSh-12 Revolver.
- **Issue #659** (reported): Two bugs discovered during gameplay testing (bugs 1 & 2).
- **v1 fix**: Addressed bugs 1 & 2 with `_cartridgeInsertionBlocked` flag and `SpawnEjectedCasings` reorder.
- **Owner feedback** (PR comment): Two additional bugs reported (bugs 3 & 4).
- **v2 fix**: Addressed bugs 3 & 4 by requiring cylinder rotation between insertions and tracking actually-fired rounds.

## Root Cause Analysis

### Bug 1: Multiple Cartridges Per Drag (Fixed in v1)

**Location**: `Revolver.HandleDragGestures()` (Revolver.cs)

**Root Cause**: The original drag gesture handler used a "continuous gesture" pattern — after a successful cartridge insertion, it reset `_dragStartPosition = currentPosition`, allowing the very next frame's mouse movement to start accumulating toward the 30px `MinDragDistance` threshold again. Since the player's mouse was still moving upward, within a few frames the threshold was exceeded again, inserting another cartridge.

**Fix (v1)**: Added `_cartridgeInsertionBlocked` flag. After a cartridge is inserted via drag gesture, all further insertions are blocked until RMB is released.

### Bug 2: Ejected Casings Freeze (Fixed in v1)

**Location**: `Revolver.SpawnEjectedCasings()` (Revolver.cs)

**Root Cause**: The original code set `LinearVelocity` on the `RigidBody2D` casing *before* calling `AddChild()`. In Godot 4, the physics server creates and registers a body when it enters the scene tree. Setting `LinearVelocity` before registration can cause the velocity to be discarded during physics initialization.

**Fix (v1)**: Reordered operations — `AddChild()` first, then `GlobalPosition` assignment and `ApplyCentralImpulse()` instead of `LinearVelocity`.

### Bug 3: Cartridges Load Into Same Slot Without Rotation (Fixed in v2)

**Location**: `Revolver.HandleDragGestures()` and `Revolver.RotateCylinder()` (Revolver.cs)

**Root Cause**: The v1 fix unblocked insertion on RMB release, but the game design requires the player to rotate the cylinder (scroll wheel) to move to the next empty chamber before inserting another cartridge. Without this, the player could repeatedly drag up without scrolling, loading all rounds into the same conceptual chamber slot.

**Expected behavior**: insert one cartridge → scroll (rotate cylinder) → insert next cartridge → scroll → etc.

**Fix (v2)**: Changed `_cartridgeInsertionBlocked` to only be cleared by `RotateCylinder()`, not by RMB release. The `HandleDragGestures()` method no longer resets the block on mouse button release. `RotateCylinder()` now sets `_cartridgeInsertionBlocked = false`. `OpenCylinder()` also resets the flag for a fresh reload sequence.

### Bug 4: Casings Eject On Every Open/Close (Fixed in v2)

**Location**: `Revolver.OpenCylinder()` and `Revolver.Fire()` (Revolver.cs)

**Root Cause**: The v1 code calculated spent casings as `cylinderCapacity - CurrentAmmo` every time the cylinder was opened. This meant if the player opened, closed, then opened again without firing, casings would be ejected again even though they were already ejected the first time. Additionally, the original code reset `CurrentAmmo = 0` on open (emptying all live rounds), which was incorrect — live rounds should stay in the cylinder.

**Fix (v2)**: Added `_roundsFiredSinceLastEject` counter. It increments in `Fire()` and `FireChamberBullet()` when a round is successfully fired. In `OpenCylinder()`, only `_roundsFiredSinceLastEject` rounds produce casings, and the counter resets to 0 after ejection. Live rounds (`CurrentAmmo`) are preserved when the cylinder opens — only empty chambers need reloading.

## Changes Made

### `Scripts/Weapons/Revolver.cs`

1. **Field `_cartridgeInsertionBlocked`**: Now cleared by `RotateCylinder()` instead of RMB release, enforcing insert → rotate → insert sequence.
2. **New field `_roundsFiredSinceLastEject`**: Tracks rounds actually fired since last casing ejection.
3. **Modified `Fire()`/`FireChamberBullet()`**: Increment `_roundsFiredSinceLastEject` on successful fire.
4. **Modified `OpenCylinder()`**: Uses `_roundsFiredSinceLastEject` for casing count (not `capacity - ammo`). Preserves `CurrentAmmo` (live rounds stay). Resets `_cartridgeInsertionBlocked` for fresh reload.
5. **Modified `RotateCylinder()`**: Clears `_cartridgeInsertionBlocked` to allow next insertion.
6. **Modified `HandleDragGestures()`**: RMB release no longer clears insertion block.
7. **Modified `SpawnEjectedCasings()`**: `AddChild()` before physics operations (v1 fix preserved).

### `tests/unit/test_revolver_reload.gd`

Updated mock class and tests:
- `MockRevolverReload`: Added `fire()`, `rounds_fired_since_last_eject`, `cartridge_insertion_blocked` fields. `open_cylinder()` preserves live ammo, uses fired counter for casings. `rotate_cylinder()` clears insertion block.
- `MockDragGestureHandler`: Uses `revolver_mock.cartridge_insertion_blocked` (shared state cleared by rotation).
- New tests: `test_issue_659_rmb_release_does_not_unblock`, `test_issue_659_rotation_unblocks_insertion`, `test_issue_659_five_drags_with_rotations_for_full_reload`, `test_issue_659_no_casings_when_nothing_fired`, `test_issue_659_no_duplicate_casings_on_repeated_open`, `test_issue_659_fire_tracks_rounds`.

## Data Files

- `game_log_20260208_180057.txt` — Original game log attached to the issue, showing revolver gameplay session.
- `game_log_20260208_182932.txt` — Second game log from owner's PR feedback, demonstrating bugs 3 & 4.
