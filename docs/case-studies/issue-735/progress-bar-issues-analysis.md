# Issue #735 - Progress Bar Issues Analysis

## Problem Summary

After resolving the merge conflicts from PR #701, two issues were reported by the user (Jhon-Crow):

1. **Teleport bracers**: Charge count displayed **always** instead of only for 300ms after activation
2. **Homing bullets**: **No progress bar** displayed at all

## Investigation Timeline

### Data Collection

1. **Game Log Analysis** (`game_log_20260210_220018.txt`):
   - Confirmed teleport bracers are working (multiple teleport events logged)
   - Confirmed homing bullets are working (activation/deactivation logged)
   - No errors in the log related to progress bars

2. **PR #701 Diff Analysis**:
   - Original implementation included progress bar infrastructure (`ActiveItemProgressBar` class)
   - GDScript `player.gd` was supposed to connect homing signals to progress bar
   - C# `Player.cs` implemented teleport charge bar directly in `_Draw()` method

### Root Cause Analysis

#### Issue 1: Teleport Charge Bar Always Visible

**Location**: `Scripts/Characters/Player.cs:4930-4936`

**Problem Code**:
```csharp
public override void _Draw()
{
    // Draw teleport bracers charge bar above player (Issue #700)
    if (_teleportBracersEquipped)
    {
        DrawTeleportChargeBar();
    }
```

**Root Cause**: The condition only checks if teleport bracers are equipped, not whether the bar should be visible. According to PR #701 design, the charge bar should only show for 300ms after teleport activation, then auto-hide.

**Missing Components**:
- No timer variable to track the 300ms delay
- No visibility flag to control when the bar should be drawn
- No timer update logic in `_PhysicsProcess`

#### Issue 2: Homing Bullets No Progress Bar

**Location**: `scripts/characters/player.gd:3234-3247`

**Problem Code**:
```gdscript
func _init_active_item_progress_bar() -> void:
	var active_item_manager: Node = get_node_or_null("/root/ActiveItemManager")
	if active_item_manager == null:
		return

	# Currently no GDScript active items have limited usage
	# (flashlight is unlimited). Progress bar infrastructure is ready
	# for future limited items...
	FileLogger.info("[Player.ProgressBar] Active item progress bar initialized (Issue #700)")
```

**Root Cause**: The merge conflict resolution preserved the old comment saying "no GDScript active items have limited usage", but **homing bullets ARE a limited-usage active item** (6 charges per battle, 1-second duration each activation).

**Missing Components**:
- No signal connections to homing bullet events
- No timer logic for the 300ms auto-hide delay
- No call to update progress bar during homing activation

## Expected Behavior (from PR #701)

### Homing Bullets Progress Bar Flow:

1. **On Activation** (Space pressed):
   - Show continuous timer bar (1.0s / 1.0s)
   - Update bar each frame during active effect
   - When timer expires, show charge bar for 300ms

2. **During Active Effect**:
   - Continuous bar shows remaining time (e.g., 0.7s / 1.0s)
   - Bar color changes based on percentage: Green > 50%, Yellow > 25%, Red < 25%

3. **After Deactivation**:
   - Switch to segmented charge bar (e.g., 5/6 charges)
   - Auto-hide after 300ms

### Teleport Bracers Progress Bar Flow:

1. **On Teleport** (Space released):
   - Show segmented charge bar (e.g., 5/6 charges)
   - Start 300ms timer

2. **During Timer**:
   - Bar remains visible

3. **After 300ms**:
   - Hide bar automatically

## Solution Implementation

### Fix 1: C# Teleport Charge Bar Timer

**Files Modified**: `Scripts/Characters/Player.cs`

**Added Variables** (lines 665-681):
```csharp
/// <summary>
/// Timer for auto-hiding charge bar after teleport (300ms delay).
/// </summary>
private float _teleportChargeBarHideTimer = 0.0f;

/// <summary>
/// Whether the charge bar should be shown (for 300ms after teleport).
/// </summary>
private bool _teleportChargeBarVisible = false;

/// <summary>
/// Duration to show charge bar after teleport before auto-hiding (in seconds).
/// </summary>
private const float TeleportChargeBarHideDelay = 0.3f;
```

**Modified `ExecuteTeleport()`** to start timer:
```csharp
// Show charge bar for 300ms after teleport (Issue #700)
_teleportChargeBarVisible = true;
_teleportChargeBarHideTimer = TeleportChargeBarHideDelay;
```

**Added Timer Update Method**:
```csharp
private void UpdateTeleportChargeBarTimer(float delta)
{
    if (_teleportChargeBarVisible)
    {
        _teleportChargeBarHideTimer -= delta;
        if (_teleportChargeBarHideTimer <= 0.0f)
        {
            _teleportChargeBarVisible = false;
            QueueRedraw();
        }
    }
}
```

