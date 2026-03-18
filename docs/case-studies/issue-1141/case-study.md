# Case Study: Issue #1141 — ESC closes pause menu instead of topmost window

## Issue Summary

**Title:** fix выход из окна по esc (fix ESC exit from window)

**Description (Russian):**
> Currently, pressing ESC in the experimental settings causes the pause menu to close, while the experimental window itself remains open. Fix it so that ESC triggers the back action for the topmost window (so ESC never closes a window below the current one).

**URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1141

---

## Root Cause Analysis

### Menu Architecture

The menu hierarchy is:
```
PauseMenu (pause_menu.gd)
  └── SettingsMenu (settings_menu.gd)
        ├── ControlsMenu (controls_menu.gd)
        ├── DifficultyMenu (difficulty_menu.gd)
        ├── SoundMenu (sound_menu.gd)
        ├── GameplayMenu (gameplay_menu.gd)
        └── ExperimentalMenu (experimental_menu.gd)
              ├── UnlockTableMenu (unlock_table_menu.gd) — added to /root
              └── EnemiesTableMenu (enemies_table_menu.gd) — added to /root
```

Additionally, `PauseMenu` also directly opens:
- ArmoryMenu (armory_menu.gd)
- LevelsMenu (levels_menu.gd)

### The Bug

**`pause_menu.gd` lines 65-68:**
```gdscript
func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("pause"):
        toggle_pause()
        get_viewport().set_input_as_handled()
```

The `"pause"` action is mapped to `KEY_ESCAPE` (see `input_settings.gd` lines 38-42).

When the user navigates to `ExperimentalMenu` and its sub-menus (`UnlockTableMenu`, `EnemiesTableMenu`), none of these menus handle the ESC/pause key. As a result, the input propagates down the node tree until it reaches `PauseMenu._unhandled_input`, which calls `toggle_pause()` → `resume_game()` — closing the entire pause menu, while the topmost window (e.g., ExperimentalMenu) remains visible.

### Why `ControlsMenu` Is Different

`controls_menu.gd` already handles ESC via `_input()` (lines 85-110) because it has a special key-binding capture mode. But it only handles ESC to cancel key-binding capture — it does not emit `back_pressed` via ESC.

### Affected Menus (Missing ESC→Back)

All menus that:
1. Have a `back_pressed` signal
2. Are visible while the pause menu is open
3. Do NOT handle ESC input

This includes **all** submenus except `ControlsMenu` (which handles ESC but only for binding capture):

| Menu | Has `back_pressed` | Handles ESC? |
|---|---|---|
| SettingsMenu | ✓ | ✗ |
| ExperimentalMenu | ✓ | ✗ |
| DifficultyMenu | ✓ | ✗ |
| SoundMenu | ✓ | ✗ |
| GameplayMenu | ✓ | ✗ |
| ControlsMenu | ✓ | Partial (binding capture only) |
| ArmoryMenu | ✓ | ✗ |
| LevelsMenu | ✓ | ✗ |
| UnlockTableMenu | ✓ | ✗ |
| EnemiesTableMenu | ✓ | ✗ |

---

## Solution Analysis

### Option 1: Add `_unhandled_input` to each submenu

Each submenu that has `back_pressed` should handle the `"pause"` action (ESC) and emit `back_pressed`, then mark the input as handled.

**Pros:**
- Simple, each menu is self-contained
- Follows existing Godot patterns
- No global state needed

**Cons:**
- Repetitive code in each file
- Must be kept in sync when new menus are added

### Option 2: Central "window stack" manager (autoload)

Create a singleton that tracks a stack of open windows. When ESC is pressed, it calls `back_pressed` on the topmost window.

**Pros:**
- DRY — one place to change
- Scalable for future windows

**Cons:**
- Over-engineering for current scale
- Requires refactoring existing menus to register/unregister

### Option 3: Override ESC handling in `pause_menu.gd`

In `pause_menu._unhandled_input`, before calling `toggle_pause()`, check if any submenu is currently visible and emit its `back_pressed` instead.

**Pros:**
- Change in one file only

**Cons:**
- `pause_menu` needs to know about all possible open submenus
- Doesn't help for deeply nested menus (UnlockTableMenu inside ExperimentalMenu)

### Chosen Solution: Option 1 (add `_unhandled_input` to each submenu)

This is the most straightforward and idiomatic Godot 4 approach. Each menu already has a `_on_back_pressed` method — we just need to add a `_unhandled_input` that calls it when ESC/pause is pressed.

**Key detail for `ControlsMenu`:** The existing ESC handler there already handles a specific case (canceling key binding). We need to add a fallback: when NOT in binding-capture mode and ESC is pressed, emit `back_pressed`.

---

## Implementation Plan

For each menu that has `back_pressed` but no ESC handling, add:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("pause"):
        _on_back_pressed()
        get_viewport().set_input_as_handled()
