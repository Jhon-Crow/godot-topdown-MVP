# Root Cause Analysis: Armory Menu Not Visible (Issue #785)

## Executive Summary

**Problem**: Armory screen doesn't display at all after clicking the "Armory" button.
**Root Cause**: Control node size is zero when added to CanvasLayer in _ready(), causing all child elements to have zero size.
**Solution**: Defer UI building to next frame OR ensure viewport size is available before building UI.

## Timeline of Events

### Initial State (Main Branch)
- ArmoryMenu scene is a CanvasLayer with process_mode=2 (PAUSABLE)
- Script sets process_mode=3 (ALWAYS) in _ready()
- UI is built programmatically in _build_ui()
- Root control uses `set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)`
- Panel uses `set_anchors_and_offsets_preset(Control.PRESET_CENTER)` followed by manual anchor settings

### Changes Made in PR#790
1. Changed scene file process_mode to 3 to match script (commit fac23341)
2. Removed `set_anchors_and_offsets_preset(Control.PRESET_CENTER)` from panel setup
3. Added manual grow_horizontal and grow_vertical settings to root control
4. Added extensive FileLogger.info() calls for debugging

### User Testing (2026-02-15 23:28:23)
- User clicks "Armory" button
- PauseMenu creates ArmoryMenu instance successfully
- ArmoryMenu._ready() is called
- ArmoryMenu._build_ui() is called
- **BUT**: No UI elements appear on screen
- Background and panel are not visible

## Evidence from Logs

### From game_log_20260215_232820.txt:

```
[23:28:23] [INFO] [PauseMenu] Armory button pressed
[23:28:23] [INFO] [PauseMenu] Creating new armory menu instance
[23:28:23] [INFO] [PauseMenu] armory_menu_scene resource path: res://scenes/ui/ArmoryMenu.tscn
[23:28:23] [INFO] [PauseMenu] Instance created, class: CanvasLayer, name: ArmoryMenu
[23:28:23] [INFO] [PauseMenu] Script attached: res://scripts/ui/armory_menu.gd
[23:28:23] [INFO] [PauseMenu] WARNING: back_pressed signal NOT found on instance!
[23:28:23] [INFO] [PauseMenu] back_pressed signal connected
[23:28:23] [INFO] [PauseMenu] Armory menu instance added as child, is_inside_tree: true
[23:28:23] [INFO] [PauseMenu] WARNING: _populate_weapon_grid method NOT found!
```

**Critical Observation**: The warnings about "back_pressed signal NOT found" and "_populate_weapon_grid method NOT found" suggest that the script hasn't fully initialized when these checks are made. However, the signal connection succeeds, which is contradictory.

**Missing Evidence**: There are NO log entries from ArmoryMenu._ready() or ArmoryMenu._build_ui() in the user's log file, despite these having extensive FileLogger.info() calls added. This suggests:
1. Either _ready() is not being called at all
2. OR FileLogger is not working as expected
3. OR the logs were captured before _ready() was called

## Code Analysis

### Current Branch Issues

#### Issue 1: Timing of _ready() Call
When a scene is instantiated and added as a child, _ready() is called. However, at this point:
- The CanvasLayer may not have a valid viewport size yet
- Control nodes rely on parent size for layout calculations
- PRESET_FULL_RECT requires knowing the viewport dimensions

#### Issue 2: Control Node Size Calculation
From the code (lines 294-302 in current branch):
```gdscript
var root_control := Control.new()
root_control.name = "MenuContainer"
root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
root_control.grow_horizontal = Control.GROW_DIRECTION_BOTH
root_control.grow_vertical = Control.GROW_DIRECTION_BOTH
add_child(root_control)
FileLogger.info("[ArmoryMenu._build_ui] Root control created and added, size: %s" % str(root_control.size))
```

**Expected**: root_control.size should be the viewport size (e.g., 1920x1080)
**Likely Actual**: root_control.size is Vector2(0, 0) because viewport isn't ready

#### Issue 3: Panel Positioning
The panel uses manual offset positioning centered on anchors 0.5, 0.5:
```gdscript
panel.anchor_left = 0.5
panel.anchor_top = 0.5
panel.anchor_right = 0.5
panel.anchor_bottom = 0.5
panel.offset_left = -500
panel.offset_top = -380
panel.offset_right = 500
panel.offset_bottom = 380
```

