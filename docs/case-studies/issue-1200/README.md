# Case Study: Issue #1200 — Settings Menu Hover & Tooltips

## Overview

**Issue:** [#1200](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1200)
**PR:** [#1201](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1201)
**Branch:** `issue-1200-dd57a8258094`
**Status:** In progress (iteration 3)

### Issue Summary

> "Add hover and tooltips to settings menu items. Including items in Experimental.
> (Currently rows are long, so without hover and tooltip with name it's hard to orient.)"
> — Jhon-Crow

---

## Timeline of Events

| Time (UTC) | Event |
|---|---|
| 2026-03-20 04:52 | Branch created, initial commit |
| 2026-03-20 04:58 | `feat(#1200)`: tooltips added to all menu rows |
| 2026-03-20 04:59 | Revert placeholder commit |
| 2026-03-20 05:01 | AI auto-restart triggered (CI failure: enemy.gd exceeded 5000-line limit) |
| 2026-03-20 05:06 | `fix`: compact enemy.gd to stay within CI limit |
| 2026-03-20 05:08 | Session 2 complete; PR marked ready |
| 2026-03-20 05:09 | Bot comments "ready to merge" |
| 2026-03-20 05:37 | **Owner feedback #1**: label must cover whole card including description; hover highlight missing |
| 2026-03-20 05:43 | `fix(#1200)`: shorten tooltip text; make rows act as labels (click forwarding added) |
| 2026-03-20 05:44 | Session 3 complete; PR marked ready again |
| 2026-03-20 05:46 | Bot comments "ready to merge" again |
| 2026-03-20 05:55 | **Owner feedback #2**: label still not covering whole card; hover highlight still missing; deep case study requested |
| 2026-03-20 05:56 | Session 4 (this session) begins |

---

## Root Cause Analysis

### Problem: Long setting rows without visual feedback

The settings menus (Difficulty, Sound, Gameplay, Optimization, Experimental) use `HBoxContainer` rows, each with a `Label` (setting name) and an interactive control (`CheckButton`, `Button`, `HSlider`, or `OptionButton`). The ExperimentalMenu additionally has a description `Label` as a sibling below each row.

**Root causes identified:**

1. **No hover visual feedback** — `HBoxContainer` has no built-in hover state. Godot's `Button` nodes get hover highlighting from theme styleboxes, but plain containers do not. The AI's first two implementations added only tooltips + click forwarding — neither session added visual hover highlighting.

2. **Description label not part of the interactive area** — The description `Label` nodes in ExperimentalMenu are siblings (not children) of the `HBoxContainer` in the `VBoxContainer`. Previous implementations only wrapped the `HBoxContainer`, leaving the description outside the clickable/hoverable area.

3. **Misunderstanding of "hover"** — The first two AI sessions interpreted "hover" as "tooltip on hover" only, missing the visual highlight (background brightening) that users expect, and that PauseMenu `Button` nodes already provide natively.

---

## Architecture Analysis

### PauseMenu (correct behavior — reference)

```
VBoxContainer
  ├── Button "Resume"      ← has neon theme → hover style built-in
  ├── Button "Armory"      ← hover style built-in
  ├── Button "Settings"    ← hover style built-in
  └── ...
```

Hover highlighting comes for free because `Button` has a `hover` state in the neon theme (`neon_button_theme.tres`).

### Settings Menus (problematic structure)

```
VBoxContainer
  ├── HBoxContainer "FOVContainer"       ← no built-in hover state
  │     ├── Label "Disable FOV Limitation"
  │     └── CheckButton "FOVCheckbox"
  ├── Label "FOVDescription"             ← sibling, not child — not part of row
  ├── HSeparator
  ├── HBoxContainer "ComplexGrenadeContainer"
  │     └── ...
```

Because `HBoxContainer` is not a `Button`, it has no hover state. The description `Label` is a sibling, not enclosed in the container.

---

## Solutions Attempted

### Attempt 1 (commit `fb37b822`)
- Added `tooltip_text` to containers and all child `Control` nodes
- **Missing**: no visual hover highlight; no click forwarding

### Attempt 2 (commit `2148f723`)
- Shortened tooltip text to just the setting name
- Added `mouse_filter = MOUSE_FILTER_STOP` + `gui_input` click forwarding
- **Missing**: still no visual hover highlight; description label not covered

### Attempt 3 (this session — pending commit)
- Added `mouse_entered`/`mouse_exited` signals → `_on_row_hovered()` which sets `self_modulate` to `Color(1.35, 1.35, 1.35)` on hover
- Pass description `Label` as optional 3rd parameter to `_setup_row_hover()`
- Description node gets same hover highlight, tooltip, and click forwarding

---

## Implementation Details

### `_setup_row_hover(container, tooltip, description=null)`

Each menu script now has this method:

```gdscript
const ROW_HOVER_MODULATE: Color = Color(1.35, 1.35, 1.35, 1.0)

func _setup_row_hover(container: Control, tooltip: String,
        description: Control = null) -> void:
    container.tooltip_text = tooltip
    container.mouse_filter = Control.MOUSE_FILTER_STOP
    for child in container.get_children():
        if child is Control:
            child.tooltip_text = tooltip
    container.mouse_entered.connect(_on_row_hovered.bind(container, description, true))
    container.mouse_exited.connect(_on_row_hovered.bind(container, description, false))
    container.gui_input.connect(_on_row_gui_input.bind(container))
    if description != null:
        description.tooltip_text = tooltip
        description.mouse_filter = Control.MOUSE_FILTER_STOP
        description.mouse_entered.connect(_on_row_hovered.bind(container, description, true))
        description.mouse_exited.connect(_on_row_hovered.bind(container, description, false))
        description.gui_input.connect(_on_row_gui_input.bind(container))

func _on_row_hovered(container: Control, description: Control, hovered: bool) -> void:
    var tint: Color = ROW_HOVER_MODULATE if hovered else Color.WHITE
    container.self_modulate = tint
    if description != null:
        description.self_modulate = tint
```

The `self_modulate` approach brightens both the container and description together when hovering over either, making the entire "card" (row header + description) feel like a unified interactive element.

### Files modified (iteration 3)

| File | Change |
|---|---|
| `scripts/ui/difficulty_menu.gd` | `_setup_row_hover` + `_on_row_hovered` updated |
| `scripts/ui/sound_menu.gd` | Same |
| `scripts/ui/gameplay_menu.gd` | Same |
| `scripts/ui/optimization_menu.gd` | Same |
| `scripts/ui/experimental_menu.gd` | Same + all 15 calls updated with description nodes |

---

## Key Lessons

1. **"Hover" in UI means visual feedback, not just tooltip.** When a user asks for hover behaviour matching existing UI (PauseMenu), always check what the reference implementation actually does (visual highlight, not just tooltip).

2. **Sibling nodes vs. child nodes matter.** Before assuming a container covers all visual elements of a "card", inspect the actual scene tree. Description labels in ExperimentalMenu are siblings, not children.

3. **Reuse existing patterns.** The `self_modulate` approach works on any `Control` node without requiring theme changes or new scene nodes. It produces a brightness boost matching the button hover effect from the neon theme.

4. **Iterate on feedback quickly.** Two rounds of owner feedback were needed to arrive at the correct behaviour. Root cause: both previous sessions misread "hover" as tooltip-only.

---

## References

- [Issue #1200](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1200)
- [PR #1201](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1201)
- Godot 4 docs — [Control.self_modulate](https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-property-self-modulate)
- Godot 4 docs — [Control.mouse_entered signal](https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-signal-mouse-entered)
- `resources/themes/neon_button_theme.tres` — defines `Button/colors/font_hover_color = Color(1.0, 0.95, 1.0, 1.0)`
- `scenes/ui/PauseMenu.tscn` — reference for correct hover behaviour via Button nodes
- `scenes/ui/ExperimentalMenu.tscn` — illustrates the sibling description label pattern
