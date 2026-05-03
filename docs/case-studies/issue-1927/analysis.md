# Case Study: Issue #1927 — Game Crash When Picking Revolver and Pressing Confirm

## Summary

Hard crash (no error printed to log) when the player opens the armory menu, selects a weapon, and presses "Apply" (подтвердить / confirm) to restart the scene while the revolver is (or was recently) equipped.

## Environment

- OS: Windows
- Build: release (non-debug), Godot 4.3-stable
- Branch: issue-1925-34da7c98b0a6
- Build date: 2026-05-03T06:05:00Z

## Crash Log

See `game_log_20260503_093315.txt`. The log ends abruptly at line 1107 during shotgun gameplay on RevolverLevel — no GDScript error, no engine panic line. This is characteristic of a hard C# / engine crash.

## Timeline of Events (from log)

| Time     | Event |
|----------|-------|
| 09:33:15 | Game started on LabyrinthLevel with revolver selected |
| 09:33:16 | Scene auto-navigated to RevolverLevel (last played level) |
| 09:33:17 | Player and 14 enemies initialized on RevolverLevel |
| 09:33:18 | Armory menu opened → player selects Shotgun |
| 09:33:20 | `GameManager.restart_scene()` called; scene reloaded with Shotgun |
| 09:33:20 | New Player/Shotgun session begins on RevolverLevel |
| 09:33:23 | **CRASH** — log ends at line 1107, no error output |

## Root Cause

**File:** `Scripts/Weapons/Revolver.cs`  
**Method:** `_ExitTree()` (line 1853)  
**Issue:** Double-free of `RevolverCylinderUI` node.

### How it Crashes

1. When the revolver is equipped, `SetupCylinderHUD()` (called via `CallDeferred` in `_Ready()`) creates a `RevolverCylinderHUDLayer` CanvasLayer node and adds it as a **direct child of the level root**. Inside this layer is a `RevolverCylinderUI` node, stored as `_cylinderUI`.

2. When the player presses "Apply" in the armory, `GameManager.restart_scene()` is called. This causes the entire level scene to be freed, including:
   - The `Revolver` node (child of the Player, which is a child of the level)
   - The `RevolverCylinderHUDLayer` node (direct child of the level root)
   - The `RevolverCylinderUI` node (child of the HUD layer)

3. During the scene teardown, Godot calls `_ExitTree()` on all nodes. The order is depth-first, but the **relative order** of `Revolver._ExitTree()` vs `RevolverCylinderUI._ExitTree()` is not guaranteed.

4. In `Revolver._ExitTree()` (line 1856-1860), the old code calls:
   ```csharp
   _cylinderUI.DisconnectFromRevolver();
   _cylinderUI.QueueFree();  // ← BUG: double-free
   ```
   But `_cylinderUI` is already being freed as part of the level tree destruction. Calling `QueueFree()` on a node that is already in the process of being freed causes a **hard crash**.

### Why There's No Error Log

This is a Godot C# engine-level crash (not a GDScript error), so `FileLogger` never gets to write an error line. The process terminates before logging can occur.

## Fix

**File:** `Scripts/Weapons/Revolver.cs` — `_ExitTree()` method

Remove the `_cylinderUI.QueueFree()` call. The `RevolverCylinderUI` is a child of the level root and will be freed automatically when the level scene is unloaded. Only disconnecting the signal is needed to prevent stale callbacks during cleanup. `RevolverCylinderUI._ExitTree()` already calls `DisconnectFromRevolver()` on its own, providing a safety net.

```csharp
// Before (BUG):
if (_cylinderUI != null && IsInstanceValid(_cylinderUI))
{
    _cylinderUI.DisconnectFromRevolver();
    _cylinderUI.QueueFree();  // double-free crash
    _cylinderUI = null;
}

// After (FIX):
if (_cylinderUI != null && IsInstanceValid(_cylinderUI))
{
    _cylinderUI.DisconnectFromRevolver();
    // Do NOT call QueueFree() — HUD is owned by the level root and freed automatically
    _cylinderUI = null;
}
```

## Reproduction Steps

1. Start game with revolver equipped on any level
2. Open the armory menu (pause → Armory)
3. Select any weapon (or keep revolver)
4. Press "Apply" / "подтвердить"
5. → Game crashes

## Why This Was Hard to Find

- No error message appears (hard engine crash, not GDScript exception)
- The crash occurs a few frames after the apply button is pressed, during scene teardown
- The `RevolverCylinderHUDLayer` is added to the level root (not as a child of the Revolver node), creating a non-obvious ownership relationship

## Related Issues

- Issue #691: Cylinder HUD creation
- Issue #1765: HUD layer z-ordering
