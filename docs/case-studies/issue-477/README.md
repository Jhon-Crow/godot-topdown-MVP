# Issue #477: Shotgun Extra Reload Bug - Case Study

## Issue Summary

**Title (Russian):** fix лишняя перезарядка дробовика

**Issue Description:**
1. When during one movement during reloading: (1) the bolt opens, (2) closes, (3) and opens again - it's impossible to close the bolt again
2. Replace the pushed shotgun shell sound with the shotgun shell sound (currently it uses regular shell sound)

## Session 2: Additional Bug Report (2026-02-04)

**User feedback (Russian):** "звук заменился, но закрыт затвор после драг-вверх-вниз-вверх не получается"
**Translation:** "The sound was replaced, but closing the bolt after drag-up-down-up doesn't work"

### New Log Analysis (game_log_20260204_093009.txt)

**Key observations from the log:**

1. At 09:30:35: "Bolt opened for loading - ReloadState=Loading, ShellsInTube=6/8"
2. User attempts to close bolt by dragging DOWN multiple times (lines 354-791)
3. At 09:30:37: "Reload drag not vertical: absY=611.1 <= absX=742.2"
4. At 09:30:39: Next drag starts with **ReloadState=Loading** still active!

**Root cause:** When a reload drag gesture fails the verticality check (drag is more horizontal than vertical), the function returns early WITHOUT resetting ReloadState. This causes the bolt to get permanently stuck in Loading state.

## Timeline / Sequence of Events

### Scenario: Single RMB drag with shell loading during pump cycle

**Pre-condition:** Shotgun fired, needs to be pumped (ActionState = NeedsPumpUp)

1. **User drags UP** - Shell ejected, ActionState = NeedsPumpDown
   - Gesture processed, drag start reset

2. **User holds MMB and drags DOWN** - During pump cycle with MMB held:
   - Code at line 779-803 (TryProcessMidDragGesture) detects MMB held
   - Transitions to Loading state (ReloadState = Loading)
   - Loads a shell via LoadShell()
   - Sets `_shellLoadedDuringMidDrag = true`
   - Gesture processed, drag start reset

3. **User drags UP** - In Loading state:
   - No handler for isDragUp in Loading state (line 873-885)
   - Nothing happens, gesture returns false, drag start NOT reset

4. **User drags DOWN** - Should close bolt but:
   - Mid-drag: Returns false for Loading + isDragDown (line 884)
   - On RMB release: ProcessReloadGesture checks `_shellLoadedDuringMidDrag`
   - **BUG:** If `_shellLoadedDuringMidDrag` is true, just breaks without closing bolt!

## Root Cause Analysis

### Bug 1: Bolt Cannot Close After Mid-Drag Shell Loading (v1 fix)

**Location:** `Scripts/Weapons/Shotgun.cs`, ProcessReloadGesture() method, lines 1104-1149

**Root Cause:** The logic order in ProcessReloadGesture() was incorrect:

```csharp
// OLD (buggy) code:
if (_shellLoadedDuringMidDrag)
{
    // Just break - don't close bolt OR load shell
    break;  // <-- BUG: Ignores user intent to close bolt
}

if (shouldLoadShell) { ... }
else { CompleteReload(); }  // Close bolt
```

The check for `_shellLoadedDuringMidDrag` was done BEFORE checking if the user wanted to close the bolt (no MMB held). This caused the bolt closing to be blocked when a shell was loaded mid-drag.

**Fix (v1):** Check MMB FIRST to determine user intent, then handle the duplicate shell loading prevention:

```csharp
// NEW (fixed) code:
if (!shouldLoadShell)
{
    // User wants to close bolt - always allow this
    CompleteReload();
}
else if (_shellLoadedDuringMidDrag)
{
    // Skip duplicate load, stay in Loading state
}
else
{
    // Load shell
    LoadShell();
}
```

### Bug 1a: Non-Vertical Drag Leaves Bolt Stuck (v2 fix)

**Location:** `Scripts/Weapons/Shotgun.cs`, ProcessDragGesture() method, lines 932-943

**Root Cause:** When a drag gesture in Loading state fails the verticality check (drag is more horizontal than vertical), the function returns early WITHOUT closing the bolt. The ReloadState stays stuck in Loading forever.

**Scenario from log:**
1. User opens bolt (ReloadState = Loading)
2. User attempts to drag DOWN to close bolt
3. Drag is slightly diagonal (absY=611 <= absX=742)
4. Function logs "Reload drag not vertical" and returns
5. ReloadState remains Loading - **BUG: Bolt is stuck open!**

**Fix (v2):** When drag is not vertical in Loading state AND MMB is not held, close the bolt anyway:

```csharp
// In ProcessDragGesture(), after verticality check fails:
if (ReloadState == ShotgunReloadState.Loading)
{
    bool shouldLoadShell = _wasMiddleMouseHeldDuringDrag || _isMiddleMouseHeld;
    if (!shouldLoadShell)
    {
        LogToFile($"[Shotgun.FIX#477v2] Non-vertical drag in Loading state without MMB - closing bolt");
        CompleteReload();
    }
}
```

### Bug 2: Shotgun Shell Sound Uses Regular Shell Sound

**Location:** `scripts/effects/casing.gd`, _get_caliber_name() method, lines 270-288

**Root Cause:** The function to get caliber name had incorrect property access for C# Resources:

```gdscript
# OLD (buggy) code:
elif caliber_data.has_method("get"):
    return caliber_data.get("caliber_name") if caliber_data.has("caliber_name") else ""
# has() checks for methods, not properties!
```

When caliber_data is a Resource passed from C# code (like WeaponData.Caliber), the `has("caliber_name")` check was looking for a METHOD named "caliber_name", not a PROPERTY. This caused the function to return an empty string, falling back to the default rifle shell sound.

**Fix:** Use Resource's get() method properly and check for non-null return value:

```gdscript
# NEW (fixed) code:
if caliber_data is Resource:
    var name_value = caliber_data.get("caliber_name")
    if name_value != null and name_value is String:
        return name_value
```

## Files Changed

1. `Scripts/Weapons/Shotgun.cs` - Fixed ProcessReloadGesture() logic order (v1) and ProcessDragGesture() non-vertical handling (v2)
2. `scripts/effects/casing.gd` - Fixed _get_caliber_name() property access

## Testing Notes

To verify the fixes:

1. **Bolt closing bug (v1 - vertical drag):**
   - Fire shotgun
   - Pump UP (eject shell)
   - Hold MMB and pump DOWN (load shell)
   - Release MMB and pump DOWN vertically (should close bolt now)

2. **Bolt closing bug (v2 - diagonal drag):**
   - Fire shotgun
   - Pump UP, DOWN to be ready
   - Drag UP to open bolt for loading
   - Drag diagonally (not purely vertical) to close bolt
   - Should close bolt even with non-vertical drag

3. **Sound bug:**
   - Walk into a shotgun shell casing on the ground
   - Should hear shotgun shell sound, not rifle shell sound

## Log Files

- `game_log_20260204_093009.txt` - User-provided log showing bolt getting stuck after diagonal drag

## Related Issues

- Issue #243: MMB timing during reload
- Issue #266: Multiple shells loading in one drag
- Issue #445: Pump gesture detection when looking up