**Updated `_Draw()` Condition**:
```csharp
// Only show for 300ms after teleport activation
if (_teleportBracersEquipped && _teleportChargeBarVisible)
{
    DrawTeleportChargeBar();
}
```

### Fix 2: GDScript Homing Bullets Progress Bar

**Files Modified**: `scripts/characters/player.gd`

**Added Variables** (lines 3221-3229):
```gdscript
## Timer for auto-hiding charge bar after activation (300ms).
var _charge_bar_hide_timer: float = 0.0

## Whether the charge bar hide timer is running.
var _charge_bar_hide_pending: bool = false

## Duration to show charge bar after activation before auto-hiding (in seconds).
const CHARGE_BAR_HIDE_DELAY: float = 0.3
```

**Updated `_init_active_item_progress_bar()`** to connect signals:
```gdscript
# Connect to homing bullets signals to show/hide progress bar on activation
if _homing_equipped:
	homing_activated.connect(_on_homing_activated_show_bar)
	homing_deactivated.connect(_on_homing_deactivated_hide_bar)
	homing_charges_changed.connect(_on_homing_charges_changed)
```

**Added Signal Handlers**:
```gdscript
func _on_homing_activated_show_bar() -> void:
	# Show continuous timer bar during active effect
	_show_active_item_timer_bar(HOMING_DURATION, HOMING_DURATION)
	# Set up charge bar to show briefly after effect ends
	_charge_bar_hide_pending = true
	_charge_bar_hide_timer = CHARGE_BAR_HIDE_DELAY

func _on_homing_deactivated_hide_bar() -> void:
	_show_active_item_charge_bar(_homing_charges, HOMING_MAX_CHARGES)
	_charge_bar_hide_pending = true
	_charge_bar_hide_timer = CHARGE_BAR_HIDE_DELAY
```

**Added Timer Update Method**:
```gdscript
func _update_charge_bar_timer(delta: float) -> void:
	# Update continuous timer bar while homing is active
	if _homing_equipped and _homing_active:
		_show_active_item_timer_bar(_homing_timer, HOMING_DURATION)

	# Handle charge bar auto-hide (300ms delay for charge-based items)
	if _charge_bar_hide_pending and not _homing_active:
		_charge_bar_hide_timer -= delta
		if _charge_bar_hide_timer <= 0.0:
			_charge_bar_hide_pending = false
			_hide_active_item_bar()
```

## Technical Details

### ActiveItemProgressBar Component

The progress bar component (`scripts/components/active_item_progress_bar.gd`) supports two modes:

1. **SEGMENTED**: Discrete charge indicators (e.g., 5 filled boxes out of 6)
   - Used for: Teleport bracers, homing bullets (when inactive)

2. **CONTINUOUS**: Smooth progress bar (e.g., filling bar showing time remaining)
   - Used for: Homing bullets (during active effect)

### Visual Specifications

- **Position**: 30 pixels above player center
- **Size**: 40px width × 6px height
- **Colors**:
  - High (>50%): Green `(0.2, 0.8, 0.4, 0.85)`
  - Medium (25-50%): Yellow `(0.9, 0.7, 0.1, 0.85)`
  - Low (<25%): Red `(0.9, 0.2, 0.2, 0.85)`
- **Auto-hide Delay**: 300ms (0.3 seconds)

## Testing Recommendations

### Manual Testing Checklist

1. **Teleport Bracers**:
   - [ ] Charge bar appears when teleport completes
   - [ ] Bar shows correct charge count (e.g., 5/6)
   - [ ] Bar disappears after 300ms
   - [ ] Bar does not appear when just walking around
   - [ ] Bar color changes based on charge percentage

2. **Homing Bullets**:
   - [ ] Continuous timer bar appears when activated
   - [ ] Bar updates smoothly during 1-second duration
   - [ ] After 1 second, switches to charge bar
   - [ ] Charge bar shows correct count (e.g., 5/6)
   - [ ] Charge bar disappears after 300ms
   - [ ] Multiple activations work correctly

### Edge Cases

1. **Rapid Activation**: Press Space multiple times quickly
   - Expected: Each activation should reset the timer

2. **Scene Change**: Switch levels while bar is visible
   - Expected: No errors, bar state resets on new level

3. **Zero Charges**: Use all charges
   - Expected: Bar shows 0/6 in red, still auto-hides

## References

- Original PR: #701
- Related Issues: #700 (Progress bars feature), #735 (This fix)
- Component: `scripts/components/active_item_progress_bar.gd`
- Test File: `tests/unit/test_active_item_progress_bar.gd`
