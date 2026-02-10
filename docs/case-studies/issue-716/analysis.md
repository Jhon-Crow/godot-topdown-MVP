# Case Study: Issue #716 - fix револьвер (Revolver Bug Fix)

## Issue Summary

**Issue Number:** #716
**Title:** fix револьвер (Fix revolver)
**Date Reported:** 2026-02-09
**Status:** In Progress (v2 - Updated based on user testing feedback)

### Original Requirements

The issue specifies two critical bugs in the revolver implementation:

1. **Empty Cylinder Hammer Cocking**: When the cylinder (барабан) is empty, it should be possible to cock the hammer (взвести курок).
2. **Empty Slot Click Sound**: When trying to fire from an empty cylinder slot, instead of a shot, the sound `assets/audio/Щелчок пустого револьвера.mp3` should play.

### Updated Requirements (from Jhon-Crow's Feedback - 2026-02-10)

The repository owner clarified the expected behavior with detailed testing feedback:

1. **Empty Slot Hammer Cocking**: Should be able to cock hammer when:
   - Current selected slot is empty, OR
   - Entire cylinder is empty
   - **(Not working in initial fix)**

2. **Uncocked Fire (LMB without prior RMB)**:
   - First, cylinder rotates to NEXT position
   - Then, shot happens from the NEW slot (after rotation)

3. **Cocked Fire (LMB after RMB cock)**:
   - Fires from CURRENT slot (no rotation before firing)
   - Either successful shot or empty click, depending on chamber state

## Technical Analysis

### v1 Analysis (Initial - Incorrect)

The initial analysis focused on:
- Removing `CurrentAmmo <= 0` check from `ManualCockHammer()`
- Adding empty click sound in `ExecuteShot()`

This fix was **incomplete** because it didn't address the cylinder rotation timing issue.

### v2 Analysis (Updated - Correct)

#### Root Cause 1: Cylinder Rotation Timing

**Problem:** The original code rotated the cylinder **AFTER** firing (in `ExecuteShot()`), but for uncocked fire, the cylinder should rotate **BEFORE** the shot.

**Relevant Code (Before Fix):**
```csharp
// In Fire() - checked current chamber BEFORE any rotation
bool currentChamberHasRound = _chamberOccupied[_currentChamberIndex];
if (!currentChamberHasRound)
{
    PlayEmptyClickSound();  // Click from CURRENT slot
    return false;
}

// In ExecuteShot() - rotated AFTER firing
_currentChamberIndex = (_currentChamberIndex + 1) % _chamberOccupied.Length;
```

**Expected Behavior:**
- For **uncocked LMB**: Rotate first, then check/fire from NEW slot
- For **cocked LMB**: Fire from CURRENT slot (no rotation)

#### Root Cause 2: Empty Chamber Check in ManualCockHammer

**Problem:** Issue #691 introduced per-chamber checking which blocked hammer cocking when current chamber was empty.

```csharp
// Issue #691 code - blocks cocking on empty chamber
if (!currentChamberHasRound)
{
    PlayEmptyClickSound();
    GD.Print($"[Revolver] Cannot cock - chamber {_currentChamberIndex} is empty");
    return false;
}
```

**Real Revolver Behavior:** Hammer can be cocked regardless of chamber state. The empty click occurs on trigger pull, not during cocking.

### Codebase Structure

The revolver implementation consists of:

