# Case Study: Fix Slot Position Jumping During Armory Item Unlock Animation (Issue #802)

## Problem Statement

After implementing animated item unlocking in PR #798 (Issue #785), users reported that during the opening animation, the unlocked cell becomes the first cell in the section while the opening happens, making it appear as if it "flies away from under the cursor."

### Reported Behavior
- When holding LMB on a locked item in the armory menu to unlock it
- The slot visually jumps or moves from its expected grid position
- The slot appears to become the "first cell" in its section
- The animation effect (shaking) makes the item fly away from the cursor

## Timeline of Events

### 2026-02-16 00:21:12 - Game Session
From the provided log file (`game_log_20260216_002112.txt`):

1. **00:21:14** - First armory menu opened, user starts unlocking items
2. **00:21:25** - SMG weapon unlocked (first unlock event)
3. **00:21:29** - Sniper weapon unlocked (second unlock event)
4. **00:21:31** - Armory menu reopened
5. **00:21:37 - 00:21:58** - Multiple items unlocked in succession:
   - Teleport Bracers (active item)
   - Homing Bullets (active item)
   - F-1 Grenade
   - Shotgun, Revolver, M16 (weapons)
   - Breaker Bullets, Flashlight (active items)
   - Silenced Pistol (weapon)

No errors were logged, but the visual issue manifested during these unlock sequences.

## Root Cause Analysis

### Code Investigation

Examining the PR #798 diff (`pr-798-diff.txt`), the problematic code is in `scripts/ui/armory_menu.gd`, lines 512-517 of the diff:

```gdscript
# Apply shaking effect based on progress
var shake_intensity: float = progress * 3.0
slot.position = Vector2(
    randf_range(-shake_intensity, shake_intensity),
    randf_range(-shake_intensity, shake_intensity)
)
```

### Technical Root Cause

**The issue is caused by directly modifying `slot.position` on a node that is a child of a GridContainer.**

#### Why This Causes the Problem:

1. **GridContainer Layout Management**: GridContainer in Godot automatically manages the position of its children based on:
   - Grid dimensions (rows × columns)
   - Cell spacing (h_separation, v_separation)
   - Child node sizes
   - The order children were added to the container

2. **Position Property Conflict**: When you manually set `position` on a Control node within a container:
   - It creates a conflict between the container's layout system and the manual position
   - The Control moves from its calculated grid cell position
   - This visual displacement makes it appear to "jump" or "fly away"
   - In some layout recalculations, the node may even visually appear in a different grid cell

3. **Layout Recalculation**: During animation frames, GridContainer may recalculate layout, causing additional visual jitter or the slot appearing in the wrong position temporarily.

### Evidence from Codebase

From `scripts/ui/armory_menu.gd`:

- Line 459-465: Weapons are added to `_weapon_grid` (a GridContainer)
- Line 502-508: Grenades are added to `_grenade_grid` (a GridContainer)
- Line 552-558: Active items are added to `_active_item_grid` (a GridContainer)

All three grids use the same slot creation and animation system, so all slots are affected by the same bug.

## Research Findings

### Godot UI Container Best Practices

Based on research from Godot documentation and community resources:

#### GridContainer Behavior ([Godot Docs](https://docs.godotengine.org/en/4.3/classes/class_gridcontainer.html))

- GridContainer arranges Control nodes in a grid layout
- Automatically calculates and sets child positions based on grid parameters
- Manual position changes on children can interfere with layout calculations
- Best practice: Don't modify position directly on GridContainer children

#### Control Node Offset Properties ([Godot Community](https://github.com/godotengine/godot-proposals/issues/8435))

- `position`: Absolute position of the node (interferes with container layout)
- `pivot_offset`: Point around which transformations (scale, rotation) occur
- Offset properties on child nodes can be used for visual effects without affecting layout

#### Shake Effect Techniques ([KidsCanCode](https://kidscancode.org/godot_recipes/4.x/2d/screen_shake/index.html))

- Use offset or modulate properties for visual-only effects
- Create wrapper nodes to handle visual displacement
- Use Control's transform properties instead of position for container children

## Proposed Solution

### Solution Approach

Instead of modifying `slot.position` directly, we should:

1. **Use an inner container's offset**: Modify the offset of the VBoxContainer child inside the slot
2. **Non-interfering property**: This creates a visual shake without affecting the slot's grid position
3. **Maintain layout integrity**: GridContainer continues to manage the slot's actual position correctly

### Technical Implementation

