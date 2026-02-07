# Case Study: Issue #568 - Skip Score Animations with LMB

## Issue Summary

**Issue**: [#568](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/568) - Add ability to skip score counting animations with LMB click and add navigation buttons (Next Level, Level Select) to the score screen.

**Reported problem**: Owner (Jhon-Crow) reported "doesn't work" ("не работает") on PR #569 with a game log file.

## Timeline of Events

1. **Initial implementation** (commit `4317c85`): Added LMB skip via `_unhandled_input()` in `animated_score_screen.gd`, added Next Level/Level Select buttons to all three levels.
2. **User testing**: Owner tested BuildingLevel, completed it (score 20666, Rank C), observed that LMB skip did not work. The full 14-second animation played before buttons appeared. Game was closed shortly after.

### Log Timeline Analysis

From `game_log_20260207_153857.txt`:

| Timestamp | Event |
|-----------|-------|
| 15:39:41 | Player controls disabled (level completed) |
| 15:39:41 | Replay recording stopped |
| 15:39:41 | ScoreManager: Level completed! Final score: 20666, Rank: C |
| 15:39:55 | Watch Replay button created (14s later = full animation played) |
| 15:39:57 | Game log ended (user closed game) |

**Key observation**: The 14-second gap between level completion and button creation indicates the full animation played without being skipped. No errors or exceptions were logged.

## Root Cause Analysis

### Root Cause #1: `_unhandled_input()` never receives mouse events

The `animated_score_screen.gd` used `_unhandled_input()` to detect LMB clicks for skipping animations. However, Godot's input processing order is:

1. `_input()` callbacks (highest priority)
2. **GUI/Control node processing** (mouse_filter determines behavior)
3. `_unhandled_input()` callbacks (lowest priority)

The score screen creates UI elements (VBoxContainer, Labels, HBoxContainer) that have the **default `mouse_filter = MOUSE_FILTER_STOP`**. This means:
- When the user clicks on the score screen area, the Control nodes **consume the mouse event** in step 2
- The event never reaches `_unhandled_input()` in step 3
- Therefore, LMB skip **never triggers**

Additionally, the parent `UI` Control node in the scene tree (`CanvasLayer/UI`) uses `PRESET_FULL_RECT` with default `MOUSE_FILTER_STOP`, creating a full-screen input barrier.

**Fix**: Changed `_unhandled_input()` to `_input()` which fires before GUI processing. Added `get_viewport().set_input_as_handled()` to prevent the click from propagating further during COUNTING and RANK_REVEAL phases.

### Root Cause #2: LevelsMenu back button not connected

When the Level Select button was pressed, a `LevelsMenu` overlay was created and added to the scene tree. However, the `back_pressed` signal from `LevelsMenu` was never connected, so clicking the "Back" button in the level selection menu would emit the signal but nothing would close the overlay.

**Fix**: Connected `back_pressed` signal to `queue_free()` on the levels menu node in all three level scripts.

## Files Changed

| File | Change |
|------|--------|
| `scripts/ui/animated_score_screen.gd` | `_unhandled_input()` → `_input()` with `set_input_as_handled()` |
| `scripts/levels/building_level.gd` | Connected `back_pressed` signal on LevelsMenu |
| `scripts/levels/castle_level.gd` | Connected `back_pressed` signal on LevelsMenu |
| `scripts/levels/test_tier.gd` | Connected `back_pressed` signal on LevelsMenu |

## Lessons Learned

1. **Godot input order matters**: When creating UI overlays with Control nodes, `_unhandled_input()` will not receive mouse events that hit those controls. Use `_input()` for input that must work regardless of UI state.
2. **Default mouse_filter is STOP**: All Control nodes (Label, VBoxContainer, etc.) have `mouse_filter = MOUSE_FILTER_STOP` by default, which consumes mouse events silently.
3. **Signal connections must be verified**: When creating UI overlays dynamically and emitting signals, always verify the signal is connected to a handler.
4. **Test with actual gameplay**: Log analysis showed no errors - the bug was a silent input routing issue that could only be found by understanding Godot's input propagation system.