1. **Revolver.cs** - Main weapon logic (C# script at `Scripts/Weapons/Revolver.cs`)
2. **audio_manager.gd** - Audio playback system (GDScript at `scripts/autoload/audio_manager.gd`)
3. **player.gd** - Player controller (GDScript at `scripts/characters/player.gd`)
4. **RevolverCylinderUI.cs** - Cylinder HUD (Issue #691)
5. **Test files**:
   - `tests/unit/test_revolver_hammer_cock.gd`
   - `tests/unit/test_revolver_reload.gd`
   - `tests/unit/test_revolver_cylinder_ui.gd`

## Timeline of Events

### Historical Context

1. **Issue #626** - Multi-step cylinder reload system implemented
2. **Issue #649** - Manual hammer cocking (RMB) feature added
3. **Issue #659** - One cartridge per slot enforcement
4. **Issue #661** - Hammer cock delay and sound added
5. **Issue #668** - Per-chamber occupancy tracking
6. **Issue #691** - Cylinder HUD and per-chamber fire logic
7. **Issue #716** - Current issue: Cylinder rotation timing and empty cocking

### Bug Introduction Analysis

1. **Original Issue #649**: Introduced manual cocking with `CurrentAmmo <= 0` check
2. **Issue #691**: Changed to per-chamber checking but made cocking logic MORE restrictive
3. **Issue #716 v1 Fix**: Removed check but didn't fix rotation timing
4. **Issue #716 v2 Fix**: Complete rewrite of fire sequence logic

## Solution Implementation (v2)

### Fix 1: Allow Empty Chamber Hammer Cocking

**Location:** `ManualCockHammer()` method

**Change:** Removed the per-chamber check entirely. Hammer can be cocked at any time (except when already cocked or cylinder is open).

```csharp
// Issue #716: Allow hammer cocking even with empty current chamber.
// Real revolvers can cock the hammer regardless of ammo state - the hammer
// mechanism is independent of whether chambers are loaded. The empty click
// occurs when firing (trigger pull), not during cocking.
```

### Fix 2: Correct Cylinder Rotation Timing

**Location:** `Fire()` method

**For Cocked Fire (hammer already cocked via RMB):**
```csharp
if (_isManuallyHammerCocked)
{
    _isManuallyHammerCocked = false;

    // Check current chamber for cocked fire - click or shoot
    bool currentChamberHasRound = _chamberOccupied[_currentChamberIndex];

    if (!currentChamberHasRound)
    {
        PlayEmptyClickSound();
        GD.Print($"[Revolver] Click - cocked hammer on empty chamber");
        return true; // Action performed
    }

    ExecuteShot(direction);
    return true;
}
```

**For Uncocked Fire (normal LMB):**
```csharp
// Issue #716: Rotate cylinder FIRST before hammer cock animation
int oldChamberIndex = _currentChamberIndex;
_currentChamberIndex = (_currentChamberIndex + 1) % _chamberOccupied.Length;
GD.Print($"[Revolver] Cylinder rotated from {oldChamberIndex} to {_currentChamberIndex}");

// Then cock hammer - shot happens after delay from NEW position
_isHammerCocked = true;
_hammerCockTimer = HammerCockDelay;
_pendingShotDirection = direction;
```

### Fix 3: Remove Double Rotation

**Location:** `ExecuteShot()` method

**Change:** Removed cylinder rotation after firing (was causing double rotation for uncocked shots):
```csharp
// Issue #716: Do NOT rotate cylinder here - rotation already happened in Fire()
// for uncocked shots. For cocked shots, cylinder stays at current position.
if (_chamberOccupied.Length > 0)
{
    _chamberOccupied[_currentChamberIndex] = false;
    // REMOVED: _currentChamberIndex = (_currentChamberIndex + 1) % _chamberOccupied.Length;
}
```

## Testing Strategy

### Test Cases

1. **Empty Cylinder Hammer Cock:**
   - Fire all rounds (empty cylinder)
   - Press RMB to manually cock hammer
   - **Expected:** Hammer cocks successfully, sounds play
   - **Status:** Fixed in v2

2. **Empty Current Slot Hammer Cock:**
   - Partially loaded cylinder
   - Rotate to empty slot using scroll wheel
   - Press RMB to cock
   - **Expected:** Hammer cocks successfully
   - **Status:** Fixed in v2

3. **Uncocked Fire - Cylinder Rotation:**
   - Loaded cylinder, slot 0 selected
   - Press LMB (uncocked)
   - **Expected:** Cylinder rotates to slot 1, fires from slot 1
   - **Status:** Fixed in v2

4. **Cocked Fire - No Rotation:**
   - Loaded cylinder, slot 0 selected
   - Press RMB to cock, then LMB to fire
   - **Expected:** Fires from slot 0 (current), no rotation before shot
   - **Status:** Fixed in v2

5. **Cocked Fire on Empty Slot:**
   - Rotate to empty slot
   - Press RMB to cock
   - Press LMB to fire
   - **Expected:** Empty click sound plays
   - **Status:** Fixed in v2

### Game Log Reference

User testing log attached: `game_log_20260210_230952.txt`

Key observations from log:
- Player equipped Revolver (ammo: 5/5)
- Multiple shots fired successfully
- Sound propagation working
- Bullet penetration working

## Risk Assessment

### Changes Made

| Change | Risk Level | Reason |
|--------|------------|--------|
| Allow empty cocking | Low | Adds functionality, no breaking changes |
| Rotation before fire | Medium | Changes fire sequence, needs thorough testing |
| Remove double rotation | Medium | Affects chamber tracking, needs verification |

### Potential Side Effects

1. **Cylinder HUD**: May need adjustment for rotation timing display
2. **Replay System**: Rotation events may record differently
3. **Sound Timing**: Rotation sound plays earlier in sequence

## References

### Related Issues
- #626 - Multi-step cylinder reload
- #649 - Manual hammer cocking (RMB)
- #659 - One cartridge per slot
- #661 - Hammer cock delay
- #668 - Per-chamber occupancy tracking
- #691 - Cylinder HUD and per-chamber logic

### Audio Files
- `assets/audio/Щелчок пустого револьвера.mp3` - Empty revolver click
- `assets/audio/взведение курка револьвера.mp3` - Hammer cock sound
- Various cylinder rotation sounds (random variants)

### Code Locations
- `Scripts/Weapons/Revolver.cs:568-632` - Fire() method
- `Scripts/Weapons/Revolver.cs:672-731` - ManualCockHammer() method
- `Scripts/Weapons/Revolver.cs:738-785` - ExecuteShot() method

## Conclusion

This issue required a deeper understanding of revolver mechanics beyond the initial analysis. The key insight from user testing feedback was that:

1. Uncocked fire should rotate BEFORE firing (not after)
2. Cocked fire should NOT rotate (fire from selected slot)
3. Hammer cocking is purely mechanical (independent of ammo state)

The v2 fix addresses all three requirements and matches real-world single-action revolver behavior where cocking the hammer advances the cylinder, while pulling the trigger on an already-cocked hammer just fires.
