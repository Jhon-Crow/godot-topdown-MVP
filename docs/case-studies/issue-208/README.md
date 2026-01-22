# Case Study: Issue #208 - Fix Shotgun Reload UI

## Issue Summary
**Issue**: fix ui (fix shotgun reloading UI)
**Date**: 2026-01-22
**Repository**: Jhon-Crow/godot-topdown-MVP

## Problem Description
When reloading the shotgun one shell at a time, the ammo counter in the UI should update immediately as each shell is loaded. Instead, the counter was only updating after firing the weapon.

### Expected Behavior
- Player loads shell (shell #1) -> Ammo counter shows "1/X"
- Player loads shell (shell #2) -> Ammo counter shows "2/X"
- (repeat until tube is full)

### Actual Behavior
- Player loads shell #1 -> Counter stays at "0/X"
- Player loads shell #2 -> Counter stays at "0/X"
- Player fires -> Counter updates to "1/X" (now incorrect since one shell was consumed)

## Timeline of Events

### Phase 1: Initial Investigation (PR #209 v1)
- **Problem Identified**: Missing signal connection in `building_level.gd`
- **Fix Applied**: Added `ShellCountChanged` signal handler to `building_level.gd`
- **Result**: Fix worked for building_level.tscn scene

### Phase 2: User Testing Feedback
- **User Report**: "Changes didn't appear" (in Russian)
- **User's Game Log**: `logs/game_log_20260122_081333.txt`
- **Key Observations from Log**:
  - User tested on Tutorial level (line 84: "Tutorial level detected")
  - Shotgun was equipped via armory menu (line 80)
  - Sound propagation working correctly
  - No error messages about signal connections

### Phase 3: Root Cause Discovery
The initial fix was **incomplete** - only `building_level.gd` was updated, but:
- `tutorial_level.gd` - NOT fixed (user tested here!)
- `test_tier.gd` - NOT fixed

Each level script has its own signal connection logic, and all must be updated.

## Root Cause Analysis

### Architecture Overview
The game uses a signal-based communication pattern between weapons and UI:

```
Shotgun.cs (C#) -> emits signals -> Level Script (GDScript) -> updates UI labels
```

Each level has its own GDScript controller that sets up signal connections:
- `building_level.gd` - Main combat level
- `tutorial_level.gd` - Tutorial/training level (where user tested)
- `test_tier.gd` - Test arena level

### Signal Flow

#### During Reload (LoadShell method)
```
LoadShell() called
    |
ShellsInTube++
    |
EmitSignal(ShellCountChanged, ShellsInTube, TubeMagazineCapacity)
    |
[X] NOT CONNECTED TO UI (in tutorial_level.gd and test_tier.gd)
```

#### During Firing (Fire method)
```
Fire() called
    |
ShellsInTube--
    |
EmitSignal(AmmoChanged, ShellsInTube, ReserveAmmo)
    |
[OK] CONNECTED: _on_weapon_ammo_changed()
    |
_update_ammo_label_magazine()
```

### The Bug
The level scripts were connected to the following weapon signals:

| Signal | building_level.gd | tutorial_level.gd | test_tier.gd |
|--------|-------------------|-------------------|--------------|
| AmmoChanged | OK (connected) | OK (connected) | OK (connected) |
| MagazinesChanged | OK (connected) | N/A | OK (connected) |
| Fired | OK (connected) | N/A | OK (connected) |
| ShellCountChanged | OK (fixed v1) | NOT connected | NOT connected |

### Key Files Involved
1. **Scripts/Weapons/Shotgun.cs** - Shotgun weapon implementation
   - `LoadShell()` method (line 534-569) - emits `ShellCountChanged`
   - `Fire()` method (line 612-684) - emits `AmmoChanged`

2. **scripts/levels/building_level.gd** - Building level UI controller
   - Fixed in PR #209 v1

3. **scripts/levels/tutorial_level.gd** - Tutorial level UI controller
   - `_setup_ammo_tracking()` (line 243-271) - signal connections
   - **MISSING** ShellCountChanged connection

4. **scripts/levels/test_tier.gd** - Test tier UI controller
   - `_setup_player_tracking()` (line 87-148) - signal connections
   - **MISSING** ShellCountChanged connection
   - Also missing Shotgun weapon detection (only handled AssaultRifle)

## Solution

### Implementation (v2 - Complete Fix)

#### 1. tutorial_level.gd
Added connection in `_setup_ammo_tracking()`:
```gdscript
# Connect to ShellCountChanged for real-time UI update during shell-by-shell reload
if shotgun.has_signal("ShellCountChanged"):
    shotgun.ShellCountChanged.connect(_on_shell_count_changed)
```

Added handler function:
```gdscript
## Called when shotgun shell count changes (during shell-by-shell reload).
## This allows the ammo counter to update immediately as each shell is loaded.
func _on_shell_count_changed(shell_count: int, _capacity: int) -> void:
    # Get the reserve ammo from the weapon for display
    var reserve_ammo: int = 0
    if _player:
        var shotgun = _player.get_node_or_null("Shotgun")
        if shotgun != null and shotgun.get("ReserveAmmo") != null:
            reserve_ammo = shotgun.ReserveAmmo
    _update_ammo_label_magazine(shell_count, reserve_ammo)
```

#### 2. test_tier.gd
Added Shotgun weapon detection:
```gdscript
# First try shotgun (if selected), then assault rifle
var weapon = _player.get_node_or_null("Shotgun")
if weapon == null:
    weapon = _player.get_node_or_null("AssaultRifle")
```

Added signal connection:
```gdscript
# Connect to ShellCountChanged for shotgun - updates ammo UI during shell-by-shell reload
if weapon.has_signal("ShellCountChanged"):
    weapon.ShellCountChanged.connect(_on_shell_count_changed)
```

Added handler function (same as tutorial_level.gd).

### Files Changed (Complete Fix)
- `scripts/levels/building_level.gd` - v1 fix (already done)
- `scripts/levels/tutorial_level.gd` - v2 fix (this update)
- `scripts/levels/test_tier.gd` - v2 fix (this update)

## Lessons Learned

### 1. Code Duplication Issue
The same signal connection logic is duplicated across multiple level scripts. This made it easy to miss updating all instances.

**Recommendation**: Consider creating a shared utility class or autoload that handles weapon signal connections, reducing code duplication.

### 2. Testing Coverage
The initial fix was tested only conceptually (code review). The user discovered the issue by testing on a different level.

**Recommendation**: When fixing signal-related bugs, search for ALL instances of similar signal connection code and update them all.

### 3. User Feedback Value
The user's Russian comment "probably language/import conflict, changes didn't appear" led to investigating why the fix didn't work, revealing the incomplete fix.

## Prevention

To prevent similar issues in the future:
1. **Search for all instances** - When fixing signal connections, search the codebase for all files that might have similar logic
2. **Document level scripts** - Maintain a list of all level scripts that need weapon signal handling
3. **Consider refactoring** - Extract common signal handling to a shared utility
4. **Test on all levels** - When fixing UI issues, test on multiple level types

## Related Resources

### Game Log Files
- `logs/game_log_20260122_081333.txt` - User's testing session log

### Related Code References
- `Scripts/Weapons/Shotgun.cs:567` - ShellCountChanged signal emission during reload
- `scripts/levels/building_level.gd:203` - Signal connection (v1 fix)
- `scripts/levels/tutorial_level.gd:256` - Signal connection (v2 fix)
- `scripts/levels/test_tier.gd:115` - Signal connection (v2 fix)