This requires the parent (root_control) to have a valid size, otherwise the center point is (0, 0).

### Comparison with Main Branch

Main branch uses:
```gdscript
panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
```

This preset might handle the case where parent size is not yet available better than manual anchor setting.

## Research Findings

### Godot 4 CanvasLayer + Control Node Issues

From web research on Godot 4 CanvasLayer visibility issues:

1. **Control nodes require valid parent dimensions**: Control nodes calculate their size based on parent dimensions. If parent has size (0,0), children will also be (0,0).

2. **CanvasLayer children timing issue**: When a Control node is added to a CanvasLayer in _ready(), the viewport size may not be available yet. ([Source](https://forum.godotengine.org/t/canvaslayer-causes-child-nodes-to-not-display/75605))

3. **PRESET_FULL_RECT doubling issue**: In some Godot 4 versions, using PRESET_FULL_RECT on CanvasLayer children can cause sizing issues. ([Source](https://godotforums.org/d/26260-problems-doing-layout-full-rect-to-control-node))

4. **First child detaching**: Known issue where first Control child of CanvasLayer may follow viewport instead of CanvasLayer. ([Source](https://github.com/godotengine/godot/issues/81514))

### Best Practices

1. **Defer UI building**: Build UI in next frame after _ready() to ensure viewport is ready
2. **Use call_deferred**: Call _build_ui with call_deferred("_build_ui")
3. **Check get_viewport_rect()**: Verify viewport size before building UI
4. **Use SubViewportContainer**: For complex UI, consider using SubViewportContainer

## Hypothesis

**Primary Hypothesis**: When _ready() is called immediately after instantiation, the CanvasLayer doesn't have access to a valid viewport rect yet. This causes:
1. root_control.size = Vector2(0, 0)
2. All children (background, panel) also have size (0, 0)
3. Nothing is visible on screen

**Supporting Evidence**:
- No visible elements despite successful instantiation
- Known Godot 4 issue with CanvasLayer + Control timing
- Missing _ready() logs suggest timing/initialization issue

**Alternative Hypothesis**: The FileLogger isn't writing to the user's log file at the time _ready() is called, so we don't see the diagnostic output. This would mean _ready() IS being called, but we can't see the logs to verify the size values.

## Proposed Solutions

### Solution 1: Defer UI Building (RECOMMENDED)
```gdscript
func _ready() -> void:
    # ... get autoload references ...

    # Defer UI building to next frame when viewport is ready
    call_deferred("_build_ui")

    # Set process mode after UI is built
    call_deferred("_set_process_mode")

func _set_process_mode() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
```

### Solution 2: Wait for Viewport Ready
```gdscript
func _ready() -> void:
    # ... get autoload references ...

    # Wait for viewport to be valid
    if not is_inside_tree():
        await tree_entered

    # Wait one more frame
    await get_tree().process_frame

    _build_ui()
    process_mode = Node.PROCESS_MODE_ALWAYS
```

### Solution 3: Restore PRESET_CENTER (Safest)
Revert the panel positioning code to use set_anchors_and_offsets_preset(Control.PRESET_CENTER) like the main branch, since this preset may handle edge cases better.

## Implementation Plan

1. Implement Solution 1 (defer _build_ui)
2. Add diagnostic logging to capture root_control.size
3. Test locally to verify UI appears
4. If Solution 1 doesn't work, try Solution 2
5. As last resort, revert to Solution 3

## Verification Steps

1. Check that root_control.size is non-zero after deferred build
2. Verify background ColorRect is visible
3. Verify panel is centered on screen
4. Verify all UI elements (buttons, labels, icons) are visible
5. Test unlock functionality still works

## References

- [Godot CanvasLayer Documentation](https://docs.godotengine.org/en/stable/classes/class_canvaslayer.html)
- [Godot Canvas Layers Tutorial](https://docs.godotengine.org/en/stable/tutorials/2d/canvas_layers.html)
- [GitHub Issue #81514: CanvasLayer not matching with first child control](https://github.com/godotengine/godot/issues/81514)
- [Godot Forum: CanvasLayer causes child nodes to not display](https://forum.godotengine.org/t/canvaslayer-causes-child-nodes-to-not-display/75605)
- [Godot Forums: Problems doing Layout > Full Rect to Control node](https://godotforums.org/d/26260-problems-doing-layout-full-rect-to-control-node)
