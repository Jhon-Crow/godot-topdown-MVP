# Case Study: Issue #210 - Shotgun Interaction Update

## Issue Summary

**Title**: update взаимодействие с дробовиком (Update shotgun interaction)
**Issue URL**: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/210
**Date Opened**: 2026-01-22

### Requirements (Translated from Russian)

1. **Building level should give 20 shotgun charges** - Currently gives too many shells
2. **Add continuous drag-and-drop reload mechanism**:
   - Hold RMB, then drag up (opens bolt)
   - Without releasing RMB, drag down (closes bolt)
   - All in one continuous movement
3. **Keep old mechanism working** - Individual RMB gestures should still work

## Technical Analysis

### Current Shotgun Implementation

**Files involved:**
- `Scripts/Weapons/Shotgun.cs` - Main shotgun weapon class
- `resources/weapons/ShotgunData.tres` - Weapon data configuration
- `scripts/levels/building_level.gd` - Building level script
- `Scripts/AbstractClasses/BaseWeapon.cs` - Base weapon class

### Current Behavior

#### Ammo System
- `TubeMagazineCapacity = 8` - Shells that can be loaded in the tube
- `MaxReserveAmmo = 24` - Reserve shells (in ShotgunData.tres)
- Total shells: 8 (tube) + 24 (reserve) = 32 shells

#### Current Reload Mechanism
The shotgun uses a state machine for reload:

```
ShotgunReloadState:
- NotReloading    → Ready for action
- WaitingToOpen   → Waiting for RMB drag UP
- Loading         → Bolt open, MMB + RMB drag DOWN to load
- WaitingToClose  → Waiting for RMB drag DOWN to close
```

**Current reload flow:**
1. RMB drag UP → Opens bolt (transitions to Loading state)
2. MMB + RMB drag DOWN → Loads a shell (stays in Loading state)
3. RMB drag DOWN (without MMB) → Closes bolt

**Issue:** Each RMB gesture requires releasing and re-pressing RMB.

### Proposed Changes

#### 1. Reduce Reserve Ammo to 20 Shells Total

The user wants 20 total shells on building level:
- Tube starts full (8 shells)
- Reserve should be 12 shells (8 + 12 = 20 total)

**Option A:** Change `MaxReserveAmmo` in ShotgunData.tres from 24 to 12
- This affects ALL levels globally

**Option B:** Configure per-level starting ammo in building_level.gd
- More flexible, different levels can have different ammo

**Recommendation:** Option A is simpler and matches the request directly.

#### 2. Continuous Drag-and-Drop Reload

The new mechanism allows:
- Hold RMB continuously
- Drag UP → Opens bolt
- (Still holding RMB) Drag DOWN → Closes bolt

**Implementation approach:**
- Track drag gestures during a single continuous RMB hold
- Process intermediate drags, not just on RMB release
- Track the current drag position relative to the last "gesture boundary"

**Key insight from code analysis:**
```csharp
// Current code in HandleDragGestures():
if (Input.IsMouseButtonPressed(MouseButton.Right))
{
    if (!_isDragging)
    {
        _dragStartPosition = GetGlobalMousePosition();
        _isDragging = true;
    }
}
else if (_isDragging)
{
    // Only processes gesture on RMB RELEASE
    Vector2 dragEnd = GetGlobalMousePosition();
    ProcessDragGesture(dragVector);
}
```

**Solution:** Add mid-drag gesture detection that:
1. Tracks when a significant UP or DOWN drag occurs during continuous RMB hold
2. Processes the gesture immediately
3. Resets the drag start position for the next gesture
4. Maintains backward compatibility with release-based gestures

## Timeline

| Event | Timestamp | Description |
|-------|-----------|-------------|
| Issue Created | 2026-01-22 | User reports need for shotgun improvements |
| Analysis Started | 2026-01-22 | Code review of shotgun mechanics |
| Implementation | 2026-01-22 | Changes to Shotgun.cs and ShotgunData.tres |

## Related Pull Requests

- **PR #214**: Fix shotgun reload input timing (recently merged)
- **PR #209**: Fix shotgun reload UI - update ammo counter immediately
- **PR #215**: This PR - Update shotgun interaction

## Files Modified

1. `resources/weapons/ShotgunData.tres` - Reduce MaxReserveAmmo to 12
2. `Scripts/Weapons/Shotgun.cs` - Add continuous drag gesture support

## Test Plan

1. Verify building level starts with exactly 20 shells total (8 in tube + 12 reserve)
2. Test continuous reload:
   - Hold RMB, drag up → bolt opens
   - Without releasing RMB, drag down → bolt closes
3. Test old reload mechanism still works:
   - RMB drag up (release) → bolt opens
   - RMB drag down (release) → bolt closes
4. Test shell loading during reload (MMB + RMB drag down)

## User Feedback and Resolution

### Feedback from @Jhon-Crow (2026-01-22)

> "новое поведение при заряде снарядов не нужно (оставь старый), новое открывание/закрывание затвора работает правильно."

**Translation:**
- "New shell loading behavior is not needed (keep the old one)"
- "New bolt open/close works correctly"

### Root Cause Analysis

The initial implementation added continuous mid-drag support for all shotgun gestures:
1. Pump-action cycling (up to eject shell, down to chamber) ✓
2. Bolt open/close (up to open, down to close) ✓
3. **Shell loading (MMB + down while in Loading state)** ← User didn't want this

The user expected shell loading to remain as a distinct, deliberate action requiring RMB release,
while the bolt open/close should support the new continuous gesture.

### Resolution

Modified `TryProcessMidDragGesture()` to:
- Keep continuous gesture support for bolt opening (drag UP in WaitingToOpen state)
- Keep continuous gesture support for bolt closing (drag DOWN in Loading state **without** MMB)
- **Preserve original shell loading behavior**: When MMB is held during drag DOWN in Loading state,
  the mid-drag gesture is not processed (returns false), requiring the user to release RMB
  to trigger shell loading via the original `ProcessReloadGesture()` path

### Code Change

```csharp
// In TryProcessMidDragGesture(), Loading state handling:
if (shouldLoadShell)
{
    // MMB held - don't process mid-drag, let user release RMB to load shell
    // This preserves the old shell loading behavior while allowing
    // continuous bolt open/close gestures
    return false;
}
else
{
    CompleteReload();
}
```

## Logs

- `logs/game_log_20260122_085458.txt` - User testing log showing shotgun behavior
- `logs/solution-draft-log-pr-1769061104361.txt` - AI solution draft log (4837 lines)
