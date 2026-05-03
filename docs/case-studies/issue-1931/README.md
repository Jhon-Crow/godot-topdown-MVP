# Case Study: Pause-Screen Music Muffle (Issue #1931)

## Issue Data

- Issue: <https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1931>
- Request: add a strong muted music effect, like underwater audio, while the game is paused on the pause screen.
- Additional requirement: collect repository data in `docs/case-studies/issue-1931`, research relevant facts, analyze possible solutions, and implement the selected fix.

## Repository Context

- `MusicManager` (`scripts/autoload/music_manager.gd`) creates a dedicated `Music` audio bus and routes its `AudioStreamPlayer` through it.
- The music player uses `Node.PROCESS_MODE_ALWAYS`, so music continues while the scene tree is paused.
- `PauseMenu` (`scripts/ui/pause_menu.gd`) is responsible for toggling `get_tree().paused` and remains active during pause through `PROCESS_MODE_ALWAYS`.
- `LevelsMenu` (`scripts/ui/levels_menu.gd`) can be opened from the pause screen and then routes selected levels through `SceneLoader.load_level()`.
- Sound settings already target the `Music` bus for music volume, so bus-level effects are the narrowest place to alter music without changing SFX.

## Feedback Artifact

Downloaded owner feedback log:

- `docs/case-studies/issue-1931/artifacts/game_log_20260503_154901.txt`

The log was produced from branch `issue-1931-00bcd7d31ef5` at build commit `10ffb3f19765645f1a5e52db6accdc73ccdbf152`. It shows several level transitions through `SceneLoader`, including:

- 15:49:10: `SceneLoader` loads `LabyrinthLevel.tscn`
- 15:49:18-15:49:19: `SceneLoader` loads `BuildingLevel.tscn`
- 15:49:27: `SceneLoader` loads `RailwayStationLevel.tscn`

Owner feedback: "сейчас при переключении уровня эффект не исчезает" ("now when switching levels the effect does not disappear").

## Root Cause

The first implementation enabled the low-pass filter from `PauseMenu.pause_game()` and disabled it from direct PauseMenu exit paths such as resume, training, roguelike, arena, and quit. The missed path was:

1. Player opens pause menu.
2. `PauseMenu` enables the global Music bus low-pass effect.
3. Player opens `LevelsMenu`.
4. `LevelsMenu._on_level_selected()` emits `back_pressed` and calls `SceneLoader.load_level(level_path)`.
5. `SceneLoader` unpauses and changes the scene.
6. The global `AudioServer` bus effect remains enabled because the scene transition bypassed `PauseMenu.resume_game()`.

Because the effect lives on the global `Music` bus, it survives scene changes unless explicitly disabled.

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

`MusicManager` installs a disabled `AudioEffectLowPassFilter` named `PauseMuffleLowPass` on the `Music` bus. `PauseMenu` calls `MusicManager.set_pause_muffle_enabled(true)` when opening and disables it when resuming, leaving for another level, or quitting.

After owner feedback, `MusicManager._sync_to_current_scene()` also disables the pause muffle whenever the active scene path changes. This makes scene transition cleanup independent of the initiating UI path (`PauseMenu`, `LevelsMenu`, `SceneLoader`, startup navigation, or a direct `change_scene_to_file` fallback).

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
- `_sync_to_current_scene()` disables the muffle effect when the current scene changes, reproducing the paused Levels menu transition failure mode.
