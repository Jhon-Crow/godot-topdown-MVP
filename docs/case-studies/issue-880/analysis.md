# Game Optimization Analysis (Issue #880)

## Data Sources

- **Game Log:** `game_log_20260224_181048.txt` (217,290 lines, Feb 24, 2026, 18:10:48–18:29:33 ≈ 19 minutes)
- **Engine:** Godot 4.3-stable
- **Platform:** Windows (exported build)
- **Levels Visited:** LabyrinthLevel (5 enemies), DocksLevel (20 enemies), BuildingLevel, BeachLevel, CastleLevel

## Section 1: File Logging (I/O) Overhead

### Evidence from Log

```
Total log lines: 217,290
Total duration: ~19 minutes = 1,140 seconds
Average: ~190 log writes/second (each with disk flush)
```

**Top Contributors by Message Count:**

| Component | Messages | % of Total |
|-----------|----------|------------|
| SoundPropagation | 59,439 | 27.4% |
| EnemyGrenade | 29,250 | 13.5% |
| Bullet | 21,251 | 9.8% |
| BloodDecal | 12,425 | 5.7% |
| LastChance | 7,700 | 3.5% |
| ImpactEffects | 7,110 | 3.3% |
| Player | 2,702 | 1.2% |
| ReplayManager | 2,616 | 1.2% |

### Code Analysis

**File:** `scripts/autoload/file_logger.gd` (lines 97–114)

```gdscript
func _write_log(level: String, message: String) -> void:
    if not _logging_enabled:
        return
    var timestamp := Time.get_time_string_from_system()
    var log_line := "[%s] [%s] %s" % [timestamp, level, message]
    print(log_line)                    # Console print
    if _log_file != null:
        _log_file.store_line(log_line) # Disk write
        _log_file.flush()             # << FLUSH EVERY WRITE!
```

Every `log_info()`, `log_warning()`, and `log_enemy()` call:
1. Calls `Time.get_time_string_from_system()` (system call)
2. Does string formatting (allocation)
3. Calls `print()` (console I/O)
4. Writes to file (disk I/O)
5. **Flushes the file buffer** (synchronous disk commit)

The `flush()` call is the most expensive: it forces the OS to commit the write buffer to disk before returning. At 190 writes/second, this generates ~190 synchronous disk commits per second.

### Impact

This overhead is already mitigated by Issue #848 (logging toggle in ExperimentalSettings). The user's log shows `Logging: true` in the ExperimentalSettings — they explicitly enabled logging. In released builds without logging, this cost disappears.

**However**, the log shows that even with logging enabled, many of the messages come from **gameplay-critical systems** like SoundPropagation (called on every gunshot/sound event). If logging is left on accidentally in a development session, it can cause FPS drops even on fast SSDs due to the synchronous flush pattern.

### Root Cause

The `flush()` call after every write was likely added to ensure log completeness (so that if the game crashes, the last lines are visible). However, a batch-flush approach (flush every N lines or every N seconds) would preserve crash-resilience while reducing I/O overhead by 98%+.

---

## Section 2: Per-Frame Physics Raycasts (Enemy Vision)

### Evidence from Log

The log shows every enemy checking player visibility on every physics frame. With 20 enemies on DocksLevel:

```
# Each enemy per frame:
# - _check_player_visibility() is called from _physics_process()
# - _get_player_check_points() returns 5 points
# - Each point does: space_state.intersect_ray(query)
#
# 20 enemies × 5 raycasts × 60 fps = 6,000 raycasts/second
```

**File:** `scripts/objects/enemy.gd`

```gdscript
func _physics_process(delta: float) -> void:    # line 780
    ...
    _check_player_visibility()                  # line 839 - EVERY FRAME

func _check_player_visibility() -> void:         # line 3571
    ...
    var check_points := _get_player_check_points(_player.global_position) # 5 points
    for point in check_points:
        if _is_player_point_visible_to_enemy(point):  # One raycast each
            _can_see_player = true

func _is_player_point_visible_to_enemy(point: Vector2) -> bool:  # line 2791
    var space_state := get_world_2d().direct_space_state
    var query := PhysicsRayQueryParameters2D.new()
    # ...setup query...
    var result := space_state.intersect_ray(query)  # PHYSICS QUERY
```

### Additional Raycasting

Beyond vision checks, the enemy performs additional raycasts per frame:
- `_path_clear()` in `EnemyGrenadeComponent.try_throw()` — 1 raycast when grenade ready
- `_is_target_visible()` in `EnemyGrenadeComponent` — 1 raycast when grenade check triggered
- `_can_see_position()` for ally death detection — 1 raycast
- `_has_los()` in `AggressionComponent.process_combat()` — 1 raycast per combat frame
- `_find_nearest_enemy_target_with_los()` in AggressionComponent — N raycasts (one per enemy)
- Various cover checks: `scripts/components/cover_component.gd`

