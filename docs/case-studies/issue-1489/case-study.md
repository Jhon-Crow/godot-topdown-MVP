# Case Study: Issue #1489 — Score Screen Bugs After Decadence Level

## Summary

After completing the **Декаданс (Decadence)** level, the score screen has two issues:
1. **No cursor** — the mouse cursor is hidden, making UI interaction difficult
2. **Armory button not highlighted** — when new items are available to unlock, the "Armory" button should display as "★ Armory — Items Available!" with gold styling, but it shows as plain "Armory" with no visual cue

## Log File

`game_log_20260325_064919.txt` — provided by the reporter.

## Timeline Reconstruction

| Time | Event |
|------|-------|
| 06:52:26 | Player transitions to DecadenceLevel |
| 06:52:26 | 13 enemies registered, ScoreManager started |
| 06:53:06 | Level completed: rank=S, score=150238 |
| 06:53:06 | `UnlockManager`: items available to unlock in armory |
| 06:53:12 | Player presses Armory button from score screen (managed to find it despite no cursor) |

Key observation from log:
- After LabyrinthLevel completion, the log shows: `[LabyrinthLevel] Watch Replay button not shown (replay viewing disabled in experimental settings)` — this indicates the full `_add_score_screen_buttons` path with proper logging ran.
- After DecadenceLevel completion, **no such log entry** appears. This indicates the Decadence level's `_add_score_screen_buttons` is a different, older, incomplete version.

## Root Cause Analysis

Comparing `decadence_level.gd` vs `labyrinth_level.gd` / `beach_level.gd` (reference implementations):

### Bug 1: No cursor (MOUSE_MODE not set)

In `labyrinth_level.gd` and `beach_level.gd`, `_add_score_screen_buttons()` ends with:
```gdscript
# Show cursor for button interaction
Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)
```

In `decadence_level.gd`, this call is **completely absent** from `_add_score_screen_buttons()`. The game keeps the cursor in `MOUSE_MODE_CONFINED_HIDDEN` (set during gameplay) throughout the score screen.

### Bug 2: Armory button not highlighted

In `labyrinth_level.gd` and `beach_level.gd`, the armory button is conditionally created with gold styling:
```gdscript
var unlock_manager: Node = get_node_or_null("/root/UnlockManager")
if unlock_manager != null and unlock_manager.has_method("has_any_available_unlock") and unlock_manager.has_any_available_unlock():
    var armory_button := Button.new()
    armory_button.text = "★ Armory — Items Available!"
    armory_button.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))
    # ... gold StyleBoxFlat ...
```

In `decadence_level.gd`, the armory button is **always created as a plain button** with text "Armory" and no condition/styling, and the `UnlockManager` is never consulted.

### Additional missing features in `decadence_level.gd`

Compared to the reference levels:
- `_on_armory_button_pressed()` lacks connections to `apply_pressed_from_score_screen` signal
- Missing `_remove_armory_button_gold_style()` helper function
- `_on_level_select_pressed()` is missing `Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)` call
- No keyboard focus set on initial button after score screen appears
- Replay button uses old API (`WatchReplayButton` vs `ReplayButton`, old text format)

## Fix

Update `decadence_level.gd`:
1. Replace the entire `_add_score_screen_buttons()` with the updated implementation matching `beach_level.gd`
2. Replace `_on_armory_button_pressed()` with the full implementation including `apply_pressed_from_score_screen` signal connection
3. Add `_remove_armory_button_gold_style()` helper function
4. Add `Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)` to `_on_level_select_pressed()`

## Online Research Context

This type of bug (mouse mode not restored after game-to-UI transition) is a well-known Godot issue. In Godot 4, `Input.set_mouse_mode()` is the correct API for controlling cursor visibility. The game hides the cursor during gameplay via `MOUSE_MODE_CONFINED_HIDDEN` for immersion, but must explicitly restore it to `MOUSE_MODE_CONFINED` when showing UI elements that need click interaction. Failure to do so is a common oversight when implementing new levels.

Gold-highlighted action buttons for "items available" notifications are a UX pattern used across all other levels in this project (Issue #897, #1050). The Decadence level simply missed this update, likely added to other levels after the Decadence level was first implemented.
