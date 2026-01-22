# Case Study: Issue #243 - Shotgun Reload Bug

## Issue Summary

**Title:** fix зарядка дробовика (fix shotgun charging)
**Issue URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/243
**Pull Request:** https://github.com/Jhon-Crow/godot-topdown-MVP/pull/244

### Problem Description

After opening the bolt (RMB drag UP), when holding MMB and performing RMB drag DOWN, the bolt closes instead of loading a shell. This issue also manifested as "only works on the second attempt."

**Original Report (Russian):**
> после первого открытия затвора:
> при зажатом MMB и драгндропе ПКМ вниз - затвор закрывается, вместо того чтобы зарядить заряд.
> добавь проверку на зажатое MMB, которая не позволит закрыть затвор, но позволит зарядить заряд.

**Translation:**
> After first opening the bolt:
> when MMB is held and RMB drag-n-drop down - bolt closes instead of loading a shell.
> Add a check for held MMB that will NOT allow closing the bolt, but WILL allow loading a shell.

---

## ROOT CAUSE ANALYSIS (2026-01-22)

### The "Only Works on Second Attempt" Bug

After multiple fix iterations, the user consistently reported that shell loading "only works on the second attempt." Investigation revealed the root cause:

### The Bug

In `_Process()`, the middle mouse button state (`_isMiddleMouseHeld`) was being updated **AFTER** `HandleDragGestures()` was called. This caused a one-frame delay in MMB state detection:

**Buggy Code Flow:**
```csharp
public override void _Process(double delta)
{
    HandleDragGestures();      // Uses STALE _isMiddleMouseHeld from previous frame!
    HandleMiddleMouseDrag();   // Updates _isMiddleMouseHeld (too late!)
}
```

**Timeline of Bug:**

| Frame | _isMiddleMouseHeld State | User Action | Result |
|-------|-------------------------|-------------|--------|
| Frame 1 | false (default) | Opens bolt, starts holding MMB | MMB state not yet tracked |
| Frame 2 | false (stale!) | Drags RMB down with MMB held | HandleDragGestures sees MMB=false → BOLT CLOSES |
| Frame 3 | true (correct) | Tries again with MMB held | Now HandleDragGestures sees MMB=true → Shell loads |

### The Fix

Update `_isMiddleMouseHeld` **BEFORE** `HandleDragGestures()`:

```csharp
public override void _Process(double delta)
{
    UpdateMiddleMouseState();  // Update MMB state FIRST!
    HandleDragGestures();      // Now uses CURRENT _isMiddleMouseHeld
}

private void UpdateMiddleMouseState()
{
    _isMiddleMouseHeld = Input.IsMouseButtonPressed(MouseButton.Middle);
}
```

### Additional Safety: `_wasMiddleMouseHeldDuringDrag`

To handle cases where users release MMB and RMB simultaneously, we track if MMB was held at **any point** during the drag:

```csharp
// At drag start
_wasMiddleMouseHeldDuringDrag = _isMiddleMouseHeld;

// During drag
if (_isMiddleMouseHeld)
    _wasMiddleMouseHeldDuringDrag = true;

// At drag end (RMB release)
bool shouldLoadShell = _wasMiddleMouseHeldDuringDrag || _isMiddleMouseHeld;
```

---

## Control Scheme

### Current Control Scheme (Restored)
```
RMB drag UP (open bolt) → [MMB hold + RMB drag DOWN]×N (load shells) → RMB drag DOWN (close bolt)
```

### Tutorial Text
`[ПКМ↑ открыть] [СКМ+ПКМ↓ x8] [ПКМ↓ закрыть]`

---

## Technical Implementation

### Key Files
- `Scripts/Weapons/Shotgun.cs` - Main shotgun weapon code

### Critical Variables
- `_isMiddleMouseHeld`: Current MMB pressed state
- `_wasMiddleMouseHeldDuringDrag`: Tracks if MMB was held during current drag
- `VerboseInputLogging`: Enable detailed diagnostic messages (currently true)

### Diagnostic Log Messages
When the fix is active, look for these log entries:
- `[Shotgun.FIX#243] RMB drag started - initial MMB state: X`
- `[Shotgun.FIX#243] RMB released - processing drag gesture (wasMMBDuringDrag=X)`
- `[Shotgun.FIX#243] RMB release in Loading state: wasMMBDuringDrag=X, isMMBHeld=X => shouldLoadShell=X`
- `[Shotgun.FIX#243] Loading shell (MMB was held during drag)`
- `[Shotgun.FIX#243] Closing bolt (MMB was not held)`

---

## Timeline of Events

