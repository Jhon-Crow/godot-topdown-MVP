# Case Study: Issue #243 - Shotgun Reload Bug

## Issue Summary

**Title:** fix зарядка дробовика (fix shotgun charging)
**Issue URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/243
**Pull Request:** https://github.com/Jhon-Crow/godot-topdown-MVP/pull/244

### Problem Description

After opening the bolt (RMB drag UP), when holding MMB and performing RMB drag DOWN, the bolt closes instead of loading a shell.

**Original Report (Russian):**
> после первого открытия затвора:
> при зажатом MMB и драгндропе ПКМ вниз - затвор закрывается, вместо того чтобы зарядить заряд.
> добавь проверку на зажатое MMB, которая не позволит закрыть затвор, но позволит зарядить заряд.

**Translation:**
> After first opening the bolt:
> when MMB is held and RMB drag-n-drop down - bolt closes instead of loading a shell.
> Add a check for held MMB that will NOT allow closing the bolt, but WILL allow loading a shell.

---

## Technical Analysis

### Code Structure

The shotgun reload mechanic is implemented in `Scripts/Weapons/Shotgun.cs`. Key components:

1. **State Machine:**
   - `ShotgunReloadState`: NotReloading, WaitingToOpen, Loading, WaitingToClose
   - `ShotgunActionState`: Ready, NeedsPumpUp, NeedsPumpDown

2. **Input Handling Methods:**
   - `HandleDragGestures()`: Main input handler for RMB drag gestures
   - `TryProcessMidDragGesture()`: Processes gestures while RMB is still held
   - `ProcessDragGesture()`: Processes gestures when RMB is released
   - `ProcessReloadGesture()`: Handles reload-specific logic
   - `HandleMiddleMouseButton()`: Tracks MMB state

3. **MMB Tracking Variables:**
   - `_isMiddleMouseHeld`: Current MMB state (updated each frame)
   - `_wasMiddleMouseHeldDuringDrag`: Whether MMB was held at any point during the drag

### The Problem: Mid-Drag vs Release-Based Gesture Processing

The shotgun supports two gesture processing modes:

1. **Mid-Drag Processing:** Gesture is processed immediately when drag threshold is reached while RMB is still held. This allows continuous gestures (drag up, then down without releasing RMB).

2. **Release-Based Processing:** Gesture is processed when RMB is released.

**The Bug:** In mid-drag processing, the bolt could close immediately when the drag-down threshold was reached, BEFORE the user had a chance to hold MMB for shell loading.

### Root Cause Analysis

The original code in `TryProcessMidDragGesture()` for `Loading` state:

```csharp
case ShotgunReloadState.Loading:
    if (isDragDown)
    {
        bool shouldLoadShell = _wasMiddleMouseHeldDuringDrag || _isMiddleMouseHeld;

        if (shouldLoadShell)
        {
            return false; // Let release-based gesture handle it
        }
        else
        {
            CompleteReload(); // BUG: Closes bolt immediately!
        }
        gestureProcessed = true;
    }
    break;
```

**Problem Scenario:**
1. User opens bolt with RMB drag UP (mid-drag)
2. `_dragStartPosition` resets to current position
3. `_wasMiddleMouseHeldDuringDrag` resets to current MMB state (likely false)
4. User presses MMB and starts dragging DOWN
5. As soon as drag threshold is reached, `TryProcessMidDragGesture()` is called
6. If MMB wasn't tracked yet (race condition), `shouldLoadShell = false`
7. `CompleteReload()` is called, closing the bolt prematurely

### The Fix

Modified `TryProcessMidDragGesture()` to NEVER process the gesture in Loading state with drag DOWN. Instead, always defer to the release-based gesture where MMB state is properly tracked:

```csharp
case ShotgunReloadState.Loading:
    if (isDragDown)
    {
        // FIX for issue #243: Always defer to release-based gesture
        // This gives user time to press MMB at any point during the drag
        return false;
    }
    break;
```

---

## Timeline of Events

| Timestamp | Event |
|-----------|-------|
| 2026-01-22 11:16:29 | Issue #243 created |
| 2026-01-22 11:17:08 | Initial commit with task details |
| 2026-01-22 11:23:58 | Fix committed: prevent bolt closing when MMB is held |
| 2026-01-22 11:26:03 | Reverted task details commit (cleanup) |
| 2026-01-22 11:26:06 | CI build completed successfully |
| 2026-01-22 14:29:19 | User reports "nothing changed" with log file |

---

## Artifacts

### Logs
- `logs/game_log_20260122_142919.txt` - User's game log
- `logs/solution-draft-log.txt` - AI solver's detailed analysis log

### Code Snapshots
The fix is in commit `308bbc2` on branch `issue-243-b3e05cb772c2`.

---

## Diagnostic Logging

To help verify the fix is active, diagnostic log messages were added:

1. **Mid-drag detection:** `[Shotgun.FIX#243] Mid-drag DOWN detected (Loading state): MMB tracked=X, deferring to RMB release`

2. **RMB release:** `[Shotgun.FIX#243] RMB release in Loading state: wasMMBDuringDrag=X, isMMBHeld=X => shouldLoadShell=X`

3. **Action taken:** `[Shotgun.FIX#243] Loading shell (MMB was held during drag)` or `[Shotgun.FIX#243] Closing bolt (MMB was NOT held during drag)`

---

## Verification Steps

To verify the fix is working:

1. **Download the latest CI build** from: https://github.com/konard/Jhon-Crow-godot-topdown-MVP/actions?query=branch%3Aissue-243-b3e05cb772c2

2. **Test the reload sequence:**
   - Hold RMB, drag UP (bolt opens)
   - While keeping RMB held, press and hold MMB
   - Drag DOWN
   - Release RMB
   - **Expected:** Shell loads, bolt stays open
   - **Log output:** Should show `shouldLoadShell=True` and "Loading shell"

3. **Check log file for diagnostic messages:**
   - Look for `[Shotgun.FIX#243]` entries
   - If these entries are missing, the build does not contain the fix

---

## Open Questions

1. **Build Version Confirmation:** The user's log file path (`I:/Загрузки/godot exe/`) suggests a downloaded build. Need to confirm they're using the latest CI artifact from this PR's branch.

2. **Timing Sensitivity:** The fix assumes the release-based gesture properly tracks MMB state throughout the drag. If there are additional timing issues, they would need separate investigation.
