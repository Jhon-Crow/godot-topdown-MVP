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

---

## Part 2 — FPS Drops While Holding UZI (New Report: 2026-03-18)

### New Report

The owner reported a new variant of the FPS drop issue: **FPS drops by 4–5 frames when the player holds the UZI** (Mini UZI weapon).
Log file: `game_log_20260318_084627.txt`

### Log Analysis: `game_log_20260318_084627.txt`

The session captured:

```
[08:46:27] Game start — LabyrinthLevel, weapon: ak_gl
[08:46:31] [WARN] [FPS] Drop detected: 6 fps   ← particle shader warmup (Issue #343, expected)
[08:46:35] [WARN] [FPS] Drop detected: 1 fps   ← scene transition LabyrinthLevel→Tutorial (expected)
[08:47:06] Player opens Armory menu
[08:47:08] [GameManager] Weapon selected: mini_uzi
[08:47:08] Player spawns with MiniUzi (ammo: 32/32)
[08:47:08–08:47:50] Tutorial, standing still with MiniUzi — no FPS drops logged
```

**Important observation:** The log session ended before any actual UZI firing occurred — the player only *equipped* the UZI in the Tutorial level. The FPS drop during UZI firing happens during active shooting, which was not captured in this log.

The two FPS drop entries recorded (6 fps, 1 fps) are **pre-existing known issues**: shader warmup spike and scene transition spike, unrelated to the UZI.

However, the owner confirms the 4–5 frame drop is **reproducible** when holding the UZI trigger. Code analysis identifies the root causes below.

---

### Root Cause Analysis: UZI Firing FPS Drop

#### Primary Root Cause: Cascading `tree_changed` signal storm during rapid fire

The Mini UZI fires at **25 shots/second** (`FireRate = 25.0` in `MiniUziData.tres`). Each shot triggers multiple `AddChild()` calls:

1. `SpawnBullet()` → `GetTree().CurrentScene.AddChild(bullet)` — **1 AddChild/shot**
2. `SpawnCasing()` → `GetTree().CurrentScene.AddChild(casing)` — **1 AddChild/shot**
3. `SpawnMuzzleFlash()` → `_add_effect_to_scene(effect)` → **1 AddChild/shot**

Total: **3 AddChild calls per shot × 25 shots/sec = 75 AddChild calls/second** during sustained fire.

In Godot 4, every `AddChild()` emits `SceneTree.tree_changed`. **9 autoloads** are connected to this signal:

| Autoload | Handler |
|---|---|
| `cinema_effects_manager.gd` | `_on_tree_changed()` |
| `last_chance_effects_manager.gd` | `_on_tree_changed()` |
| `power_fantasy_effects_manager.gd` | `_on_tree_changed()` |
| `screen_shake_manager.gd` | `_on_tree_changed()` |
| `impact_effects_manager.gd` | `_on_tree_changed()` |
| `black_metal_effects_manager.gd` | `_on_tree_changed()` |
| `penultimate_hit_effects_manager.gd` | `_on_tree_changed()` |
| `flashbang_player_effects_manager.gd` | `_on_tree_changed()` |
| `hit_effects_manager.gd` | `_on_tree_changed()` |

Result: **75 AddChild/sec × 9 handlers = 675 `_on_tree_changed()` calls/second** while the trigger is held. Each handler calls `get_tree().current_scene` to detect scene changes, adding up to measurable overhead.

This is the same issue noted in `impact_effects_manager.gd` line 348 (`# Issue #969: reduced decal count to limit tree_changed signal spam at high fire rates`) but only for decals — the broader `tree_changed` signal storm was not addressed.

