# Case Study: Issue #1751 — Combo counter not visible on Building and Labyrinth Complex maps

## Summary

After the initial fix for issue #1751 (widening the combo label to prevent text overflow), the repo owner reported that the combo counter no longer appears at all on two maps:
- **Здание** (Building)
- **Лабиринт Комплекс** (Labyrinth Complex / Labyrinth2)

Log file: [`game_log_20260410_030727.txt`](./game_log_20260410_030727.txt)

---

## Timeline / Sequence of Events

1. **Original bug (issue #1751)**: Combo counter text was clipped/truncated on the right side of the screen because `offset_left = -200` gave only 190px of width — not enough for text like "x3 COMBO (+300)" at font size 28.

2. **Initial fix (PR #1787, commit `8d99616f`)**: Widened `offset_left` from `-200`/`-220` to `-350` in all 15 level scripts, giving ~340px of width.

3. **New regression reported**: Combo counter doesn't appear at all on Building and Labyrinth Complex maps.

---

## Root Cause Analysis

### Root Cause 1: BuildingLevel — GDScript `_ready()` never executes

Key log line:
```
[LevelInitFallback] GDScript _ready() did NOT execute - performing C# fallback initialization
```

`building_level.gd` `_ready()` never runs. Instead, `LevelInitFallback.cs` (a C# component) handles all level initialization as a fallback. The problem: `LevelInitFallback.cs`'s `SetupDebugUI()` creates `DifficultyLabel` and `MagazinesLabel` but **does NOT**:
- Create a `ComboLabel` node
- Connect to the `ScoreManager`'s `combo_changed` signal

Without a combo label or signal connection, no combo counter ever appears.

**File**: `Scripts/Components/LevelInitFallback.cs`, method `SetupDebugUI()` (~line 538) and `InitializeScoreManager()` (~line 519)

### Root Cause 2: Labyrinth2Level — ComboLabel node doesn't exist in scene tree

`labyrinth2_level.gd` at line 663 tries to find the combo label in the scene tree:
```gdscript
_combo_label = get_node_or_null("CanvasLayer/UI/ComboLabel")
```

But there is **no `ComboLabel` node** in `scenes/levels/Labyrinth2Level.tscn`. Unlike other level scripts that dynamically create the combo label via `Label.new()` and `ui.add_child(_combo_label)`, `labyrinth2_level.gd` expects the node to already exist in the scene — and it doesn't.

**File**: `scripts/levels/labyrinth2_level.gd`, line 663  
**Scene**: `scenes/levels/Labyrinth2Level.tscn`

---

## Why Only These Two Maps?

- All other 13 levels (with GDScript `_ready()` that works) dynamically create the combo label via `Label.new()` + `ui.add_child()`.
- `BuildingLevel` is special: it has a GDScript but its `_ready()` doesn't execute (engine/scene configuration issue), falling back to C# code that doesn't know about the combo label.
- `Labyrinth2Level` is special: it tries to find the combo label in the scene tree rather than creating it dynamically, and the node was never added to the `.tscn` file.

---

## Fix

### Fix 1: `LevelInitFallback.cs`
In `SetupDebugUI()`, add creation of `ComboLabel` (same as in GDScript levels: `offset_left = -350`, `offset_right = -10`, `offset_top = 80`, `offset_bottom = 120`, font size 28, gold color, `visible = false`).

In `InitializeScoreManager()`, connect to `combo_changed` signal and handle it with a method that updates the combo label.

### Fix 2: `labyrinth2_level.gd`
Change the combo label initialization from:
```gdscript
_combo_label = get_node_or_null("CanvasLayer/UI/ComboLabel")
```
To dynamically create and add the label (same pattern as other levels):
```gdscript
_combo_label = Label.new()
_combo_label.name = "ComboLabel"
# ... configure properties ...
ui.add_child(_combo_label)
```

---

## Additional Context

The `LevelInitFallback.cs` fallback is triggered when the level's GDScript `_ready()` doesn't execute. This can happen due to script compilation issues or scene configuration. The fallback is designed to handle core level setup, but was not updated to include the combo label feature when it was added in the previous PR.

The `labyrinth2_level.gd` diverges in pattern from other level scripts — most create UI elements dynamically, but this one mixes scene-tree lookup for some elements and dynamic creation for others. The combo label was added to the script but its corresponding scene node was never added to the `.tscn` file.
