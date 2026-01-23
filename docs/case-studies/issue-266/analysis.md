# Issue #266: Shotgun Reload - Multiple Shells Loading in One Drag

## Summary

The shotgun reload system had two bugs:
1. Multiple shells could be loaded during a single RMB drag down motion (should be strictly 1 shell per drag)
2. An unnecessary "action open" sound played when transitioning from pump-down to reload mode (bolt was already open)

## Timeline

1. **PR #244**: Initial shotgun reload fix implemented
2. **Issue #266**: User reported that one drag motion could load multiple shells

## Root Cause Analysis

### Bug #1: Multiple Shells Loading in One Drag

**Sequence of events that caused the bug:**

1. User is in `NeedsPumpDown` state (after firing and pumping up)
2. User presses MMB + RMB and drags DOWN
3. At ~frame 3, `TryProcessMidDragGesture()` detects the drag threshold is reached:
   - Detects MMB is held, so transitions from `NeedsPumpDown` to `Loading` state
   - Calls `LoadShell()` - **First shell loaded**
   - Resets `_dragStartPosition` to current position for next gesture
   - Resets `_wasMiddleMouseHeldDuringDrag = anyMMBDetected` (still TRUE because MMB is held!)
4. User continues dragging down (RMB still held)
5. On RMB release, `ProcessReloadGesture()` is called:
   - Sees `_wasMiddleMouseHeldDuringDrag = true`
   - Calls `LoadShell()` - **Second shell loaded (BUG!)**

**Evidence from game log (lines 162-180):**
```
[22:15:56] [Shotgun.FIX#243] Mid-drag MMB+DOWN during pump cycle: transitioning to reload mode
[22:15:56] [Shotgun.FIX#243] LoadShell called - ShellsInTube=6/8
[22:15:56] [Shotgun.FIX#243] Shell LOADED - 7/8 shells in tube   <-- First shell
...
[22:15:56] [Shotgun.FIX#243] RMB released after 6 frames - wasMMBDuringDrag=True
[22:15:56] [Shotgun.FIX#243] Loading shell (MMB was held during drag)
[22:15:56] [Shotgun.FIX#243] Shell LOADED - 8/8 shells in tube   <-- Second shell (BUG!)
```

### Bug #2: Unnecessary Action Open Sound

When transitioning from `NeedsPumpDown` to `Loading` state, the code called `PlayActionOpenSound()`. However, the bolt is already open from the previous pump UP action. This caused an unnecessary/confusing sound effect.

## Solution

### Fix #1: Track Mid-Drag Shell Loading

Added a new flag `_shellLoadedDuringMidDrag` to track if a shell was loaded during mid-drag gesture processing.

**Changes:**
1. Added `_shellLoadedDuringMidDrag` field (initialized to `false`)
2. Set `_shellLoadedDuringMidDrag = true` when `LoadShell()` is called from `TryProcessMidDragGesture()`
3. In `ProcessReloadGesture()`, check this flag and skip loading if already loaded mid-drag
4. Reset the flag when drag ends (along with `_wasMiddleMouseHeldDuringDrag`)

### Fix #2: Remove Unnecessary Sound

Removed the `PlayActionOpenSound()` call when transitioning from `NeedsPumpDown` to `Loading` state, since the bolt is already open.

## Code Changes

### Scripts/Weapons/Shotgun.cs

1. Added new field:
```csharp
/// <summary>
/// Whether a shell was loaded during the current mid-drag gesture.
/// This prevents loading multiple shells in one drag motion (Issue #266).
/// </summary>
private bool _shellLoadedDuringMidDrag = false;
```

2. Modified `TryProcessMidDragGesture()` and `ProcessPumpActionGesture()`:
   - Set `_shellLoadedDuringMidDrag = true` after calling `LoadShell()`
   - Removed `PlayActionOpenSound()` call (bolt already open)

3. Modified `ProcessReloadGesture()`:
   - Added check: if `_shellLoadedDuringMidDrag` is true, skip loading another shell

4. Modified drag end handling:
   - Added reset: `_shellLoadedDuringMidDrag = false`

## Testing

- Build passes with no new errors
- The fix ensures only one shell loads per drag motion
- Users can still load multiple shells by performing multiple separate drag motions

## References

- Issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/266
- Related PR: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/244 (initial shotgun reload fix)
- Game log: `game_log_20260122_221539.txt`