| Timestamp | Event |
|-----------|-------|
| 2026-01-22 11:16:29 | Issue #243 created |
| 2026-01-22 11:17:08 | Initial commit with task details |
| 2026-01-22 11:23:58 | Fix v1: prevent bolt closing when MMB is held |
| 2026-01-22 14:29:19 | User reports "nothing changed" (fix not in build) |
| 2026-01-22 14:41:36 | User tested new build, reports "only works on second attempt" |
| 2026-01-22 14:46:31 | User requests: try MMB drag down instead |
| 2026-01-22 ~14:54 | Fix v2: MMB drag DOWN for shell loading (new control scheme) |
| 2026-01-22 15:05:43 | User reports: "this option also only works on second attempt" |
| 2026-01-22 15:07:44 | Root cause identified: MMB state update timing issue |
| 2026-01-22 ~15:40 | Fix v3: Proper timing + revert to original control scheme |
| 2026-01-22 12:23:12 UTC | User reports "я использую последний билд" with log file 15:21:59 (12:21:59 UTC) |
| 2026-01-22 12:48:24 UTC | Fix v4: LogToFile() instead of GD.Print() for diagnostic messages (commit 7189e98) |
| 2026-01-22 12:49:49 UTC | New CI build completed with LogToFile fix |

---

## Key Discovery: GD.Print() vs LogToFile()

### The Problem

The diagnostic messages (`[Shotgun.FIX#243]`) were using `GD.Print()` which only writes to the **Godot console**. However, the user's log files are generated by the **FileLogger autoload** - a separate logging system.

Since `GD.Print()` doesn't write to FileLogger, the diagnostic messages never appeared in the user's `game_log_*.txt` files.

### The Solution

Changed all `[Shotgun.FIX#243]` diagnostic messages to use `LogToFile()` method:

```csharp
private void LogToFile(string message)
{
    GD.Print(message);  // Console
    var fileLogger = GetNodeOrNull("/root/FileLogger");
    if (fileLogger != null && fileLogger.HasMethod("log_info"))
    {
        fileLogger.Call("log_info", message);  // File
    }
}
```

This writes to both:
1. The Godot console (`GD.Print()`)
2. The FileLogger autoload (`game_log_*.txt` file)

---

## Artifacts

### Logs
- `logs/game_log_20260122_142919.txt` - User's first test (no fix messages - old build)
- `logs/game_log_20260122_144136.txt` - User's second test
- `logs/game_log_20260122_144154.txt` - User's third test
- `logs/game_log_20260122_144226.txt` - User's fourth test
- `logs/game_log_20260122_150232.txt` - User's test with MMB drag down (still no fix messages)
- `logs/game_log_20260122_152159.txt` - User's test before LogToFile fix (created 12:21:59 UTC, before fix at 12:48:24 UTC)

### Key Observation from Logs
None of the user logs contained `[Shotgun.FIX#243]` diagnostic messages. Root cause identified:

1. **GD.Print() vs FileLogger**: The diagnostic messages used `GD.Print()` which only writes to Godot console, NOT to FileLogger's `game_log_*.txt` files
2. **Build timing**: User's latest test (game_log_20260122_152159.txt) was from 12:21:59 UTC, but the LogToFile fix was committed at 12:48:24 UTC

### Verification Pending
User needs to download the build from 12:49:49 UTC or later to test the LogToFile fix.

---

## Verification Steps

To verify the fix is working:

1. **Download the latest CI build** from: https://github.com/konard/Jhon-Crow-godot-topdown-MVP/actions?query=branch%3Aissue-243-b3e05cb772c2

2. **Test the reload sequence:**
   - RMB drag UP (bolt opens)
   - While keeping RMB held or after releasing, hold MMB
   - RMB drag DOWN with MMB held (shell loads)
   - Repeat for more shells
   - RMB drag DOWN without MMB (bolt closes)

3. **Critical: Check log for `[Shotgun.FIX#243]` messages**
   - If these messages are NOT present, the build does NOT contain the fix
   - Messages should appear on every RMB drag start/end and state transition

---

## Lessons Learned

1. **Input state update order matters**: In frame-based game loops, the order of input state updates relative to input processing is critical.

2. **Track cumulative state for user-friendly input**: Users often press/release buttons simultaneously. Tracking "was ever pressed during gesture" is more robust than "is currently pressed."

3. **Diagnostic logging is essential**: The root cause was only identified after noticing that user logs lacked the expected diagnostic messages.

4. **Verify build deployment**: When users report "nothing changed," verify they are actually running the new build by checking for diagnostic log messages.

5. **Use the correct logging system**: In multi-system projects, ensure diagnostic messages use the appropriate logging mechanism. `GD.Print()` only writes to console; FileLogger must be called explicitly for file logging.

6. **Verify timing of builds vs tests**: Always compare timestamps of user test logs with CI build completion times to ensure they tested the correct build.
