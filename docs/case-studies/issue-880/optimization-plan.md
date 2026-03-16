# Optimization Plan (Issue #880)

## Overview

This plan is based on analysis of `game_log_20260224_181048.txt` (19-minute session, 217,290 log lines) and code review of all major systems. Items are prioritized by impact and implementation cost.

**Priority Legend:**
- 🔴 CRITICAL — Immediate measurable FPS impact, easy fix
- 🟠 HIGH — Significant performance improvement, moderate complexity
- 🟡 MEDIUM — Important for scale/longevity, requires design consideration
- 🟢 LOW — Minor improvement, quality-of-life for development

---

## Priority 1 (🔴 CRITICAL): File Logger Batch Buffering

### Problem
`FileLogger._write_log()` calls `_log_file.flush()` after **every single write** (file: `scripts/autoload/file_logger.gd`, line 109). At 190 writes/second, this generates 190 synchronous disk commits/second.

### Evidence
217,290 log lines in 19 minutes = 190 writes/second, each flushed immediately.

### Proposed Solution
Replace per-write flush with periodic batch flush:

```gdscript
# In file_logger.gd:
const FLUSH_INTERVAL_SEC: float = 1.0
var _flush_timer: float = 0.0
var _unflushed_writes: int = 0

func _process(delta: float) -> void:
    if not _logging_enabled or _log_file == null:
        return
    _flush_timer += delta
    if _flush_timer >= FLUSH_INTERVAL_SEC:
        _flush_timer = 0.0
        if _unflushed_writes > 0:
            _log_file.flush()
            _unflushed_writes = 0

func _write_log(level: String, message: String) -> void:
    if not _logging_enabled:
        return
    var timestamp := Time.get_time_string_from_system()
    var log_line := "[%s] [%s] %s" % [timestamp, level, message]
    print(log_line)
    if _log_file != null:
        _log_file.store_line(log_line)
        _unflushed_writes += 1
        # Only flush immediately for errors (to preserve crash info)
        if level == "ERROR":
            _log_file.flush()
            _unflushed_writes = 0
```

### On-Crash Safety
For graceful crashes, the `_notification(NOTIFICATION_WM_CLOSE_REQUEST)` handler will flush. For hard crashes, at most 1 second of logs may be lost — acceptable given the benefit.

### Expected Benefit
- 190× reduction in synchronous disk commits
- Eliminates ~190 small OS blocking operations per second
- Estimated FPS improvement: **1–3 fps** on mid-range hardware with HDD

### Existing Precedent
Issue #848 already added a logging toggle for performance. This is the natural next step.

---

## Priority 2 (🟠 HIGH): Enemy Vision Raycast Throttling

### Problem
`_check_player_visibility()` runs every physics frame (60 fps) for every enemy. Each call performs **5 raycasts** via direct space state. With 20 enemies: **6,000 raycasts/second** just for player visibility.

**File:** `scripts/objects/enemy.gd`, lines 839, 3571–3629

### Evidence
Log shows 5 enemies on LabyrinthLevel, 20 on DocksLevel. Every enemy logs ROT_CHANGE messages continuously, indicating full per-frame AI processing.

### Proposed Solution
Stagger vision checks across frames and cache results:

```gdscript
# In enemy.gd, class variables:
const VISION_CHECK_INTERVAL: int = 6  # Check every 6 frames = ~10 fps
var _vision_frame_offset: int = 0     # Set at spawn time

# In _ready() or spawn setup:
# Stagger enemies to check on different frames
var enemy_index := int(Engine.get_physics_frames() % VISION_CHECK_INTERVAL)
_vision_frame_offset = enemy_index

# In _physics_process():
func _physics_process(delta: float) -> void:
    ...
    # Only check vision on designated frames
    if Engine.get_physics_frames() % VISION_CHECK_INTERVAL == _vision_frame_offset:
        _check_player_visibility()
    # _can_see_player retains its last known value between checks
    # (enemies won't "forget" player mid-frame)
    ...
```