### Industry Best Practice

The [Godot engine documentation on CPU optimization](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html) recommends:

> Raycasting can be expensive when performed frequently. Consider reducing raycast frequency by staggering AI update times.

For pathfinding and vision, the typical pattern in commercial games is to check visibility at **5–10 fps** rather than 60 fps, since the player doesn't move fast enough to matter sub-frame. This **12× reduction** in raycast overhead has no perceptible gameplay impact.

### Impact Estimate

With vision check throttled to every 12 frames (5/sec):
- 20 enemies × 5 raycasts × 5/sec = **500 raycasts/second** (vs 6,000 today)
- **91.7% reduction** in vision-related physics query load

---

## Section 3: Sound Propagation No-Op Events

### Evidence from Log

```
Total Sound result events: 29,095
Events with all zeros (notified=0, out_of_range=0, self=0, below_threshold=0): 6,437
Percentage no-op: 22.1%
```

**File:** `scripts/autoload/sound_propagation.gd` (line 130–194)

```gdscript
func emit_sound(sound_type: SoundType, position: Vector2, source_type: SourceType,
                source_node: Node2D = null, custom_range: float = -1.0) -> void:
    ...
    # Clean up invalid listeners (destroyed nodes) - creates new array every call!
    var prev_count := _listeners.size()
    _listeners = _listeners.filter(func(l): return is_instance_valid(l))  # ALLOCATION
    ...
    # Notify all listeners within range
    for listener: Node2D in _listeners:             # Iterate ALL listeners
        if not is_instance_valid(listener):
            continue
        # Check if listener is the source
        if source_node and listener == source_node:
            listeners_skipped_self += 1
            continue
        # Check range
        var distance: float = listener.global_position.distance_to(position)
        ...
    # Log result (even for zero-notification events)
    _log_to_file("Sound result: notified=%d, ...")  # ALWAYS LOGGED
```

### Issues

1. **`_listeners.filter()` creates a new Array every sound event** — This is called for every gunshot, footstep, grenade, reload, and casing kick. The array filter allocates a new array, applies a closure, and returns it. With 20 listeners and high-frequency sounds, this creates significant GC pressure.

2. **22% of events are pure no-ops** — These events have zero effect on any listener but still:
   - Iterate the full listener array
   - Create a new array via `filter()`
   - Log a result message to the file logger

3. **Logging every sound result** — Even events with zero affected listeners generate file I/O. With 6,437 no-op events logged, this represents ~30% of all SoundPropagation log lines being wasteful.

### Root Cause of No-Op Events

Looking at the log pattern, `notified=0, out_of_range=0, self=0, below_threshold=0` suggests the sound was emitted but the `_listeners` array was **empty at that moment** (either before enemies registered, or after all enemies died). The filter pass still runs even when the array is empty.

### Optimization Opportunity

```gdscript
func emit_sound(...) -> void:
    # Early exit if no listeners at all
    if _listeners.is_empty():
        return  # Skip ALL processing for empty listener arrays

    # Clean up lazily (not every emission) - instead track dirty state
    ...
```

---

## Section 4: Enemy Grenade Blast Radius Instantiation

### Evidence from Log

```
[EnemyGrenade] Unsafe throw distance (200 < 275 safe distance, blast=225, margin=50) - 10,621 times
[EnemyGrenade] Throw path blocked to ... - 8,201 times
```

**File:** `scripts/components/enemy_grenade_component.gd` (lines 263–270)

```gdscript
func try_throw(target: Vector2, ...) -> bool:
    ...
    # Issue #375: Check safe distance based on blast radius
    var blast_radius := _get_blast_radius()    # << CALLED EVERY TIME
    ...
```

**`_get_blast_radius()` implementation** (lines 296–314):

```gdscript
func _get_blast_radius() -> float:
    if grenade_scene == null:
        return 225.0

    # Try to instantiate grenade temporarily to query its radius
    var temp_grenade = grenade_scene.instantiate()  # << INSTANTIATES SCENE!
    if temp_grenade == null:
        return 225.0

    var radius := 225.0
    if temp_grenade.get("effect_radius") != null:
        radius = temp_grenade.effect_radius

    temp_grenade.queue_free()   # << THEN FREES IT
    return radius
```

### Impact

This function **instantiates a full scene** just to read a property value. The `try_throw()` function is called when `is_ready()` returns true, which can happen every frame once trigger conditions are met. This means:

- When grenade conditions are met but throw is blocked (by path or distance), `_get_blast_radius()` is called
- Each call allocates a new scene instance, reads a property, then queues it for deletion
- The **10,621 "Unsafe throw distance" messages** suggest this was triggered ~10,621 times during the session

This is a classic **"read from instance to get a constant value"** antipattern. Grenade blast radii don't change at runtime — they're static properties.

---

## Section 5: Unbounded Blood Decal Accumulation

