# Case Study: Issue #1006 - Fix Weapon Selection After Score Screen

## Issue Summary

**Issue:** When the player opens the armory from the score screen and selects a new weapon, the current level restarts instead of returning to the score screen.

**Expected Behavior:** After selecting a weapon from the armory (opened from the score screen), the player should return to the score screen. The armory should close, and the level should NOT restart.

**Actual Behavior (Bug):** After selecting a weapon from the armory (opened from the score screen), the level restarts, losing the score screen context.

## Timeline of Events

1. Player completes a level
2. Score screen is displayed with statistics (kills, combos, time, accuracy, etc.)
3. If unlockable items are available, an "Armory" button appears on the score screen
4. Player clicks the "Armory" button
5. Armory menu opens as an overlay
6. Player selects a new weapon/grenade/active item
7. Player clicks "Apply" button
8. **BUG:** Level restarts instead of closing the armory and returning to the score screen

## Root Cause Analysis

### Code Flow Before Fix

1. **Score Screen** (`scripts/levels/*_level.gd`):
   - `_add_score_screen_buttons()` creates an "Armory" button if unlockable items are available
   - Button's `pressed` signal connects to `_on_armory_button_pressed()`
   - `_on_armory_button_pressed()` loads and instantiates the armory menu scene

2. **Armory Menu** (`scripts/ui/armory_menu.gd`):
   - `_on_apply_pressed()` is called when the Apply button is clicked
   - This function always called `GameManager.restart_scene()` after applying changes
   - There was no distinction between:
     - Armory opened from pause menu (during gameplay) - restart is correct
     - Armory opened from score screen (after level completion) - restart is incorrect

### The Problem

The `_on_apply_pressed()` function in `armory_menu.gd` unconditionally restarted the level:

```gdscript
# Before fix (lines 1095-1100)
if weapon_changed or grenade_changed or active_item_changed:
    if GameManager:
        get_tree().paused = false
        Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
        GameManager.restart_scene()  # Always restarts!
```

## Solution

### Approach

1. **Add context tracking** to the armory menu to know where it was opened from
2. **Modify behavior based on context**:
   - From score screen: Just close the armory (no restart)
   - From pause menu: Continue with restart (existing behavior)

### Implementation Details

1. **Added new property** in `armory_menu.gd`:
```gdscript
## Whether the armory was opened from the score screen (Issue #1006).
var opened_from_score_screen: bool = false
```

2. **Added new signal** for explicit communication:
```gdscript
## Signal emitted when Apply is pressed from score screen context.
signal apply_pressed_from_score_screen
```

3. **Modified `_on_apply_pressed()`** to check context:
```gdscript
if weapon_changed or grenade_changed or active_item_changed:
    if opened_from_score_screen:
        # Issue #1006: Close armory and return to score screen
        apply_pressed_from_score_screen.emit()
        queue_free()
    elif GameManager:
        # Normal behavior: restart level
        get_tree().paused = false
        Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
        GameManager.restart_scene()
```

4. **Updated all level scripts** to set the flag when opening armory from score screen:
```gdscript
func _on_armory_button_pressed() -> void:
    var armory_menu = armory_menu_scene.instantiate()
    # Issue #1006: Mark as opened from score screen
    armory_menu.opened_from_score_screen = true
    get_tree().root.add_child(armory_menu)
```

## Files Modified

1. `scripts/ui/armory_menu.gd` - Core fix: added property, signal, and conditional logic
2. `scripts/levels/city_level.gd` - Set flag when opening from score screen
3. `scripts/levels/labyrinth_level.gd` - Set flag when opening from score screen
4. `scripts/levels/building_level.gd` - Set flag when opening from score screen
5. `scripts/levels/castle_level.gd` - Set flag when opening from score screen
6. `scripts/levels/beach_level.gd` - Set flag when opening from score screen
7. `scripts/levels/docks_level.gd` - Set flag when opening from score screen
8. `scripts/levels/revolver_level.gd` - Set flag when opening from score screen
9. `scripts/levels/test_tier.gd` - Set flag when opening from score screen

## Testing

### Test Scenarios

1. **Score Screen -> Armory -> Apply:**
   - Complete a level
   - Open armory from score screen
   - Select a different weapon
   - Click Apply
   - **Expected:** Armory closes, score screen remains visible, level does NOT restart

2. **Pause Menu -> Armory -> Apply:**
   - During gameplay, open pause menu
   - Open armory from pause menu
   - Select a different weapon
   - Click Apply
   - **Expected:** Level restarts with new weapon (existing behavior unchanged)

3. **Score Screen -> Armory -> Back:**
   - Complete a level
   - Open armory from score screen
   - Click Back without making changes
   - **Expected:** Armory closes, score screen remains visible

## Design Considerations

### Why Not Use a Constructor Parameter?

Using a property (`opened_from_score_screen`) instead of a constructor parameter allows:
- Backward compatibility with existing code
- Default value of `false` maintains existing pause menu behavior
- Simpler scene instantiation (no need to modify scene loading)

### Why a New Signal?

The `apply_pressed_from_score_screen` signal allows level scripts to:
- React to the apply action if needed (e.g., update displayed weapon in score screen)
- Maintain loose coupling between armory and level logic

## References

- Issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1006
- Related Issue #897: Armory button shown on score screen when items are available to unlock
