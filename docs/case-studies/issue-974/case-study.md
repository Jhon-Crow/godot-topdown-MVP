# Case Study: Issue #974 - Add Progress Bars

## Problem Statement

Issue #974 requested adding progress bars to items with charges (homing bullets, trajectory glasses) to display remaining charges at the moment of use.

### Original Request (Russian → English Translation)

> Add progress bars to items:
> - **Homing bullets, trajectory glasses** - show remaining charges at the moment of use.
>
> **Rule for the future:**
> 1. If an item has a number of charges (in units) and there's no way to organically incorporate their counter (like done for teleport and force field) - add a progress bar with divisions, appearing at the moment of use.
> 2. If an item can be used unlimited times but has limited active time (like force shield) - show a decreasing progress bar without divisions when activated.

## Timeline of Events

| Date | Event |
|------|-------|
| 2026-03-05 | Issue #974 created by Jhon-Crow |
| 2026-03-11 | Analysis and implementation started |

## Existing Implementation Analysis

### Prior Art: ActiveItemProgressBar Component

The codebase already had `ActiveItemProgressBar` (`scripts/components/active_item_progress_bar.gd`) supporting two display modes:

1. **SEGMENTED** - Discrete charge segments for charge-limited items
2. **CONTINUOUS** - Smooth progress bar for time-limited items

### Items Analyzed

| Item | Charges | Duration | Prior Display |
|------|---------|----------|---------------|
| Homing Bullets | 2 per battle | 1.2s each | CONTINUOUS timer bar |
| Trajectory Glasses | 2 per battle | 10s each | Custom HUD with pips + timer |
| Force Field | Depletable (8s total) | N/A | CONTINUOUS timer bar |
| Teleport Bracers | 6 per battle | Instant | Built-in counter display |

## Root Cause Analysis

### Homing Bullets
The original implementation showed a CONTINUOUS timer bar during activation, then briefly showed a SEGMENTED charge bar when the effect ended. This was inconsistent with the requested behavior of showing remaining charges **at the moment of use**.

**File:** `scripts/characters/player.gd`
**Functions affected:**
- `_on_homing_activated_show_bar()` - showed timer bar instead of charge bar
- `_update_charge_bar_timer()` - continuously updated timer bar during active effect

### Trajectory Glasses
Had its own custom HUD (`scripts/ui/trajectory_glasses_hud.gd`) showing charge pips, but wasn't using the standardized `ActiveItemProgressBar` component for consistency.

## Solution

### Design Decision

Follow the established rule:
1. **Charge-based items** → SEGMENTED progress bar showing remaining charges
2. **Time-limited items** (unlimited uses) → CONTINUOUS progress bar

### Implementation Changes

#### 1. Homing Bullets (`player.gd`)

**Before:**
```gdscript
func _on_homing_activated_show_bar() -> void:
    _show_active_item_timer_bar(HOMING_DURATION, HOMING_DURATION)
    _charge_bar_hide_pending = true
    _charge_bar_hide_timer = CHARGE_BAR_HIDE_DELAY
```

**After:**
```gdscript
func _on_homing_activated_show_bar() -> void:
    _show_active_item_charge_bar(_homing_charges, HOMING_MAX_CHARGES)
    _charge_bar_hide_pending = false
```

#### 2. Trajectory Glasses (`player.gd`)

Added standard progress bar integration alongside existing custom HUD:

```gdscript
func _on_trajectory_activated(charges_remaining: int) -> void:
    # ... existing HUD code ...
    _show_active_item_charge_bar(charges_remaining, _trajectory_glasses.MAX_CHARGES)
```

## Visual Behavior

### Homing Bullets
1. Player presses Space → Segmented bar appears showing remaining charges (0-2 segments filled)
2. Bar stays visible during 1.2s effect duration
3. Effect ends → Bar auto-hides after 300ms

### Trajectory Glasses
1. Player presses Space → Segmented bar appears showing remaining charges (0-2 segments filled)
2. Custom HUD also shows charge pips + timer countdown
3. Effect ends after 10s → Bar auto-hides after 300ms

## Technical References

- [Godot ProgressBar Documentation](https://docs.godotengine.org/en/stable/classes/class_progressbar.html)
- [Segmented Bar Addon for Godot 4](https://github.com/Astridson/godot-segmented-bar)
- [Procedural Segmented Progress Bar Shader](https://godotshaders.com/shader/procedural-segmented-bar/)

## Testing Considerations

1. Verify segmented bar shows correct number of filled segments
2. Verify bar appears immediately on item activation
3. Verify bar hides after deactivation delay
4. Verify trajectory glasses shows both custom HUD and standard progress bar
5. Verify no visual conflicts between overlapping UI elements

## Files Modified

- `scripts/characters/player.gd` - Progress bar activation logic for homing bullets and trajectory glasses

## Conclusion

The implementation follows the established rules:
- **Charge-based items** (homing bullets, trajectory glasses) → Segmented progress bar with divisions
- **Time-limited items** (force field) → Continuous decreasing bar (unchanged)

This provides consistent visual feedback to players about item charge status at the moment of use.
