# Case Study: Issue #1514 — Performance Menu Bugs (Empty Select + Can't Exit)

## Summary

After the V-Sync toggle and FPS limit selector were added to the Performance menu (PR #1515), two bugs were reported by the repository owner:

1. **Bug A — Empty FPS limit dropdown**: Opening the Performance menu shows no items in the FPS limit `OptionButton` selector.
2. **Bug B — Cannot exit Performance settings**: Pressing ESC or clicking the "Back" button does not navigate back to the Settings menu.

---

## Timeline / Sequence of Events

| Time (UTC) | Event |
|------|-------|
| 2026-03-26 03:51 | PR #1515 opened with V-Sync toggle and FPS limit selector |
| 2026-03-26 03:52 | Auto-restart (merge conflict resolved) |
| 2026-03-26 03:54 | PR marked ready, CI passes |
| 2026-03-26 04:36 | Owner (Jhon-Crow) tests the feature in-game and reports bugs (log: 07:35 Moscow = 04:35 UTC) |
| 2026-03-26 04:50 | Fix commit `d3487242` applied: `select()` instead of `selected=`, ESC popup guard |
| 2026-03-26 04:50 | CI passes with new build artifact |
| 2026-03-26 05:36 | Owner (Jhon-Crow) tests again and reports SAME bugs persist (log: 08:36 Moscow = 05:36 UTC) |

---

## Game Log Analysis

### Log 1: `game_log_20260326_073519.txt` (07:35 Moscow / 04:35 UTC)

The log covers a gameplay session in the Sewer Level (07:35:19–07:35:59). Key observations:

- `PerformanceSettings` autoload initialized correctly:
  ```
  [07:35:19] [INFO] [PerformanceSettings] PerformanceSettings initialized - particles: true,
  blood_decals: true, screen_shake: true, explosion_lights: true, ai: true, vsync: true, fps_limit: 0
  ```
- No errors related to PerformanceMenu during this session.
- The user did NOT open the Performance menu during this session — it was a gameplay session.
- **Build info**: `not available (build_info.cfg not found)` — user is NOT running a CI build.

### Log 2: `game_log_20260326_083603.txt` (08:36 Moscow / 05:36 UTC)

Second test after our fix. Key observations:

- `PerformanceSettings` autoload initialized correctly with new fields:
  ```
  [08:36:03] [INFO] [PerformanceSettings] PerformanceSettings initialized - particles: true,
  blood_decals: false, screen_shake: false, explosion_lights: true, ai: true, vsync: true, fps_limit: 0
  ```
- No `[PerformanceMenu]` log entries — the performance menu script has no logging.
- **Build info**: `not available (build_info.cfg not found)` — SAME build type without CI metadata.
- The game ran ~20 seconds in Tutorial level then quit. No settings interactions were captured.

### Critical Finding: Build Source Unknown

Both game logs show `Build info: not available (build_info.cfg not found)`. CI builds from our workflow include `build_info.cfg` embedded in the PCK at `res://build_info.cfg`. The absence of this file means the user is running a build that was NOT produced by our CI pipeline.

This means we cannot confirm whether the user tested our latest fix commits (`d3487242`). The user may have built the game locally from an older version of the branch, or downloaded an artifact from a different point in time.

**Action taken**: Added `FileLogger`-based diagnostic logging throughout `performance_menu.gd` so the next game log will show exactly which code paths executed when the performance menu was opened.

---

## Root Cause Analysis

### Bug A — Empty FPS limit dropdown (`OptionButton` shows no items)

**Code path** (`scripts/ui/performance_menu.gd`):

In `_ready()`, items are added to `fps_limit_option`:
```gdscript
fps_limit_option.clear()
fps_limit_option.add_item("Unlimited", 0)
fps_limit_option.add_item("30 FPS", 30)
fps_limit_option.add_item("60 FPS", 60)
fps_limit_option.add_item("120 FPS", 120)
```

Then in `_update_ui()`, the selected item is set:
```gdscript
fps_limit_option.selected = fps_idx if fps_idx >= 0 else 0
```

**Root cause**: In Godot 4, assigning the `selected` **property** directly (`selected = idx`) does not always refresh the button's displayed text. The `select(idx)` **method** is the correct API for programmatically selecting an item and updating the visual state. This inconsistency means the button can show empty/no text even when items are present.

**Evidence**: The sibling `GameplayMenu` uses `weapon_hints_option.select(current_mode)` which works correctly. The performance menu uses `fps_limit_option.selected = fps_idx` which does not trigger the visual update reliably.

**Additional contributing factor**: The `OptionButton` is inside a `ScrollContainer` (unique to PerformanceMenu, not present in GameplayMenu). This affects the available rendering area for the button's visible text.

---

### Bug B — Cannot exit Performance settings (ESC and Back button unresponsive)

**Code path for ESC key**:

When ESC is pressed while the Performance submenu is open, TWO handlers compete:

1. **`pause_menu._unhandled_input`** (layer=100, `scripts/ui/pause_menu.gd:72`):
   ```gdscript
   func _unhandled_input(event: InputEvent) -> void:
       if event.is_action_pressed("pause"):
           toggle_pause()
           get_viewport().set_input_as_handled()
   ```
   **No guard condition** — fires unconditionally when ESC is pressed.

2. **`performance_menu._unhandled_input`** (layer=101, `scripts/ui/performance_menu.gd:289`):
   ```gdscript
   func _unhandled_input(event: InputEvent) -> void:
       if visible and event.is_action_pressed("pause"):
           _on_back_pressed()
           get_viewport().set_input_as_handled()
   ```
   Checks `visible` but no guard for whether a popup (OptionButton dropdown) is currently open.

**Race condition / ordering issue**: In Godot 4, `_unhandled_input` processing order across independent `CanvasLayer` nodes is determined by their `layer` value (higher layer = higher input priority). With PerformanceMenu at layer=101 and PauseMenu at layer=100, PerformanceMenu **should** receive ESC first.

However, when the FPS limit `OptionButton` popup is open and the user presses ESC to close it:
1. The PopupMenu closes (consuming the ESC event)
2. Godot may or may not mark the ESC as fully handled
3. If ESC propagates further, `performance_menu._unhandled_input` fires → navigates back → but the user intended only to close the dropdown

This creates confusing behavior where the user loses their place in the menu.

**Back button root cause**: The Back button signal connection (`back_button.pressed.connect(_on_back_pressed)`) should work correctly. However, if the ESC key has already triggered `resume_game()` via the pause_menu, the `settings_menu` may be in a partially hidden state, making `_on_sub_back`'s `menu_container.show()` ineffective (the parent CanvasLayer is hidden).

---

## Proposed Solutions

### Fix A — Use `select()` instead of `selected =`

In `_update_ui()`, replace:
```gdscript
fps_limit_option.selected = fps_idx if fps_idx >= 0 else 0
```
With:
```gdscript
fps_limit_option.select(fps_idx if fps_idx >= 0 else 0)
```

This matches the pattern used in `gameplay_menu.gd` for `weapon_hints_option.select(current_mode)` and reliably updates the displayed text.

### Fix B — Guard ESC handling in performance_menu when popup is open

Add a check to prevent `_on_back_pressed()` from firing when the `OptionButton` popup is open:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
    if visible and event.is_action_pressed("pause"):
        # Don't close the menu if the FPS limit popup is open
        if fps_limit_option.get_popup().visible:
            return
        _on_back_pressed()
        get_viewport().set_input_as_handled()
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/ui/performance_menu.gd` | Use `select()` for OptionButton; add popup-open guard for ESC |
| `tests/unit/test_performance_menu.gd` | Add tests for OptionButton select behavior |

---

## References

- [Godot 4 OptionButton docs](https://docs.godotengine.org/en/stable/classes/class_optionbutton.html)
- `scripts/ui/gameplay_menu.gd` — reference implementation using `select()`
- `scripts/ui/pause_menu.gd:72` — unguarded ESC handler
- PR #1515: Add V-Sync toggle and FPS limit selector
