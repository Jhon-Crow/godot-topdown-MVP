# Case Study: Issue #974 - Add Progress Bars to Items

## Issue Summary

**Issue:** [#974](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/974)
**Title:** добавить прогрессбары (Add Progress Bars)
**Date:** 2026-03-11

### Requirements

The issue requests adding progress bars to items with the following rules:

1. **Charge-based items** (like Homing Bullets, Trajectory Glasses):
   - Show remaining charges when using
   - Display segmented progress bar with divisions that appears during use
   - Apply when charges cannot be organically shown (unlike Teleport and Force Field which already have counters)

2. **Time-based items** (like Force Shield):
   - Show decreasing progress bar without divisions when activated
   - For items that can be used unlimited times but have limited active time

### Items Requiring Progress Bars

| Item | Type | Charges | Duration | Current Status |
|------|------|---------|----------|----------------|
| Homing Bullets | Charge + Timer | 2 charges | 1.2s each | Partially implemented |
| Trajectory Glasses | Charge + Timer | 2 charges | 10s each | Has custom HUD |
| Teleport Bracers | Charge only | 6 charges | instant | Reference (organic counter) |
| Force Field | Time only | N/A | 8s total | Reference (organic display) |

## Timeline of Events

1. **Initial Implementation**: `ActiveItemProgressBar` component created with:
   - `SEGMENTED` mode for charge-based display
   - `CONTINUOUS` mode for time-based display
   - Positioned above player, auto-hiding behavior

2. **Homing Bullets Integration**:
   - Connected to `homing_activated` and `homing_deactivated` signals
   - Shows timer bar during active effect
   - Shows charge bar briefly (300ms) after deactivation

3. **Trajectory Glasses**: Has separate `TrajectoryGlassesHUD` with:
   - Charge pips (small rectangles)
   - Timer bar during active effect
   - Does NOT use `ActiveItemProgressBar`

## Current Implementation Analysis

### ActiveItemProgressBar Component (`scripts/components/active_item_progress_bar.gd`)

```
- DisplayMode.SEGMENTED: Draws discrete segments
- DisplayMode.CONTINUOUS: Draws smooth bar
- Colors change based on percentage (green >50%, yellow >25%, red <=25%)
- Positioned at BAR_Y_OFFSET = -30.0 above player
- Width: 40px, Height: 6px
```

### Player Integration (`scripts/characters/player.gd` lines 3840-3952)

```
- _show_active_item_charge_bar(current, max): SEGMENTED mode
- _show_active_item_timer_bar(time_remaining, max_time): CONTINUOUS mode
- Auto-hide after 300ms via _charge_bar_hide_timer
- Homing bullets: Shows timer during active, then charge bar briefly
```

### Trajectory Glasses HUD (`scripts/ui/trajectory_glasses_hud.gd`)

```
- Separate implementation, doesn't use ActiveItemProgressBar
- Shows charge pips (small colored rectangles)
- Shows timer bar during active effect
- Positioned at OFFSET_Y = -40.0
```

## Root Cause Analysis

### Problem 1: Inconsistent Implementations

The trajectory glasses use a completely separate HUD implementation instead of the shared `ActiveItemProgressBar`. This causes:
- Code duplication
- Inconsistent visual appearance
- Different positioning (Y offset differs)

### Problem 2: Homing Bullets Progress Bar Logic

Current behavior in player.gd:
1. On activation: Shows timer bar (continuous)
2. On deactivation: Shows charge bar briefly, then hides

**Gap:** The charge bar is only shown AFTER use, not during. Users cannot see remaining charges while the effect is active.

### Problem 3: Missing Unified Approach

No documented pattern for:
- When to show charge vs timer bars
- Where to position bars relative to other UI
- How to combine charge + timer displays

## Proposed Solutions

### Solution 1: Unify Implementation

Migrate `TrajectoryGlassesHUD` functionality into `ActiveItemProgressBar` to have a single component that can:
- Show charge segments
- Show timer bar
- Support showing both simultaneously (charge pips + timer bar)

### Solution 2: Enhanced Display Rules

For charge-limited items with active duration:
1. When activated: Show BOTH charge segments AND timer bar
2. Timer bar decreases during active effect
3. Charge segments show remaining uses
4. Hide after brief delay when effect ends

### Solution 3: Documentation

Create a design pattern document for future items:
```
RULE 1: Charge-only items (e.g., Teleport) -> Show segmented bar on use
RULE 2: Time-only items (e.g., Force Shield) -> Show continuous bar while active
RULE 3: Charge+Time items (e.g., Homing) -> Show both: charge pips + timer bar
```

## External Resources

- [Godot Segmented Bar Addon](https://github.com/Astridson/godot-segmented-bar) - Reference implementation
- [Procedural Segmented Progress Bar Shader](https://godotshaders.com/shader/procedural-segmented-bar/) - Shader approach
- [ProgressBar Documentation (Godot 4.4)](https://docs.godotengine.org/en/4.4/classes/class_progressbar.html)

## Implementation Plan

1. **Enhance ActiveItemProgressBar**:
   - Add combined mode showing both charges and timer
   - Standardize positioning

2. **Update Homing Bullets**:
   - Show charge pips during active effect
   - Timer bar depletes below charge pips

3. **Migrate Trajectory Glasses**:
   - Use enhanced ActiveItemProgressBar
   - Remove duplicate TrajectoryGlassesHUD (or keep for backward compat)

4. **Document Pattern**:
   - Add guidelines to CONTRIBUTING.md or CLAUDE.md

## Files Involved

- `scripts/components/active_item_progress_bar.gd` - Core component
- `scripts/characters/player.gd` - Item integration
- `scripts/ui/trajectory_glasses_hud.gd` - Current separate implementation
- `scripts/effects/trajectory_glasses_effect.gd` - Effect controller
- `tests/unit/test_active_item_progress_bar.gd` - Unit tests

## Implementation Results

### Changes Made

1. **ActiveItemProgressBar Enhanced** (`scripts/components/active_item_progress_bar.gd`):
   - Added `DisplayMode.COMBINED` for items with both charges AND duration
   - Added `show_combined_bar(charges_current, charges_max, time_remaining, time_max)` method
   - Added `update_timer(time_remaining)` and `update_charges(charges_current)` methods
   - Combined mode draws charge pips on top, timer bar below

2. **Homing Bullets Updated** (`scripts/characters/player.gd`):
   - `_on_homing_activated_show_bar()` now shows combined bar
   - Timer updates via `_update_charge_bar_timer()` in physics process
   - After deactivation, shows segmented charge bar briefly

3. **Trajectory Glasses Updated** (`scripts/characters/player.gd`):
   - `_on_trajectory_activated()` now shows combined bar
   - Timer updates continuously during active state
   - After deactivation, shows segmented charge bar briefly

4. **Tests Added** (`tests/unit/test_active_item_progress_bar.gd`):
   - Combined mode tests for charge and timer values
   - Homing bullets integration tests with combined bar

---

## Rules for Future Items (Issue #974)

### When to Show Progress Bars

| Item Type | Display Mode | When to Show | Example |
|-----------|--------------|--------------|---------|
| Charge-only | SEGMENTED | On use, briefly after | Teleport Bracers |
| Time-only | CONTINUOUS | While active | Force Shield |
| Charge + Time | COMBINED | During activation | Homing Bullets, Trajectory Glasses |

### Implementation Pattern for New Items

```gdscript
# For charge-only items (e.g., Teleport Bracers):
func _on_item_used() -> void:
    _show_active_item_charge_bar(charges_remaining, max_charges)
    _charge_bar_hide_pending = true
    _charge_bar_hide_timer = CHARGE_BAR_HIDE_DELAY

# For time-only items (e.g., Force Shield):
func _on_item_activated() -> void:
    _show_active_item_timer_bar(duration, max_duration)

func _on_item_active_update(delta: float) -> void:
    _update_active_item_bar(time_remaining)

# For charge + time items (e.g., Homing Bullets, Trajectory Glasses):
func _on_item_activated() -> void:
    _show_active_item_combined_bar(
        charges_remaining,
        max_charges,
        duration,
        max_duration
    )

func _on_item_active_update(delta: float) -> void:
    _update_active_item_timer(time_remaining)

func _on_item_deactivated() -> void:
    _show_active_item_charge_bar(charges_remaining, max_charges)
    _charge_bar_hide_pending = true
    _charge_bar_hide_timer = CHARGE_BAR_HIDE_DELAY
```

### Visual Design

- **Charge pips**: Small colored rectangles (4px height) showing remaining uses
- **Timer bar**: Horizontal bar (3px height) showing remaining activation time
- **Colors**:
  - Green: >50% remaining
  - Yellow: 25-50% remaining
  - Red: <25% remaining
  - Cyan: Timer bar fill (distinct from charge color)

### Position

- Progress bar positioned at Y offset -30px above player center
- In combined mode: charge pips at -30px, timer bar at -30px + 4px + 2px gap = -24px
