# Issue #816: Fix Warehouse Passages Visual Display

## Problem

Warehouses A and B in the Docks level appeared to have no passages (looking like solid walls), although passages actually existed in the collision layer.

## Root Cause

The issue was in the visual representation (ColorRect nodes) of the split walls:

### Warehouse A - Bottom Wall
- The bottom wall was split into `WallBottomL` and `WallBottomR` to create a passage
- However, the ColorRect visual elements were touching edge-to-edge:
  - `WallBottomL` ColorRect spanned from x=-250 to x=0
  - `WallBottomR` ColorRect spanned from x=0 to x=250
  - Result: A visually solid 500-unit wall with no visible gap

### Warehouse B - Top Wall
- The top wall was split into `WallTopL` and `WallTopR` to create a passage
- Same issue with ColorRects touching:
  - `WallTopL` ColorRect spanned from x=-350 to x=0
  - `WallTopR` ColorRect spanned from x=0 to x=350
  - Result: A visually solid 700-unit wall with no visible gap

## Solution

Adjusted the ColorRect offsets to create visible gaps representing the passages:

### Warehouse A Bottom Wall Fix
- `WallBottomL` ColorRect: Changed `offset_right` from 125.0 to 50.0
  - Now spans from x=-250 to x=-75 (local to position x=-125)
- `WallBottomR` ColorRect: Changed `offset_left` from -125.0 to -50.0
  - Now spans from x=75 to x=250 (local to position x=125)
- **Result**: 150-unit visible gap from x=-75 to x=75

### Warehouse B Top Wall Fix
- `WallTopL` ColorRect: Changed `offset_right` from 175.0 to 75.0
  - Now spans from x=-350 to x=-100 (local to position x=-175)
- `WallTopR` ColorRect: Changed `offset_left` from -175.0 to -75.0
  - Now spans from x=100 to x=350 (local to position x=175)
- **Result**: 200-unit visible gap from x=-100 to x=100

## Files Modified

- `scenes/levels/DocksLevel.tscn` - Fixed ColorRect offsets for warehouse passages
- `scripts/levels/docks_level.gd` - Added from PR #799 (Docks level implementation)
- `scripts/ui/levels_menu.gd` - Added Docks level to menu (from PR #799)

## Technical Details

The collision shapes were already correctly sized to allow passage, but the visual representation (ColorRect) did not match. The fix ensures that players can both see and access the warehouse passages, making the level design clearer and more intuitive.

## Related

- Issue #816: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/816
- PR #799 (Docks Level): https://github.com/Jhon-Crow/godot-topdown-MVP/pull/799
