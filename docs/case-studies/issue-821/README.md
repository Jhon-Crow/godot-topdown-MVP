# Case Study: Issue #821 - Automatic Shot After Reload/Pump Bug

## Issue Summary

**Title:** fix автоматический выстрел после перезаредки (fix automatic shot after reload)

**Problem:** When the player presses LMB (shoot) while a weapon is being reloaded or pumped, the shot is buffered and fires automatically once the reload/pump completes. The expected behavior is that pressing LMB during reload should trigger an empty trigger click sound, not queue a shot.

### Reproduction Steps

1. **Shotgun scenario:**
   - Fire the shotgun
   - Hold/press LMB while the shotgun needs pumping (NeedsPumpUp or NeedsPumpDown state)
   - Complete the pump action (rack the slide)
   - **Actual:** A shot fires automatically
   - **Expected:** Empty trigger click sound should play, no automatic shot

2. **PM Pistol (Makarov) scenario:**
   - Fire until empty or nearly empty
   - Press LMB and immediately start reload
   - Complete the reload sequence
   - **Actual:** A shot fires automatically
   - **Expected:** Empty trigger click sound when pressing LMB during reload, no automatic shot

## Timeline / Sequence of Events

```
1. User fires weapon → weapon now needs reload/pump
2. User presses LMB (while weapon cannot fire)
   └─→ BUG: _semiAutoShootBuffered = true (unconditionally)
3. User completes reload/pump
   └─→ Weapon.CanFire = true
4. Next frame: shootInputActive = _semiAutoShootBuffered && CanFire = true
   └─→ BUG: Automatic shot fires
```

## Root Cause Analysis

### Code Location: `Scripts/Characters/Player.cs`

The issue is in the `HandleShootingInput()` method at lines 1348-1377:

```csharp
// For semi-automatic weapons, buffer click inputs so fast clicking works.
// When the player clicks while the fire timer is still active, the click
// is buffered and consumed as soon as the weapon can fire again.
// This prevents lost inputs when clicking faster than the fire rate allows.
if (!isAutomatic && Input.IsActionJustPressed("shoot"))
{
    _semiAutoShootBuffered = true;  // BUG: Buffered unconditionally!
}

// Determine if shooting input is active
bool shootInputActive;
if (isAutomatic)
{
    shootInputActive = Input.IsActionPressed("shoot") && CurrentWeapon.CanFire;
}
else
{
    // For semi-auto: fire if we have a buffered click and weapon can fire
    shootInputActive = _semiAutoShootBuffered && CurrentWeapon.CanFire;
}
```

### Problem

The buffer system was introduced in Issue #625 to prevent lost inputs when clicking faster than the fire rate allows. However, the buffer is set **unconditionally** when the player clicks:

1. If the player clicks during reload, the click is buffered
2. When reload completes, `CanFire` becomes true
3. The buffered click triggers an automatic shot

### Why This Is A Bug

The semi-auto buffer system was designed to handle clicks during the fire cooldown (between shots). It was NOT designed to buffer clicks during:
- Reload sequences (any weapon type)
- Pump actions (shotgun)
- Other weapon states where firing is temporarily disabled

When a weapon cannot fire due to reload/pump state, pressing LMB should:
1. Play the empty trigger click sound
2. NOT buffer a shot for later

## Related Systems

### Semi-Auto Shoot Buffer (Issue #625)

The buffer system was added to solve lost inputs when clicking faster than fire rate allows. The test file `tests/unit/test_semi_auto_shoot_buffer.gd` documents the expected behavior:

- `test_click_during_cooldown_is_buffered()` - Clicks during fire timer cooldown should be buffered
- `test_buffer_works_during_reload()` - **This test actually expects buffered clicks to fire after reload!**

The test at line 290-306 validates that buffered clicks fire after reload - this is the **documented behavior that needs to change**.

### Weapon Systems Affected

1. **Shotgun:** Uses tube magazine with pump-action cycling
   - `ShotgunActionState.NeedsPumpUp` - needs pump up gesture
   - `ShotgunActionState.NeedsPumpDown` - needs pump down gesture
   - `CanFire` requires `ActionState == Ready`

2. **PM Pistol (Makarov):** Uses standard magazine reload
   - Uses R→R reload sequence (2-step)
   - `_isReloadingSequence` tracks reload state

3. **All Semi-Auto Weapons:** Affected by the `_semiAutoShootBuffered` system

## Proposed Solution

### Option 1: Clear buffer during reload/pump (Recommended)

Clear `_semiAutoShootBuffered` when the weapon enters a reload or pump state:

```csharp
if (!isAutomatic && Input.IsActionJustPressed("shoot"))
{
    // Only buffer if weapon is ready to fire soon (not reloading/pumping)
    // Check for shotgun pump state
    var shotgun = CurrentWeapon as Shotgun;
    bool shotgunNeedsPump = shotgun != null &&
        shotgun.ActionState != ShotgunActionState.Ready;

    // Check for reload sequence
    bool isReloading = _isReloadingSequence ||
        (CurrentWeapon != null && CurrentWeapon.IsReloading);

    if (!isReloading && !shotgunNeedsPump)
    {
        _semiAutoShootBuffered = true;
    }
    else
    {
        // Play empty click sound for feedback
        PlayEmptyClickSound();
    }
}
```

### Option 2: Clear buffer on reload/pump start

Add code to reset `_semiAutoShootBuffered = false` whenever:
- A reload sequence starts (`_reloadSequenceStep = 1`)
- A shotgun enters pump state (`ActionState` changes to `NeedsPumpUp`)

### Recommendation

**Option 1** is cleaner because it prevents the buffer from being set in the first place. Option 2 is a fallback but requires changes in multiple places.

## Test Plan

1. **Manual Testing:**
   - Shotgun: Fire, hold LMB, pump → verify no auto-shot
   - PM Pistol: Fire until empty, hold LMB, reload → verify no auto-shot
   - All semi-auto weapons: Quick clicks should still work (buffer for fire cooldown)

2. **Unit Tests:**
   - Update `test_semi_auto_shoot_buffer.gd` to reflect new expected behavior
   - Add test: `test_buffer_not_set_during_reload()`
   - Add test: `test_buffer_not_set_during_pump_action()`

## References

- Issue #625: Original semi-auto shoot buffer implementation
- Test file: `tests/unit/test_semi_auto_shoot_buffer.gd`
- Player.cs: `HandleShootingInput()` method (lines 1327-1434)
- Shotgun.cs: `ShotgunActionState` enum and `CanFire` property
