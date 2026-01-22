# Case Study: Issue #232 - Shotgun Shell Loading Regression

## Problem Statement

**Issue:** After the first bolt opening, when holding MMB and doing RMB drag down, the bolt closes instead of loading a shell. This is a regression from the fix in #213.

**Original (Russian):** "после первого открытия затвора: при зажатом MMB и драгндропе ПКМ вниз - затвор закрывается, вместо того чтобы зарядить заряд."

## User Requirement Clarification

**User stated (in Russian):** "при зажатом MMB должно быть невозможно закрыть затвор"

**Translation:** "While MMB is held, it should be impossible to close the bolt"

**Interpretation:**
- When MMB is held, bolt closing should be BLOCKED entirely
- Any RMB drag DOWN while MMB is held should load a shell (if possible)
- Bolt can only be closed when MMB is released

**Expected reload workflow:**
1. Open bolt (RMB drag UP)
2. Hold MMB
3. RMB drag DOWN → load shell 1 (bolt stays open)
4. RMB drag DOWN → load shell 2 (bolt stays open - MMB blocks close)
5. RMB drag DOWN → load shell 3 (bolt stays open - MMB blocks close)
6. Release MMB
7. RMB drag DOWN → close bolt

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

5. **User Feedback** (2026-01-22 13:07 Moscow time): "problem persists"
   - Log file shows NO `[Shotgun.Reload]` debug messages
   - This indicates C# code changes were NOT included in the user's build
   - See "C# Build Issue" section below

6. **Second User Feedback** (2026-01-22 13:23 Moscow time): Same issue
   - User confirms: "при зажатом MMB должно быть невозможно закрыть затвор"
   - Clarifies the expected behavior: MMB should BLOCK bolt closing

## C# Build Issue

### Evidence

Both user-provided logs (`game_log_20260122_130529.txt` and `game_log_20260122_132129.txt`) show:
- The shotgun IS being detected: `[Player] Detected weapon: Shotgun (Shotgun pose)`
- Multiple gunshot sounds from shotgun firing
- **NO `[Shotgun.Reload]` debug messages at all**

This is definitive evidence that the C# code changes (which include detailed reload logging) are NOT being compiled into the user's export.

### Possible Causes

1. **User running old build**: The C# code was not recompiled before export
2. **Export configuration issue**: Windows export might not include C# assemblies
3. **Godot C# export bug**: See [GitHub issue #112918](https://github.com/godotengine/godot/issues/112918) - affects Godot 4.6 dev builds

### Solution

Added version identifier to Shotgun.cs initialization:
```csharp
GD.Print("[Shotgun] *** C# BUILD VERSION: 2026-01-22-v2 (Issue #232 fix) ***");
```

If this message does NOT appear in the log, the C# code was not recompiled!

## The Fix (v2)

### Changed Behavior

In `ProcessReloadGesture()` for `ShotgunReloadState.Loading`:

**If MMB is currently held OR was held during drag:**
- ALWAYS attempt to load a shell
- Bolt close is BLOCKED
- Bolt remains open for more shells

**If MMB was never held during drag:**
- Close bolt

```csharp
case ShotgunReloadState.Loading:
    if (isDragDown)
    {
        bool shouldLoadShell = _wasMiddleMouseHeldDuringDrag || _isMiddleMouseHeld;

        if (shouldLoadShell)
        {
            // Load shell (bolt close blocked while MMB held)
            LoadShell();
            // Bolt remains OPEN for more shells
        }
        else
        {
            // Close bolt (MMB never held)
            CompleteReload();
        }
    }
    break;
```

### Mid-Drag Gesture Handling

In `TryProcessMidDragGesture()`, the Loading state with drag DOWN now ALWAYS returns `false` to defer to release-based gesture processing:

```csharp
case ShotgunReloadState.Loading:
    if (isDragDown)
    {
        // Always wait for RMB release to give user time to press MMB
        return false;
    }
    break;
```

## Files Changed

- `Scripts/Weapons/Shotgun.cs` - Fix in `ProcessReloadGesture()` and `TryProcessMidDragGesture()` plus version identifier

## User-Provided Logs

- `logs/game_log_20260122_130529.txt` - First log (no reload messages)
- `logs/game_log_20260122_132129.txt` - Second log (still no reload messages)

## Verification Instructions

To verify the fix is working:

1. **Check for version message in log:**
   ```
   [Shotgun] *** C# BUILD VERSION: 2026-01-22-v2 (Issue #232 fix) ***
   ```

2. **Check for reload debug messages:**
   ```
   [Shotgun.Reload] === BOLT OPENED ===
   [Shotgun.Reload] === MMB DETECTED DURING DRAG ===
   [Shotgun.Reload] >>> LOADING SHELL (MMB is/was held) <<<
   [Shotgun.Reload] Bolt remains OPEN for more shells
   ```

3. **Test the workflow:**
   - Open bolt (RMB drag UP)
   - Hold MMB
   - RMB drag DOWN → should load shell, bolt stays open
   - RMB drag DOWN → should load another shell
   - Release MMB
   - RMB drag DOWN → should close bolt

## C# Build Requirements

For the fix to work, the user must:

1. **Rebuild C# assemblies** before exporting:
   - In Godot Editor: Build → Build Solution (or Ctrl+Shift+B)
   - Or from command line: `dotnet build`

2. **Use correct export template**:
   - Ensure using Godot .NET/Mono version
   - Download matching export templates

3. **Check engine version**:
   - User's log shows "4.3-stable"
   - This version should work correctly
   - Avoid Godot 4.6 dev builds (have export bugs)

## Related Issues

- **Issue #213**: Original shell loading bug (fixed input processing order)
- **Issue #210**: Continuous gestures feature (introduced regression)
- **PR #214**: Fix for #213
- **PR #215**: Continuous gestures implementation
- **PR #233**: Fix for #232 (this issue)

## References

- [Godot C# Export Bug #112918](https://github.com/godotengine/godot/issues/112918)
