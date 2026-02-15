# Issue #785 Investigation Report

## Problem Statement
After clicking on the "Armory" button in the pause menu, the armory screen does not appear.

**Original Report** (from PR comment):
> После нажатия на пункт меню armory не появляется экран armory.
> (Translation: After clicking on the armory menu item, the armory screen does not appear.)

**Update (2026-02-15 20:13)**: User confirmed issue persists after initial fixes:
> проблема сохранилась - на экране armory ничего нет (виден только полупрозрачный фон)
> (Translation: The problem persists - there's nothing on the armory screen (only a semi-transparent background is visible))

## Timeline of Events

### 2026-02-15 19:50 - Initial Implementation
- Commit `dfd66d12`: feat(armory): implement hold-to-unlock case opening system
- Implemented UnlockManager, hold-to-unlock mechanics, case opening animations
- Modified armory_menu.gd extensively with unlock functionality

### 2026-02-15 20:00 - First Bug Report
- User (Jhon-Crow) reported that clicking "armory" menu item doesn't show the armory screen
- Requested to download logs and perform deep case study analysis

### 2026-02-15 20:07 - Initial Bug Fixes
- Commit `574b2c98`: fix(armory): preserve locked style in _highlight_selected_items
- Commit `fac23341`: fix(armory): set correct process_mode in ArmoryMenu scene

### 2026-02-15 20:13 - Issue Persists
- User reported issue still present: "only semi-transparent background visible"
- User provided log files for analysis

### 2026-02-15 20:20 - Log Analysis
- Downloaded and analyzed game_log_20260215_231232.txt and game_log_20260215_231333.txt
- Found critical warnings in logs indicating script method detection issues

## Log Analysis Findings

### Key Log Entries (from game_log_20260215_231232.txt, lines 190-198):
```
[23:12:37] [INFO] [PauseMenu] Armory button pressed
[23:12:37] [INFO] [PauseMenu] Creating new armory menu instance
[23:12:37] [INFO] [PauseMenu] armory_menu_scene resource path: res://scenes/ui/ArmoryMenu.tscn
[23:12:37] [INFO] [PauseMenu] Instance created, class: CanvasLayer, name: ArmoryMenu
[23:12:37] [INFO] [PauseMenu] Script attached: res://scripts/ui/armory_menu.gd
[23:12:37] [INFO] [PauseMenu] WARNING: back_pressed signal NOT found on instance!
[23:12:37] [INFO] [PauseMenu] back_pressed signal connected
[23:12:37] [INFO] [PauseMenu] Armory menu instance added as child, is_inside_tree: true
[23:12:37] [INFO] [PauseMenu] WARNING: _populate_weapon_grid method NOT found!
```

### Critical Observations:

1. **Script IS attached** - confirmed by log: "Script attached: res://scripts/ui/armory_menu.gd"

2. **`has_signal("back_pressed")` returns FALSE** - but signal IS declared in script (line 10: `signal back_pressed`)

3. **Signal connection SUCCEEDS** - despite `has_signal` returning false, `back_pressed.connect()` worked

4. **`has_method("_populate_weapon_grid")` returns FALSE** - but method IS defined in script (line 1246)

5. **NO [ArmoryMenu] logs appear** - despite armory_menu.gd having FileLogger calls in `_ready()`

### Interpretation:

The script appears to be partially loaded or not executing properly. This pattern suggests:
- The scene loads with the script file path reference
- But the script's content (signals, methods, _ready function) is NOT being recognized
- This could indicate a GDScript compilation/parsing error in the exported build

### Comparison with Working Menus:

| Menu | Scene Structure | UI Creation |
|------|----------------|-------------|
| ControlsMenu | Child nodes in .tscn | Hybrid (scene + code) |
| DifficultyMenu | Child nodes in .tscn | Hybrid (scene + code) |
| LevelsMenu | Child nodes in .tscn | Hybrid (scene + code) |
| **ArmoryMenu** | **NO child nodes** | **100% programmatic** |

The ArmoryMenu is the ONLY menu that creates its entire UI programmatically in `_build_ui()`. If the script doesn't execute properly, no UI appears.

### What User Sees:

The "semi-transparent background" the user sees is likely the **PauseMenu's ColorRect** (layer 100, Color(0, 0, 0, 0.5)), NOT the ArmoryMenu's background. The PauseMenu's ColorRect is a direct child of the CanvasLayer and is NOT hidden when `menu_container.hide()` is called.

## Research: Known Godot 4 Issues

### GDScript Export Mode (Godot Issue #94150)
- Godot 4.3 GDScript export mode can break exported builds with some addons
- Binary tokens or compressed binary tokens mode may cause resource loading failures
- Project uses `script_export_mode=0` (Text mode) - should be safe

### has_signal / has_method Issues
- Multiple reports of `has_signal()` returning false for declared signals
- `has_method()` may not work reliably with certain script types
- Signals can sometimes connect even when `has_signal()` returns false

### Programmatic UI Control Layout Issues
- Controls created programmatically default to `LAYOUT_MODE_POSITION`
- Anchors don't work properly unless `layout_mode` is set to `LAYOUT_MODE_ANCHORS`
- `set_anchors_and_offsets_preset()` doesn't automatically change layout_mode

**Sources:**
- [Godot 4.3 GDScript export mode breaks exported builds](https://github.com/godotengine/godot/issues/94150)
- [has_method does not work on class](https://github.com/godotengine/godot/issues/22838)
- [Layout Mode in Control not updating](https://github.com/godotengine/godot/issues/85185)
- [set_anchor methods don't work](https://github.com/godotengine/godot/issues/86004)

## Bugs Identified and Fixed

### Bug #1: Locked Style Overwritten (Fixed)
**Location**: `scripts/ui/armory_menu.gd:1080-1103`
**Fix**: Commit `574b2c98` - preserve locked style for locked items

### Bug #2: Process Mode Mismatch (Fixed)
**Location**: `scenes/ui/ArmoryMenu.tscn`
**Fix**: Commit `fac23341` - changed scene to `process_mode = 3` to match script

### Bug #3: Missing Diagnostic Logging (Added)
**Location**: `scripts/ui/armory_menu.gd`
**Fix**: Commit `ece21718` - added extensive FileLogger calls to trace execution

## Current Hypothesis

The armory_menu.gd script is NOT executing properly in the exported Windows build. Possible causes:

1. **Script Compilation Error**: The script may have a syntax or semantic error that only manifests in the exported build
2. **Resource Loading Issue**: Some resource the script depends on may not be available
3. **Godot Export Bug**: Known issues with GDScript in exported builds
4. **Cache/Metadata Issue**: The .godot directory or export cache may be stale

## Diagnostic Logging Added

Commit `ece21718` adds extensive logging to armory_menu.gd:
- `[ArmoryMenu] _ready() called`
- `[ArmoryMenu] GrenadeManager: found/NOT found`
- `[ArmoryMenu] ActiveItemManager: found/NOT found`
- `[ArmoryMenu] UnlockManager: found/NOT found`
- `[ArmoryMenu] Weapon resources loaded: N`
- `[ArmoryMenu] Pending selections: weapon=X, grenade=Y, item=Z`
- `[ArmoryMenu] Calling _build_ui()...`
- `[ArmoryMenu._build_ui] Starting UI build...`
- `[ArmoryMenu._build_ui] Root control created and added, size: (X, Y)`
- `[ArmoryMenu._build_ui] Background created`
- `[ArmoryMenu._build_ui] Panel anchors set: offsets=(...)`
- `[ArmoryMenu._build_ui] Panel created and added to root_control`
- `[ArmoryMenu._build_ui] Content HBox created`
- `[ArmoryMenu._build_ui] Building sidebar...`
- `[ArmoryMenu._build_ui] Sidebar built and added`
- `[ArmoryMenu._build_ui] Building right area (weapon/grenade grids)...`
- `[ArmoryMenu._build_ui] Right area built and added`
- `[ArmoryMenu._build_ui] UI build completed successfully`
- `[ArmoryMenu] _build_ui() completed`
- `[ArmoryMenu] _ready() completed`

## Next Steps

1. **User Test**: User should re-export and test with commit `ece21718`
2. **Log Analysis**: Analyze new logs to see where execution stops
3. **If No [ArmoryMenu] Logs**: Confirms script not executing - investigate GDScript compilation
4. **If Partial Logs**: Identifies exact point of failure
5. **Alternative Fix**: Consider converting ArmoryMenu to use scene-defined UI like other menus

## Commits in This Session
1. `574b2c98` - fix(armory): preserve locked style in _highlight_selected_items
2. `fac23341` - fix(armory): set correct process_mode in ArmoryMenu scene
3. `ece21718` - debug(armory): add diagnostic logging and save user-provided logs

## Files
- User logs saved to: `docs/case-studies/issue-785/logs/`
  - `game_log_20260215_231232.txt`
  - `game_log_20260215_231333.txt`
