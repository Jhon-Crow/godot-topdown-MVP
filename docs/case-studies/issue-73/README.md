# Case Study: Issue #73 - Multiple Sounds Being Cut Off

## Issue Summary

**Title:** fix when there are many sounds - some are not heard (fix kogda mnogo zvukov - nekotorye ne slyshno)
**Repository:** Jhon-Crow/godot-topdown-MVP
**Issue URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/73

## Requirements

Original requirements (translated from Russian):
1. Player shooting sounds are not heard when many other sounds are playing (falling casings, enemy fire, etc.)
2. Reload sounds (e.g., shotgun) are not heard when many other sounds are playing
3. **Goal**: Make it possible for an unlimited number of sounds to play simultaneously

## Current Implementation Analysis

### AudioManager Architecture

The current implementation (`scripts/autoload/audio_manager.gd`) uses a **fixed-size audio player pool**:

```gdscript
## Pool of AudioStreamPlayer nodes for non-positional sounds.
var _audio_pool: Array[AudioStreamPlayer] = []

## Pool of AudioStreamPlayer2D nodes for positional sounds.
var _audio_2d_pool: Array[AudioStreamPlayer2D] = []

## Number of audio players in each pool.
const POOL_SIZE: int = 16
```

### Root Cause

When all 16 players in either pool are busy, the system **interrupts the first player** and reuses it:

```gdscript
## Gets an available non-positional audio player from the pool.
func _get_available_player() -> AudioStreamPlayer:
    for player in _audio_pool:
        if not player.playing:
            return player
    # All players busy, return the first one (will interrupt it)
    return _audio_pool[0]
```

This is a FIFO (First-In-First-Out) voice stealing approach that cuts off the oldest sound. In intense combat scenarios with:
- Multiple weapon shots
- Shell casings dropping
- Enemy gunfire
- Bullet impacts
- Reload sequences

...the pool of 16 players can easily be exhausted, causing important sounds like player gunfire and reload sequences to be cut off.

### Sound Sources in the Game

From the codebase analysis:

| Sound Category | Example | Priority |
|---------------|---------|----------|
| Player shooting | M16, Shotgun, Silenced pistol | HIGH |
| Reload sounds | Magazine in/out, bolt cycling, shell loading | HIGH |
| Enemy shooting | Same weapon sounds | MEDIUM |
| Shell casings | Rifle, pistol, shotgun casings | LOW |
| Bullet impacts | Wall hits, ricochets | MEDIUM |
| Grenades | Activation, throw, landing, explosion | HIGH |

## Technical Background

### Polyphony in Audio Systems

**Polyphony** refers to the ability to play multiple sounds simultaneously. In game audio:

1. **Hardware Voice Limit**: Sound hardware has a maximum number of simultaneous "voices" (typically 32-128 for modern systems)
2. **Software Mixing**: Audio engines mix multiple sounds into a limited number of output channels
3. **Voice Stealing**: When limits are reached, older/less important sounds are interrupted

### Godot Audio Architecture

Godot 4 introduced several mechanisms for handling multiple simultaneous sounds:

#### 1. Max Polyphony Property

Each `AudioStreamPlayer`, `AudioStreamPlayer2D`, and `AudioStreamPlayer3D` has a `max_polyphony` property:

> By default Max Polyphony is set to 1, which means that no more than one instance of that sound can be playing at the same time. Setting a higher value means that the sound can be instantiated multiple times, until the max number of polyphony voices defined is reached.

**Important**: When limit is exceeded, the **oldest sound is cut off**.

