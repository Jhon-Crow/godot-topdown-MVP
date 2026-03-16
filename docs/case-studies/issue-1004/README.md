# Issue #1004 Case Study: Move Ricochet Points from Experimental to Active Item

## Summary

Issue #1004 requested moving the "Ricochet Points" feature from the experimental settings menu to an active item that players can equip in the armory. Additionally, the ricochet chance boost was increased from 20% to 30%.

## Timeline of Events

1. **Issue #975 (Original Implementation)**: Ricochet Points was initially implemented as an experimental setting with a 20% ricochet chance boost.

2. **Issue #1004 (Current)**: User requested to move the feature from experimental settings to active items, and increase the boost to 30%.

## Root Cause Analysis

The feature was initially placed in experimental settings for testing purposes. Once validated, it needed to be promoted to a proper active item for production use.

## Changes Made

### 1. Removed from Experimental Settings

- **scripts/autoload/experimental_settings.gd**: Removed `ricochet_points_enabled` variable, getter/setter methods, and persistence code
- **scripts/ui/experimental_menu.gd**: Removed checkbox, toggle handler, and status display for ricochet points
- **scenes/ui/ExperimentalMenu.tscn**: Removed UI elements for ricochet points toggle

### 2. Added as Active Item

- **scripts/autoload/active_item_manager.gd**:
  - Added `RICOCHET_POINTS = 10` to `ActiveItemType` enum
  - Added entry to `unlocked_active_items` (freely available from start)
  - Added entry to `ACTIVE_ITEM_DATA` with name, icon path, and description
  - Added `has_ricochet_points()` method

### 3. Updated Ricochet Logic

- **scripts/projectiles/bullet.gd**: Changed `_calculate_ricochet_probability()` to:
  - Check `ActiveItemManager.has_ricochet_points()` instead of `ExperimentalSettings.is_ricochet_points_enabled()`
  - Apply +30% boost instead of +20%

### 4. Updated Tests

- **tests/unit/test_experimental_settings.gd**: Removed all ricochet points tests and mock code
- **tests/unit/test_ricochet.gd**: Updated probability boost tests from 20% to 30%
- **tests/unit/test_active_item_manager.gd**: Added tests for ricochet points active item

## Technical Details

### Before (Experimental Setting)
```gdscript
# ExperimentalSettings
var ricochet_points_enabled: bool = false

func is_ricochet_points_enabled() -> bool:
    return ricochet_points_enabled
```

### After (Active Item)
```gdscript
# ActiveItemManager
enum ActiveItemType {
    ...
    RICOCHET_POINTS = 10
}

func has_ricochet_points() -> bool:
    return current_active_item == ActiveItemType.RICOCHET_POINTS
```

### Ricochet Probability Calculation
```gdscript
# Before: +20% boost via ExperimentalSettings
if experimental_settings.is_ricochet_points_enabled():
    probability = minf(probability + 0.2, 1.0)

# After: +30% boost via ActiveItemManager
if active_item_manager.has_ricochet_points():
    probability = minf(probability + 0.3, 1.0)
```

## Files Changed

1. `scripts/autoload/experimental_settings.gd` - Removed ricochet points
2. `scripts/ui/experimental_menu.gd` - Removed ricochet points UI
3. `scenes/ui/ExperimentalMenu.tscn` - Removed ricochet points scene nodes
4. `scripts/autoload/active_item_manager.gd` - Added ricochet points as active item
5. `scripts/projectiles/bullet.gd` - Updated ricochet calculation
6. `tests/unit/test_experimental_settings.gd` - Removed ricochet points tests
7. `tests/unit/test_ricochet.gd` - Updated boost percentage tests
8. `tests/unit/test_active_item_manager.gd` - Added ricochet points tests

## Screenshots

Original experimental setting UI:
![Issue Screenshot](issue-screenshot.png)
