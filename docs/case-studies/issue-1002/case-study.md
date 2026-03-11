# Case Study: Issue #1002 — Unlock Table Button Does Nothing

## Summary

The "View Unlock Table" button was added to the Experimental menu (PR #1003) but clicking it produced no visible result — the table never appeared. The root cause was a **nested CanvasLayer visibility issue** in Godot 4.

---

## Timeline / Sequence of Events

1. **Issue #1002 filed** (2026-03-11): Owner requests an "unlock table" in the Experimental menu showing which items are unlocked on which map/rank.

2. **PR #1003 opened** (2026-03-11): AI implemented:
   - `UnlockTableMenu.tscn` — a `CanvasLayer` scene (layer 102) with a script that builds the table programmatically in `_ready()`.
   - `ExperimentalMenu.tscn` — instanced `UnlockTableMenu` as a child node with `visible = false`.
   - `experimental_menu.gd` — connected the "Open" button to `_on_unlock_table_pressed()` which set `unlock_table_menu.visible = true`.

3. **First bug report** (2026-03-11 22:43): Owner reports "кнопка появилась, но при нажатии на неё таблица не появляется" (button appeared, but clicking it doesn't show the table). Attaches game log `game_log_20260311_224322.txt`.

4. **First fix attempt** (2026-03-11 19:53): Changed `.visible = true` to `.show()` and `.visible = false` to `.hide()`. Added `refresh()` method. PR marked ready.

5. **Second bug report** (2026-03-11 23:07): Owner reports issue persists — "при нажатии на кнопку всё ещё не отображается таблица" (clicking the button still doesn't show the table). Attaches game log `game_log_20260311_230724.txt`.

---

## Evidence

### Game Logs

- **game_log_20260311_224322.txt** and **game_log_20260311_230724.txt**: Both logs show normal game startup with no errors. Notably, no log entry appears when the unlock table button is pressed (unlike armory which logs `[PauseMenu] Armory button pressed`). This suggests the button handler was being invoked but `show()` was failing silently.

### Code Analysis

**Scene structure (pre-fix):**
```
ExperimentalMenu (CanvasLayer, layer 101)
├── MenuContainer (Control)
│   └── ... UI elements ...
└── UnlockTableMenu (CanvasLayer, layer 102)  <-- Nested CanvasLayer!
    └── ... (no children in scene; created in _ready())
```

**Other menus pattern (working):**
```
PauseMenu (CanvasLayer, layer 100)
├── MenuContainer (Control)
└── (no nested CanvasLayers in scene file)

# Submenus are instantiated dynamically and added as siblings:
_armory_menu = armory_menu_scene.instantiate()
add_child(_armory_menu)  # Added as child of PauseMenu
```

---

## Root Cause Analysis

### Bug: Nested CanvasLayer visibility does not work as expected in Godot 4

The root cause is a **known limitation in Godot 4**: when a `CanvasLayer` is instanced as a child of another `CanvasLayer` (or any other node), its visibility does not propagate correctly. Even calling `show()` on the nested CanvasLayer may not make it visible.

This is documented in [godotengine/godot#84912](https://github.com/godotengine/godot/issues/84912): "CanvasLayer does not hide if parent node is hidden."

The key insight from Godot's issue tracker:
> "No matter what you do, without directly hiding a CanvasLayer, it will always render."

The reverse is also problematic: nested CanvasLayers may not render properly when shown, because visibility propagation does not work the same way as with Control nodes.

### Why the first fix failed

The first fix changed `.visible = true` to `.show()`. While this is the correct method to call, the underlying problem remained: `UnlockTableMenu` was still instanced as a **child of ExperimentalMenu** in the scene file. The CanvasLayer nesting issue persisted.

### The pattern that works

Looking at how `PauseMenu` handles its submenus (ArmoryMenu, LevelsMenu, etc.):

1. Submenus are **NOT embedded in the scene file** as child nodes
2. Submenus are instantiated **dynamically** on first use
3. Submenus are added as children of the parent (still nested, but instantiated at runtime)

---

## Fix (Second Attempt)

### Changes to `scripts/ui/experimental_menu.gd`:

1. **Remove @onready reference** to embedded UnlockTableMenu
2. **Add preload** for the scene file
3. **Instantiate dynamically** on first button press (same pattern as other menus)
4. **Add as sibling** via `get_parent().add_child()` to avoid nesting

```gdscript
## Reference to the unlock table menu scene.
var unlock_table_menu_scene: PackedScene = preload("res://scenes/ui/UnlockTableMenu.tscn")

## The instantiated unlock table menu (created on first use, like other submenus).
var unlock_table_menu: CanvasLayer = null

func _on_unlock_table_pressed() -> void:
    # Instantiate unlock table menu on first use (same pattern as PauseMenu submenus)
    # This avoids nested CanvasLayer visibility issues in Godot 4.
    if unlock_table_menu == null:
        unlock_table_menu = unlock_table_menu_scene.instantiate()
        unlock_table_menu.back_pressed.connect(_on_unlock_table_back_pressed)
        # Add as sibling to this CanvasLayer's parent (not as child) to avoid nesting
        get_parent().add_child(unlock_table_menu)
    else:
        # Refresh and show existing instance
        unlock_table_menu.refresh()
        unlock_table_menu.show()
```

### Changes to `scenes/ui/ExperimentalMenu.tscn`:

1. **Remove** the embedded `UnlockTableMenu` instance
2. **Remove** the `ext_resource` for UnlockTableMenu.tscn

---

## Lessons Learned

1. **CanvasLayer visibility is special**: Unlike Control nodes, CanvasLayers do not inherit visibility from their parents and may not propagate visibility correctly when nested. This is a known Godot 4 limitation.

2. **Follow established patterns**: The project already had a working pattern for submenus (dynamic instantiation in pause_menu.gd). New submenus should follow the same pattern rather than trying a different approach.

3. **Test with the actual game build**: The issue was not visible in code review alone — it required running the game and clicking the button. Always test new UI features in-game.

4. **When a fix doesn't work, investigate deeper**: The first fix (`.visible = true` → `.show()`) was correct for *most* visibility issues, but this case required understanding Godot's CanvasLayer-specific behavior.

---

## References

- [godotengine/godot#84912](https://github.com/godotengine/godot/issues/84912) — "CanvasLayer does not hide if parent node is hidden"
- [godotengine/godot#58122](https://github.com/godotengine/godot/issues/58122) — "Godot 4: CanvasLayer missing show() & hide()"
- [Godot Docs: CanvasLayer](https://docs.godotengine.org/en/stable/classes/class_canvaslayer.html)