```

Menus to update:
1. `settings_menu.gd`
2. `experimental_menu.gd`
3. `difficulty_menu.gd`
4. `sound_menu.gd`
5. `gameplay_menu.gd`
6. `controls_menu.gd` (add fallback ESC → back for when not in binding mode)
7. `armory_menu.gd`
8. `levels_menu.gd`
9. `unlock_table_menu.gd`
10. `enemies_table_menu.gd`

Also, `process_mode = Node.PROCESS_MODE_ALWAYS` must be set in each menu so input is processed while the game tree is paused.

---

## Post-Fix Bug Report (2026-03-18)

After the initial fix (adding `_unhandled_input` to all submenus), Jhon-Crow reported a regression:

> "ESC allows exit only from ONE menu — you can't navigate back through menus sequentially with ESC, and after unpausing you can't reopen the pause menu with ESC."
>
> Log: `docs/case-studies/issue-1141/logs/game_log_20260318_075032.txt`

### Root Cause of Regression

**`pause_menu.gd` was missing `process_mode = Node.PROCESS_MODE_ALWAYS`.**

The `PauseMenu` node is a child of the level scene (e.g., `LabyrinthLevel`), not an autoload. When `pause_game()` calls `get_tree().paused = true`, all nodes with `PROCESS_MODE_INHERIT` (the default) stop processing — including `PauseMenu` itself.

This meant:
- Opening the pause menu: works (game is not yet paused when the first ESC fires)
- After `pause_game()` runs: `PauseMenu._unhandled_input` stops receiving events
- ESC in submenus: works (all submenus set `process_mode = PROCESS_MODE_ALWAYS` in their `_ready()`)
- ESC to close the main pause menu (resume game): BROKEN — `PauseMenu` can't receive input

The symptom "can only exit one menu level" makes sense now: the submenus (which have `PROCESS_MODE_ALWAYS`) handle ESC to go back one step. But once back at the main pause menu list, ESC can't resume the game because `PauseMenu` is paused itself.

### Additional Fix

Added to `pause_menu.gd`'s `_ready()`:

```gdscript
process_mode = Node.PROCESS_MODE_ALWAYS
```

This ensures `PauseMenu` continues to receive `_unhandled_input` while the game tree is paused, allowing ESC to resume the game from the main pause menu screen.

---

## Second Bug Report (2026-03-18, after regression fix)

After the regression fix (adding `process_mode = PROCESS_MODE_ALWAYS` to `PauseMenu`), Jhon-Crow reported the problem persisted:

> "проблема не исчезла - esc срабатывает только один раз" (the problem has not gone away — ESC fires only once)
>
> Log: `docs/case-studies/issue-1141/logs/game_log_20260318_080605.txt`

### Root Cause of Second Regression

**Hidden submenus were consuming ESC events without a `visible` guard.**

All submenus are instantiated once and reused (cached in `_settings_menu`, `_armory_menu`, `_levels_menu` etc. in `PauseMenu`). When a submenu is closed, it is only hidden (`.hide()` is called) — it remains a child node with `process_mode = PROCESS_MODE_ALWAYS`.

Since `_unhandled_input` fires for all nodes that process input, a **hidden** submenu with no `visible` check would intercept ESC, emit `back_pressed` (triggering its back handler in PauseMenu), and mark the input as handled — preventing `PauseMenu._unhandled_input` from ever seeing it.

**Example scenario:**
1. User opens PauseMenu → Settings → Sound, then presses ESC
2. SoundMenu handles ESC → emits `back_pressed` → hides SoundMenu, shows SettingsMenu list ✓
3. User presses ESC again on SettingsMenu list
4. The now-hidden SoundMenu fires `_unhandled_input`, its guard `if event.is_action_pressed("pause")` passes (no visibility check!), it emits `back_pressed` again → PauseMenu runs `_on_settings_back()` (hides SettingsMenu, shows main pause menu list) — but this was unintended! ✗
5. Or alternatively: SoundMenu consumes ESC, marks it handled → SettingsMenu and PauseMenu never see the event

**Affected files (missing `visible` guard):**
- `difficulty_menu.gd`
- `sound_menu.gd`
- `gameplay_menu.gd`
- `levels_menu.gd`
- `armory_menu.gd`
- `controls_menu.gd`
- `experimental_menu.gd`
- `settings_menu.gd` (had `menu_container.visible` but not the outer `visible` check)

### Fix

Added `visible and` guard to every submenu's `_unhandled_input` so hidden menus don't consume ESC:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
    if visible and event.is_action_pressed("pause"):
        _on_back_pressed()
        get_viewport().set_input_as_handled()
```

This ensures only the currently-visible topmost menu handles ESC. Hidden menus pass the event through to their parent.

---

## References

- Godot 4 Input handling: https://docs.godotengine.org/en/stable/tutorials/inputs/inputevent.html
- `set_input_as_handled()` prevents propagation: https://docs.godotengine.org/en/stable/classes/class_viewport.html#class-viewport-method-set-input-as-handled
- `_unhandled_input` vs `_input`: `_unhandled_input` is called only when no other node consumed the event. Since submenus render on top, their `_unhandled_input` will fire before `pause_menu`'s.
- Godot issue on CanvasLayer input ordering: CanvasLayer nodes receive input based on their layer value, but `_unhandled_input` propagation follows the scene tree order.
- Godot 4 `process_mode`: https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-property-process-mode — nodes with `PROCESS_MODE_INHERIT` stop when the tree is paused; use `PROCESS_MODE_ALWAYS` for UI that must work while the game is paused.