### Trade-off Analysis
- At 10 fps vision checks: player could move ~17 pixels between checks (at 170px/s walk speed)
- At 5 fps vision checks: ~34 pixels — still far less than enemy detection radius
- Enemies will still react within 100–200ms of player becoming visible

### Expected Benefit
- With interval=6: **83% reduction** in vision raycasts
- 20 enemies × 5 raycasts / 6 = ~17 raycasts/frame (vs 100)
- Estimated improvement: **2–5 fps** on DocksLevel (20 enemies)

### Alternative: Use RayCast2D Node with auto_update
Instead of manual `force_raycast_update()` in direct space state, attach a `RayCast2D` node to each enemy and let Godot batch the raycast updates. This allows Godot's physics engine to optimize the batch rather than issuing individual synchronous queries.

---

## Priority 3 (🟠 HIGH): Cache Grenade Blast Radius

### Problem
`EnemyGrenadeComponent._get_blast_radius()` instantiates a temporary grenade scene **every time the function is called** to read the `effect_radius` property. This function is called from `try_throw()` which runs when throw conditions are met.

**File:** `scripts/components/enemy_grenade_component.gd`, lines 296–314

### Evidence
10,621 "Unsafe throw distance" messages in the session log. Each represents a call to `try_throw()` → `_get_blast_radius()` → `grenade_scene.instantiate()`.

### Proposed Solution
Cache the blast radius on first access:

```gdscript
# In EnemyGrenadeComponent:
var _cached_blast_radius: float = -1.0  # Sentinel: not yet cached

func _get_blast_radius() -> float:
    # Return cached value if available
    if _cached_blast_radius >= 0.0:
        return _cached_blast_radius

    if grenade_scene == null:
        _cached_blast_radius = 225.0
        return _cached_blast_radius

    # One-time instantiation to read property
    var temp_grenade = grenade_scene.instantiate()
    if temp_grenade == null:
        _cached_blast_radius = 225.0
        return _cached_blast_radius

    if temp_grenade.get("effect_radius") != null:
        _cached_blast_radius = temp_grenade.effect_radius
    else:
        _cached_blast_radius = 225.0

    temp_grenade.queue_free()
    return _cached_blast_radius
```

Also invalidate the cache in `initialize()` when `grenade_scene` can change:
```gdscript
func initialize() -> void:
    _cached_blast_radius = -1.0  # Reset cache if scene changes
    ...
```

### Expected Benefit
- Eliminates **~10,621 scene instantiations** per session
- Replaces O(n) repeated work with O(1) cached lookup
- Estimated improvement: **eliminates micro-stutters** when enemies have active grenade conditions

---

## Priority 4 (🟠 HIGH): Sound Propagation Early Exit + Lazy Cleanup

### Problem
`SoundPropagation.emit_sound()` runs listener cleanup and full iteration even when there are no listeners (22% no-op events). The `filter()` call creates a new array every invocation.

**File:** `scripts/autoload/sound_propagation.gd`, lines 150–194

### Evidence
6,437 out of 29,095 sound events had `notified=0, out_of_range=0, self=0, below_threshold=0`.

### Proposed Solution
Add early-exit and lazy cleanup:

```gdscript
var _listeners_dirty: bool = false  # Track when cleanup is needed

func register_listener(listener: Node2D) -> void:
    if listener and not _listeners.has(listener):
        _listeners.append(listener)
        ...

func unregister_listener(listener: Node2D) -> void:
    var idx := _listeners.find(listener)
    if idx >= 0:
        _listeners.remove_at(idx)

# When a listener becomes invalid (enemy dies), mark dirty instead of scanning
func mark_dirty() -> void:
    _listeners_dirty = true

func emit_sound(sound_type: SoundType, position: Vector2, source_type: SourceType,
                source_node: Node2D = null, custom_range: float = -1.0) -> void:
    # EARLY EXIT: No listeners at all
    if _listeners.is_empty():
        return

    # Lazy cleanup: only scan for invalid listeners when needed
    if _listeners_dirty:
        _listeners = _listeners.filter(func(l): return is_instance_valid(l))
        _listeners_dirty = false

    # EARLY EXIT: After cleanup, still no listeners
    if _listeners.is_empty():
        return

    ...
    # Only log if there are results (avoid logging no-op events)
    if listeners_notified > 0 or _debug_logging:
        _log_to_file("Sound result: notified=%d, ..." % [...])
```

