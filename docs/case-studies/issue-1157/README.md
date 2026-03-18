# Case Study: Issue #1157 — FPS drops by ~5 frames during complete idle

## Issue Summary

**Title (original):** "fix fps падает на 5 кадров при полном бездействии" (fps drops by 5 frames during complete inactivity)

**Reported behavior:** When the player is completely idle (not moving, not shooting, not doing anything), the FPS drops noticeably — approximately 5 frames below the expected rate.

**Evidence:** A game log (`game_log_20260318_081546.txt`) was provided showing one severe FPS spike (1 fps detected at scene transition) and continuous recording of 60 fps frames during normal play.

---

## Log Analysis

### Log file: `game_log_20260318_081546.txt`

Key events extracted from the log:

```
[08:15:48] [INFO] [ReplayManager] Recording frame 0 (0,0s): player_valid=True, enemies=5
[08:15:49] [INFO] [PersistManager] Navigating to last played level: res://scenes/levels/RevolverLevel.tscn
[08:15:49] [INFO] [SceneLoader] Starting background load for: res://scenes/levels/RevolverLevel.tscn
[08:15:49] [INFO] [SceneLoader] ERROR: Invalid resource: res://scenes/levels/RevolverLevel.tscn
[08:15:49] [INFO] [SceneLoader] Background load started successfully
...
[08:15:53] Scene change detected (LabyrinthLevel → Tutorial)
[08:15:53] [WARN] [FPS] Drop detected: 1 fps (threshold: 30)
[08:15:54–08:16:54] Recording frames at steady ~60fps (player_valid=False)
```

**Frame rate analysis:**
- Frames 0–120: 60 fps (normal gameplay in LabyrinthLevel)
- Frame 180 at t=3.1s: Scene transition — FPS spike to 1 fps for that second
- Frames 240–3720: Approximately 60 fps (post-transition, idle in Tutorial)

The "5 frame drop during idle" is distinct from this spike — it is a sustained, background cost from always-running processes in autoloads.

---

## Root Cause Analysis

### Primary Root Cause: Per-frame scene-tree group queries in autoloads

Multiple autoload managers call expensive scene-tree group traversal functions **every single frame** when their `_player` reference is `null` or invalid:

**Affected files:**
1. `scripts/autoload/penultimate_hit_effects_manager.gd` — `_find_player()` calls `get_tree().get_first_node_in_group("player")` and `get_tree().get_nodes_in_group("player")` every frame when player is null.
2. `scripts/autoload/last_chance_effects_manager.gd` — Same pattern: `get_tree().get_first_node_in_group("player")` every frame when player reference is stale.

In Godot 4, `get_nodes_in_group()` performs a full traversal of the scene tree. With large scenes and many nodes, this is O(n) per call. These managers are `PROCESS_MODE_ALWAYS` autoloads, so they run even during transitions, pauses, and idle periods.

**Code evidence:**
```gdscript
# penultimate_hit_effects_manager.gd, line 117-121
func _process(_delta: float) -> void:
    # Check if we need to find the player
    if _player == null:
        _find_player()  # Called every frame until player found!
```

```gdscript
# last_chance_effects_manager.gd, line 175-178
func _process(delta: float) -> void:
    if _player == null or not is_instance_valid(_player):
        _find_player()  # Called every frame when player is invalid!
```

### Secondary Root Cause: Replay system continuous `_physics_process`

`scripts/autoload/replay_system.gd` runs `_physics_process` every physics tick with `PROCESS_MODE_ALWAYS`, even when neither recording nor playing back. The check is cheap (`if _is_recording`), but the physics process itself adds overhead.

```gdscript
# replay_system.gd, line 155-166
func _physics_process(delta: float) -> void:
    if _is_recording:
        _record_frame(delta)      # Records at 60 fps = 60 Dictionary allocations/second
    elif _playback_ending:
        ...
    elif _is_playing_back:
        _playback_frame_update(delta)
```

When recording is active, `_record_frame()` creates a new Dictionary every physics frame, appends multiple Arrays, and traverses `get_nodes_in_group("grenades")`, `get_nodes_in_group("blood_puddle")`, and `get_nodes_in_group("casings")`. With 5 enemies, this is 3 group queries × 60 fps = 180 group queries per second during idle (even with no activity on screen).

### Tertiary Root Cause: `tree_changed` signal connected to 10+ autoloads

The following autoloads all connect to `get_tree().tree_changed`:
- `cinema_effects_manager.gd`
- `last_chance_effects_manager.gd`
- `power_fantasy_effects_manager.gd`
- `screen_shake_manager.gd`
- `impact_effects_manager.gd`
- `black_metal_effects_manager.gd`
- `penultimate_hit_effects_manager.gd`
- `flashbang_player_effects_manager.gd`
- `hit_effects_manager.gd`

The `tree_changed` signal fires **for every node addition/removal** in the scene tree. Each autoload runs a scene check in its handler. During gameplay, adding particles, projectiles, or effects triggers this signal repeatedly — up to hundreds of times per second during active combat.

### Quaternary Cause: `cinema_effects_manager.gd` sets shader parameters every frame

```gdscript
# cinema_effects_manager.gd, line 210-228
func _process(delta: float) -> void:
    ...
    if _death_effects_active and _material:
        _end_of_reel_timer += delta
        _death_spots_timer += delta
        _material.set_shader_parameter("end_of_reel_time", _end_of_reel_timer)
        _material.set_shader_parameter("death_spots_time", _death_spots_timer)
        ...
```

