# Case Study: Issue #1145 — FPS Drop When Shooting at Walls

## Summary

**Issue**: FPS drops from 60 to ~27–30 when shooting at walls, reported by user with Mini UZI on the BuildingLevel (10 enemies).

**Root cause**: Redundant physics raycasts in `bullet.gd` — `_get_surface_normal()` is called **twice per wall hit** (once for the dust effect, once for ricochet calculation), even though both calls hit the same wall at the same position in the same physics frame.

**Fix**: Cache the surface normal from the first call in `_on_body_entered` and pass it to both `_spawn_wall_hit_effect()` and `_try_ricochet()` to eliminate the duplicate raycast.

---

## Evidence from Game Log

File: [`game_log_20260318_064123.txt`](./game_log_20260318_064123.txt)

| Time | Event |
|------|-------|
| 06:41:52 | Player starts firing Mini UZI (32 shots total over ~3 seconds) |
| 06:41:55 | `[WARN] [FPS] Drop detected: 29 fps (threshold: 30)` |
| 06:41:56 | `[WARN] [FPS] Drop detected: 26 fps (threshold: 30)` |
| 06:41:57 | `[WARN] [FPS] Drop detected: 27 fps (threshold: 30)` |

The FPS drops begin exactly when shooting starts (line 745) and persist while the gun is empty-clicking (lines 881+). The level has 10 enemies, each running sound propagation + AI logic, but those were present before the drops — the drops are uniquely triggered by shots.

---

## Root Cause: Duplicate Raycasts per Bullet-Wall Collision

### Code path in `scripts/projectiles/bullet.gd`

When a bullet hits a `StaticBody2D` wall, `_on_body_entered()` executes:

```gdscript
# Line 522-524: _on_body_entered
if body is StaticBody2D or body is TileMap:
    _spawn_wall_hit_effect(body)   # ← calls _get_surface_normal(body) → raycast #1
    ...
    if _try_ricochet(body):        # ← calls _get_surface_normal(body) → raycast #2 (DUPLICATE)
```

Both `_spawn_wall_hit_effect` and `_try_ricochet` independently call `_get_surface_normal(body)`:

```gdscript
# Line 967-978: _spawn_wall_hit_effect
func _spawn_wall_hit_effect(body: Node2D) -> void:
    var surface_normal := _get_surface_normal(body)  # raycast
    impact_manager.spawn_dust_effect(global_position, surface_normal, caliber_data)

# Line 680-718: _try_ricochet
func _try_ricochet(body: Node2D) -> bool:
    var surface_normal := _get_surface_normal(body)  # SAME raycast again
    ...
    _perform_ricochet(surface_normal)
```

And `_get_surface_normal` creates a new `PhysicsRayQueryParameters2D` and calls `space_state.intersect_ray()` every time:

```gdscript
# Line 730-749: _get_surface_normal
func _get_surface_normal(body: Node2D) -> Vector2:
    var space_state := get_world_2d().direct_space_state
    var ray_start := global_position - direction * 50.0
    var ray_end := global_position + direction * 10.0
    var query := PhysicsRayQueryParameters2D.create(ray_start, ray_end)
    query.collision_mask = collision_mask
    query.exclude = [self]
    var result := space_state.intersect_ray(query)  # expensive operation
    ...
```

### Secondary issue: `_is_still_inside_obstacle()` in `_physics_process`

While a bullet is penetrating a wall, `_physics_process` calls `_is_still_inside_obstacle()` every frame (60 fps), which fires **2 raycasts per frame** (one forward, one backward). This is bounded by `DEFAULT_MAX_PENETRATION_DISTANCE = 48px` (~1–2 frames at 2500 px/s), so impact is minor, but adds to the overall raycast budget.

### Scale of the problem

With Mini UZI firing at ~10–15 shots/second, each bullet hitting a wall produces **2 raycasts per collision**, while there are already many other raycasts in flight (10 enemies doing AI raycasts, RPG/breaker checks, etc.). The Godot physics BVH must traverse the entire collision tree per query, and the per-query cost grows with scene complexity.

Community benchmarks confirm: 50 objects doing 8 raycasts each (400/frame) on a complex scene can cause unplayable slowdown (Godot Forums). The game has 10 enemies plus bullets, and each wall hit costs 2x the necessary raycasts.

---

## Existing Similar Fixes in This Codebase

This type of redundant-work fix has already been applied:

- **Issue #969**: CASING_KICK sound propagation was throttled after discovering it was being emitted once per shot from high-fire-rate weapons, flooding the propagation system.
- **Issue #724**: Object pooling added to eliminate per-bullet `instantiate()` calls.
- **Issue #343**: Shader warmup to eliminate first-shot lag spikes.
- **Issue #883**: FPS monitoring added, which is how this issue was detected.

---

## Possible Solutions

### Solution 1 (Implemented): Cache surface normal within `_on_body_entered` ✅

Compute `_get_surface_normal(body)` **once** in `_on_body_entered`, then pass it directly to both `_spawn_wall_hit_effect` and `_try_ricochet`, eliminating the duplicate raycast.

**Pros**: Minimal change, no behavioral difference, ~50% reduction in wall-hit raycasts.
**Cons**: None — the normal is the same for both calls.

**Effort**: Very low (add one parameter to two internal methods).

### Solution 2: RaycastBody2D node cached in the bullet

Replace the on-demand `space_state.intersect_ray` with a persistent `RayCast2D` child node. `RayCast2D` can be enabled only when needed and Godot updates it automatically during `_physics_process`, so the result is ready without manual queries.

**Pros**: Cleaner architecture, Godot-native approach.
**Cons**: Requires restructuring bullet scene; adds node overhead for non-wall-hitting bullets.

### Solution 3: Limit total raycasts per frame with a budget

Maintain a global counter of raycasts per physics frame. If budget exceeded (e.g., 100 raycasts/frame), fall back to estimated surface normal (`-direction.normalized()`).

**Pros**: Hard ceiling on physics cost.
**Cons**: Complex; fallback normal means imprecise ricochet at high fire rates.

### Solution 4 (Known library): `godot-blast-bullets-2d` plugin

A Godot plugin using MultiMesh pooling and batch raycasting for thousands of simultaneous bullets. Used by bullet-hell games.

**Pros**: Extreme scalability.
**Cons**: Major architectural change; overkill for this game's scale.

---

## Fix Applied

**File**: `scripts/projectiles/bullet.gd`

Changes:
1. `_on_body_entered`: call `_get_surface_normal(body)` once, store in `cached_normal`.
2. `_spawn_wall_hit_effect(body, normal)`: add `normal` parameter, skip internal raycast if provided.
3. `_try_ricochet(body, normal)`: add `normal` parameter, skip internal raycast if provided.

This eliminates exactly one `intersect_ray` call per bullet-wall collision — a 50% reduction in wall-hit raycast cost.

---

## References

- [Godot 4 ray-casting documentation](https://docs.godotengine.org/en/stable/tutorials/physics/ray-casting.html)
- [PhysicsDirectSpaceState2D](https://docs.godotengine.org/en/stable/classes/class_physicsdirectspacestate2d.html)
- [Godot Forum: Collision Pairs optimization for bullet-hell games](https://forum.godotengine.org/t/collision-pairs-optimizing-performance-of-bullet-hell-enemy-hell-games/35027)
- [Godot Forum: Multithreading intersect_ray raycasts](https://forum.godotengine.org/t/multithreading-intersect-ray-raycasts/52663)