### Expected Benefit
- Eliminates 22% of all sound propagation processing (6,437 early exits)
- Reduces array allocation frequency significantly
- Reduces file log writes by ~6,437 lines per session

---

## Priority 5 (🟡 MEDIUM): Blood Decal Physics Optimization

### Problem
12,425 blood decals created in 19 minutes with no cleanup. Each has an `Area2D` with `monitorable = true`, creating 12,425+ physics shapes tracked by Godot's physics server.

**Files:** `scripts/autoload/impact_effects_manager.gd`, `scripts/effects/blood_decal.gd`

### Evidence
12,425 "Blood puddle created" log messages, `MAX_BLOOD_DECALS = 0` (unlimited).

### Proposed Solution A: Disable Area2D after timeout
Blood puddle physics only matters when a character steps in fresh blood. Old puddles don't need collision:

```gdscript
# In blood_decal.gd:
const PUDDLE_PHYSICS_LIFETIME: float = 60.0  # Keep physics for 1 minute

func _ready() -> void:
    ...
    if is_puddle:
        add_to_group("blood_puddle")
        _setup_puddle_area()
        # Schedule physics disable
        get_tree().create_timer(PUDDLE_PHYSICS_LIFETIME).timeout.connect(_disable_physics)

func _disable_physics() -> void:
    if is_instance_valid(_puddle_area):
        _puddle_area.monitorable = false  # Remove from physics tracking
        # Optionally: remove Area2D entirely
        _puddle_area.queue_free()
        _puddle_area = null
```

