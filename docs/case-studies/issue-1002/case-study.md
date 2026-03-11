# Case Study: Issue #1002 — Unlock Table Button Does Nothing

## Summary

The "View Unlock Table" button was added to the Experimental menu (PR #1003) but clicking it produced no visible result — the table never appeared.

---

## Timeline / Sequence of Events

1. **Issue #1002 filed** (2026-03-11): Owner requests an "unlock table" in the Experimental menu showing which items are unlocked on which map/rank.
2. **PR #1003 opened** (2026-03-11): AI implemented:
   - `UnlockTableMenu.tscn` — a `CanvasLayer` scene with a script that builds the table programmatically in `_ready()`.
   - `ExperimentalMenu.tscn` — instanced `UnlockTableMenu` as a child with `visible = false`.
   - `experimental_menu.gd` — connected the "Open" button to `_on_unlock_table_pressed()` which sets `unlock_table_menu.visible = true`.
3. **Owner tests the build** (2026-03-11 22:43): Reports "кнопка появилась, но при нажатии на неё таблица не появляется" (button appeared, but clicking it doesn't show the table). Attaches game log `game_log_20260311_224322.txt`.

---

## Evidence

- **Game log** (`game_log_20260311_224322.txt`): No errors or warnings related to the unlock table were found. `[UnlockManager] UnlockManager ready` confirms the autoload is available. The button press itself was not captured in the log.
- **Source code** (`scripts/ui/experimental_menu.gd` lines 222–226):
  ```gdscript
  func _on_unlock_table_pressed() -> void:
      if unlock_table_menu:
          unlock_table_menu.visible = true
  ```
- **Scene file** (`scenes/ui/ExperimentalMenu.tscn` line 366):
  ```
  [node name="UnlockTableMenu" parent="." instance=ExtResource("2_unlocktable")]
  visible = false
  ```

---

## Root Cause Analysis

### Bug: `CanvasLayer.visible = true` does not reliably show the layer

In Godot 4, `CanvasLayer` is **not** a `Control` node — it inherits from `Node` directly. While `CanvasLayer` does expose a `visible` property (added in Godot 4.0), using the **property assignment** syntax (`node.visible = true`) on a `CanvasLayer` can fail silently or behave inconsistently, because `CanvasLayer` overrides visibility differently than `Control` nodes.

The correct and idiomatic way to show/hide a `CanvasLayer` (and any Godot node) is to call the **methods** `show()` and `hide()`, which are defined on `Node` and properly propagate through the scene tree.

#### Evidence from the codebase

All other menus in `pause_menu.gd` consistently use `show()` and `hide()`:

```gdscript
# pause_menu.gd — consistent pattern throughout:
_experimental_menu.hide()
_controls_menu.hide()
menu_container.show()
show()
```

Only the new `_on_unlock_table_pressed()` code used `.visible = true` instead.

### Secondary Issue: Table not refreshed on reopen

`_build_ui()` is called once in `_ready()`. Unlock status can change while the game is running (e.g., completing a level while the pause menu is open). The issue owner stated the table "should always display current unlock conditions." The table must be rebuilt each time it is opened.

---

## Fix

Two changes in `scripts/ui/experimental_menu.gd`:

1. Replace `unlock_table_menu.visible = true` → `unlock_table_menu.show()`
2. Replace `unlock_table_menu.visible = false` → `unlock_table_menu.hide()`

One change in `scripts/ui/unlock_table_menu.gd`:

3. Add a `refresh()` method that clears and rebuilds the table, called from `experimental_menu.gd` each time the table is opened.

---

## Lessons Learned

- When hiding/showing `CanvasLayer` nodes in Godot 4, always use `show()` / `hide()` methods, not direct `.visible` property assignment.
- Programmatically-built UIs that display live game data should expose a `refresh()` method so callers can force a rebuild when needed.
- Code review should verify that new visibility patterns match the project's established conventions (all other menus use `show()`/`hide()`).
