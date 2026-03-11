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
| 2026-03-11 | Initial implementation completed (PR #1008) |
| 2026-03-11 | User reported progress bars not appearing |
| 2026-03-11 | Investigation and debug logging added |

## Investigation: Progress Bars Not Appearing

### User Report

On 2026-03-11, the repository owner reported that progress bars were not showing up. A game log file was attached: `game_log_20260311_235157.txt` (stored in `logs/` subfolder).

### Log Analysis

The game log was analyzed to trace why progress bars were not appearing.

#### Expected Log Entries (Not Found)

The following log entries SHOULD appear when progress bar system is properly initialized:
- `[Player.ProgressBar] Active item progress bar initialized (Issue #700)` - NOT FOUND

#### Observed Log Entries

From the log file:
```
[23:51:57] [INFO] [Player.Homing] Homing bullets equipped, charges: 2/2
[23:51:57] [INFO] [Player.TrajectoryGlasses] No trajectory glasses selected in ActiveItemManager
[23:51:57] [INFO] [Player] Ready! Ammo: 30/30, Grenades: 1/3, Health: 3/4
...
[23:52:04] [INFO] [Player.Homing] Homing activated! Duration: 1,2s, charges remaining: 1/2
```

The homing bullets ARE being activated, but there's no log entry for the progress bar being shown.

### Root Cause Hypothesis

The `_init_active_item_progress_bar()` function in `player.gd` returns early if `ActiveItemManager` is null:

```gdscript
func _init_active_item_progress_bar() -> void:
    var active_item_manager: Node = get_node_or_null("/root/ActiveItemManager")
    if active_item_manager == null:
        return  # Silent return with no logging!
```

However, the log shows `ActiveItemManager` IS present:
```
[23:51:57] [INFO] [ActiveItemManager] Active item changed from None to Homing Bullets
```

This is contradictory. The function should NOT return early, yet the log message at the end of the function is not appearing.

### Investigation Actions

1. **Added debug logging** to trace progress bar initialization:
   - `_init_active_item_progress_bar()` - logs when ActiveItemManager is not found
   - `_init_active_item_progress_bar()` - logs when signals are connected
   - `_ensure_progress_bar_node()` - logs when progress bar node is created
   - `_show_active_item_charge_bar()` - logs when segmented bar is shown
   - `_on_homing_activated_show_bar()` - logs when activation callback fires
   - `_on_trajectory_activated()` - logs when trajectory glasses callback fires
   - `_on_homing_deactivated_hide_bar()` - logs when hide is scheduled

2. **Preserved game log** in `docs/case-studies/issue-974/logs/` for future analysis

### Next Steps

With the added debug logging, the next test run will provide detailed trace information to pinpoint exactly where the progress bar display is failing.

---

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

## Original Implementation (PR #1008)

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
6. **Check debug logs** for `[Player.ProgressBar]` entries to trace initialization

## Files Modified

- `scripts/characters/player.gd` - Progress bar activation logic for homing bullets and trajectory glasses

## Conclusion

The implementation follows the established rules:
- **Charge-based items** (homing bullets, trajectory glasses) → Segmented progress bar with divisions
- **Time-limited items** (force field) → Continuous decreasing bar (unchanged)

Debug logging has been added to trace the exact sequence of events when the progress bar system initializes and when items are activated. This will help diagnose why progress bars are not appearing for the user.