### Proposed Solution B: Implement soft decal limit for old decals
Without removing decals (preserving visual fidelity per #293, #370), disable physics for decals beyond a "recent N" threshold:

```gdscript
# In impact_effects_manager.gd:
const MAX_ACTIVE_PUDDLE_PHYSICS: int = 50  # Only most recent 50 have collision

# When adding new decal, disable physics on oldest if over limit:
func _spawn_blood_decal(position, ...):
    ...
    _blood_decals.append(decal)
    if _blood_decals.size() > MAX_ACTIVE_PUDDLE_PHYSICS:
        var oldest_decal = _blood_decals[_blood_decals.size() - MAX_ACTIVE_PUDDLE_PHYSICS - 1]
        if is_instance_valid(oldest_decal) and oldest_decal.has_method("_disable_physics"):
            oldest_decal._disable_physics()
```

### Expected Benefit
- Reduces physics tracking from O(session_time) to O(MAX_ACTIVE_PUDDLE_PHYSICS)
- On a long session (1 hour): prevents 30,000+ physics shapes accumulating
- Estimated improvement: **visible in sessions > 30 minutes** or with many enemies

---

## Priority 6 (🟡 MEDIUM): Aggression Component Enemy Cache

### Problem
`AggressionComponent` calls `get_nodes_in_group("enemies")` up to 3 times per frame per aggressive enemy.

**File:** `scripts/components/aggression_component.gd`

### Proposed Solution
Add a global `EnemyRegistry` autoload or use the existing group with caching:

```gdscript
# Option A: Simple frame-based cache in AggressionComponent
var _cached_enemies: Array = []
var _cache_frame: int = -1

func _get_enemies() -> Array:
    var frame := Engine.get_physics_frames()
    if frame != _cache_frame:
        _cached_enemies = get_tree().get_nodes_in_group("enemies")
        _cache_frame = frame
    return _cached_enemies
```

This ensures at most 1 group lookup per frame per aggressive enemy (vs 3).

---

## Priority 7 (🟡 MEDIUM): Replay Manager Memory Buffering

### Problem
ReplayManager writes frame data through FileLogger (with flush) during recording.

**File:** `scripts/autoload/replay_system.gd`

### Proposed Solution
Buffer replay frame data in memory during recording, write to disk only on replay save:

```gdscript
# Instead of: log_info("Recording frame %d..." % frame_number)  # per frame
# Use in-memory buffer:
var _frame_buffer: Array = []

func _record_frame(frame_data: Dictionary) -> void:
    _frame_buffer.append(frame_data)  # Memory only, no disk I/O

func save_replay(path: String) -> void:
    # Write entire replay at once
    var file = FileAccess.open(path, FileAccess.WRITE)
    for frame in _frame_buffer:
        file.store_string(JSON.stringify(frame) + "\n")
    file.flush()
    file.close()
```

---

## Priority 8 (🟢 LOW): Vision Component Multi-Raycast Optimization

### Problem
`VisionComponent._calculate_visibility_ratio()` performs 5 raycasts per call.

**File:** `scripts/components/vision_component.gd`, lines 134–145

### Proposed Solution
Short-circuit the 5-point check with a fast single-point check first:

```gdscript
func _calculate_visibility_ratio() -> float:
    if not _target:
        return 0.0

    # Fast path: check center point first
    if not _is_point_visible(_target.global_position):
        return 0.0  # Center blocked = likely fully hidden, skip 4 more raycasts

    var check_points := _get_target_check_points(_target.global_position)
    var visible_count := 1  # Already counted center as visible

    for i in range(1, check_points.size()):  # Skip index 0 (already checked)
        if _is_point_visible(check_points[i]):
            visible_count += 1

    return float(visible_count) / float(check_points.size())
```

This skips 4 raycasts when the center is blocked (which is the common case for "fully behind cover").

---

## Summary Table

| Priority | Issue | File | Estimated Benefit | Complexity |
|----------|-------|------|-------------------|------------|
| 🔴 CRITICAL | File logger batch flush | `file_logger.gd` | 1–3 fps, eliminates disk stutter | Low |
| 🟠 HIGH | Enemy vision throttling | `enemy.gd` | 2–5 fps on large levels | Medium |
| 🟠 HIGH | Cache grenade blast radius | `enemy_grenade_component.gd` | Eliminates micro-stutters | Low |
| 🟠 HIGH | Sound propagation early exit | `sound_propagation.gd` | 22% reduction in sound processing | Low |
| 🟡 MEDIUM | Blood decal physics limit | `impact_effects_manager.gd`, `blood_decal.gd` | Long-session performance | Medium |
| 🟡 MEDIUM | Aggression group cache | `aggression_component.gd` | Reduces group lookups 3× | Low |
| 🟡 MEDIUM | Replay memory buffering | `replay_system.gd` | Reduces I/O during recording | Medium |
| 🟢 LOW | Vision short-circuit | `vision_component.gd` | ~40% raycast reduction for hidden targets | Low |

## Implementation Order

1. **Start with low-complexity, high-impact changes** (Priority 1, 3, 4): These are localized changes with no gameplay impact.
2. **Test vision throttling carefully** (Priority 2): Requires playtesting to ensure AI still feels responsive.
3. **Blood decal physics** (Priority 5): Design decision needed — coordinate with level designers.
4. **Aggression cache** (Priority 6): Simple change, low risk.
5. **Replay buffering** (Priority 7): Can be deferred as replay is optional.

## Testing Approach

For each optimization:
1. Enable in-game profiler: `Project > Tools > Profiler`
2. Run DocksLevel (20 enemies) for 2 minutes with active combat
3. Compare frame time in profiler before and after change
4. Verify gameplay behavior is unchanged (enemies still react correctly)

For regression testing, run the full test suite:
```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit,res://tests/integration -ginclude_subdirs -gexit
```
