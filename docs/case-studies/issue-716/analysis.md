# Case Study: Issue #716 - fix револьвер (Revolver Bug Fix)

## Issue Summary

**Issue Number:** #716
**Title:** fix револьвер (Fix revolver)
**Date Reported:** 2026-02-09
**Status:** In Progress

### Requirements

The issue specifies two critical bugs in the revolver implementation:

1. **Empty Cylinder Hammer Cocking**: When the cylinder (барабан) is empty, it should be possible to cock the hammer (взвести курок).
2. **Empty Slot Click Sound**: When trying to fire from an empty cylinder slot, instead of a shot, the sound `assets/audio/Щелчок пустого револьвера.mp3` should play.

### Additional Requirement

The issue also requests a deep case study analysis with:
- Timeline/sequence of events reconstruction
- Root cause analysis
- Proposed solutions
- All relevant logs and data compiled to `./docs/case-studies/issue-{id}` folder

## Technical Analysis

### Codebase Structure

The revolver implementation consists of:

1. **Revolver.cs** - Main weapon logic (C# script at `Scripts/Weapons/Revolver.cs`)
2. **audio_manager.gd** - Audio playback system (GDScript at `scripts/autoload/audio_manager.gd`)
3. **player.gd** - Player controller (GDScript at `scripts/characters/player.gd`)
4. **Test files**:
   - `tests/unit/test_revolver_hammer_cock.gd`
   - `tests/unit/test_revolver_reload.gd`

### Root Cause Analysis

#### Problem 1: Empty Cylinder Hammer Cocking Blocked

**Location:** `Scripts/Weapons/Revolver.cs`, lines 573-622 (ManualCockHammer method)

**Current Behavior:**
```csharp
// Lines 587-592
// Cannot cock with empty cylinder
if (CurrentAmmo <= 0)
{
    PlayEmptyClickSound();
    return false;
}
```

**Root Cause:**
The `ManualCockHammer()` method explicitly blocks hammer cocking when `CurrentAmmo <= 0`, playing an empty click sound instead. This was likely implemented as a safety check, but it doesn't match real-world revolver mechanics where the hammer can be cocked regardless of ammunition state.

**Real-World Behavior:**
In a real revolver, the hammer can be cocked even with an empty cylinder. The hammer mechanism is independent of the ammunition state. The empty click occurs when the trigger is pulled (firing pin strikes), not during cocking.

**Impact:**
- Players cannot cock the hammer when the cylinder is empty
- Breaks immersion and realistic weapon mechanics
- Blocks certain gameplay mechanics (e.g., intimidation, pre-cocking before reload)

#### Problem 2: Empty Slot Click Sound

**Location:** `Scripts/Weapons/Revolver.cs`, lines 514-519 (Fire method)

**Current Implementation:**
```csharp
// Check for empty cylinder - play click sound
if (CurrentAmmo <= 0)
{
    PlayEmptyClickSound();
    return false;
}
```

**Analysis:**
The empty click sound implementation appears to be correct. The `Fire()` method properly checks for empty cylinder and calls `PlayEmptyClickSound()`, which is connected to the audio file `assets/audio/Щелчок пустого револьвера.mp3` (line 172 in audio_manager.gd).

**Verification Needed:**
The second requirement might already be working, but needs testing to confirm:
- Does the sound play correctly?
- Is the audio file path correct?
- Are there any edge cases (e.g., partially loaded cylinder with empty chambers)?

### Chamber-by-Chamber Mechanics

The revolver implements advanced per-chamber tracking (Issue #668):

```csharp
// Line 94-100
private bool[] _chamberOccupied = System.Array.Empty<bool>();
private int _currentChamberIndex = 0;
```

**Important Note:**
The revolver tracks each chamber individually. When firing, it should:
1. Check if the current chamber is occupied (`_chamberOccupied[_currentChamberIndex]`)
2. If empty, play the empty click sound
3. If loaded, fire the bullet

**Current Fire Logic:**
The current implementation only checks `CurrentAmmo <= 0` (total ammo), not the individual chamber state. This means:
- If cylinder has 3/5 rounds but current chamber is empty → should click, but might not
- Need to verify chamber-specific empty click behavior

## Timeline of Events

### Historical Context

1. **Issue #626** - Multi-step cylinder reload system implemented
2. **Issue #649** - Manual hammer cocking (RMB) feature added
3. **Issue #659** - One cartridge per slot enforcement
4. **Issue #661** - Hammer cock delay and sound added
5. **Issue #668** - Per-chamber occupancy tracking
6. **Issue #716** - Current issue: Empty cylinder hammer cocking blocked

### Bug Introduction

The hammer cocking restriction was likely introduced in Issue #649 or #661 as a "feature" to prevent cocking with no ammo. However, this doesn't match real revolver behavior and creates the current bug.

## Proposed Solution

### Fix for Problem 1: Allow Empty Cylinder Hammer Cocking

**Modification:** Remove the `CurrentAmmo <= 0` check from `ManualCockHammer()` method.

**Implementation:**
```csharp
// Modified ManualCockHammer() - Remove lines 587-592
public bool ManualCockHammer()
{
    // Cannot cock while cylinder is open
    if (ReloadState != RevolverReloadState.NotReloading)
    {
        return false;
    }

    // Cannot cock if already cocked (either manually or via LMB fire sequence)
    if (_isHammerCocked || _isManuallyHammerCocked)
    {
        return false;
    }

    // CHECK REMOVED: Allow cocking even with empty cylinder
    // Real revolvers can cock the hammer regardless of ammo state

    // Check weapon data and bullet scene are available
    if (WeaponData == null || BulletScene == null)
    {
        return false;
    }

    // ... rest of the method remains unchanged
}
```

**Alternative Approach (More Complex):**
Add a parameter to distinguish between "action cocking" (which should always work) and "firing cocking" (which might have restrictions). However, this adds unnecessary complexity.

### Fix for Problem 2: Verify/Enhance Empty Click Sound

**Option A: Current Implementation is Correct**
If testing confirms the sound works, no changes needed.

**Option B: Add Chamber-Specific Check** (if needed)
```csharp
// Enhanced Fire() method
if (CurrentAmmo <= 0 || !IsCurrentChamberLoaded())
{
    PlayEmptyClickSound();
    return false;
}

private bool IsCurrentChamberLoaded()
{
    return _chamberOccupied.Length > 0
        && _currentChamberIndex < _chamberOccupied.Length
        && _chamberOccupied[_currentChamberIndex];
}
```

## Testing Strategy

### Test Cases

1. **Empty Cylinder Hammer Cock:**
   - Load game with revolver
   - Fire all rounds (empty cylinder)
   - Press RMB to manually cock hammer
   - **Expected:** Hammer cocks successfully, rotation sound plays
   - **Actual (before fix):** Empty click sound plays, hammer doesn't cock

2. **Empty Cylinder Fire Attempt:**
   - Empty cylinder (all 5 rounds fired)
   - Press LMB to fire
   - **Expected:** Empty click sound plays (`Щелчок пустого револьвера.mp3`)
   - **Actual:** Needs verification

3. **Partially Loaded Cylinder Empty Chamber:**
   - Load 3 of 5 rounds
   - Rotate to empty chamber
   - Press LMB to fire
   - **Expected:** Empty click sound plays
   - **Actual:** Needs verification

4. **Cock Then Fire Empty:**
   - Empty cylinder
   - Cock hammer (RMB)
   - Fire (LMB)
   - **Expected:** Empty click sound plays
   - **Actual (after fix):** Should work correctly

### Automated Tests

Update existing test files:
- `tests/unit/test_revolver_hammer_cock.gd` - Add empty cylinder cocking test
- `tests/unit/test_revolver_reload.gd` - Verify no regression

## Risk Assessment

### Low Risk Changes

- Removing the ammo check from `ManualCockHammer()` is low risk
- The method is only called from player input (RMB press)
- Hammer cock is a preparatory action, not a firing action
- Worst case: Player can cock hammer with no ammo (intended behavior)

### Potential Side Effects

1. **Gameplay Balance:** None expected - cocking empty revolver is a realistic mechanic
2. **Performance:** No impact - same code path, just removed check
3. **Audio System:** No changes needed - sounds already implemented
4. **Animation System:** May need verification that animations work with empty cylinder

## Implementation Plan

1. ✅ Create case study directory structure
2. ✅ Document root cause analysis
3. ⏳ Modify `Scripts/Weapons/Revolver.cs`:
   - Remove lines 587-592 (empty ammo check in ManualCockHammer)
   - Add explanatory comment about why cocking is allowed when empty
4. ⏳ Test the fix:
   - Manual testing: Empty cylinder cocking
   - Manual testing: Empty click sound verification
   - Run existing unit tests
5. ⏳ Commit changes with clear message
6. ⏳ Update PR description with findings
7. ⏳ Mark PR as ready for review

## References

### Related Issues
- #626 - Multi-step cylinder reload
- #649 - Manual hammer cocking (RMB)
- #659 - One cartridge per slot
- #661 - Hammer cock delay
- #668 - Per-chamber occupancy tracking

### Audio Files
- `assets/audio/Щелчок пустого револьвера.mp3` - Empty revolver click
- `assets/audio/взведение курка револьвера.mp3` - Hammer cock sound

### Code Locations
- `Scripts/Weapons/Revolver.cs:573-622` - ManualCockHammer() method
- `Scripts/Weapons/Revolver.cs:514-519` - Fire() empty check
- `scripts/autoload/audio_manager.gd:936-937` - play_revolver_empty_click()

## Conclusion

This is a straightforward bug fix with clear root cause and low-risk solution. The main issue is an overly restrictive check that doesn't match real-world revolver mechanics. Removing this check will allow players to cock the hammer with an empty cylinder, which is both realistic and doesn't break any game mechanics.

The empty click sound appears to be already implemented correctly, but will be verified during testing.