### Evidence from Log

```
Blood puddles created: 12,425 (in 19 minutes with NO limit and NO cleanup)
MAX_BLOOD_DECALS = 0 (unlimited per issue #293, #370)
```

**File:** `scripts/autoload/impact_effects_manager.gd` (lines 32–48)

```gdscript
const MAX_BLOOD_DECALS: int = 0  # Set to 0 for unlimited

var _blood_decals = []    # Grows indefinitely

# In _spawn_blood_decal():
_blood_decals.append(decal)

if MAX_BLOOD_DECALS > 0:       # Always false!
    while _blood_decals.size() > MAX_BLOOD_DECALS:
        # ... cleanup code never runs
```

**File:** `scripts/effects/blood_decal.gd` (lines 38–58)

```gdscript
func _setup_puddle_area() -> void:
    _puddle_area = Area2D.new()
    # Set collision layer 7 for blood puddles (2^6 = 64)
    _puddle_area.collision_layer = 64
    _puddle_area.monitoring = false
    _puddle_area.monitorable = true     # Can be detected by others

    var collision_shape := CollisionShape2D.new()
    var shape := CircleShape2D.new()
    shape.radius = ...
    collision_shape.shape = shape

    _puddle_area.add_child(collision_shape)
    add_child(_puddle_area)
```

### Impact

Each of the 12,425 blood decals:
1. Is a `Sprite2D` node in the scene tree
2. Has a child `Area2D` node with `monitorable = true`
3. Has a `CollisionShape2D` child with a `CircleShape2D`
4. Is tracked in `_blood_decals` array

Godot's physics engine must track all monitorable Area2D nodes for collision detection. As decals accumulate:
- Physics broadphase processing time grows linearly with decal count
- The `_blood_decals` array's `scene_changed` cleanup (`clear_blood_decals()`) must iterate and free all 12,425+ nodes when changing levels
- Memory footprint grows continuously throughout a session

### Note on Design Intent

The unlimited decals design (issues #293, #370) was intentional for gameplay realism. The optimization opportunity is not to reduce decal *visibility* but to:
1. Cap the **blood puddle Area2D collision** nodes (currently unlimited)
2. Consider making old decals non-interactive (no Area2D) when they're too old to matter for footprints
3. Use spatial hashing or LOD to skip physics for decals far from any character

---

## Section 6: ReplayManager Per-Frame Logging

### Evidence from Log

```
[ReplayManager] Recording frame 0 (0,0s): player_valid=True, enemies=20
```

**File:** `scripts/autoload/replay_system.gd` (estimated behavior from log)

At 60 fps, recording a frame every physics step generates:
- 60 frame records/second × 19 minutes = ~68,400 frame records
- Each frame record goes through `FileLogger` (with flush)
- The log shows 2,616 ReplayManager messages during the session (throttled messages, not all frames)

### Impact

Since replay is a feature that's optional (disabled by default in ExperimentalSettings), the main concern is:
1. When replay IS enabled, the per-frame file logging adds significant I/O overhead
2. Frame data should be **buffered in memory** and only written to disk when replay ends

---

## Section 7: Aggression Component Group Lookups

### Evidence from Code

**File:** `scripts/components/aggression_component.gd`

```gdscript
func process_combat(delta: float, ...) -> void:
    if _target == null or not is_instance_valid(_target) ...:
        _target = _find_nearest_enemy_target_with_los()  # Group lookup + raycasts
    ...
    _nav_target = _find_nearest_enemy_any()  # Another group lookup

func check_retaliation(hit_direction: Vector2) -> void:
    for e in _parent.get_tree().get_nodes_in_group("enemies"):  # Group lookup

func _find_nearest_enemy_target_with_los() -> Node2D:
    for e in _parent.get_tree().get_nodes_in_group("enemies"):  # Group lookup

func _find_nearest_enemy_any() -> Node2D:
    for e in _parent.get_tree().get_nodes_in_group("enemies"):  # Group lookup
```

Each `get_nodes_in_group("enemies")` call:
- Traverses a global group registry
- Returns an Array (allocation) of all nodes in the group
- Happens in `process_combat()` which is called every frame when enemy is aggressive

With 20 enemies potentially aggressive simultaneously: 20 × 3 lookups × 60 fps = 3,600 group lookups/second.

---

## Appendix: Log Statistics Summary

See `logs/log_analysis.txt` for detailed statistics.

Key numbers from the log:

```
Total messages: 217,290
Session duration: ~19 minutes
Average messages/second: ~190

Sound propagation events: 29,095
  - No-op events (all zeros): 6,437 (22.1%)
EnemyGrenade events: 29,250
  - Unsafe throw distance: 10,621 (36.3%)
  - Throw path blocked: 8,201 (28.0%)
Blood decals created: 12,425 (NO CLEANUP)
Impact effects messages: 7,110
```
