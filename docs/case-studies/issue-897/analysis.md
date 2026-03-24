# Issue #897: Armory Button Highlight for Available Unlocks

## Problem Statement

When an unlock condition is met (a level is completed with sufficient rank) but the corresponding
item has not yet been opened by the player, the **Armory** menu button in the pause menu should
be highlighted in gold to draw attention to available unlocks.

Additionally, after completing a level, a highlighted **Armory** button should appear on the
score screen if there are items ready to unlock.

The highlight disappears once the player has unlocked all available items.

Also, the individual item card in the armory that is available to unlock should have a gold
background (this was already partially implemented via `_apply_condition_met_style()`).

## Root Cause Analysis

The code already had:
1. `UnlockManager` with methods `is_weapon_condition_met()`, `is_grenade_condition_met()`, and
   `is_active_item_condition_met()` for checking individual item conditions
2. `_apply_condition_met_style()` in `armory_menu.gd` that applies a gold background to item slots
   where the condition is met (gold card background was already implemented)
3. `PauseMenu` with an `armory_button: Button` reference

What was **missing**:
1. A method to check if **any** item across all categories has a condition met but is not yet unlocked
2. Logic to highlight the pause menu armory button using that method
3. An armory button on the score screen after level completion

## Solution

### 1. Added `has_any_available_unlock()` to `UnlockManager`

A new method that returns `true` if at least one item (weapon, grenade, or active item) has its
unlock condition satisfied but is not yet unlocked by the player.

### 2. Updated `PauseMenu` to Highlight Armory Button

- Added `_refresh_armory_button_highlight()` method that applies a gold style to the armory button
  when `has_any_available_unlock()` returns `true`
- Called on `_ready()`, when the pause menu opens (`pause_game()`), and when returning from the
  armory (`_on_armory_back()`)

### 3. Added Highlighted Armory Button to All Level Score Screens

Added gold-styled "★ Armory — Items Available!" button to `_add_score_screen_buttons()` in all
level scripts:
- `building_level.gd`
- `labyrinth_level.gd`
- `castle_level.gd`
- `docks_level.gd`
- `beach_level.gd`
- `revolver_level.gd`
- `test_tier.gd`
- `city_level.gd`

The button is only shown when `has_any_available_unlock()` returns `true`. Clicking it opens the
armory menu as a CanvasLayer overlay (same pattern as the existing level select button).

### 4. Tests Added

New tests for `has_any_available_unlock()` in `tests/unit/test_unlock_manager.gd`:
- No available unlocks when no progress
- No available unlocks when condition not met
- Has available unlock when weapon condition met and item locked
- No available unlocks when item already unlocked
- Has available unlock when active item condition met
- Correct behavior when all items unlocked
- Correct behavior with mixed lock states
- Updates correctly after new level completion

## Visual Design

Gold highlight uses:
- Background: `Color(0.28, 0.22, 0.08, 0.9)` — dark amber
- Border: `Color(1.0, 0.8, 0.1, 1.0)` — bright gold
- Font color: `Color(1.0, 0.85, 0.2, 1.0)` — gold

This matches the existing `_apply_condition_met_style()` colors used for individual item cards in
the armory, creating a consistent visual language for "unlockable content available".