Source: [Exploring the new audio features in Godot 4.0](https://blog.blips.fm/articles/exploring-the-new-audio-features-in-godot-40)

#### 2. AudioStreamPolyphonic

Godot 4 introduced `AudioStreamPolyphonic` for programmatic control over multiple sounds:

```gdscript
var player = $SomeNode as AudioStreamPlayer
player.stream = AudioStreamPolyphonic.new()
var playback = player.get_stream_playback() as AudioStreamPlaybackPolyphonic
var id = playback.play_stream(preload("res://Clip1.ogg"))
# Later: control the sound
playback.set_stream_volume(id, -6)
playback.stop_stream(id)
```

Source: [Godot AudioStreamPolyphonic Documentation](https://docs.godotengine.org/en/stable/classes/class_audiostreampolyphonic.html)

#### 3. Dynamic Player Creation

Create and destroy players as needed:

```gdscript
func _play_polyphonic(stream: AudioStream) -> void:
    var new_player := AudioStreamPlayer.new()
    new_player.stream = stream
    new_player.finished.connect(new_player.queue_free)
    get_tree().root.add_child(new_player)
    new_player.play()
```

Source: [Godot Forum - Best practices for multiple audio files](https://godotforums.org/d/30469-best-practices-for-multiple-audio-files)

### AAA Game Audio Priority Systems

Professional game audio implements **priority-based voice management**:

> The human ear cannot distinguish hundreds of independent channels of audio at any given time. It simply becomes a wall of sound, so there needs to be a limit put in place. Every instance of sound that occurs in the game has a direct impact on the amount of CPU being used by the audio engine.

**Key concepts**:

1. **Priority Levels**: Higher priority sounds trump lower priority ones
2. **Voice Stealing**: Lower-priority sounds stop when limits are reached
3. **Virtualization**: Sound data is tracked but not played, resuming later
4. **Ducking**: Lower priority sounds are reduced in volume (not stopped)

Source: [Splice Blog - How to design a dynamic game audio mix](https://splice.com/blog/dynamic-game-audio-mix/)

### Priority Guidelines from Industry

From AAA mixing practices:

> Sounds that are in direct relation to the player character and visible on-screen should always be of high priority. In a third-person game with a fixed avatar, this can include everything from footsteps to spellcasting and weapon fire sounds, since their absence will be disorienting to the player and break immersion.

Source: [AudioTechnology - Mixing AAA Videogames](https://www.audiotechnology.com/features/mixing-aaa-videogames)

## Proposed Solutions

### Solution 1: Increase Pool Size (Simple, Limited)

**Approach**: Simply increase `POOL_SIZE` from 16 to a higher value (e.g., 32, 64).

```gdscript
const POOL_SIZE: int = 64  # Increased from 16
```

**Pros**:
- Simplest change (one line)
- No architectural changes required
- Works for most gameplay scenarios

**Cons**:
- Still has a hard limit
- Memory usage increases
- Not a complete solution for "unlimited sounds"
- Does not implement priority system

**Performance Note**:
> Do not set this value higher than needed as it can potentially impact performance. This will probably only happen when using multiple AudioStreamPlayer nodes set with high polyphony playing at the same time.

Source: [Exploring the new audio features in Godot 4.0](https://blog.blips.fm/articles/exploring-the-new-audio-features-in-godot-40)

---

### Solution 2: Dynamic Pool with Auto-Expansion (Recommended for "Unlimited")

**Approach**: Allow the pool to grow dynamically when needed, with optional cleanup of unused players.

```gdscript
## Minimum pool size (preallocated)
const MIN_POOL_SIZE: int = 16

## Maximum pool size (soft limit, can be disabled)
const MAX_POOL_SIZE: int = 128  # Set to -1 for truly unlimited

## Gets an available player, creating a new one if needed
func _get_available_player_2d() -> AudioStreamPlayer2D:
    # First, try to find an available player in existing pool
    for player in _audio_2d_pool:
        if not player.playing:
            return player

    # No available player - expand pool if allowed
    if MAX_POOL_SIZE == -1 or _audio_2d_pool.size() < MAX_POOL_SIZE:
        var new_player := AudioStreamPlayer2D.new()
        new_player.bus = "Master"
        new_player.max_distance = 2000.0
        add_child(new_player)
        _audio_2d_pool.append(new_player)
        return new_player

    # Pool is at maximum, return oldest (current behavior)
    return _audio_2d_pool[0]
```

**Optional**: Add periodic cleanup of idle players:

```gdscript
var _cleanup_timer: float = 0.0
const CLEANUP_INTERVAL: float = 5.0

func _process(delta: float) -> void:
    _cleanup_timer += delta
    if _cleanup_timer >= CLEANUP_INTERVAL:
        _cleanup_timer = 0.0
        _cleanup_idle_players()

func _cleanup_idle_players() -> void:
    while _audio_2d_pool.size() > MIN_POOL_SIZE:
        var idle_player: AudioStreamPlayer2D = null
        for i in range(_audio_2d_pool.size() - 1, MIN_POOL_SIZE - 1, -1):
            if not _audio_2d_pool[i].playing:
                idle_player = _audio_2d_pool[i]
                _audio_2d_pool.remove_at(i)
                idle_player.queue_free()
                break
        if idle_player == null:
            break
```

**Pros**:
- True "unlimited" sounds possible
- Minimal changes to existing API
- Automatic resource management
- Scales with demand

**Cons**:
- More complex implementation
- Potential memory growth in extreme cases
- Still no priority system

---

### Solution 3: Priority-Based Voice Management (AAA Approach)

**Approach**: Implement a priority system where important sounds (player actions) never get cut off.

```gdscript
enum SoundPriority {
    CRITICAL = 0,  # Never cut off (player shooting, reloading)
    HIGH = 1,      # Cut off last (enemy shooting, explosions)
    MEDIUM = 2,    # Normal (bullet impacts)
    LOW = 3        # Cut off first (shell casings, ambient)
}

class PlayingSound:
    var player: AudioStreamPlayer2D
    var priority: SoundPriority
    var start_time: float

var _playing_sounds: Array[PlayingSound] = []

func play_sound_2d_with_priority(path: String, position: Vector2,
                                  volume_db: float, priority: SoundPriority) -> void:
    var stream := _get_stream(path)
    if stream == null:
        return

    var player := _get_available_player_by_priority(priority)
    if player == null:
        return  # All slots taken by higher priority sounds

    player.stream = stream
    player.volume_db = volume_db
    player.global_position = position
    player.play()

    _register_playing_sound(player, priority)

func _get_available_player_by_priority(priority: SoundPriority) -> AudioStreamPlayer2D:
    # First, find a free player
    for player in _audio_2d_pool:
        if not player.playing:
            return player

    # Find the lowest priority sound that we can steal from
    var lowest_priority: SoundPriority = priority
    var victim: PlayingSound = null

    for sound in _playing_sounds:
        if sound.priority > lowest_priority:  # Lower value = higher priority
            lowest_priority = sound.priority
            victim = sound
        elif sound.priority == lowest_priority and victim != null:
            # Same priority, steal older sound
            if sound.start_time < victim.start_time:
                victim = sound

    if victim != null:
        return victim.player

    return null  # Cannot steal - all sounds are higher priority
```

**Convenience Methods Update**:

```gdscript
## Player shooting - CRITICAL priority
func play_m16_shot(position: Vector2) -> void:
    play_sound_2d_with_priority(M16_SHOTS[randi() % M16_SHOTS.size()],
                                 position, VOLUME_SHOT, SoundPriority.CRITICAL)

## Shell casings - LOW priority (can be cut off)
func play_shell_rifle(position: Vector2) -> void:
    play_sound_2d_with_priority(SHELL_RIFLE, position, VOLUME_SHELL,
                                 SoundPriority.LOW)

## Reload sounds - CRITICAL priority
func play_reload_mag_out(position: Vector2) -> void:
    play_sound_2d_with_priority(RELOAD_MAG_OUT, position, VOLUME_RELOAD,
                                 SoundPriority.CRITICAL)
```

**Pros**:
- Player-critical sounds never cut off
- Industry-standard approach
- Predictable audio behavior
- Excellent user experience

**Cons**:
- Most complex implementation
- Requires updating all convenience methods
- Need to carefully assign priorities

---

### Solution 4: Use AudioStreamPolyphonic (Modern Godot 4 Approach)

**Approach**: Leverage Godot 4's built-in polyphonic audio system.

```gdscript
extends Node

var _poly_player: AudioStreamPlayer
var _poly_2d_player: AudioStreamPlayer2D
var _playback: AudioStreamPlaybackPolyphonic
var _playback_2d: AudioStreamPlaybackPolyphonic

func _ready() -> void:
    # Set up polyphonic streams
    _poly_player = AudioStreamPlayer.new()
    var poly_stream := AudioStreamPolyphonic.new()
    poly_stream.polyphony = 128  # Set maximum concurrent sounds
    _poly_player.stream = poly_stream
    add_child(_poly_player)
    _poly_player.play()
    _playback = _poly_player.get_stream_playback()

    # Similar for 2D (but AudioStreamPolyphonic doesn't support 2D positioning directly)
    _preload_all_sounds()

func play_sound(path: String, volume_db: float = 0.0) -> int:
    var stream := _get_stream(path)
    if stream == null:
        return AudioStreamPlaybackPolyphonic.INVALID_ID

    return _playback.play_stream(stream, 0.0, volume_db, 1.0)
```

**Note**: `AudioStreamPolyphonic` does not directly support 2D positioning. For positional audio, you'd need either:
- Multiple `AudioStreamPlayer2D` nodes with polyphonic streams at different positions
- A hybrid approach using standard pools for 2D audio

**Pros**:
- Native Godot 4 solution
- Very efficient for non-positional sounds
- Configurable polyphony limit

**Cons**:
- Does not support 2D/3D positioning directly
- Requires hybrid approach for this game's needs
- Returns INVALID_ID when polyphony limit reached

Source: [Godot AudioStreamPlaybackPolyphonic Documentation](https://docs.godotengine.org/en/stable/classes/class_audiostreamplaybackpolyphonic.html)

---

### Solution 5: Existing Plugin/Addon Integration

**Approach**: Use a well-maintained audio management addon.

#### Option A: godot_sound_manager by nathanhoad

> A simple music and sound effect player for Godot 4 that handles music crossfades, autodetects probable audio buses for sounds and music, and organizes sounds into UI sounds and local sounds.

- **GitHub**: https://github.com/nathanhoad/godot_sound_manager
- **Features**: Pooled audio players, music crossfading, bus detection
- **Integration**: Copy `addons/sound_manager` to project

#### Option B: Resonate by hugemenace (Deprecated)

> An all-in-one sound and music management addon. The SoundManager automatically pools and orchestrates AudioStreamPlayers and gives control over the players when needed.

- **GitHub**: https://github.com/hugemenace/resonate
- **Features**: Pooled audio stream players, automatic 2D/3D space detection, polyphonic playback

**Note**: This addon is marked as deprecated in the Godot Asset Library.

#### Option C: Audio Manager Tutorial (KidsCanCode)

Recipe-based approach with well-documented code:
- **URL**: https://kidscancode.org/godot_recipes/4.x/audio/audio_manager/
- **GitHub**: https://github.com/godotrecipes/audio_manager
- Adapted from SFXPlayer by TheDuriel

**Pros**:
- Pre-built, tested solutions
- Community-maintained
- Documented best practices

**Cons**:
- External dependency
- May need customization for this project's specific needs
- Potential compatibility issues with future Godot versions

---

## Recommended Solution

For this project, I recommend **Solution 2 (Dynamic Pool with Auto-Expansion)** combined with elements of **Solution 3 (Priority-Based)**:

### Implementation Plan

1. **Phase 1**: Implement dynamic pool expansion ✅ **IMPLEMENTED**
   - Allow pool to grow from 16 up to 128 players
   - Add cleanup mechanism for idle players
   - Minimal API changes

2. **Phase 2**: Add basic priority system ✅ **IMPLEMENTED**
   - Define priority levels for different sound types
   - Player actions (shooting, reloading) = CRITICAL
   - Shell casings, ambient = LOW
   - Oldest low-priority sounds cut first

3. **Phase 3**: Optional - Add configurable settings
   - Allow users to set max pool size in game settings
   - Add audio quality setting that affects pool size

---

## Implementation Status

### Changes Made (PR #362)

The fix was implemented in `scripts/autoload/audio_manager.gd`:

#### 1. Priority System

Added `SoundPriority` enum with four levels:

```gdscript
enum SoundPriority {
    CRITICAL = 0,  ## Never cut off (player shooting, reloading)
    HIGH = 1,      ## Cut off last (enemy shooting, explosions)
    MEDIUM = 2,    ## Normal (bullet impacts)
    LOW = 3        ## Cut off first (shell casings, ambient)
}
```

#### 2. Dynamic Pool Expansion

- `MIN_POOL_SIZE`: 16 (preallocated at startup)
- `MAX_POOL_SIZE`: 128 (hard limit to prevent memory issues)
- Pool grows automatically when all players are busy
- Idle players are cleaned up every 5 seconds

#### 3. Priority-Based Voice Stealing

When pool is at max size, the system:
1. Looks for lower-priority sounds to steal from
2. If same priority, steals from oldest sound
3. CRITICAL sounds are never stolen

#### 4. Priority Assignments

| Sound Type | Priority | Rationale |
|------------|----------|-----------|
| Player shooting (M16, shotgun, silenced) | CRITICAL | Must always be heard |
| Player reload sounds | CRITICAL | Must always be heard |
| Player empty click | CRITICAL | Feedback for player actions |
| Grenade activation/throw | CRITICAL | Player action feedback |
| Enemy shooting | HIGH | Important for gameplay |
| Hit sounds (lethal/non-lethal) | HIGH | Combat feedback |
| Bullets near player | HIGH | Player awareness |
| Explosions | HIGH | Significant events |
| Bullet wall impacts | MEDIUM | Environmental feedback |
| Ricochets | MEDIUM | Environmental feedback |
| Grenade impacts | MEDIUM | Environmental feedback |
| Shell casings (rifle, pistol, shotgun) | LOW | Can be cut off without breaking gameplay |

#### 5. Backward Compatibility

All existing API methods work unchanged. New priority-aware methods added:
- `play_sound_with_priority()`
- `play_sound_2d_with_priority()`
- `play_random_sound_with_priority()`
- `play_random_sound_2d_with_priority()`

#### 6. Debug Utilities

Added helper methods for debugging:
- `set_debug_logging()` - Enable/disable pool debug logs
- `get_pool_size()` / `get_pool_2d_size()` - Current pool sizes
- `get_playing_count()` / `get_playing_2d_count()` - Active sounds

### Files Changed

| File | Changes |
|------|---------|
| `scripts/autoload/audio_manager.gd` | +300 lines: dynamic pool, priority system, updated methods |
| `docs/case-studies/issue-73/logs/` | Game log from user testing |

### Log Files

- `logs/game_log_20260125_050205.txt` - Combat log showing high sound activity

## References

### Official Godot Documentation
- [AudioStreamPolyphonic](https://docs.godotengine.org/en/stable/classes/class_audiostreampolyphonic.html)
- [AudioStreamPlaybackPolyphonic](https://docs.godotengine.org/en/stable/classes/class_audiostreamplaybackpolyphonic.html)
- [Audio Tutorials Index](https://docs.godotengine.org/en/stable/tutorials/audio/index.html)

### Godot Feature Discussions
- [Add polyphony to AudioStreamPlayer - Proposal #1827](https://github.com/godotengine/godot-proposals/issues/1827)
- [Add AudioStreamPolyphonic PR #71855](https://github.com/godotengine/godot/pull/71855)
- [AudioStreamPolyphonic not obvious how it works - Issue #9488](https://github.com/godotengine/godot-docs/issues/9488)

### Game Audio Design Resources
- [Splice - How to design a dynamic game audio mix](https://splice.com/blog/dynamic-game-audio-mix/)
- [AudioTechnology - Mixing AAA Videogames](https://www.audiotechnology.com/features/mixing-aaa-videogames)
- [Gamedeveloper - Game Audio Theory: Ducking](https://www.gamedeveloper.com/audio/game-audio-theory-ducking)
- [The Game Audio Co - 5 Audio Pitfalls Every Developer Should Know](https://www.thegameaudioco.com/5-audio-pitfalls-every-game-developer-should-know)
- [PulseGeek - Audio Pipeline Basics for Game Engines](https://pulsegeek.com/articles/audio-pipeline-basics-for-game-engines/)

### Community Forums and Tutorials
- [Godot Forum - Best way to handle lots of sound effects](https://forum.godotengine.org/t/best-way-to-handle-lots-of-sound-effect/87295)
- [Godot Forum - How to play Polyphonic Audio through code](https://forum.godotengine.org/t/how-to-play-polyphonic-audio-through-code/37854)
- [Blips.fm - Exploring the new audio features in Godot 4.0](https://blog.blips.fm/articles/exploring-the-new-audio-features-in-godot-40)
- [KidsCanCode - Audio Manager Recipe](https://kidscancode.org/godot_recipes/4.x/audio/audio_manager/)

### Audio Addons for Godot
- [godot_sound_manager by nathanhoad](https://github.com/nathanhoad/godot_sound_manager)
- [Resonate by hugemenace](https://github.com/hugemenace/resonate)
- [godot-audio-manager by MarekZdun](https://github.com/MarekZdun/godot-audio-manager)
- [Sound Manager by Xecestel](https://xecestel.itch.io/sound-manager-plugin)

## Related Issues

- Issue #84: Sound Propagation System (related audio implementation)
