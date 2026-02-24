# Case Study: Issue #842 — Shotgun Broken and Wrong Empty-Shot Sounds

## Summary

After PR #837 (fix for Issue #835), two regressions appeared:

1. **Shotgun stopped shooting** — clicking LMB plays an M16 empty-click sound instead of firing.
2. **All weapons play the wrong empty-shot sound** — every weapon plays the M16/pistol empty sound instead of its own weapon-specific sound.

---

## Timeline of Events

```
PR #835 (Issue #835 fix):
  - Introduced weaponEmpty check: bool weaponEmpty = CurrentWeapon.CurrentAmmo <= 0
  - Introduced PlayEmptyClickSound() in Player.cs that always calls play_empty_click
  - Both changes were reasonable for pistols/rifles but missed the Shotgun's unique architecture

Issue #842 filed (2026-02-19):
  - Reporter: Jhon-Crow
  - Regression: shotgun won't fire (plays M16 empty sound instead)
  - Regression: all weapons use M16 empty sound for dry-fire clicks
```

---

## Root Cause Analysis

### Bug 1: Shotgun Never Fires (always hit weaponEmpty = true)

In `Scripts/Characters/Player.cs`, `HandleShootingInput()` (line ~1379):

```csharp
bool weaponEmpty = CurrentWeapon.CurrentAmmo <= 0;  // ← ALWAYS TRUE for Shotgun!

if (isReloading || shotgunNeedsPump || revolverReloading || shotgunReloading || weaponEmpty)
{
    PlayEmptyClickSound();  // Shotgun ALWAYS reaches here
}
else
{
    _semiAutoShootBuffered = true;  // Shotgun NEVER reaches here → never fires
}
```

**Why `CurrentAmmo` is always 0 for the Shotgun:**

The Shotgun uses a tube magazine system (`ShellsInTube`) instead of a detachable magazine. In `Shotgun.cs` (~line 355), the `CurrentMagazine.CurrentAmmo` is explicitly set to `0` as a placeholder:

```csharp
// Set CurrentMagazine to 0 since we don't use it (tube is separate)
if (MagazineInventory.CurrentMagazine != null)
{
    MagazineInventory.CurrentMagazine.CurrentAmmo = 0;  // Always 0!
}
```

And `BaseWeapon.CurrentAmmo` reads from `MagazineInventory.CurrentMagazine?.CurrentAmmo ?? 0`, so it returns `0` for the Shotgun regardless of how many shells are in the tube.

The Shotgun already has its own `CanFire` override that correctly checks `ShellsInTube`:

```csharp
// Shotgun.cs - correct check exists but HandleShootingInput never reaches Shoot()
public override bool CanFire => ShellsInTube > 0 &&
                                 ActionState == ShotgunActionState.Ready &&
                                 ReloadState == ShotgunReloadState.NotReloading &&
                                 _fireTimer <= 0;
```

The bug is that `HandleShootingInput()` in `Player.cs` gates on `CurrentAmmo` before ever reaching `CanFire`.

### Bug 2: Wrong Empty Sound (M16 for all weapons)

`PlayEmptyClickSound()` in `Player.cs` always calls `play_empty_click` which is the M16/pistol sound:

```csharp
private void PlayEmptyClickSound()
{
    var audioManager = GetNodeOrNull("/root/AudioManager");
    if (audioManager != null && audioManager.HasMethod("play_empty_click"))
    {
        audioManager.Call("play_empty_click", GlobalPosition);  // ← Always M16/pistol
    }
}
```

Meanwhile, the individual weapon classes have correct weapon-specific implementations:

| Weapon | Method called | Sound file |
|--------|---------------|------------|
| Shotgun | `play_shotgun_empty_click` | `выстрел без патронов дробовик.mp3` |
| Revolver | `play_revolver_empty_click` | `Щелчок пустого револьвера.mp3` |
| MakarovPM, SilencedPistol, AssaultRifle | `play_empty_click` | `кончились патроны в пистолете.wav` |

The centralized `PlayEmptyClickSound()` in `Player.cs` was added without considering weapon-specific sounds.

---

## Sequence of Events for Bug 1 (Shotgun Can't Fire)

```
Frame N:   Player has Shotgun equipped (ShellsInTube=8, CurrentAmmo=0)
Frame N:   Player clicks LMB → Input.IsActionJustPressed("shoot") = true
           HandleShootingInput():
             shotgun != null → shotgunNeedsPump = false (ActionState.Ready)
             isReloading = false
             revolverReloading = false
             shotgunReloading = false
             weaponEmpty = CurrentWeapon.CurrentAmmo <= 0 = (0 <= 0) = TRUE  ← BUG!
           → PlayEmptyClickSound() called (wrong: M16 sound)
           → _semiAutoShootBuffered = false → Shotgun NEVER FIRES
```

---

## Fixes

### Fix 1: Weapon-aware `weaponEmpty` check

Replace the generic `CurrentAmmo` check with a weapon-type-aware check:

```csharp
// For shotgun, use ShellsInTube; for other weapons, use CurrentAmmo
bool weaponEmpty;
if (shotgun != null)
    weaponEmpty = shotgun.ShellsInTube <= 0;
else
    weaponEmpty = CurrentWeapon.CurrentAmmo <= 0;
```

This ensures the Shotgun's `weaponEmpty` is `false` when it has shells in the tube, allowing `_semiAutoShootBuffered = true` to be set, and the subsequent `CanFire` check (which correctly evaluates `ShellsInTube`) to allow firing.

### Fix 2: Weapon-specific empty click sound

Replace the hardcoded `play_empty_click` call with a weapon-type-aware dispatch:

```csharp
private void PlayEmptyClickSound()
{
    var audioManager = GetNodeOrNull("/root/AudioManager");
    if (audioManager == null) return;

    if (CurrentWeapon is Shotgun && audioManager.HasMethod("play_shotgun_empty_click"))
        audioManager.Call("play_shotgun_empty_click", GlobalPosition);
    else if (CurrentWeapon is Revolver && audioManager.HasMethod("play_revolver_empty_click"))
        audioManager.Call("play_revolver_empty_click", GlobalPosition);
    else if (audioManager.HasMethod("play_empty_click"))
        audioManager.Call("play_empty_click", GlobalPosition);
}
```

---

## Files Changed

- `Scripts/Characters/Player.cs` — Fixed `weaponEmpty` check and `PlayEmptyClickSound()` method

---

## References

- Issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/842
- Regressing PR: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/837
- Related issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/835
