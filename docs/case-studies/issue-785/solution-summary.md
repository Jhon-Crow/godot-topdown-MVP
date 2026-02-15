# Solution Summary: Armory Menu Not Visible (Issue #785)

## Problem

User reported that the armory screen doesn't display at all after clicking the "Armory" button - no background, no sections, nothing appears.

## Root Cause

When the ArmoryMenu is instantiated and _ready() is called, the UI is built immediately using programmatically created Control nodes. However, at this point in the Godot lifecycle:

1. **The CanvasLayer doesn't have a valid viewport rect yet**
2. **Control nodes calculate their size based on parent dimensions**
3. **If parent has size (0, 0), all children will also be (0, 0)**
4. **Result: All UI elements are created but have zero size, making them invisible**

### Evidence

From user's log file (`game_log_20260215_232820.txt`):
- Line 169-177: ArmoryMenu is successfully instantiated and added to scene tree
- **Missing**: No logs from ArmoryMenu._ready() or ArmoryMenu._build_ui()
  - This is because the user was testing a version BEFORE diagnostic logging was added (commit ece21718)
  - User's test: 2026-02-15 23:28:20
  - Diagnostic logging commit: 2026-02-15 21:22:11 (but user tested with commit fac23341 from 21:06:22)

### Technical Analysis

In Godot 4, when a CanvasLayer is instantiated and added as a child:
1. The `instantiate()` call creates the node
2. `add_child()` adds it to the tree and triggers `_ready()`
3. **At _ready() time, the CanvasLayer may not have access to viewport dimensions yet**
4. Control nodes using `PRESET_FULL_RECT` require knowing viewport size
5. Building UI immediately in _ready() causes size calculation to fail

### Research Findings

From Godot community forums and GitHub issues:
- [CanvasLayer causes child nodes to not display](https://forum.godotengine.org/t/canvaslayer-causes-child-nodes-to-not-display/75605)
- [CanvasLayer not matching with first child control](https://github.com/godotengine/godot/issues/81514)
- [Problems doing Layout > Full Rect to Control node](https://godotforums.org/d/26260-problems-doing-layout-full-rect-to-control-node)

## Solution

**Defer UI building to the next frame** using `call_deferred()`. This ensures the viewport is fully initialized before Control nodes calculate their sizes.

### Implementation

```gdscript
func _ready() -> void:
    # ... initialize references and data ...

    # Defer UI building to next frame (Issue #785 fix)
    call_deferred("_build_ui_deferred")

    # Set process mode
    process_mode = Node.PROCESS_MODE_ALWAYS

func _build_ui_deferred() -> void:
    # Viewport is now ready, build UI
    _build_ui()
```

### Why This Works

1. **Timing**: By deferring to next frame, we ensure viewport is fully initialized
2. **Size calculation**: Control nodes can now properly query viewport size
3. **Anchoring**: PRESET_FULL_RECT can correctly fill the available space
4. **Rendering**: All elements have valid sizes and render correctly

## Changes Made

### File: scripts/ui/armory_menu.gd

**Before:**
```gdscript
func _ready() -> void:
    # ... initialization ...
    _build_ui()  # Immediate build
    process_mode = Node.PROCESS_MODE_ALWAYS
```

**After:**
```gdscript
func _ready() -> void:
    # ... initialization ...
    var viewport_rect: Rect2 = get_viewport_rect()
    FileLogger.info("[ArmoryMenu] Viewport rect in _ready(): %s" % viewport_rect)

    # Defer UI building to next frame (Issue #785 fix)
    call_deferred("_build_ui_deferred")

    process_mode = Node.PROCESS_MODE_ALWAYS

func _build_ui_deferred() -> void:
    var viewport_rect: Rect2 = get_viewport_rect()
    FileLogger.info("[ArmoryMenu._build_ui_deferred] Viewport rect: %s" % viewport_rect)
    _build_ui()
```

**Additional Diagnostics:**
- Added viewport rect logging in _ready() vs _build_ui_deferred()
- Added root_control size, position, and anchor logging
- Added background size and color logging

## Expected Behavior After Fix

1. User clicks "Armory" button
2. ArmoryMenu is instantiated and added to tree
3. _ready() is called, defers UI building
4. Next frame: _build_ui_deferred() is called with valid viewport
5. UI elements are created with correct sizes
6. Background, panel, and all UI elements are visible

## Verification

To verify the fix works:
1. Check logs show non-zero viewport rect in _build_ui_deferred()
2. Check logs show non-zero root_control.size
3. Check logs show non-zero background.size
4. Verify armory screen appears when clicking button
5. Verify all UI elements (weapons, grenades, items) are visible

## Related Godot Issues

This is a known timing issue in Godot 4 when building UI programmatically in CanvasLayers:
- Control nodes need valid parent dimensions for layout calculations
- CanvasLayers may not have viewport access immediately in _ready()
- Best practice: defer UI building or check viewport availability first

## References

- [Godot CanvasLayer Documentation](https://docs.godotengine.org/en/stable/classes/class_canvaslayer.html)
- [Godot Canvas Layers Tutorial](https://docs.godotengine.org/en/stable/tutorials/2d/canvas_layers.html)
- [GitHub Issue #81514: CanvasLayer not matching with first child control](https://github.com/godotengine/godot/issues/81514)
- [Godot Forum: CanvasLayer causes child nodes to not display](https://forum.godotengine.org/t/canvaslayer-causes-child-nodes-to-not-display/75605)
