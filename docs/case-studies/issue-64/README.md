# Case Study: Issue #64 - Fire Mode Toggle Sound Not Playing in Export

## Problem Description

**Issue**: [#64 - добавь звук на нажатие кнопки b](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/64)

**Reported Symptom**: The fire mode toggle sound (B key) works correctly in the Godot editor but does not play in the exported Windows executable.

**Audio File**: `игрок изменил режим стрельбы (нажал b).wav` (Cyrillic filename meaning "player changed fire mode (pressed b)")

## Investigation Summary

### Code Implementation Analysis

The implementation follows the correct pattern:

1. **AudioManager (`scripts/autoload/audio_manager.gd`)**:
   - Sound constant defined: `FIRE_MODE_TOGGLE: String = "res://assets/audio/игрок изменил режим стрельбы (нажал b).wav"`
   - Sound is added to preload list in `_preload_all_sounds()`
   - Method `play_fire_mode_toggle(position: Vector2)` implemented correctly
   - Volume set to `-3.0 dB`

2. **AssaultRifle (`Scripts/Weapons/AssaultRifle.cs`)**:
   - `PlayFireModeToggleSound()` method correctly calls AudioManager via `GetNodeOrNull("/root/AudioManager")`
   - Called from `ToggleFireMode()` method

3. **Player (`Scripts/Characters/Player.cs`)**:
   - Input handling on B key (`toggle_fire_mode` action) triggers `ToggleFireMode()`

### Root Cause Analysis

Based on extensive research, the most likely root causes are:

#### Primary Hypothesis: Cyrillic Filename Characters

The audio file uses Cyrillic (Russian) characters in the filename: `игрок изменил режим стрельбы (нажал b).wav`

**Evidence from Godot Issues**:
- [GitHub Issue #56406](https://github.com/godotengine/godot/issues/56406): "Android build crashes after adding AudioStream due to audio filename containing non-ASCII characters"
- [GitHub PR #56517](https://github.com/godotengine/godot/pull/56517): "Fix decoding UTF-8 filenames on unzipping" - explicitly mentions this affects exports
- The Godot maintainer confirmed: "The MP3 filename in the MRP contains non-ASCII characters, which are known to work poorly on Android"

While the fix (PR #56517) was implemented in Godot 4.0, 3.5, and 3.4.3, there are still reports of issues with non-ASCII filenames in exports, especially on certain platforms.

#### Secondary Hypotheses

1. **Dynamic Loading Issues (Godot 4.4+)**
   - [Forum Thread](https://forum.godotengine.org/t/after-moving-my-project-to-godot-4-4-almost-all-the-sound-effects-that-i-play-dynamically-stopped-working/104218): Reports of dynamically loaded audio not playing after Godot 4.4 migration
   - Only sounds assigned in the editor work; runtime-loaded sounds fail silently

2. **Export Settings**
   - Although `export_filter="all_resources"` is set, `load()` at runtime may not properly reference files with Unicode paths

3. **Cross-Language Autoload Access**
   - C# code uses `GetNodeOrNull("/root/AudioManager")` to access GDScript autoload
   - This works in editor but may have timing or initialization issues in exports

## Testing Methodology

To verify the root cause:

1. **Test ASCII Filename**: Rename the audio file to `fire_mode_toggle.wav` and update all references
2. **Check Console Logs**: Look for `push_warning("AudioManager: Could not load sound: ...")` messages
3. **Verify Autoload Access**: Add debug logging to confirm AudioManager is found

## Proposed Solutions

### Solution 1: Rename Audio File (Recommended)

Rename the file from Cyrillic to ASCII-only characters:

**Before**: `игрок изменил режим стрельбы (нажал b).wav`
**After**: `fire_mode_toggle.wav`

Update `audio_manager.gd`:
```gdscript
const FIRE_MODE_TOGGLE: String = "res://assets/audio/fire_mode_toggle.wav"
```

**Pros**: Simple, reliable, follows best practices
**Cons**: Changes the original filename

### Solution 2: Preload with @export Resource Type

Instead of using string paths with `load()`, use preloaded resources:

```gdscript
var fire_mode_toggle_stream: AudioStream = preload("res://assets/audio/игрок изменил режим стрельбы (нажал b).wav")
```

**Pros**: Forces Godot to include the resource at compile time
**Cons**: May not resolve Unicode path issues

### Solution 3: Add File to Export Include Filter

In `export_presets.cfg`, explicitly include the audio file:

```
include_filter="*.wav"
```

Or more specifically:
```
include_filter="assets/audio/*"
```

**Pros**: Ensures file is included in export
**Cons**: May not resolve path resolution issues at runtime

## Recommended Action

**Primary Fix**: Rename all audio files with non-ASCII characters to use ASCII-only filenames. This is the most reliable solution based on the documented Godot issues and ensures cross-platform compatibility.

## References

### Godot Documentation
- [Exporting Projects](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html)
- [Singletons (Autoload)](https://docs.godotengine.org/en/stable/tutorials/scripting/singletons_autoload.html)

### Related GitHub Issues
- [#56406 - Android build crashes with non-ASCII audio filenames](https://github.com/godotengine/godot/issues/56406)
- [#56517 - Fix decoding UTF-8 filenames on unzipping](https://github.com/godotengine/godot/pull/56517)
- [#18222 - Corrupt exported Android APK with non-ASCII filenames](https://github.com/godotengine/godot/issues/18222)

### Forum Discussions
- [Stream audio not working in exported game](https://forum.godotengine.org/t/stream-audio-not-working-in-exported-game/119312)
- [Godot 4.4 dynamic audio stopped working](https://forum.godotengine.org/t/after-moving-my-project-to-godot-4-4-almost-all-the-sound-effects-that-i-play-dynamically-stopped-working/104218)
- [Autoload script functions not called in exported build](https://forum.godotengine.org/t/autoload-script-functions-not-being-called-in-exported-build/127658)

## Project Files Affected

| File | Role |
|------|------|
| `assets/audio/игрок изменил режим стрельбы (нажал b).wav` | Audio file (Cyrillic filename) |
| `scripts/autoload/audio_manager.gd` | AudioManager autoload |
| `Scripts/Weapons/AssaultRifle.cs` | Weapon implementation |
| `Scripts/Characters/Player.cs` | Player input handling |
| `project.godot` | Project configuration |
| `export_presets.cfg` | Export settings |
