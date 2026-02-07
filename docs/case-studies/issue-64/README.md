# Case Study: Issue #64 — Add Sound on Fire Mode Toggle (B Key)

## Problem

The assault rifle has a fire mode toggle (B key) that switches between automatic
and burst fire modes, but no audio feedback was provided to the player when
toggling. The issue requested adding the sound file
`assets/audio/игрок изменил режим стрельбы (нажал b).mp3` to play on each toggle.

Issue: [#64 — добавь звук на нажатие кнопки b](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/64)

## Root Cause Analysis

### Missing Audio Integration

The `ToggleFireMode()` method in `Scripts/Weapons/AssaultRifle.cs` toggled the
fire mode and emitted a signal, but never called the AudioManager to play a
sound:

```csharp
public void ToggleFireMode()
{
    CurrentFireMode = CurrentFireMode == FireMode.Automatic ? FireMode.Burst : FireMode.Automatic;
    EmitSignal(SignalName.FireModeChanged, (int)CurrentFireMode);
    GD.Print($"[AssaultRifle] Fire mode changed to: {CurrentFireMode}");
}
```

The audio file `игрок изменил режим стрельбы (нажал b).mp3` existed in the
`assets/audio/` directory but was never registered in the AudioManager or played
anywhere in the code.

### Previous Attempt (PR #65 — Closed)

A previous PR (#65) attempted to solve this issue but was closed because:

1. It renamed the Cyrillic audio file to `fire_mode_toggle.wav`, which was
   inconsistent with the rest of the codebase that uses Cyrillic filenames
   throughout (e.g., `кончились патроны в пистолете.wav`,
   `падает гильза автомата.wav`, etc.)
2. The comment on the issue noted: "звук из ассетов не был добавлен в ветке"
   (the sound from assets was not added in the branch)

## Fix

### 1. AudioManager (`scripts/autoload/audio_manager.gd`)

Added the fire mode toggle sound following the existing pattern used by all other
sounds in the codebase:

- **Constant**: `FIRE_MODE_TOGGLE` pointing to the original Cyrillic-named `.mp3`
  file (as specified in the issue)
- **Volume**: `VOLUME_FIRE_MODE_TOGGLE = -3.0` dB (same as other player action
  feedback sounds like empty click, reload)
- **Preloading**: Added to `_preload_all_sounds()` for faster playback
- **Convenience method**: `play_fire_mode_toggle(position)` using `CRITICAL`
  priority (consistent with other player action feedback sounds)

### 2. AssaultRifle (`Scripts/Weapons/AssaultRifle.cs`)

- Added `PlayFireModeToggleSound()` private method following the same pattern as
  `PlayEmptyClickSound()` and `PlayM16ShotSound()`
- Called `PlayFireModeToggleSound()` from `ToggleFireMode()` to play the sound
  immediately when the fire mode is switched

### Design Decisions

- **Kept original Cyrillic filename**: Unlike PR #65, this implementation keeps
  the original `игрок изменил режим стрельбы (нажал b).mp3` filename, consistent
  with all other audio files in the project
- **Used `.mp3` format**: The issue specifically references the `.mp3` file (both
  `.mp3` and `.wav` versions exist in the repository)
- **CRITICAL priority**: Fire mode toggle is a direct player action that should
  always produce audible feedback, matching the priority of other player feedback
  sounds (empty click, reload, shooting)
- **Positional 2D audio**: Uses `play_sound_2d_with_priority()` so the sound
  emanates from the player's position, consistent with other weapon sounds

## Verification

The sound plays when:
1. Player presses the B key (mapped to `toggle_fire_mode` input action)
2. The currently equipped weapon is an assault rifle
3. The assault rifle switches between burst and automatic fire modes
