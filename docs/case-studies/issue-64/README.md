# Case Study: Issue #64 - Fire Mode Toggle Sound Not Playing in Export

## Problem Description

**Issue**: [#64 - добавь звук на нажатие кнопки b](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/64)

**Reported Symptom**: The fire mode toggle sound (B key) works correctly in the Godot editor but does not play in the exported Windows executable.

**Audio File**: Originally `игрок изменил режим стрельбы (нажал b).wav` (Cyrillic filename), renamed to `fire_mode_toggle.wav`

## Timeline of Investigation

### Session 1: Initial Fix (2026-01-12)
1. Identified Cyrillic filename issue
2. Renamed audio file to ASCII: `fire_mode_toggle.wav`
3. Updated AudioManager with `play_fire_mode_toggle` method

### Session 2: Additional Fix (2026-01-12)
1. User reported sound still not playing in export
2. Discovered `load()` vs `preload()` issue
3. Changed to use `preload()` at class level

### Session 3: Root Cause Clarification (2026-01-20)
1. User submitted game log showing `[SoundPropagation]` entries
2. **Key Discovery**: The game log shows features from the `main` branch (SoundPropagation, BuildingLevel scene) that are NOT present in the PR branch
3. **Hypothesis**: User is exporting from `main` branch, not from the PR branch
4. The `main` branch does NOT have the fire mode toggle sound implementation

### Evidence Analysis (Session 3)

**Game Log Analysis** (`game_log_20260120_205151.txt`):
- Shows `[SoundPropagation]` autoload entries (only exists on `main` branch)
- Shows `BuildingLevel` scene (only exists on `main` branch)
- Does NOT show `[AssaultRifle] Fire mode changed to: ...` log entry
- This log entry would appear if the user pressed B key with our PR code

**Branch Comparison**:
| Feature | main branch | PR branch |
|---------|-------------|-----------|
| SoundPropagation autoload | ✅ Yes | ❌ No |
| BuildingLevel scene | ✅ Yes | ❌ No |
| play_fire_mode_toggle method | ❌ No | ✅ Yes |
| PlayFireModeToggleSound call | ❌ No | ✅ Yes |
| fire_mode_toggle.wav file | ❌ No | ✅ Yes |

**Conclusion**: The user needs to build from the PR branch, not the main branch.

## Solution Applied

The fix involves two parts:

1. **Renamed the audio file** from Cyrillic to ASCII: `fire_mode_toggle.wav`
2. **Used `preload()` instead of `load()`** to ensure the resource is compiled into the export

### Key Code Change

```gdscript
# In audio_manager.gd:
# Use preload() at class level to ensure the resource is included in exports
var _fire_mode_toggle_stream: AudioStream = preload("res://assets/audio/fire_mode_toggle.wav")
```

This approach works because `preload()` happens at compile-time, forcing Godot to include the resource in the export package, while `load()` happens at runtime and may fail if the resource isn't properly detected as a dependency.

## Investigation Summary

### Root Cause Analysis

Based on extensive research, two issues were identified:

#### Issue 1: Cyrillic Filename Characters

The original audio file used Cyrillic (Russian) characters in the filename: `игрок изменил режим стрельбы (нажал b).wav`

**Evidence from Godot Issues**:
- [GitHub Issue #56406](https://github.com/godotengine/godot/issues/56406): "Android build crashes after adding AudioStream due to audio filename containing non-ASCII characters"
- [GitHub PR #56517](https://github.com/godotengine/godot/pull/56517): "Fix decoding UTF-8 filenames on unzipping"

#### Issue 2: Dynamic Loading with `load()` in Exports

Even after renaming to ASCII, the sound still didn't work. This is because:
- The AudioManager uses `load()` at runtime in `_preload_all_sounds()`
- In exported builds, `load()` may fail if resources aren't properly detected as dependencies
- [Forum Thread](https://forum.godotengine.org/t/stream-audio-not-working-in-exported-game/119312): Confirms that dynamically loaded audio using `load()` may not work in exports

**Solution**: Use `preload()` instead of `load()` for critical audio resources. `preload()` happens at compile-time, ensuring the resource is bundled with the export.

### Code Implementation

1. **AudioManager (`scripts/autoload/audio_manager.gd`)**:
   - Sound constant defined: `FIRE_MODE_TOGGLE: String = "res://assets/audio/fire_mode_toggle.wav"`
   - Sound is preloaded at class level: `var _fire_mode_toggle_stream: AudioStream = preload(...)`
   - Method `play_fire_mode_toggle(position: Vector2)` implemented correctly
   - Volume set to `-3.0 dB`

2. **AssaultRifle (`Scripts/Weapons/AssaultRifle.cs`)**:
   - `PlayFireModeToggleSound()` method correctly calls AudioManager via `GetNodeOrNull("/root/AudioManager")`
   - Called from `ToggleFireMode()` method

3. **Player (`Scripts/Characters/Player.cs`)**:
   - Input handling on B key (`toggle_fire_mode` action) triggers `ToggleFireMode()`

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

**Primary Fix**: Use `preload()` instead of `load()` for audio resources that must work in exports. Additionally, rename files with non-ASCII characters to ASCII-only filenames for cross-platform compatibility.

**Why `preload()` works**:
- `preload()` happens at compile-time, forcing Godot to include the resource in the export
- `load()` happens at runtime and may fail if resources aren't detected as dependencies
- This is the standard solution for audio not playing in Godot exports

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
