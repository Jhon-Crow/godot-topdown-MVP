# Case Study: Issue #131 - Fix ESC Function

## Overview

**Issue**: #131 - fix esc function (fix esc funkcju)
**PR**: #135
**Date**: 2026-01-20

This case study analyzes the ESC key pause menu functionality issue in the Godot top-down game, identifying the root cause and implementing a fix.

## Problem Statement

The issue reports that pressing ESC should open a menu with items. The user also mentions that all old functionality should be preserved in the exported .exe file.

**Original Issue (Russian)**:
> "pri nazhatii esc dolzhno otkryvat'sya menyu s punktami."
> "ves' staryy funktsional dolzhen byt' sokhranyon v exe."

**Translation**:
> "Pressing ESC should open a menu with items."
> "All old functionality should be preserved in exe."

## Timeline Reconstruction

### PR #120: Fullscreen Mode (Merged 2026-01-18)

Added fullscreen mode with mouse capture:
- Enabled exclusive fullscreen mode (`window/size/mode=3`)
- Set mouse to `MOUSE_MODE_CONFINED_HIDDEN` during gameplay
- Added cursor visibility toggle in pause menu

### PR #125: Difficulty Selection (Merged 2026-01-18)

Added difficulty selection menu as sub-menu of pause menu:
- Normal mode (classic gameplay)
- Hard mode (enemies react when player looks away)

### Issue #131 Reported (2026-01-20)

User reports ESC function not working as expected.

## Technical Analysis

### Current Implementation

The pause menu system consists of:

| File | Purpose |
|------|---------|
| `scenes/ui/PauseMenu.tscn` | Pause menu UI layout |
| `scripts/ui/pause_menu.gd` | Pause menu controller |
| `scripts/autoload/input_settings.gd` | Input handling singleton |
| `project.godot` | ESC key mapped to "pause" action |

### Input Flow

```
ESC Key Press
    |
    v
InputMap "pause" action triggered
    |
    v
PauseMenu._unhandled_input() should be called
    |
    v
toggle_pause() opens/closes menu
```

### Root Cause Identified

**The bug is in `scenes/ui/PauseMenu.tscn` line 7:**

```
process_mode = 2
```

In Godot 4, the `ProcessMode` enum values are:

| Constant | Value | Behavior |
|----------|-------|----------|
| PROCESS_MODE_INHERIT | 0 | Inherit from parent |
| PROCESS_MODE_PAUSABLE | 1 | Paused when game is paused |
| PROCESS_MODE_WHEN_PAUSED | 2 | **Only processes when game IS paused** |
| PROCESS_MODE_ALWAYS | 3 | Always processes regardless of pause state |
| PROCESS_MODE_DISABLED | 4 | Never processes |

**The Problem:**
- `process_mode = 2` means `PROCESS_MODE_WHEN_PAUSED`
- Initially, the game is NOT paused
- Therefore, the PauseMenu node does not process `_unhandled_input()`
- When user presses ESC, the pause menu cannot detect it
- The menu never opens!

### Why It Worked Before

This is likely a regression. Looking at related PRs:
- PR #120 added the pause menu with fullscreen mode
- The process_mode was probably set incorrectly at that time, but may have been masked by other factors during testing in the editor (where the pause state might behave differently)

## Solution

**Change `process_mode` from 2 to 3 in `PauseMenu.tscn`:**

```diff
[node name="PauseMenu" type="CanvasLayer"]
layer = 100
-process_mode = 2
+process_mode = 3
script = ExtResource("1_pause")
```

**Why `PROCESS_MODE_ALWAYS (3)` is correct:**
1. Allows detecting ESC when game is NOT paused (to open menu)
2. Continues processing when game IS paused (to handle menu buttons and close menu)
3. The pause menu is lightweight (only a few buttons) so performance impact is negligible

## Test Plan

1. Launch the game
2. Verify game starts in unpaused state
3. Press ESC - pause menu should appear with items (Resume, Controls, Difficulty, Quit)
4. Click Resume or press ESC again - menu should close, game should resume
5. Press ESC, click Controls - controls menu should appear
6. Press ESC, click Difficulty - difficulty menu should appear
7. Export to .exe and repeat all tests

## Files Changed

- `scenes/ui/PauseMenu.tscn` - Changed process_mode from 2 to 3

## References

- [Godot Documentation: Pausing Games](https://docs.godotengine.org/en/stable/tutorials/scripting/pausing_games.html)
- [Godot Documentation: Node Process Mode](https://docs.godotengine.org/en/stable/classes/class_node.html)
- [Related PR #120: Fullscreen mode with mouse capture](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/120)

## Conclusion

The ESC key pause menu was not working because the `PauseMenu` node was set to `PROCESS_MODE_WHEN_PAUSED`, which prevents it from detecting input when the game is not paused. The fix is to change the process mode to `PROCESS_MODE_ALWAYS` so the pause menu can always detect the ESC key press regardless of the game's pause state.
