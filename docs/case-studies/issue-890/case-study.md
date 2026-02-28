# Case Study: Issue #890 — Homing Bullets Scanner Sound Not Playing

## Summary

**Issue**: Add a quiet scanner looping sound that plays while the Homing Bullets item is **active** (Space pressed during active window).
**Status**: Resolved (fourth attempt)
**Affected files**: `Scripts/Characters/Player.cs`, `scripts/characters/player.gd`

---

## Timeline of Events

### 2026-02-24 — First attempt (commit b0711e74)
- Added scanner loop to **GDScript** `scripts/characters/player.gd` only
- **Missed**: All actual game levels use `scenes/characters/csharp/Player.tscn`, which references `Scripts/Characters/Player.cs` (C#)
- Owner feedback: "звук не добавился, проверь C#" (sound wasn't added, check C#)

### 2026-02-24 — Second attempt (commit b0ba8a0c)
- Added scanner loop to **C# `Scripts/Characters/Player.cs`**
- Game log (game_log_20260225_001249.txt) confirms code executed: `[Player.Homing] Homing scanner loop started (Issue #890)`
- Owner feedback: "fix звук пока активен предмет не появился" (sound still not appearing)

### 2026-02-24 — Third attempt (commit 99e27810)
- Deep analysis of WAV file structure and Godot 4 AudioStreamWav behavior
- Fixed missing `LoopEnd` and `LoopBegin` settings (Godot defaults `LoopEnd = 0` → silent loop after first play-through)
- Game log (game_log_20260225_013747.txt) confirms sound IS now looping (samples=88200 confirmed)
- **But**: Sound started at item **selection** time, not during homing **activation**
- Owner feedback (2026-02-24T22:39):
  1. "звук начинает работать как только выбран предмет, а не после активации" (sound starts when item selected, not after activation)
  2. "должен прекращаться, когда пули перестают наводиться" (should stop when bullets stop homing)
  3. "звук слишком громкий (сделай тише в 3 раза)" (sound too loud, make it 3x quieter)

### 2026-02-24 — Fourth attempt (this session)
- Fixed timing: scanner only plays during `_homingActive == true`, stops when `_homingActive` becomes false
- Fixed volume: from -18.0 dB to -27.5 dB (3x quieter in linear amplitude)

---

## Root Cause Analysis

### Bug 1: Wrong Timing — Sound Plays at Selection, Not Activation

**Symptom**: Scanner sound starts immediately when Homing Bullets item is picked up / equipped, not when the player activates the effect by pressing Space.

**Evidence from game_log_20260225_013747.txt**:
```
[01:37:59] [INFO] [ActiveItemManager] Active item changed from None to Homing Bullets
[01:37:59] [INFO] [Player.Homing] Homing activation sound loaded
[01:37:59] [INFO] [Player.Homing] Homing scanner loop started (Issue #890), samples=88200
[01:37:59] [INFO] [Player.Homing] Homing bullets equipped, charges: 6/6
...
[01:38:07] [INFO] [Player.Homing] Homing activated! Duration: 1s, charges remaining: 5/6
[01:38:08] [INFO] [Player.Homing] Homing effect expired, charges remaining: 5/6
```

"Homing scanner loop started" fires 8 seconds before "Homing activated!" — at the moment of item selection, not activation.

**Root cause**: In `SetupHomingAudio()`, `_homingScannerPlayer.Play()` was called immediately after adding the player as a child. The scanner was designed to be "always-on while equipped" rather than "on only during active homing".

**Fix**: Remove `Play()` from `SetupHomingAudio()`. Instead, start the scanner when `_homingActive` becomes `true` (in `HandleHomingBulletsInput`) and stop it when `_homingActive` becomes `false` (when timer expires).

### Bug 2: Volume Too Loud

**Symptom**: Owner reports sound is too loud; needs to be 3x quieter.

**Root cause**: Volume was set at `-18.0 dB`. Converting 3x amplitude reduction to dB: 20 × log10(1/3) ≈ -9.54 dB. So new volume = -18.0 - 9.54 = **-27.5 dB**.

### Resolved Bug from Third Attempt: WAV LoopEnd = 0 (silent loop)

**Root cause**: Godot 4 defaults `AudioStreamWav.LoopEnd = 0`. With `LoopMode = LOOP_FORWARD` and `LoopEnd = 0`, the loop region is zero samples — audio plays once then loops silence.
- Reference: [Godot issue #33141](https://github.com/godotengine/godot/issues/33141)
- **Fix**: Set `LoopEnd = totalSamples` (88200 for 2s 44100Hz mono WAV)

---

## Fix (Fourth Attempt)

### C# (`Scripts/Characters/Player.cs`)

In `SetupHomingAudio()`: Remove `_homingScannerPlayer.Play()`. Change volume from `-18.0f` to `-27.5f`.

In `HandleHomingBulletsInput()`: Start scanner on activation, stop scanner when timer expires.

In `PlayHomingSound()` → renamed: added `StartHomingScanner()` and `StopHomingScanner()` helpers.

### GDScript (`scripts/characters/player.gd`)

Same changes applied to the GDScript counterpart.

---

## Additional Notes

- Volume formula: 3x quieter = 20×log10(1/3) ≈ -9.54 dB → -18.0 - 9.54 = -27.5 dB
- The activation sound (`homing_activation.wav`) correctly plays once per activation and does not need looping changes.
- Previous WAV loop fix (LoopEnd = totalSamples) is still required and remains in place.

---

## Files Changed
- `Scripts/Characters/Player.cs` — Fixed timing and volume of scanner sound
- `scripts/characters/player.gd` — Same fixes in GDScript counterpart
- `docs/case-studies/issue-890/case-study.md` — This document
- `docs/case-studies/issue-890/game_log_20260225_001249.txt` — Game log from second owner test
- `docs/case-studies/issue-890/game_log_20260225_013747.txt` — Game log from third owner test
