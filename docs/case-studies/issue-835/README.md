# Case Study: Issue #835 — Automatic Shot After Reloading Empty Pistols

## Issue Description

**Title:** fix самопроизвольный выстрел после перезарядки пистолетов (automatic shot after reloading pistols)

**Reported by:** Jhon-Crow
**Affected weapons:** MakarovPM, SilencedPistol

**Bug description:** An unintended shot fires automatically right after completing a reload of an empty pistol (MakarovPM or SilencedPistol), if the player pressed LMB (shoot) before/during the reload.

**Reproduction steps:**
1. Fire the pistol until the magazine is empty (or have an empty magazine)
2. Click/hold LMB (shoot button)
3. Press R to reload
4. Complete the reload sequence (R→R for MakarovPM, or R→F→R for SilencedPistol)
5. Observe: a shot fires automatically right after reload completes

---

## Evidence

### Game Logs

Two game logs were provided:

**Log 1:** `game_log_20260219_192638.txt` (845 lines)
**Log 2:** `game_log_20260219_192814.txt` (2173 lines)

#### Key Evidence from Log 1 (lines 320–327):
```
[19:26:55] [Player.Reload.Anim] Phase changed to: GrabMagazine (duration: 0,25s)
[19:26:55] [Player.Reload.Anim] Phase changed to: InsertMagazine (duration: 0,30s)
[19:26:55] [Player.Reload.Anim] Phase changed to: ReturnIdle (duration: 0,20s)
[19:26:55] [SoundPropagation] Sound emitted: type=GUNSHOT, pos=(150, 366), source=PLAYER (MakarovPM), range=1469, listeners=0
[19:26:56] [Player.Reload.Anim] Animation complete, returning to normal
```

A gunshot fires DURING the ReturnIdle animation phase, BEFORE "Animation complete".

#### Key Evidence from Log 2 (lines 420–425):
```
[19:28:23] [Player.Reload.Anim] Phase changed to: GrabMagazine (duration: 0,25s)
[19:28:24] [Player.Reload.Anim] Phase changed to: InsertMagazine (duration: 0,30s)
[19:28:24] [Player.Reload.Anim] Phase changed to: ReturnIdle (duration: 0,20s)
[19:28:24] [SoundPropagation] Sound emitted: type=GUNSHOT, pos=(150, 366), source=PLAYER (MakarovPM), range=1469, listeners=0
[19:28:24] [Player.Reload.Anim] Animation complete, returning to normal
```

Same pattern: GUNSHOT fires right when ReturnIdle phase starts, not when animation completes.

---

## Timeline Reconstruction

```
Frame N:   Player has 0 ammo in magazine
Frame N:   Player clicks LMB (shoot button) → IsActionJustPressed("shoot") = true
           HandleShootingInput() checks:
             - isReloading = false (reload not started yet)
             - shotgunNeedsPump = false
             - revolverReloading = false
             - shotgunReloading = false
           → _semiAutoShootBuffered = true  ← BUG: buffer set despite empty weapon!

           shootInputActive = _semiAutoShootBuffered && CurrentWeapon.CanFire
                            = true && false (ammo=0 → CanFire=false)
           → No shot fires this frame

Frame N+k: Player presses R → reload sequence starts (_isReloadingSequence = true)

Frame N+m: Player completes reload (presses R again for pistol, or R→F→R for assault)
           CompleteReloadSequence() called
           → InstantReload() → magazine refilled, CanFire = true
           → ResetReloadSequence() → _isReloadingSequence = false
           → _semiAutoShootBuffered is NOT cleared ← BUG: stale buffer remains!

Frame N+m+1: HandleShootingInput() runs:
             shootInputActive = _semiAutoShootBuffered && CurrentWeapon.CanFire
                              = true && true  ← both conditions met!
             → UNINTENDED SHOT FIRES!
```

---

## Root Cause Analysis

### Primary Cause: Buffer Set When Weapon is Empty

In `Player.cs`, `HandleShootingInput()` (line ~1355), the semi-auto shoot buffer gets set when:
1. The weapon is not automatic
2. LMB is just pressed
3. No reload/pump is currently in progress

The condition does NOT check if the weapon has ammo. When the player clicks LMB with an empty weapon BEFORE starting the reload, the buffer is set (`_semiAutoShootBuffered = true`).

### Secondary Cause: Buffer Not Cleared After Reload

After `CompleteReloadSequence()` → `ResetReloadSequence()` is called (which resets `_isReloadingSequence = false`), the `_semiAutoShootBuffered` flag is NOT cleared. So the stale buffer from the click-on-empty-weapon persists and triggers a shot immediately after reload.

### Why the #821 Fix Didn't Catch This

Issue #821 fixed the case where the player clicks LMB WHILE already in a reload/pump sequence. It added checks:
```csharp
bool isReloading = _isReloadingSequence || (CurrentWeapon != null && CurrentWeapon.IsReloading);
if (isReloading || shotgunNeedsPump || revolverReloading || shotgunReloading)
{
    PlayEmptyClickSound(); // Don't buffer
}
```

This works for clicks AFTER reload starts. But it misses clicks that happen BEFORE reload starts (on same or earlier frames when weapon just ran out of ammo).

### Input Processing Order

In `_Process()`, the order is:
1. `HandleGrenadeInput()`
2. `HandleShootingInput()` ← sets `_semiAutoShootBuffered = true`
3. `HandleReloadSequenceInput()` ← sets `_isReloadingSequence = true`

When LMB and R are pressed on the SAME frame, `HandleShootingInput()` processes LMB first (sees `_isReloadingSequence = false`), then `HandleReloadSequenceInput()` starts the reload. The buffer gets set before the reload check, bypassing the #821 protection.

---

## Solution

Two complementary fixes:

### Fix 1: Don't buffer clicks when weapon has no ammo (Primary Fix)

In `HandleShootingInput()`, add a check for `CurrentAmmo <= 0` before setting the buffer:

```csharp
// Also don't buffer if weapon has no ammo - clicking on empty weapon should not
// trigger a shot after reload (Issue #835)
bool weaponEmpty = CurrentWeapon.CurrentAmmo <= 0;

if (isReloading || shotgunNeedsPump || revolverReloading || shotgunReloading || weaponEmpty)
{
    PlayEmptyClickSound();
    // ...
}
else
{
    _semiAutoShootBuffered = true;
}
```

**Rationale:** When the weapon is empty, clicking LMB is a "try to shoot with empty weapon" action. The intended behavior is just to hear an empty click. The click should NOT be saved as a pending shot for after the reload.

### Fix 2: Clear buffer when reload sequence completes (Secondary Safety Net)

In `CompleteReloadSequence()` and `ResetReloadSequence()`, clear the buffer:

```csharp
private void CompleteReloadSequence()
{
    // ...
    CurrentWeapon.InstantReload();
    _semiAutoShootBuffered = false; // Clear any stale buffered shot from before reload
    // ...
}
```

**Rationale:** Even if a click somehow gets buffered before reload starts, clearing it after reload completes prevents the automatic shot.

---

## Files Changed

- `Scripts/Characters/Player.cs` — Add ammo check before buffering shot; clear buffer after reload
- `tests/unit/test_semi_auto_shoot_buffer.gd` — Add test cases for Issue #835

---

## Related Issues

- **Issue #821** — Previous related fix: automatic shot after shotgun pump/PM reload when clicking DURING reload
- **Issue #625** — Original semi-auto shoot buffer implementation
