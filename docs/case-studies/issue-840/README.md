# Case Study: Issue #840 — Empty Shot Sound for Pistols

## Overview

**Issue**: Replace the empty-shot (dry-fire) sound for PM, UZI, and silenced pistol with `assets/audio/попытка выстрелить без заряда ПМ.mp3`.

**PR**: [#847](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/847)

**Status (as of 2026-02-19)**: **Root cause found and fixed** — see "Second Investigation" below.

---

## Timeline of Events

| Time (UTC) | Event |
|---|---|
| 2026-02-19T17:24:20 | AI session started to work on issue #840 |
| 2026-02-19T17:27:27 | Fix committed: `bf1a267d` — adds `play_pistol_empty_click()` and updates all three weapon scripts |
| 2026-02-19T17:28:10 | CI runs triggered; "Build Windows Portable EXE" workflow completes successfully |
| 2026-02-19T17:43:07 | Owner (Jhon-Crow) reports: UZI works, PM and silenced pistol did NOT change |
| 2026-02-19T17:43:07 | Owner attaches `game_log_20260219_204140.txt` |
| 2026-02-19T19:20:16 | Second AI session started |
| 2026-02-19T19:31:21 | AI concludes owner didn't actually empty PM/SilencedPistol magazines in first test |
| 2026-02-19T19:58:55 | Owner tests again, reports: PM and SilencedPistol still not playing correct sound |
| 2026-02-19T19:58:55 | Owner attaches `game_log_20260219_225629.txt` |
| 2026-02-19T20:00:40 | Third AI session started |
| 2026-02-19T20:00:XX | **True root cause found** — `Player.PlayEmptyClickSound()` fallback bug |
| 2026-02-19T20:XX:XX | Fix committed to `Player.cs` |

---

## Files Attached

| File | Description |
|---|---|
| `game_log_20260219_204140.txt` | Game session log from owner's first test (20:41:40 local time) |
| `game_log_20260219_225629.txt` | Game session log from owner's second test (22:56:29 local time) |

---

## First Investigation (Incorrect Conclusion)

### Initial Analysis of `game_log_20260219_204140.txt`

The log revealed that in the first test session the player never actually depleted the PM or SilencedPistol magazine:

- **MakarovPM**: Reloaded before running out, then opened Armory to switch weapons
- **SilencedPistol**: Opened Armory 6 seconds after equipping (fired 0 shots)
- **MiniUzi**: Fired all 32 rounds → empty click triggered → UZI "worked"

**Conclusion (incorrect)**: The first fix was fine; the owner just didn't test with an empty magazine.

### Why This Was Wrong

The owner tested again in `game_log_20260219_225629.txt`. Analysis of that log shows:

- **MakarovPM**: Fired 12+ shots from a 9-round magazine (3+ empty-click attempts)
- **SilencedPistol**: Fired all 13 rounds plus attempted multiple more times
- **No `[MakarovPM]` or `[SilencedPistol]` debug logs appeared**

The absence of our `GD.Print()` debug messages in the log is NOT evidence that the code didn't run — it's because **`GD.Print()` in C# does NOT write to the GDScript `FileLogger` game log file**. The game log only captures GDScript `print()` calls.

---

## Second Investigation — True Root Cause

### Key Finding: Dual Empty-Click Path in `Player.cs`

There are **two separate places** where the empty click sound is triggered:

#### Path A: Automatic weapons (MiniUzi in full-auto mode)
```
Input.IsActionPressed("shoot") [held down]
  → shootInputActive = true
  → Shoot() → CurrentWeapon.Fire(dir)
  → MiniUzi.Fire(): if (CurrentAmmo <= 0) → MiniUzi.PlayEmptyClickSound()
  → audioManager.Call("play_pistol_empty_click", ...)  ✓
```

#### Path B: Semi-automatic weapons (MakarovPM, SilencedPistol)
```
Input.IsActionJustPressed("shoot") [clicked]
  → weaponEmpty = true
  → Player.PlayEmptyClickSound()  ← INTERCEPTED HERE
  → audioManager.Call("play_empty_click", ...)  ✗ (OLD GENERIC SOUND)
```

`Player.cs`'s `PlayEmptyClickSound()` had a branch for Shotgun and Revolver but fell back to the generic `play_empty_click` for all other weapons including MakarovPM and SilencedPistol.

### The Bug in `Player.PlayEmptyClickSound()`

**Before fix** (`Scripts/Characters/Player.cs`):
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
        audioManager.Call("play_empty_click", GlobalPosition);  // ← WRONG SOUND for pistols
}
```

**After fix**:
```csharp
private void PlayEmptyClickSound()
{
    var audioManager = GetNodeOrNull("/root/AudioManager");
    if (audioManager == null) return;

    if (CurrentWeapon is Shotgun && audioManager.HasMethod("play_shotgun_empty_click"))
        audioManager.Call("play_shotgun_empty_click", GlobalPosition);
    else if (CurrentWeapon is Revolver && audioManager.HasMethod("play_revolver_empty_click"))
        audioManager.Call("play_revolver_empty_click", GlobalPosition);
    else if ((CurrentWeapon is MakarovPM || CurrentWeapon is MiniUzi || CurrentWeapon is SilencedPistol)
        && audioManager.HasMethod("play_pistol_empty_click"))
        audioManager.Call("play_pistol_empty_click", GlobalPosition);  // ← CORRECT SOUND
    else if (audioManager.HasMethod("play_empty_click"))
        audioManager.Call("play_empty_click", GlobalPosition);
}
```

### Why UZI "Worked"

MiniUzi is **automatic** (IsAutomatic=true). For automatic weapons, `Player.cs` skips the semi-auto click interception at line 1355 (`if (!isAutomatic && Input.IsActionJustPressed("shoot"))`). The empty click is handled by `MiniUzi.Fire()` → `MiniUzi.PlayEmptyClickSound()` which already calls `play_pistol_empty_click`.

For MakarovPM and SilencedPistol (semi-automatic), the Player's `HandleShootingInput()` intercepts the click **before** the weapon's own `Fire()` is called, so the weapon-level fix in `bf1a267d` had no effect for those weapons.

---

## Sound Constants

| Constant | File | Used by |
|---|---|---|
| `EMPTY_GUN_CLICK` | `кончились патроны в пистолете.wav` | Generic fallback (other weapons) |
| `PISTOL_EMPTY_CLICK` | `попытка выстрелить без заряда ПМ.mp3` | PM, UZI, SilencedPistol (Issue #840) |
| `SHOTGUN_EMPTY_CLICK` | `выстрел без патронов дробовик.mp3` | Shotgun |
| `REVOLVER_EMPTY_CLICK` | `Щелчок пустого револьвера.mp3` | Revolver |

---

## Complete Fix Summary

Two commits were needed to fully fix this issue:

1. **`bf1a267d`** — Adds `play_pistol_empty_click()` to AudioManager, updates weapon scripts (fixes automatic weapon path)
2. **`37557356`** — Adds debug logging to track the empty click events
3. **This commit** — Fixes `Player.PlayEmptyClickSound()` to handle pistol weapons (fixes semi-automatic weapon path)

---

## Proposed Test Protocol

To properly verify the fix, the owner should download the latest CI build and:

1. **MakarovPM** (9 rounds): Fire all 9 shots → try to fire again → should hear `попытка выстрелить без заряда ПМ.mp3`
2. **SilencedPistol** (13 rounds): Fire all 13 shots → try to fire again → should hear `попытка выстрелить без заряда ПМ.mp3`
3. **MiniUzi** (32 rounds): Fire all 32 rounds → try to fire again → should hear `попытка выстрелить без заряда ПМ.mp3`
4. **Shotgun**: Verify it still plays `выстрел без патронов дробовик.mp3`
5. **Revolver**: Verify it still plays `Щелчок пустого револьвера.mp3`

---

## Online Context

- **Godot `is` type check documentation**: https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html
- **GDScript `HasMethod` documentation**: https://docs.godotengine.org/en/stable/classes/class_object.html#class-object-method-has-method
- **Issue #840**: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/840
- **PR #847**: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/847