#### Current Code (Problematic)
```gdscript
# Apply shaking effect based on progress
var shake_intensity: float = progress * 3.0
slot.position = Vector2(
    randf_range(-shake_intensity, shake_intensity),
    randf_range(-shake_intensity, shake_intensity)
)
```

#### Fixed Code (Solution)
```gdscript
# Apply shaking effect to inner container to avoid layout conflicts
var shake_intensity: float = progress * 3.0
var vbox: VBoxContainer = slot.get_child(0) as VBoxContainer
if vbox:
    # Use offset instead of position to avoid GridContainer layout conflicts
    vbox.position = Vector2(
        randf_range(-shake_intensity, shake_intensity),
        randf_range(-shake_intensity, shake_intensity)
    )
```

#### Cleanup Update (in `_remove_progress_overlay`)
```gdscript
# Reset inner container position
var vbox: VBoxContainer = slot.get_child(0) as VBoxContainer
if vbox:
    vbox.position = Vector2.ZERO
```

### Why This Solves the Problem

1. **Slot position unchanged**: The PanelContainer slot stays in its GridContainer-assigned position
2. **Visual shake achieved**: The VBoxContainer inside moves, creating the shake effect
3. **No layout conflicts**: GridContainer doesn't manage the VBoxContainer's position, only the slot's
4. **Cursor alignment maintained**: The slot's actual hit area stays under the cursor

## Alternative Solutions Considered

### Alternative 1: Use Control.offset_* Properties
- Could use offset_left, offset_top, offset_right, offset_bottom
- More complex to animate (4 properties instead of 1 Vector2)
- Less intuitive than position offset on inner node

### Alternative 2: Create Wrapper Node
- Add an intermediate Control node between slot and vbox
- More node overhead
- Unnecessary complexity for this use case

### Alternative 3: Disable GridContainer Layout During Animation
- Set custom_minimum_size or size_flags
- Could cause other layout issues
- More invasive change

**Selected Solution: Modify inner VBoxContainer position** - Simplest, most direct fix with minimal code changes.

## Files Modified

1. `scripts/ui/armory_menu.gd`:
   - `_update_progress_overlay()` - Change shake target from slot to inner vbox
   - `_remove_progress_overlay()` - Reset inner vbox position to zero

## Testing Plan

1. **Visual Verification**:
   - Open armory menu with locked items
   - Hold LMB on a locked item to start unlock animation
   - Verify slot stays in same grid position during shake animation
   - Verify cursor remains over the slot throughout animation
   - Verify item doesn't appear to jump to different grid cell

2. **Multiple Item Types**:
   - Test with locked weapons (weapon_grid)
   - Test with locked grenades (grenade_grid)
   - Test with locked active items (active_item_grid)
   - Verify fix works for all three categories

3. **Edge Cases**:
   - Test with items in different grid positions (first, middle, last)
   - Test rapid unlocking of multiple items in sequence
   - Test releasing LMB before unlock completes (should reset cleanly)

4. **Animation Quality**:
   - Verify shake effect still visible and satisfying
   - Verify progress bar still fills correctly
   - Verify sound effects still play at correct intervals
   - Verify unlock reveal animation plays correctly after shake

## References

### Issue and PR Links
- Original issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/802
- Related PR #798: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/798 (Animated item unlocking - Issue #785)

### Documentation
- [GridContainer — Godot Engine (4.3) documentation](https://docs.godotengine.org/en/4.3/classes/class_gridcontainer.html)
- [Overview of Godot UI containers | GDQuest](https://school.gdquest.com/courses/learn_2d_gamedev_godot_4/start_a_dialogue/all_the_containers)
- [Screen Shake :: Godot 4 Recipes](https://kidscancode.org/godot_recipes/4.x/2d/screen_shake/index.html)
- [Add Pivot Offset presets to Control nodes - Godot Proposals](https://github.com/godotengine/godot-proposals/issues/8435)

### Community Resources
- [Creating a dynamic UI with GridContainer - Godot Forum](https://forum.godotengine.org/t/creating-a-dynamic-ui-with-gridcontainer-example-gif-included/76691)
- [GitHub - Eneskp3441/Shaker: shake plugin for godot](https://github.com/Eneskp3441/Shaker)

## Conclusion

The slot position jumping issue was caused by directly modifying the `position` property of GridContainer children, which conflicts with the container's automatic layout management. By moving the shake effect to an inner VBoxContainer node, we preserve the grid layout integrity while maintaining the desired visual effect.

This fix is minimal, focused, and addresses the root cause without introducing additional complexity or side effects.
