# Technical Analysis: Fire Mode Toggle Sound Export Issue

## Code Flow Analysis

### 1. Input Detection Flow

```
Player.cs::_PhysicsProcess()
    |
    v
Input.IsActionJustPressed("toggle_fire_mode") // B key
    |
    v
Player.cs::ToggleFireMode()
    |
    v
AssaultRifle.cs::ToggleFireMode()
    |
    v
AssaultRifle.cs::PlayFireModeToggleSound()
    |
    v
GetNodeOrNull("/root/AudioManager")
    |
    v
audioManager.Call("play_fire_mode_toggle", GlobalPosition)
```

### 2. AudioManager Sound Loading Flow

```
audio_manager.gd::_ready()
    |
    v
_create_audio_pools()  // Creates AudioStreamPlayer2D pool
    |
    v
_preload_all_sounds()
    |
    v
all_sounds.append(FIRE_MODE_TOGGLE)  // "res://assets/audio/игрок изменил режим стрельбы (нажал b).wav"
    |
    v
for path in all_sounds:
    var stream := load(path) as AudioStream  // <-- POTENTIAL FAILURE POINT
    if stream:
        _audio_cache[path] = stream
```

### 3. Sound Playback Flow

```
audio_manager.gd::play_fire_mode_toggle(position: Vector2)
    |
    v
play_sound_2d(FIRE_MODE_TOGGLE, position, VOLUME_FIRE_MODE_TOGGLE)
    |
    v
_get_stream(path)  // Returns from cache or loads
    |
    v
if stream == null:
    push_warning("AudioManager: Could not load sound: " + path)  // <-- WARNING IF FAILED
    return
    |
    v
_get_available_player_2d()  // Get AudioStreamPlayer2D from pool
    |
    v
player.stream = stream
player.volume_db = volume_db
player.global_position = position
player.play()
```

## Potential Failure Points

### Point 1: Resource Path Resolution

The `load()` function uses the path:
```
"res://assets/audio/игрок изменил режим стрельбы (нажал b).wav"
```

In exported builds, the `res://` paths are resolved from the embedded PCK file. If the PCK packaging doesn't correctly handle UTF-8/Cyrillic characters, the path lookup fails.

### Point 2: Cross-Language Method Invocation

```csharp
// AssaultRifle.cs
var audioManager = GetNodeOrNull("/root/AudioManager");
if (audioManager != null && audioManager.HasMethod("play_fire_mode_toggle"))
{
    audioManager.Call("play_fire_mode_toggle", GlobalPosition);
}
```

The `HasMethod()` check should pass if AudioManager is loaded. The `Call()` method performs cross-language invocation between C# and GDScript.

**Potential Issues**:
- Method name casing differences (GDScript uses snake_case)
- Parameter type marshalling (Vector2 between C# and GDScript)

### Point 3: Autoload Initialization Order

In exported builds, the autoload initialization order may differ from the editor:
1. `InputSettings` (scripts/autoload/input_settings.gd)
2. `GameManager` (scripts/autoload/game_manager.gd)
3. `HitEffectsManager` (scripts/autoload/hit_effects_manager.gd)
4. `AudioManager` (scripts/autoload/audio_manager.gd)

If AudioManager's `_ready()` fails silently during `_preload_all_sounds()`, the cache won't be populated.

## Evidence Comparison: Editor vs Export

| Aspect | Editor | Export |
|--------|--------|--------|
| Resource loading | Direct file access | PCK/ZIP extraction |
| Path resolution | File system lookup | Virtual file system |
| UTF-8 handling | OS native | Godot's internal UTF-8 decoder |
| Error visibility | Console output | Potentially silent |

## Test Script

Create this script to diagnose the issue in exports:

```gdscript
# debug_audio_test.gd
extends Node

func _ready():
    test_audio_loading()

func test_audio_loading():
    var test_paths = [
        "res://assets/audio/игрок изменил режим стрельбы (нажал b).wav",
        "res://assets/audio/m16 1.wav",  # ASCII filename for comparison
    ]

    for path in test_paths:
        var stream = load(path)
        if stream:
            print("SUCCESS: Loaded ", path)
        else:
            print("FAILED: Could not load ", path)

        # Also test file existence
        if FileAccess.file_exists(path):
            print("  File exists at path")
        else:
            print("  File NOT FOUND at path")
```

## Comparison: Working vs Non-Working Audio Files

### Working Audio (ASCII filename)
```gdscript
const M16_SHOTS: Array[String] = [
    "res://assets/audio/m16 1.wav",      // ASCII only
    "res://assets/audio/m16 2.wav",      // ASCII only
    "res://assets/audio/m16 3.wav"       // ASCII only
]
```

### Non-Working Audio (Cyrillic filename)
```gdscript
const FIRE_MODE_TOGGLE: String = "res://assets/audio/игрок изменил режим стрельбы (нажал b).wav"
```

### Pattern Analysis

All other audio files in the project also use Cyrillic:
- `взвод затвора m16 1.wav` - Bolt sounds
- `игрок достал магазин (первая фаза перезарядки).wav` - Reload sounds
- `звук попадания не смертельного попадания.wav` - Hit sounds
- `пуля попала в стену или укрытие (сделать по тише).wav` - Impact sounds

**Question**: Are ALL Cyrillic-named audio files failing, or only the specific fire mode toggle sound?

If ALL Cyrillic audio fails, it confirms the UTF-8 filename theory.
If only this specific file fails, there may be a different issue.

## Debugging Commands

To check audio loading in an exported build:

1. Run with console enabled (`export_console_wrapper=1` in export settings)
2. Look for `push_warning` messages from AudioManager
3. Check for any resource loading errors

## Recommended Fix Implementation

### Option A: Rename Single File (Minimal Change)

```bash
# In assets/audio/
mv "игрок изменил режим стрельбы (нажал b).wav" "fire_mode_toggle.wav"
```

Update `audio_manager.gd`:
```gdscript
const FIRE_MODE_TOGGLE: String = "res://assets/audio/fire_mode_toggle.wav"
```

### Option B: Rename All Cyrillic Files (Comprehensive)

Create ASCII aliases for all audio files for export compatibility:

| Original (Cyrillic) | New (ASCII) |
|---------------------|-------------|
| `игрок изменил режим стрельбы (нажал b).wav` | `fire_mode_toggle.wav` |
| `взвод затвора m16 1.wav` | `m16_bolt_1.wav` |
| `игрок достал магазин (первая фаза перезарядки).wav` | `reload_mag_out.wav` |
| `игрок вставил магазин (вторая фаза перезарядки).wav` | `reload_mag_in.wav` |
| etc. | etc. |

### Option C: Use UID References (Godot 4.x)

Godot 4.x supports UID-based resource references that may work better:

```gdscript
# Instead of path string, use the .import file's uid
const FIRE_MODE_TOGGLE: String = "uid://abc123..."
```

However, UIDs require the `.import` files to be generated, which may not be present in this project.
