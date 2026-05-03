# Case Study: Pause-Screen Music Muffle (Issue #1931)

## Issue Data

- Issue: <https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1931>
- Request: add a strong muted music effect, like underwater audio, while the game is paused on the pause screen.
- Additional requirement: collect repository data in `docs/case-studies/issue-1931`, research relevant facts, analyze possible solutions, and implement the selected fix.

## Repository Context

- `MusicManager` (`scripts/autoload/music_manager.gd`) creates a dedicated `Music` audio bus and routes its `AudioStreamPlayer` through it.
- The music player uses `Node.PROCESS_MODE_ALWAYS`, so music continues while the scene tree is paused.
- `PauseMenu` (`scripts/ui/pause_menu.gd`) is responsible for toggling `get_tree().paused` and remains active during pause through `PROCESS_MODE_ALWAYS`.
- Sound settings already target the `Music` bus for music volume, so bus-level effects are the narrowest place to alter music without changing SFX.

## External Research

Godot's official audio filter API supports low-pass filters through `AudioEffectLowPassFilter`, which cuts frequencies above `AudioEffectFilter.cutoff_hz`. The `AudioServer` API can add effects to buses at runtime with `add_bus_effect(bus_idx, effect, at_position=-1)`.

Sources:

- Godot 4.3 `AudioEffectFilter` documentation: <https://docs.godotengine.org/en/4.3/classes/class_audioeffectfilter.html>
- Godot 4.5 `AudioServer` documentation: <https://docs.godotengine.org/en/4.5/classes/class_audioserver.html>
- Godot latest `AudioEffectLowPassFilter` documentation: <https://docs.godotengine.org/en/latest/classes/class_audioeffectlowpassfilter.html>

## Solution Options

1. Lower music volume during pause.
   - Simple, but it does not sound underwater or strongly muffled.
   - It also fights the user's music-volume setting.

2. Add a duplicate filtered pause music player.
   - Allows custom processing, but duplicates playback state and risks phase/restart bugs.
   - More complex than needed because a Music bus already exists.

3. Add a low-pass filter to the existing Music bus and enable it only while paused.
   - Matches the "underwater" requirement by removing high frequencies.
   - Keeps playback continuous and preserves the existing music slider.
   - Does not affect SFX if they remain on their own buses.

## Selected Implementation

`MusicManager` now installs a disabled `AudioEffectLowPassFilter` named `PauseMuffleLowPass` on the `Music` bus. `PauseMenu` calls `MusicManager.set_pause_muffle_enabled(true)` when opening and disables it when resuming, leaving for another level, or quitting.

Chosen filter parameters:

- `cutoff_hz = 650.0`
- `db = FILTER_24DB`
- `resonance = 0.45`

This is intentionally strong: most high-frequency content is removed while preserving enough low-frequency energy that the music remains audible under the pause screen.

## Verification

Added regression coverage in `tests/unit/test_music_manager.gd`:

- Music bus includes a pause low-pass filter.
- The filter starts disabled during gameplay.
- `set_pause_muffle_enabled(true/false)` toggles the bus effect.
