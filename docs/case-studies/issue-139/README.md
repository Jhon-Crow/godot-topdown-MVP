# Case Study: Issue #139 - Tutorial Level Implementation

## Overview

**Issue:** [#139 - добавь обучение на Test tier (C#)](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/139)
**Pull Request:** [#142](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/142)
**Date Created:** 2026-01-20
**Status:** In Progress (Follow-up after initial solution draft)

## Timeline of Events

### Phase 1: Initial Issue Creation (2026-01-20T18:17:02Z)

User @Jhon-Crow created issue #139 with the following requirements:

1. Rename "Test tier (C#)" to "Обучение" (Training/Tutorial)
2. Remove control hints from the screen (they shouldn't be visible on any level)
3. Tutorial flow:
   - Player approaches targets
   - Player shoots targets
   - Player reloads
   - Completion message appears with Q restart hint
4. Key prompts should float near the player until the action is completed

### Phase 2: Initial AI Solution Draft (2026-01-20T18:32:48Z)

The AI solver (Claude) created an initial solution draft that:

- Created `tutorial_level.gd` script with tutorial state machine
- Renamed the level menu entry
- Added floating prompts that follow the player
- Added target hit detection
- Added completion message

**Cost:**
- Public pricing estimate: $4.148673 USD
- Calculated by Anthropic: $2.490313 USD (40% lower)

### Phase 3: User Feedback (2026-01-20T18:38:09Z)

User @Jhon-Crow tested the compiled exe and reported the following issues:

1. **"на других уровнях не должно быть подсказок управления"** (Control hints shouldn't be on other levels)
   - TestTier.tscn and BuildingLevel.tscn still had InstructionsLabel showing WASD controls

2. **"на учебном уровне должно быть отображение кол-ва патронов"** (Tutorial level should show ammo count)
   - The tutorial level was missing the AmmoLabel UI element

3. **"prompt на учебной карте не появляется"** (Prompt on tutorial map doesn't appear)
   - The floating tutorial prompts weren't visible in the compiled executable

4. **"я использую собранные exe"** (I'm using compiled exe)
   - This indicated the issue was specific to exported/compiled builds, not the editor

## Root Cause Analysis

### Issue 1: Control Hints on Other Levels

**Root Cause:** The initial implementation focused only on the tutorial level, leaving the InstructionsLabel nodes in:
- `scenes/levels/TestTier.tscn` (lines 1344-1352)
- `scenes/levels/BuildingLevel.tscn` (lines 938-946)

Additionally, the GDScript files `test_tier.gd` and `building_level.gd` contained code that updated these labels:
```gdscript
var instructions_label := get_node_or_null("CanvasLayer/UI/InstructionsLabel")
if instructions_label:
    instructions_label.text = "WASD - Move | LMB - Shoot..."
```

**Fix Applied:**
1. Removed InstructionsLabel nodes from both scene files
2. Removed the label update code from both GDScript files

### Issue 2: Missing Ammo Count on Tutorial Level

**Root Cause:** The tutorial level scene (`scenes/levels/csharp/TestTier.tscn`) was created without copying the AmmoLabel from the main TestTier scene. The tutorial_level.gd script also lacked the ammo tracking functionality present in test_tier.gd.

**Fix Applied:**
1. Added AmmoLabel node to `scenes/levels/csharp/TestTier.tscn`
2. Added ammo tracking variables and functions to `tutorial_level.gd`:
   - `_ammo_label` reference
   - `_setup_ammo_tracking()` function
   - `_on_weapon_ammo_changed()` callback
   - `_on_player_ammo_changed()` callback
   - `_update_ammo_label()` and `_update_ammo_label_magazine()` functions

### Issue 3: Tutorial Prompts Not Appearing in Compiled Exe

**Root Cause:** The original `_update_prompt_position()` function used an unreliable method to calculate screen position:

```gdscript
# Original problematic code
var camera := get_viewport().get_camera_2d()
if camera:
    var screen_pos := _player.global_position - camera.global_position + get_viewport().size / 2.0
    _prompt_label.position = screen_pos + Vector2(-_prompt_label.size.x / 2, -80)
```

This approach had several problems in exported builds:
1. `get_viewport().size` returns the actual window size, which may differ from the designed resolution
2. The camera position calculation assumes a specific viewport setup
3. `_prompt_label.size.x` might be zero before the label is properly sized

**Fix Applied:**
```gdscript
# Fixed code using canvas transform
var canvas_transform: Transform2D = get_viewport().get_canvas_transform()
var screen_pos: Vector2 = canvas_transform * _player.global_position
_prompt_label.custom_minimum_size = Vector2(300, 30)
_prompt_label.position = screen_pos + Vector2(-150, -80)
```

The canvas transform method works correctly because:
1. It accounts for camera position, zoom, and any other canvas transformations
2. It works consistently in both editor and exported builds
3. Using `custom_minimum_size` ensures the label has a known width for centering

## Technical Insights

### Godot Engine: Editor vs Export Differences

When testing Godot games, there are significant differences between running in the editor and running exported builds:

1. **Viewport Size:** The editor window size is dynamic, while exports can have fixed resolution settings
2. **Camera Transform:** The editor preview may apply different camera settings
3. **Debug Output:** `print()` statements don't show in exported builds by default
4. **Resource Loading:** Some resource paths may resolve differently

### Best Practices for Godot UI Positioning

For UI elements that need to follow world objects:

1. **Use Canvas Transform:** `get_viewport().get_canvas_transform() * world_position` reliably converts world to screen coordinates
2. **Set Minimum Sizes:** Always set `custom_minimum_size` for dynamically created labels to ensure consistent sizing
3. **Add Error Logging:** Use `push_error()` instead of `print()` for important warnings that should appear in export logs

### C# vs GDScript Signal Compatibility

The tutorial level needed to support both C# (PascalCase signals) and GDScript (snake_case signals):

```gdscript
# C# signals
if _player.has_signal("ReloadCompleted"):
    _player.ReloadCompleted.connect(_on_player_reload_completed)
# GDScript signals
elif _player.has_signal("reload_completed"):
    _player.reload_completed.connect(_on_player_reload_completed)
```

## Files Modified in Fix

1. `scenes/levels/TestTier.tscn` - Removed InstructionsLabel node
2. `scenes/levels/BuildingLevel.tscn` - Removed InstructionsLabel node
3. `scripts/levels/test_tier.gd` - Removed InstructionsLabel update code
4. `scripts/levels/building_level.gd` - Removed InstructionsLabel update code
5. `scenes/levels/csharp/TestTier.tscn` - Added AmmoLabel node
6. `scripts/levels/tutorial_level.gd` - Added ammo tracking and fixed prompt positioning

### Phase 4: Additional User Feedback (2026-01-20T18:49:45Z)

User @Jhon-Crow provided additional feedback after testing:

1. **"перезарядка не r, а последовательность r -> f -> r"** (Reload is not R, but sequence R -> F -> R)
   - The game uses a complex 3-step reload sequence for realism
   - Step 1: Press R to eject magazine
   - Step 2: Press F to insert new magazine
   - Step 3: Press R to chamber a round (complete reload)

2. **"добавь пункт обучения только если у игрока в руках штурмовая винтовка - нажать b чтобы переключить режим стрельбы"** (Add tutorial step only if player has assault rifle - press B to switch fire mode)
   - The assault rifle supports Automatic and Burst fire modes
   - This step should come BEFORE the reload step
   - Should only appear if player has an assault rifle

## Root Cause Analysis - Phase 4

### Issue 4: Incorrect Reload Sequence in Tutorial

**Root Cause:** The initial implementation assumed simple reload with just "R" key, but the C# Player.cs code shows a complex 3-step reload sequence (`HandleReloadSequenceInput()` method):

```csharp
// From Player.cs
/// Step 0: Press R to start sequence (eject magazine)
/// Step 1: Press F to continue (insert new magazine)
/// Step 2: Press R to complete reload instantly (chamber round)
private void HandleReloadSequenceInput()
```

**Fix Applied:**
Changed the reload prompt from `[R] Перезарядись` to `[R] [F] [R] Перезарядись` to accurately reflect the game's reload mechanics.

### Issue 5: Missing Fire Mode Switch Tutorial

**Root Cause:** The AssaultRifle.cs supports fire mode toggling via B key (bound to `toggle_fire_mode` action), with `FireModeChanged` signal emitted on toggle. This feature was not covered in the tutorial.

```csharp
// From AssaultRifle.cs
public void ToggleFireMode()
{
    CurrentFireMode = CurrentFireMode == FireMode.Automatic ? FireMode.Burst : FireMode.Automatic;
    EmitSignal(SignalName.FireModeChanged, (int)CurrentFireMode);
}
```

**Fix Applied:**
1. Added `SWITCH_FIRE_MODE` step to the tutorial state machine (between `SHOOT_TARGETS` and `RELOAD`)
2. Added detection for whether player has assault rifle (`_has_assault_rifle` flag)
3. Connected to `FireModeChanged` signal from weapon to detect when player switches modes
4. Added prompt `[B] Переключи режим стрельбы` for the fire mode step
5. If player doesn't have assault rifle, the step is skipped automatically

## Files Modified in Phase 4 Fix

1. `scripts/levels/tutorial_level.gd`:
   - Added `SWITCH_FIRE_MODE` enum value
   - Added `_has_switched_fire_mode`, `_has_assault_rifle`, `_assault_rifle` variables
   - Added connection to `FireModeChanged` signal
   - Added `_on_fire_mode_changed()` callback
   - Updated tutorial flow to include fire mode step before reload (only for assault rifle)
   - Fixed reload prompt to show `[R] [F] [R]` sequence

## Lessons Learned

1. **Test in Export Builds:** Always test gameplay features in exported builds, not just the editor
2. **Complete Feature Implementation:** When adding a new level, ensure all UI elements from reference levels are included
3. **Use Robust Positioning:** For UI that follows world objects, use canvas transforms instead of manual calculations
4. **Check All Affected Files:** When removing a feature, search all files to ensure no references remain
5. **Understand Game Mechanics Fully:** Read the source code carefully to understand complex mechanics like multi-step reload sequences
6. **Document All Player Actions:** For tutorials, ensure all unique weapon/player actions are covered (fire modes, reload sequences)
7. **Conditional Tutorial Steps:** Some tutorial steps should only appear based on player equipment (e.g., fire mode switch for assault rifle only)

## Related Files

- [solution-draft-log.txt](./solution-draft-log.txt) - Complete AI execution trace
- [issue-data.json](./issue-data.json) - Original issue data
- [pr-data.json](./pr-data.json) - Pull request metadata
- [pr-comments.json](./pr-comments.json) - PR discussion comments
