# Case Study: Issue #188 - Armory Menu Breakage After Frag Grenade Implementation

## Executive Summary

This case study documents the investigation and resolution of a bug where the armory menu stopped displaying content after implementing the frag grenade feature (Issue #188). The root cause was identified as invalid node naming in Godot due to spaces in grenade names.

## Timeline of Events

### Phase 1: Initial Implementation (PR #189)
- **Date:** 2026-01-22 ~00:13
- **Action:** AI solver implemented frag grenade feature
- **Changes Made:**
  1. Added `GrenadeManager` autoload for grenade type selection
  2. Modified `armory_menu.gd` to include grenade selection UI
  3. Removed flashbang from the `WEAPONS` dictionary (moved to `GrenadeManager`)
  4. Added dynamic grenade slot creation in armory menu

### Phase 2: User Testing
- **Date:** 2026-01-22 03:32
- **Action:** User tested the build
- **Result:** User reported "armory сломалось - там ничего не отображается" (armory broke - nothing is displayed there)
- **Logs Provided:**
  - `game_log_20260122_033222.txt`
  - `game_log_20260122_033248.txt`

### Phase 3: Investigation
- **Date:** 2026-01-22
- **Findings:**
  1. Logs showed normal game operation, no explicit errors
  2. GrenadeManager was loading correctly
  3. Identified potential issue: Node naming with spaces

## Root Cause Analysis

### Primary Issue: Invalid Node Names

In Godot 4.x, node names cannot contain spaces. The code in `_create_grenade_slot()` was setting:

```gdscript
slot.name = grenade_data.get("name", "grenade") + "_slot"
```

With `GRENADE_DATA` containing:
```gdscript
GrenadeType.FRAG: {
    "name": "Frag Grenade",  # Contains a space!
    ...
}
```

This would create a node named "Frag Grenade_slot" which violates Godot's node naming rules.

### Secondary Issues Identified

1. **No defensive checks:** The code didn't validate that UI elements were properly initialized
2. **No logging:** Without diagnostic logging, it was difficult to trace the execution path
3. **WEAPONS dictionary modification:** Removing flashbang from WEAPONS could have unintended consequences if other code depended on it

## Solution Implemented

### Fix 1: Sanitize Node Names
```gdscript
func _create_grenade_slot(grenade_type: int, grenade_data: Dictionary, is_selected: bool) -> PanelContainer:
    var slot := PanelContainer.new()
    # Use sanitized name for node (no spaces allowed in Godot node names)
    var grenade_name: String = grenade_data.get("name", "grenade")
    slot.name = grenade_name.replace(" ", "_") + "_slot"
```

### Fix 2: Add Defensive Checks
```gdscript
func _populate_weapon_grid() -> void:
    # Verify weapon_grid is valid
    if weapon_grid == null:
        FileLogger.info("[ArmoryMenu] ERROR: weapon_grid is null!")
        return
```

### Fix 3: Add Diagnostic Logging
Added comprehensive logging throughout the armory menu to track:
- When `_ready()` is called
- Whether `GrenadeManager` was found
- Number of weapon/grenade slots being created
- Completion of grid population

## Files Modified

1. `scripts/ui/armory_menu.gd`
   - Fixed node naming to replace spaces with underscores
   - Added null checks for weapon_grid
   - Added diagnostic logging

## Lessons Learned

1. **Godot Node Naming:** Always sanitize user-facing strings before using them as node names
2. **Defensive Programming:** Add null checks and validation for @onready variables
3. **Logging:** Implement logging early in development to aid debugging
4. **Testing:** Visual UI changes should be manually tested before merging

## Recommendations

1. Create a utility function for sanitizing node names
2. Add unit tests that verify node naming conventions
3. Consider adding debug overlay for UI debugging
4. Document Godot-specific constraints in coding guidelines

### Phase 4: Second Fix Attempt (Continued Investigation)
- **Date:** 2026-01-22 ~00:48
- **Action:** User reported armory still broken
- **New Log:** `game_log_20260122_034730.txt`
- **Key Observation:** Log shows GrenadeManager loading correctly, but **NO `[ArmoryMenu]` entries**
  - This indicates the armory menu was never opened during the test session
  - OR the script's `_ready()` function never executed

### Phase 5: Enhanced Debugging
- **Date:** 2026-01-22
- **Actions Taken:**
  1. Added comprehensive logging to pause_menu.gd for armory button handling
  2. Enhanced logging in armory_menu.gd with per-slot creation messages
  3. Added validation for all UI elements (back_button, status_label, weapon_grid)
  4. Added refresh call when re-opening existing armory menu (like levels_menu does)

## Key Observations from Logs

### Log Analysis Summary:

| Log File | ArmoryMenu Entries | GrenadeManager Entries | Interpretation |
|----------|-------------------|------------------------|----------------|
| game_log_20260122_033222.txt | **NONE** | Present | Armory not opened |
| game_log_20260122_033248.txt | **NONE** | Present | Armory not opened |
| game_log_20260122_034730.txt | **NONE** | Present | Armory not opened |

### Conclusion:
The logs show the GrenadeManager is loading correctly (proving the new code is running), but there are NO `[ArmoryMenu]` entries in any of the logs. This means either:
1. The user did not open the armory menu during these test sessions
2. The armory menu's script is not executing at all
3. There's an issue before the logging starts

## Enhanced Solution

### Additional Fix: Pause Menu Logging
```gdscript
func _on_armory_pressed() -> void:
    FileLogger.info("[PauseMenu] Armory button pressed")
    # ... existing code ...
    FileLogger.info("[PauseMenu] Armory menu instance created and added as child")
```

### Additional Fix: Armory Menu Refresh on Re-open
```gdscript
# In pause_menu.gd _on_armory_pressed():
else:
    FileLogger.info("[PauseMenu] Showing existing armory menu")
    # Refresh the weapon grid in case grenade selection changed
    if _armory_menu.has_method("_populate_weapon_grid"):
        _armory_menu._populate_weapon_grid()
    _armory_menu.show()
```

### Additional Fix: Per-Slot Logging
Added logging for each weapon and grenade slot creation to trace exactly which items are being added.

## Related Files

- [Game Log 1](logs/game_log_20260122_033222.txt)
- [Game Log 2](logs/game_log_20260122_033248.txt)
- [Game Log 3](game_log_20260122_034730.txt)
- [Game Log 4 (Latest)](game_log_20260122_041025.txt)

---

## Phase 6: Fourth Log Analysis (2026-01-22 04:10)

### New Log: `game_log_20260122_041025.txt`

This log provides **critical new information**:

```
[04:10:26] [INFO] [PauseMenu] Armory button pressed
[04:10:26] [INFO] [PauseMenu] Creating new armory menu instance
[04:10:26] [INFO] [PauseMenu] Armory menu instance created and added as child
```

And later:
```
[04:10:44] [INFO] [PauseMenu] Armory button pressed
[04:10:44] [INFO] [PauseMenu] Creating new armory menu instance
[04:10:44] [INFO] [PauseMenu] Armory menu instance created and added as child
```

### Key Finding

The `[PauseMenu]` logs ARE appearing (proving the latest code is running), but there are **STILL NO `[ArmoryMenu]` entries**. This means:

1. The armory button IS being pressed ✓
2. The scene IS being instantiated ✓
3. The instance IS being added as a child ✓
4. **BUT `_ready()` in armory_menu.gd is NOT being called!**

### Hypothesis: Silent Script Error

When a Godot script has an error that prevents execution, the `_ready()` function may silently fail to run. Possible causes:
1. The `@onready` variables fail to resolve their node paths
2. There's a parse-time error in the script
3. The script is somehow not attached to the instantiated scene

### Investigation Actions

1. **Added `_enter_tree()` function** - This runs before `_ready()` and before `@onready` variables are initialized:
   ```gdscript
   func _enter_tree() -> void:
       FileLogger.info("[ArmoryMenu] _enter_tree() called - node added to tree")
   ```

2. **Enhanced pause menu logging** - Added detailed logging to trace the exact state:
   ```gdscript
   FileLogger.info("[PauseMenu] armory_menu_scene resource path: %s" % armory_menu_scene.resource_path)
   FileLogger.info("[PauseMenu] Instance created, class: %s, name: %s" % [_armory_menu.get_class(), _armory_menu.name])
   FileLogger.info("[PauseMenu] is_inside_tree: %s" % _armory_menu.is_inside_tree())
   ```

### Next Steps

User needs to:
1. Rebuild the game with the latest code
2. Open the armory menu
3. Provide the new log file

Expected log entries if `_enter_tree()` works but `_ready()` doesn't:
```
[PauseMenu] armory_menu_scene resource path: res://scenes/ui/ArmoryMenu.tscn
[PauseMenu] Instance created, class: CanvasLayer, name: ArmoryMenu
[ArmoryMenu] _enter_tree() called - node added to tree
[PauseMenu] is_inside_tree: true
```

If `_enter_tree()` also doesn't appear, the script is not executing at all (possibly not attached).