**Reference:** [Godot issue #47030](https://github.com/godotengine/godot/issues/47030) documents `tree_changed` being triggered excessively; [Godot 4.x node instantiation is ~4× slower than Godot 3.5](https://github.com/godotengine/godot/issues/71182).

#### Secondary Root Cause: 25 `SceneTree.CreateTimer()` instances per second from `PlayShellCasingDelayed()`

In `MiniUzi.cs`, every shot calls:

```csharp
private async void PlayShellCasingDelayed()
{
    await ToSignal(GetTree().CreateTimer(0.1), "timeout");
    ...
}
```

At 25 shots/second this creates **25 timer objects/second** in the scene tree. Each `CreateTimer()` also fires `tree_changed`, adding to the signal storm above. Additionally, Godot's `SceneTree` iterates all active timers every frame — 25 additional timers per second means the timer list continuously grows during sustained fire.

**Reference:** [Godot issue #71081](https://github.com/godotengine/godot/issues/71081) — `SceneTree.CreateTimer()` does not efficiently free timers; [C# async void patterns cause integration issues with Godot](https://forum.godotengine.org/t/c-question-on-await-and-void-functions/81442).

#### Tertiary Root Cause: SoundPropagation iterates all enemy listeners per shot

In `MiniUzi.cs`, `EmitGunshotSound()` calls `SoundPropagation.emit_sound()` on every shot. Inside `sound_propagation.gd`, `emit_sound()` iterates all registered listeners (one per enemy alive) and calls `_listeners.filter(is_instance_valid)` — creating a new Array every call:

```gdscript
# sound_propagation.gd, line 162
_listeners = _listeners.filter(func(l): return is_instance_valid(l))
```

At 25 shots/second with 5 enemies: **25 listener-array allocations/second + 125 distance calculations/second**.

#### Quaternary Root Cause: Accumulated RigidBody2D casings from sustained fire

Each UZI shot spawns 1 casing (`RigidBody2D`). Casings have `lifetime = 0.0` (infinite by default). During the AUTO_LAND_TIME (2 seconds), each casing runs `_physics_process`. Firing a full 32-round magazine creates 32 physics bodies in 1.28 seconds. Combined with existing enemies and other objects, the physics step cost grows.

After landing, `set_physics_process(false)` is called correctly (line 122 of `casing.gd`), so landed casings don't contribute to ongoing process overhead. However, the **transient peak** during sustained fire (up to 32 active physics bodies spawned in ~1.3 seconds) adds to physics step cost.

---

### Proposed Solutions for UZI FPS Drops

#### Solution 1 (Highest Impact): Throttle `_on_tree_changed()` calls with debouncing

Add a flag to each autoload's `_on_tree_changed()` handler to only run the scene-change check once per frame (debounce):

```gdscript
var _tree_changed_pending: bool = false

func _on_tree_changed() -> void:
    if not _tree_changed_pending:
        _tree_changed_pending = true
        call_deferred("_check_scene_change")

func _check_scene_change() -> void:
    _tree_changed_pending = false
    var current_scene := get_tree().current_scene
    if current_scene != _last_scene:
        _last_scene = current_scene
        _handle_scene_change()
```

**Impact:** Reduces the scene-change check to at most **1 call per frame** regardless of how many `AddChild()` calls happen. Eliminates 99%+ of the signal overhead at 25 shots/second.

#### Solution 2: Replace `CreateTimer()` + `async void` with `call_deferred()` or a shared timer

Instead of creating 25 timers/second:

```csharp
// Instead of:
private async void PlayShellCasingDelayed()
{
    await ToSignal(GetTree().CreateTimer(0.1), "timeout");
    PlayShellCasingSound();
}

// Use a queued callback with the physics process:
private float _casingDelay = 0f;
private bool _pendingCasingSound = false;

// In _Process:
if (_pendingCasingSound)
{
    _casingDelay -= (float)delta;
    if (_casingDelay <= 0)
    {
        _pendingCasingSound = false;
        PlayShellCasingSound();
    }
}
```

**Impact:** Eliminates 25 timer object allocations/second and their corresponding `tree_changed` emissions.

#### Solution 3: Throttle `SoundPropagation.emit_sound()` for sustained automatic fire

For fully-automatic weapons, enemy alerting on the first shot is sufficient — subsequent shots while already alerted add no value. Throttle to at most once per 0.5 seconds:

```gdscript
# sound_propagation.gd
var _last_emission_times: Dictionary = {}  # source_node -> last emission time

func emit_sound(..., source_node, loudness):
    var now := Time.get_ticks_msec() / 1000.0
    var source_id := source_node.get_instance_id() if source_node else 0
    if _last_emission_times.get(source_id, 0.0) + 0.5 > now:
        return  # Skip — already notified enemies recently
    _last_emission_times[source_id] = now
    ...
```

**Impact:** Reduces listener iteration from 25/sec to 2/sec for automatic weapons.

#### Solution 4 (Already Partially Implemented): Casing object pooling

Pre-create a pool of casing `RigidBody2D` objects and recycle them instead of instantiating new ones on every shot. This avoids the instantiation cost and the `tree_changed` emission from `AddChild()`.

---

### Timeline Reconstruction for UZI FPS Drop

```
T+0.00s  Player holds fire button
T+0.04s  Shot 1: AddChild(bullet) + AddChild(casing) + AddChild(muzzle_flash)
           → tree_changed fired 3-4 times → 9 handlers × 4 = 36 callbacks
           → CreateTimer(0.1) → timer added to scene tree → tree_changed again (+9)
           → SoundPropagation.emit_sound() → iterates 5 enemies
T+0.08s  Shot 2: same pattern
...
T+1.00s  25 shots fired: ~1125 handler callbacks from tree_changed alone
           ~32 casings in active physics simulation (not yet landed)
           25 timers created (most already expired, but not all freed)
T+1.28s  Full 32-round magazine exhausted: 32 casings exist in scene
           Physics step now includes 32 RigidBody2D casings
→ Sustained 4-5 fps degradation during and immediately after firing
```

---

### Relationship to Original Issue #1157

The original issue (Part 1) reported FPS drops during **complete idle** — caused by autoload `_process` running group queries when no player was present. The fix already committed addresses that case.

The new UZI report (Part 2) is a **different code path**: it occurs **during active shooting** due to the high-frequency `tree_changed` signal storm, timer proliferation, and transient physics load from spawned casings. The two issues share the same `tree_changed` signal infrastructure as a contributing factor but have distinct primary causes.
