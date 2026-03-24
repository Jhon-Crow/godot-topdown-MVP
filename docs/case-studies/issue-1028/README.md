# Case Study: Issue #1028 — Remove Ricochet Points Item, Merge Effect into Trajectory Glasses

## Overview

**Issue:** [#1028](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1028)
**Title:** Fix — Remove accidental "Ricochet Points" item; move its effect onto "Trajectory Glasses"
**Status:** Resolved in PR #1029
**Branch:** `issue-1028-7dc94da1c8f4`

---

## Problem Statement

The item "Ricochet Points" (`ActiveItemType.RICOCHET_POINTS`, enum value `10`) was accidentally added to the game as a separate selectable item in the armory. Its effect — a passive +30% ricochet chance boost at valid angles (the "green trajectory" zone) — was intended to be an **additional passive effect** of the existing "Trajectory Glasses" item (`ActiveItemType.TRAJECTORY_GLASSES`, enum value `8`), not a standalone item.

The reporter (author: Jhon-Crow) noted:
> "случайно было добавлен предмет Ricochet Points [...] его эффект [...] должен быть дополнительным эффектом предмета Очки рикошета"
>
> Translation: "Ricochet Points was accidentally added [...] its effect [...] should be an additional effect of the Trajectory Glasses item."

---

## Timeline / Sequence of Events

1. **Issue #975** — An experimental setting `is_ricochet_points_enabled()` was added in `caliber_data.gd` that boosts ricochet probability by 20% when enabled. This was an experimental/debug toggle.

2. **Issue #1004** — A full implementation of "Ricochet Points" was added as a standalone active item (`RICOCHET_POINTS = 10`) with:
   - Entry in `ActiveItemType` enum
   - Entry in `ACTIVE_ITEM_DATA` dictionary with its own icon and description
   - `has_ricochet_points()` helper on `ActiveItemManager`
   - A +30% ricochet probability boost in `bullet.gd::_calculate_ricochet_probability()` triggered when the item is equipped
   - Tests in `test_active_item_manager.gd` and `test_ricochet.gd`

3. **Issue #1028** — The author realized the "Ricochet Points" item was accidental. The ricochet probability boost (+30% at valid angles) should instead be a **passive bonus** that activates automatically when "Trajectory Glasses" (`TRAJECTORY_GLASSES`) are equipped, not a separate item.

---

## Root Cause Analysis

The root cause is a **feature design misalignment**:
- The developer implementing Issue #1004 created a new standalone item for the ricochet boost.
- The game designer (repository owner) intended the boost to be a passive secondary effect of the existing "Trajectory Glasses" item.
- No explicit design document or acceptance criteria was linked in Issue #1004 clarifying this intent.

This is a common issue in game development where gameplay features are implemented before design specifications are fully clarified.

---

## Affected Files

| File | Change |
|------|--------|
| `scripts/autoload/active_item_manager.gd` | Removed `RICOCHET_POINTS` enum entry, dictionary entry, unlock entry, and `has_ricochet_points()` method. Updated Trajectory Glasses description to mention passive +30% boost. |
| `scripts/projectiles/bullet.gd` | Changed ricochet probability boost trigger from `has_ricochet_points()` → `has_trajectory_glasses()`. |
| `tests/unit/test_active_item_manager.gd` | Removed "Ricochet Points" tests section. Added tests verifying: (a) no item exists at index 10, (b) Trajectory Glasses description mentions 30% passive boost. Updated trajectory glasses description test to check for "30%" and "passive". |
| `tests/unit/test_ricochet.gd` | Updated section header and test names to reflect the boost now comes from Trajectory Glasses (Issue #1028), not a separate Ricochet Points item. |

---

## Solution

### Change 1: `active_item_manager.gd`

- **Removed** `RICOCHET_POINTS = 10` from `ActiveItemType` enum
- **Removed** `ActiveItemType.RICOCHET_POINTS: true` from `unlocked_active_items`
- **Removed** `ActiveItemType.RICOCHET_POINTS: {...}` entry from `ACTIVE_ITEM_DATA`
- **Removed** `has_ricochet_points()` method
- **Updated** `TRAJECTORY_GLASSES` description to append: `" Passive: ricochet chance is increased by 30% at angles where ricochet is possible (green ray)."`

### Change 2: `bullet.gd`

In `_calculate_ricochet_probability()`:
```gdscript
# Before (Issue #1004)
if active_item_manager.has_ricochet_points():
    probability = minf(probability + 0.3, 1.0)

# After (Issue #1028)
if active_item_manager.has_trajectory_glasses():
    probability = minf(probability + 0.3, 1.0)
```

The ricochet boost now activates whenever the player has Trajectory Glasses equipped — which is the correct design intent.

### Change 3: Tests

Tests were updated to:
- Verify no item exists at index 10 (confirming `RICOCHET_POINTS` is gone)
- Verify Trajectory Glasses description now mentions "30%" and "passive"
- Rename ricochet boost math tests to reference Trajectory Glasses, not Ricochet Points

---

## Impact Analysis

- **Gameplay change:** Players who previously selected "Ricochet Points" as their active item for the +30% boost will now need to select "Trajectory Glasses" instead. The boost is the same (+30% at valid angles), but now it is bundled with the trajectory visualization ability.
- **No regression:** The probability boost math is unchanged; only the condition (which item triggers it) changed.
- **Simplification:** The armory now has one fewer item to choose from, reducing confusion.

---

## Verification

All existing tests pass with the changes. New tests added:
- `test_trajectory_glasses_data_has_no_separate_ricochet_points_item` — confirms index 10 is empty
- `test_trajectory_glasses_description_mentions_passive_boost` — confirms description updated
- `test_trajectory_glasses_data_has_description` — extended to also check "30%" and "passive"
- Six ricochet probability boost math tests renamed to reference Trajectory Glasses

---

## Related Issues

- **Issue #744** — Original Trajectory Glasses implementation
- **Issue #975** — Experimental `ricochet_points` toggle in `caliber_data.gd` (separate from the active item)
- **Issue #1004** — Accidental standalone Ricochet Points item (root cause of this issue)
- **Issue #1028** — This fix
