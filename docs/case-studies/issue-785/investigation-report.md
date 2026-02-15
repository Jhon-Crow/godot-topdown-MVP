# Issue #785 Investigation Report

## Problem Statement
After clicking on the "Armory" button in the pause menu, the armory screen does not appear.

**Original Report** (from PR comment):
> После нажатия на пункт меню armory не появляется экран armory.
> (Translation: After clicking on the armory menu item, the armory screen does not appear.)

## Timeline of Events

### 2026-02-15 19:50 - Initial Implementation
- Commit `dfd66d12`: feat(armory): implement hold-to-unlock case opening system
- Implemented UnlockManager, hold-to-unlock mechanics, case opening animations
- Modified armory_menu.gd extensively with unlock functionality

### 2026-02-15 20:00 - Bug Report
- User (Jhon-Crow) reported that clicking "armory" menu item doesn't show the armory screen
- Requested to download logs and perform deep case study analysis

## Investigation Findings

### 1. Code Changes Analysis

**Files Modified in PR #790:**
- `scripts/ui/armory_menu.gd` - Extensive changes (+439 lines)
- `scripts/autoload/unlock_manager.gd` - New file (+250 lines)
- `scripts/autoload/audio_manager.gd` - Added unlock sound methods (+41 lines)
- `tests/unit/test_unlock_manager.gd` - New test file (+351 lines)
- `project.godot` - Registered UnlockManager autoload
- `docs/case-studies/issue-785/README.md` - Documentation

### 2. Bugs Identified

#### Bug #1: Locked Style Overwritten in _highlight_selected_items()
**Location**: `scripts/ui/armory_menu.gd:1080-1103`

**Description**:
The `_highlight_selected_items()` function resets ALL slots to default style, including locked ones. This overwrites the locked style that was applied during slot creation.

**Code flow**:
1. Slots created in `_create_item_slot()` with locked style applied (line 813)
2. `_highlight_selected_items()` called at end of `_build_ui()` (line 417)
3. All slots reset to default style (lines 1082-1091), losing locked appearance

**Impact**:
- Locked items lose their visual distinction
- May cause confusion about which items are locked
- **However, this should NOT prevent the menu from appearing**

**Fix Applied**:
Modified `_highlight_selected_items()` to preserve locked style for locked items and only highlight unlocked items as selected.

Commit: `574b2c98` - fix(armory): preserve locked style in _highlight_selected_items

### 3. UnlockManager Default State

**Default Unlocked Items**:
- Weapons: Only `["makarov_pm"]` (PM pistol)
- Grenades: Only `[0]` (Flashbang)
- Active Items: Only `[0]` (NONE - no item equipped)

This means **most items will be locked by default**, showing case icons instead of actual item icons.

### 4. Menu Visibility Analysis

**ArmoryMenu.tscn Structure**:
- CanvasLayer with layer=101, process_mode=2
- NO child nodes - all UI created programmatically in `_build_ui()`

**Pause Menu Integration** (`pause_menu.gd:194-230`):
- Extensive FileLogger debugging already present (suggests previous debugging attempts)
- Checks for script attachment, signals, and methods
- Pattern matches other menus (controls, difficulty) - no explicit `show()` call needed

**CanvasLayer Visibility**:
- CanvasLayers are visible by default when added to tree
- No explicit `hide()` call on ArmoryMenu
- Same pattern as other working menus (controls, difficulty, levels)

### 5. Potential Root Causes

Based on analysis, the menu not appearing could be caused by:

1. **Script Error During _ready()**: If `_build_ui()` throws an error, the menu would appear blank
   - Possible causes: texture loading failures, null references, UnlockManager not ready

2. **Empty/Blank UI**: Menu created but no visible content
   - All items might be locked and styled incorrectly (fixed with commit 574b2c98)
   - Progress bar or overlay might be blocking view

3. **Layer Ordering Issue**: According to Godot forum research:
   - Window class elements (popups, dialogs) render on layer 1024
   - Non-dynamic UI on layer 0 (or configured layer)
   - ArmoryMenu uses layer 101 - should be visible

4. **Process Mode Conflict**: ArmoryMenu has `process_mode = 2` (PROCESS_MODE_PAUSABLE)
   - Game is paused when pause menu opens
   - Might interfere with UI building

## Godot CanvasLayer Visibility Research

### Common Issues (from Godot Forums):
- Layer ordering problems with dynamic UI elements
- Control nodes directly under CanvasLayer can cause rendering issues
- Visibility property must be set correctly
- Process modes can interfere with UI display when game is paused

### Sources:
- [CanvasLayer does not display - Godot Forum](https://forum.godotengine.org/t/canvaslayer-does-not-display/52841)
- [UI canvas layer issue - Godot Forum](https://forum.godotengine.org/t/ui-canvas-layer-issue/38490)
- [CanvasLayer not showing correctly in game - Godot Forum](https://forum.godotengine.org/t/canvaslayer-not-showing-correctly-in-game/128500)
- [Visibility Issues With A CanvasLayer - Godot Forum](https://forum.godotengine.org/t/visibility-issues-with-a-canvaslayer/54390)
- [Godot 4: CanvasLayer missing show() & hide() · Issue #58122](https://github.com/godotengine/godot/issues/58122)

## Next Steps

### Immediate Actions:
1. ✅ Fixed locked style bug in `_highlight_selected_items()`
2. ⏳ Need actual error logs or reproduction steps to identify root cause
3. ⏳ Test locally with Godot to verify menu displays
4. ⏳ Add more error handling and logging if needed

### Questions for User:
1. Does the armory menu appear at all (blank screen) or nothing happens?
2. Are there any error messages in the Godot console?
3. Does the FileLogger output show the armory menu being created?
4. Do other menus (Controls, Difficulty, Levels) work correctly?

## Commits in This Session
1. `574b2c98` - fix(armory): preserve locked style in _highlight_selected_items
