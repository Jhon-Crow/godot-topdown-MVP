# Case Study: Issue #232 - Shotgun Shell Loading Regression

## Problem Statement

**Issue:** After the first bolt opening, when holding MMB and doing RMB drag down, the bolt closes instead of loading a shell. This is a regression from the fix in #213.

**Original (Russian):** "после первого открытия затвора: при зажатом MMB и драгндропе ПКМ вниз - затвор закрывается, вместо того чтобы зарядить заряд."

## Timeline of Events

### Historical Context

1. **Issue #213** (2026-01-22 05:31): First report of shell loading bug
   - After opening bolt, first MMB + RMB drag down closes bolt instead of loading shell
   - Root cause: Input processing order in `_Process()` - MMB state was checked before being updated
   - Fix: Reorder `HandleMiddleMouseButton()` before `HandleDragGestures()`
   - PR #214 merged at 05:45

2. **Issue #210** (2026-01-22): Continuous gesture support added
   - PR #215 added mid-drag gesture processing
   - This allowed bolt open/close in one fluid motion
   - Introduced a NEW bug: Mid-drag processing could close bolt before user had time to press MMB

3. **Issue #232** (2026-01-22 09:19): Regression reported
   - Same symptom as #213: bolt closes instead of loading shell
   - Different root cause: Mid-drag gesture processing in `TryProcessMidDragGesture()`

4. **First Fix Attempt** (2026-01-22 10:26): PR #233 created
   - Modified `TryProcessMidDragGesture()` to never process drag DOWN in Loading state
   - Always defers to release-based gesture processing
   - User reports: "problem persists" (2026-01-22 13:07 Moscow time)

## Root Cause Analysis

### The Problematic Code Path (Before Fix)

In `TryProcessMidDragGesture()` for `ShotgunReloadState.Loading`:

```csharp
case ShotgunReloadState.Loading:
    if (isDragDown)
    {
        bool shouldLoadShell = _wasMiddleMouseHeldDuringDrag || _isMiddleMouseHeld;

        if (shouldLoadShell)
        {
            return false;  // Don't process mid-drag
        }
        else
        {
            CompleteReload();  // BUG: Closes bolt prematurely!
        }
        gestureProcessed = true;
    }
    break;
```

**The Bug Flow:**
1. User opens bolt (RMB drag UP) - works fine
2. User wants to load a shell: holds MMB + RMB drag DOWN
3. `TryProcessMidDragGesture()` is called as soon as drag threshold (~30px) is reached
4. If user hasn't pressed MMB yet at that exact moment, `shouldLoadShell` evaluates to `false`
5. Bolt closes prematurely via `CompleteReload()`

### The Fix Applied

Changed the Loading state handling to never process mid-drag:

```csharp
case ShotgunReloadState.Loading:
    if (isDragDown)
    {
        // Always wait for RMB release in Loading state
        return false;
    }
    break;
```

### Why The User Might Still See The Issue

Possible reasons:

1. **Testing against main branch**: PR #233 is not yet merged
   - User needs to test against the `issue-232-5205289e4453` branch

2. **Build not updated**: User might be running an old build
   - The fix was committed at 10:26:27 UTC+1
   - User's log is from 13:05:30 (likely UTC+3) = 10:05:30 UTC
   - This is BEFORE the fix commit!

3. **Another code path**: There might be another scenario not covered

4. **GDScript interop issue**: The user mentioned "conflict of languages or imports"
   - Need to verify C# and GDScript are working together correctly

## Investigation: MMB Tracking During Reload

The core logic for tracking MMB during reload:

1. **Drag start**: `_wasMiddleMouseHeldDuringDrag = _isMiddleMouseHeld`
2. **During drag**: `if (_isMiddleMouseHeld) { _wasMiddleMouseHeldDuringDrag = true; }`
3. **After mid-drag gesture**: `_wasMiddleMouseHeldDuringDrag = _isMiddleMouseHeld` (RESET)
4. **On RMB release**: Check `_wasMiddleMouseHeldDuringDrag || _isMiddleMouseHeld`

**Potential Issue Found:**
After a mid-drag gesture (like opening bolt), the flag is reset at line 415. If:
- Bolt opens via mid-drag
- Flag is reset to current MMB state (false if not held)
- User presses MMB after this reset
- The tracking loop (lines 419-424) should set flag to true
- BUT: This only happens if RMB is still held

**Edge Case:** If user releases RMB very quickly after opening bolt, and MMB was not captured during the tracking window, the shell won't load.

## Proposed Solutions

### Solution 1: Add More Comprehensive Debug Logging
Add detailed logging at every step of the reload process to understand the exact sequence of events.

### Solution 2: Review and Improve MMB Tracking
Ensure `_wasMiddleMouseHeldDuringDrag` is properly maintained across all scenarios.

### Solution 3: Consider Using Input Events Instead of Polling
The current approach polls `Input.IsMouseButtonPressed()` in `_Process()`. Using input events via `_Input()` might provide more reliable button state tracking.

## Files Changed

- `Scripts/Weapons/Shotgun.cs` - Fix in `TryProcessMidDragGesture()` and enhanced logging

## Related Issues

- **Issue #213**: Original shell loading bug (fixed input processing order)
- **Issue #210**: Continuous gestures feature (introduced regression)
- **PR #214**: Fix for #213
- **PR #215**: Continuous gestures implementation

## User-Provided Logs

- `logs/game_log_20260122_130529.txt` - Game log showing shotgun firing but no reload log messages

## Next Steps

1. Verify user is testing with the correct branch/build
2. Add comprehensive debug logging
3. Test all edge cases:
   - Quick gestures (MMB pressed late)
   - Slow gestures (MMB pressed early)
   - Same-frame button releases
   - Continuous gesture flows (UP then DOWN without release)