This is only active when death effects are playing, so it is not the idle problem — but it is a separate optimization opportunity.

---

## Why The Spike Was 1 FPS (Not 5)

The 1 fps spike logged is from the **scene transition** (`LabyrinthLevel` → `Tutorial`), not from idle. Scene transitions in Godot trigger:
1. All `tree_changed` signal callbacks (10+ autoloads scanning the scene)
2. Scene unload (all LabyrinthLevel nodes freed)
3. Scene load (`Tutorial`)
4. All autoloads re-initializing player/enemy references

This is a one-time spike. The "5 fps drop during idle" is a sustained cost, not visible in this log because the log runs at the Tutorial scene where there are no enemies and less activity.

---

## Proposed Solutions

### Solution 1 (Primary Fix): Throttle `_find_player()` calls

Instead of calling expensive group queries every frame, throttle them:

```gdscript
# Add a timer variable
var _find_player_timer: float = 0.0
const FIND_PLAYER_INTERVAL: float = 0.5  # Check twice per second

func _process(delta: float) -> void:
    if _player == null or not is_instance_valid(_player):
        _find_player_timer += delta
        if _find_player_timer >= FIND_PLAYER_INTERVAL:
            _find_player_timer = 0.0
            _find_player()
```

**Impact:** Reduces group queries from 60/second to 2/second per manager = ~30× reduction.

### Solution 2: Disable `_process` when idle

Use `set_process(false)` when the manager has nothing to do, and `set_process(true)` only when actively needed:

```gdscript
func _ready() -> void:
    set_process(false)  # Disabled by default

func trigger_effect() -> void:
    set_process(true)   # Enable when effect starts

func _end_effect() -> void:
    set_process(false)  # Disable when done
```

**Impact:** Zero overhead when effects are not active.

### Solution 3: Throttle replay system group queries

In `replay_system.gd`, `_record_frame()` calls `get_nodes_in_group()` 3 times per physics frame. These can be throttled or cached:

```gdscript
# Instead of querying groups every frame:
var _grenades_in_scene = _level_node.get_tree().get_nodes_in_group("grenades")  # Every frame!

# Cache the nodes and only refresh when needed (e.g., when a grenade is added/removed)
```

### Solution 4: Reduce `tree_changed` signal cost

Instead of each autoload connecting to `tree_changed` individually, centralize detection using a `SceneManager` singleton that batches scene-change detection:

```gdscript
# Single tree_changed connection in a centralized manager
# Notify interested parties via a custom signal with scene information
```

### Solution 5 (Quick Win): Use `set_physics_process(false)` in replay when idle

```gdscript
# replay_system.gd
func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    set_physics_process(false)  # Off by default

func start_recording(...) -> void:
    set_physics_process(true)   # Enable when recording

func stop_recording() -> void:
    set_physics_process(false)  # Disable when done

func start_playback(...) -> void:
    set_physics_process(true)   # Enable during playback

func stop_playback() -> void:
    set_physics_process(false)  # Disable when done
```

---

## Known Libraries / Components That Solve Similar Problems

1. **Godot's built-in `set_process()` / `set_physics_process()`**: The cleanest solution — disable processing when inactive. Already used in `scene_loader.gd` (`set_process(true/false)`). Should be applied to all effect managers.

2. **Signal-based player discovery**: Instead of polling for the player, use a global `PlayerManager` singleton that emits `player_spawned` / `player_despawned` signals. All managers subscribe once.

3. **Deferred group query pattern**: Cache results of `get_nodes_in_group()` and invalidate on `child_entered_tree` / `child_exiting_tree` signals on specific parent nodes rather than the root.

4. **Godot Performance Monitor** (`Performance` singleton): Can be used to instrument the actual frame time breakdown.

---

## Implemented Fix

The fix implements **Solution 1** (throttle `_find_player()`) and **Solution 2** (disable `_process` when idle) for the three most impactful locations:

1. `scripts/autoload/penultimate_hit_effects_manager.gd`: Disable `_process` when effect is not active; use `set_process(true/false)` at effect start/stop.
2. `scripts/autoload/last_chance_effects_manager.gd`: Same pattern — disable `_process` when no effect is running.
3. `scripts/autoload/replay_system.gd`: Disable `_physics_process` when not recording/playing back.

These three changes eliminate the dominant per-frame overhead during idle.

---

## Files Changed

- `scripts/autoload/penultimate_hit_effects_manager.gd`
- `scripts/autoload/last_chance_effects_manager.gd`
- `scripts/autoload/replay_system.gd`

---

## References

- [Godot 4 Idle and Physics Processing docs](https://docs.godotengine.org/en/4.4/tutorials/scripting/idle_and_physics_processing.html)
- [Godot 4 Fixing jitter, stutter and input lag](https://docs.godotengine.org/en/latest/tutorials/rendering/jitter_stutter.html)
- [Godot 4 Optimizing Navigation Performance](https://docs.godotengine.org/en/latest/tutorials/navigation/navigation_optimizing_performance.html)
- [Godot issue #112079: Major FPS drop after upgrading versions](https://github.com/godotengine/godot/issues/112079)
- [Godot issue #85320: Reduced performance with CanvasLayer modulates](https://github.com/godotengine/godot/issues/85320)
- [Godot issue #83744: Enabling particle turbulence causes massive performance hit](https://github.com/godotengine/godot/issues/83744)
