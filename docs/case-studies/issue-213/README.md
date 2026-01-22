# Case Study: Issue #213 - Shotgun Reload First Attempt Bug

## Problem Statement

**Issue:** After opening the bolt and trying to load a shell (MMB + RMB drag down) for the first time, the bolt closes instead of loading a shell.

**Original (Russian):** "После открытия затвора и попытки зарядить патрон (MMB + RMB драг вниз) в первый раз - затвор закрывается (должно сразу заряжаться)."

## Timeline of Events

1. User opens bolt (RMB drag UP)
2. User attempts to load shell (MMB + RMB drag DOWN)
3. **Bug:** Bolt closes unexpectedly instead of loading the shell
4. (On subsequent attempts, loading works correctly)

## Root Cause Analysis

### Investigation

The shotgun reload system uses two key variables to track middle mouse button (MMB) state:

1. `_isMiddleMouseHeld` - Whether MMB is currently pressed (updated each frame)
2. `_wasMiddleMouseHeldDuringDrag` - Whether MMB was held at any point during the current RMB drag

### The Bug

The bug was caused by **incorrect order of operations** in the `_Process()` method:

```csharp
// BEFORE FIX (problematic order)
public override void _Process(double delta)
{
    HandleDragGestures();      // Checks _isMiddleMouseHeld (from PREVIOUS frame)
    HandleMiddleMouseButton(); // Updates _isMiddleMouseHeld (for CURRENT frame)
}
```

When the user pressed MMB on the **same frame** as starting the RMB drag:

1. `HandleDragGestures()` runs first and resets `_wasMiddleMouseHeldDuringDrag = false`
2. It then checks `if (_isMiddleMouseHeld)`, but this value is still from the **previous frame**
3. `HandleMiddleMouseButton()` updates `_isMiddleMouseHeld = true`, but it's **too late**
4. If the drag is very quick, MMB is never detected as held during the drag

### Secondary Issue

Additionally, at the start of each new drag, `_wasMiddleMouseHeldDuringDrag` was unconditionally reset to `false`:

```csharp
// BEFORE FIX
if (!_isDragging)
{
    _wasMiddleMouseHeldDuringDrag = false; // Always reset, even if MMB was held!
}
```

This meant that even if MMB was already held when the RMB drag started, that information was lost.

## Solution

### Fix 1: Reorder operations in _Process()

Call `HandleMiddleMouseButton()` **before** `HandleDragGestures()` so that `_isMiddleMouseHeld` is up-to-date when checking during drag processing:

```csharp
// AFTER FIX (correct order)
public override void _Process(double delta)
{
    HandleMiddleMouseButton(); // Update MMB state FIRST
    HandleDragGestures();      // THEN check it during drag handling
}
```

### Fix 2: Initialize flag based on current MMB state

Instead of unconditionally resetting `_wasMiddleMouseHeldDuringDrag` to `false`, initialize it based on the current MMB state:

```csharp
// AFTER FIX
if (!_isDragging)
{
    // Initialize based on CURRENT MMB state
    _wasMiddleMouseHeldDuringDrag = _isMiddleMouseHeld;
}
```

### Fix 3: Add diagnostic logging

Added a `VerboseInputLogging` flag (off by default) to help debug similar input timing issues in the future:

```csharp
private const bool VerboseInputLogging = false;

// In ProcessReloadGesture():
if (VerboseInputLogging)
{
    GD.Print($"[Shotgun.Input] Drag DOWN in Loading state: _wasMMBDuringDrag={_wasMiddleMouseHeldDuringDrag}, _isMMBHeld={_isMiddleMouseHeld}");
}
```

## Files Changed

- `Scripts/Weapons/Shotgun.cs` - Fixed input processing order and MMB tracking logic

## Testing

### Test Steps

1. Start tutorial level with shotgun equipped
2. Fire some shells to create space in the tube magazine
3. Open bolt (RMB drag UP)
4. Immediately try to load a shell (MMB + RMB drag DOWN)
5. Verify shell is loaded (not bolt closed)
6. Repeat multiple times with varying timing
7. Verify subsequent shell loading also works
8. Close bolt and verify normal operation

### Verification

- Build succeeds with no new errors
- No regressions in normal reload behavior
- First load attempt now works correctly regardless of button press timing

## Lessons Learned

1. **Order of input processing matters** - When tracking multiple button states across frames, ensure dependencies are processed in the correct order.

2. **Simultaneous button presses need special handling** - Users often press multiple buttons on the same frame, which requires careful state tracking.

3. **Diagnostic logging is valuable** - Adding debug logging (controlled by a flag) helps diagnose similar issues in the future without affecting performance in production.

4. **Frame-based state vs. instant state** - Be aware that `Input.IsMouseButtonPressed()` returns the current frame's state, but variables set in previous function calls within the same frame still hold their old values.

## Related Issues

- Issue #208 - Shotgun reload UI not updating (fixed in PR #209) - Related to the same reload system but different aspect (UI updates)
