# Research: Godot 4 Optimization Best Practices (Issue #880)

## Official Godot Documentation

### 1. General Optimization Tips
**Source:** [General optimization tips — Godot Engine (stable)](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html)

Key points:
- **Profile first, optimize later**: Use Godot's built-in profiler before making changes
- **Avoid per-frame allocations**: Don't create objects in `_process()` or `_physics_process()`
- **Reduce physics queries**: Raycasts and shape queries are expensive when used every frame
- **Use `set_process(false)`** when a node doesn't need updates to avoid idle processing

### 2. CPU Optimization
**Source:** [CPU optimization — Godot Engine (stable)](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html)

Key points:
- GDScript function calls have overhead; minimize calls in hot paths
- Object creation (`.new()`, `.instantiate()`) is expensive; prefer pooling
- Array operations on large arrays (especially `filter()`) create allocations
- Group lookups (`get_nodes_in_group()`) iterate global registry — cache results

### 3. Physics and Raycasting
**Source:** [Ray-casting — Godot Engine (4.4)](https://docs.godotengine.org/en/4.4/tutorials/physics/ray-casting.html)

Key points:
- `force_raycast_update()` immediately triggers a physics query (bypasses deferred update)
- Use direct space state (`get_world_2d().direct_space_state.intersect_ray()`) for one-shot queries without a persistent node
- `PhysicsRayQueryParameters2D.create()` is preferred over `new()` + property assignment
- Consider layer masking to reduce collision check overhead

## Industry Patterns

### Object Pooling for Decals and Effects
**Sources:**
- [Complete Guide to Object Pooling for Godot Performance](https://uhiyama-lab.com/en/notes/godot/godot-object-pooling-basics/)
- [CPU optimization — Godot Engine (stable)](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html)

The core pattern for blood decals:
```gdscript
# Anti-pattern: create on hit, free on timeout
var decal = decal_scene.instantiate()  # Allocation every hit
add_child(decal)
await get_tree().create_timer(30.0).timeout
decal.queue_free()  # Deallocation

# Better: Pre-allocate pool, reuse on hit
var _pool: Array = []  # Pre-warmed with N instances
func get_decal() -> BloodDecal:
    if _pool.size() > 0:
        return _pool.pop_back()
    return _create_new_decal()  # Fallback

func return_decal(decal: BloodDecal) -> void:
    decal.visible = false  # Hide instead of free
    _pool.push_back(decal)  # Return to pool
```

Existing implementation: `ProjectilePoolManager` (Issue #724) already demonstrates this pattern. The same approach can be applied to blood decals.

### AI Vision Staggering
**Source:** [GDQuest: Making the most of Godot's speed](https://www.gdquest.com/tutorial/godot/gdscript/optimization-engine/)

For AI vision checks with multiple enemies:

```gdscript
# Anti-pattern: all enemies check same frame
func _physics_process(delta: float) -> void:
    _check_player_visibility()  # ALL enemies check EVERY frame

# Better: stagger across frames
var _vision_frame_offset: int = 0  # Assigned from 0..TOTAL_ENEMIES at spawn

func _physics_process(delta: float) -> void:
    var current_frame := Engine.get_physics_frames()
    if (current_frame % VISION_CHECK_INTERVAL) == _vision_frame_offset:
        _check_player_visibility()  # Only check 1/N frames
```

With `VISION_CHECK_INTERVAL = 6`:
- 20 enemies → each checks every 6 frames (~10 fps)
- Total raycasts/frame: 20/6 ≈ 3–4 enemies checking per frame
- vs 20 enemies every frame (83% reduction)

This pattern is used successfully in commercial games (Valve's AI in Half-Life 2 updates vision at 10 fps despite the game running at 60+ fps).

### Batch Logging / Deferred File Writes
**Source:** General software engineering practice

```gdscript
# Anti-pattern: flush every write
func _write_log(level: String, message: String) -> void:
    _log_file.store_line(log_line)
    _log_file.flush()  # Synchronous disk commit every write!

# Better: buffer and flush periodically
const FLUSH_INTERVAL_SECONDS := 1.0
var _pending_lines: Array[String] = []
var _time_since_flush: float = 0.0

func _write_log(level: String, message: String) -> void:
    _pending_lines.append(log_line)
    # Or flush on frame end via call_deferred

func _flush_to_disk() -> void:
    for line in _pending_lines:
        _log_file.store_line(line)
    _log_file.flush()   # One flush for many lines
    _pending_lines.clear()
```

This reduces disk I/O operations from N-per-second to 1-per-second while maintaining crash resilience (at most 1 second of logs lost on crash).

### Caching Static Properties
**Source:** [General optimization tips — Godot Engine](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html)

```gdscript
# Anti-pattern: instantiate scene to read a constant property
func _get_blast_radius() -> float:
    var temp_grenade = grenade_scene.instantiate()  # Slow!
    var radius := temp_grenade.effect_radius
    temp_grenade.queue_free()
    return radius

# Better: cache on first access
var _cached_blast_radius: float = -1.0  # -1 = not cached yet

func _get_blast_radius() -> float:
    if _cached_blast_radius < 0.0:
        var temp_grenade = grenade_scene.instantiate()
        _cached_blast_radius = temp_grenade.effect_radius
        temp_grenade.queue_free()
    return _cached_blast_radius  # O(1) after first call
```

Since `grenade_scene` doesn't change at runtime (it's set during initialization), the blast radius is effectively a compile-time constant that should only be computed once.

### Sound Propagation Early Exit
**Source:** Code analysis + general algorithmic optimization

```gdscript
# Anti-pattern: iterate all listeners even when none exist
func emit_sound(...) -> void:
    _listeners = _listeners.filter(...)  # Allocation even for empty array
    for listener in _listeners:  # Empty loop has overhead too
        ...
    _log_to_file("Sound result: notified=0, ...")  # Log even for no-op

# Better: early exit for empty listener list
func emit_sound(...) -> void:
    # Quick check before any work
    if _listeners.is_empty():
        return

    # Clean up listeners lazily (not on every emit)
    if _dirty:
        _listeners = _listeners.filter(func(l): return is_instance_valid(l))
        _dirty = false

    if _listeners.is_empty():
        return  # All listeners were invalid
    ...
```

### Known Godot 4 Performance Concerns

1. **`get_nodes_in_group()`**: Returns a new Array every call. With 20+ enemies doing this 3× per frame, the GC pressure is significant. Cache the result in an autoload or use a global `EnemyRegistry` singleton.

2. **`Array.filter()` with closures**: In GDScript, closures have overhead for capture. Prefer manual loops when performance matters.

3. **`PhysicsRayQueryParameters2D.new()`**: Creating a new query object every raycast is slightly slower than reusing one. Use static `create()` method or cache the parameters object.

4. **Decal Area2D with `monitorable = true`**: Every monitorable Area2D is registered in the physics server's overlap detection system. 12,425 monitorable Areas means the physics server must check 12,425 potential overlap pairs per frame.

## Existing Optimizations in Codebase (Good Examples)

The codebase already demonstrates several optimization patterns worth highlighting:

1. **`ProjectilePoolManager`** (Issue #724): Full object pooling for bullets and shrapnel. 300 bullet pool, 150 shrapnel, 200 breaker shrapnel. Pre-warmed during loading screen.

2. **`ImpactEffects` explosion light pool** (lines 1076–1084): Pre-created pool of `PointLight2D` nodes with `MAX_CONCURRENT_EXPLOSION_LIGHTS = 8`.

3. **Shader warmup** (Issue #343): All shaders pre-compiled during game start to avoid runtime hitching.

4. **Log throttling in ROT_CHANGE**: Enemy rotation logging is throttled to prevent spam (`_last_rotation_reason` comparison).

5. **Vision frame throttling (partial)**: Detection delay (`detection_delay = 0.2s`) but the raycast itself still runs every frame.

## Tools for Further Investigation

- **Godot Profiler**: `Project > Tools > Profiler` — shows per-frame time breakdown
- **GPU Profiler**: `Project > Tools > GPU Profiler` — for rendering bottlenecks
- **Network Profiler**: For multiplayer (not applicable here)
- **Debug > Visible Collision Shapes**: Shows all active physics shapes (including blood decal Areas)

## External References

- [GDQuest: Optimization tips](https://www.gdquest.com/tutorial/godot/gdscript/optimization-engine/)
- [Godot docs: General optimization](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html)
- [Godot docs: CPU optimization](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html)
- [Godot docs: Ray-casting](https://docs.godotengine.org/en/4.4/tutorials/physics/ray-casting.html)
- [Object Pooling in Godot](https://uhiyama-lab.com/en/notes/godot/godot-object-pooling-basics/)
- [Godot: AI frame budgeting proposal](https://github.com/godotengine/godot-proposals/issues/3238)
