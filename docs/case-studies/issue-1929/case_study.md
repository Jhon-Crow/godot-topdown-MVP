# Case Study: Music Does Not Stop After Level Clearance (Issue #1929)

## Affected Levels
- ЖД Станция (RailwayStationLevel)
- Полигон (TestTier)
- Двойной коридор (RevolverLevel)
- Доки (DocksLevel)

## Log File
- `game_log_20260503_095214.txt` (47,000 lines)

## Timeline Reconstruction

### Session Start (09:52:14)
- Game starts, SoundSettings initialized (music: 1.00)
- Navigates to last played level: RailwayStationLevel

### RailwayStationLevel (09:52:15)
- GDScript `_ready()` runs: 18 enemies registered
- MusicManager detects new scene, connects to exit zone
- **Level was abandoned without clearing** (no deaths logged, player navigated away)

### BuildingLevel / TestTier (09:52:30)
- C# fallback runs (GDScript binary tokenization bug)
- Exit zone created via `CallDeferred`
- 10 enemies registered
- **Level cleared at 09:52:51** (`LevelInitFallback] All enemies eliminated! Arena cleared!`)
- Exit zone activated → but music stop not logged (no MusicManager logging)

### RevolverLevel — **First attempt** (09:53:29)
- GDScript `_ready()` runs: 14 enemies registered
- MusicManager connects to exit zone in first `_process()` call after `_ready()`
- `_exit_zones_connected = true`

### RevolverLevel — **Second attempt / restart** (09:53:36)
- Scene reloaded (same path `res://scenes/levels/RevolverLevel.tscn`)
- In `MusicManager._sync_to_current_scene()`: `path == _current_scene_path` → EARLY RETURN
- `_exit_zones_connected` is still `true` from the first load
- **NEW exit zone instance from reloaded scene is NEVER connected**
- If player clears this level → `activated` signal emitted but MusicManager never receives it → music keeps playing

### DocksLevel — Multiple restarts (09:55:17, 09:55:25, 09:56:58, 09:57:08)
- Same issue: DocksLevel reloaded 4 times
- After the first load, `_exit_zones_connected = true`
- Subsequent reloads: new exit zone instances never connected to MusicManager
- **Bug reproduced here**: player eventually clears the level → music doesn't stop

### Labyrinth2Level (09:59:36–10:00:31)
- C# fallback runs
- **Cleared at 10:00:31** (Arena cleared!)
- Same issue may apply if level was previously visited

## Root Cause

**File**: `scripts/autoload/music_manager.gd`, function `_sync_to_current_scene()` (lines 137–155)

The MusicManager uses a boolean flag `_exit_zones_connected` to avoid walking the scene tree every frame. When a scene is first loaded, it connects to the exit zone's `activated` signal and sets `_exit_zones_connected = true`.

When the **same level is restarted** (after player death or manual restart), the scene path remains identical. The `_sync_to_current_scene()` function detects `path == _current_scene_path` and, seeing `_exit_zones_connected == true`, **returns immediately without reconnecting**.

The old exit zone node is freed when the scene reloads. The new exit zone instance (created fresh in the reloaded scene) is never connected to MusicManager. When the player clears the level, the new exit zone emits `activated`, but MusicManager never receives it — so the music keeps playing.

### Race Condition Code Path

```gdscript
func _sync_to_current_scene() -> void:
    ...
    if path == _current_scene_path:
        if not _exit_zones_connected:            # ← True because of previous scene load
            _exit_zones_connected = _connect_exit_zones(scene)
        return                                   # ← Returns without reconnecting!
    ...
```

### Affected Levels

All levels that can be restarted are affected, but the issue is most visible on:
- **RailwayStation**: 0 enemies, exit zone activates immediately → if restarted, second load's exit zone never stops music
- **RevolverLevel, DocksLevel**: Many enemies; player often dies and restarts multiple times. On each restart the signal connection is lost.
- **TestTier**: Same issue, plus uses C# fallback which adds additional timing complexity.

## Secondary Issue: C# Fallback Exit Zone Timing

For levels using `LevelInitFallback.cs` (TestTier/BuildingLevel/Labyrinth2Level), the exit zone is created via `CallDeferred` in `_Ready()`. This means on the very first frame after scene load, the exit zone doesn't exist yet in the scene tree. MusicManager's `_process()` fires and calls `_connect_exit_zones()`, which returns `false`. On the next frame, it retries and finds the zone. This is correctly handled by the current code. However, if the level is restarted, the same stale `_exit_zones_connected = true` bug applies.

## Proposed Fix

Track the actual connected exit zone nodes. On each `_sync_to_current_scene()` call when `path == _current_scene_path`, verify that the previously connected nodes are still valid (not freed). If any are invalid, reset `_exit_zones_connected = false` and reconnect.

```gdscript
# New member variable
var _connected_exit_zones: Array = []

func _connect_exit_zones(scene: Node) -> bool:
    var any_found := false
    for node in _find_exit_zones(scene):
        any_found = true
        if node.has_signal("activated") and not node.activated.is_connected(_on_exit_zone_activated):
            node.activated.connect(_on_exit_zone_activated)
            _connected_exit_zones.append(node)  # Track connected nodes
        if "_is_active" in node and node._is_active:
            _on_exit_zone_activated()
    return any_found

func _sync_to_current_scene() -> void:
    ...
    if path == _current_scene_path:
        # Check if previously connected exit zones are still valid
        if _exit_zones_connected:
            _exit_zones_connected = _connected_exit_zones.any(func(n): return is_instance_valid(n))
            if not _exit_zones_connected:
                _connected_exit_zones.clear()
        if not _exit_zones_connected:
            _exit_zones_connected = _connect_exit_zones(scene)
        return
    
    _current_scene_path = path
    _connected_exit_zones.clear()
    _exit_zones_connected = _connect_exit_zones(scene)
    _play_track_for_path(path)
```

## Evidence from Log

- Log line 6470: `[RevolverLevel] GDScript _ready() already ran (enemies tracked: 14) - skipping fallback` — shows second load of RevolverLevel with same path
- Log line 7035: same for another restart
- Log lines 15091, 15787, 21280, 22044: DocksLevel restarted 4 times
- Log line 3481: `Exit zone activated` for BuildingLevel — music should stop here
- Log line 41654: `Exit zone activated` for Labyrinth2Level — music should stop here
- **No MusicManager log entries exist** because MusicManager has no logging — this is a secondary gap

## Impact

The bug occurs on any level that has been visited before (same session or via level select). Music stops correctly only on the very first visit to each level within a session. All restarts (due to death, manual restart, or returning to a previously visited level) lose the signal connection.
