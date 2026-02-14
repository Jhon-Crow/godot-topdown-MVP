# Case Study: Projectile Optimization for Bullet-Hell Scenarios (Issue #724)

## Problem Statement

The game needs optimized bullets and shrapnel (fragments) that can handle bullet-hell scenarios without FPS drops, while maintaining all existing functionality.

**Requirements:**
- Optimize bullets and shrapnel for mass spawning (bullet-hell situations)
- Support 200+ simultaneous projectiles on screen (like The Binding of Isaac: Rebirth)
- Do not reduce quantity, visible bullets, or effects
- Support hundreds to thousands of projectiles simultaneously

## Documentation

| Document | Description |
|----------|-------------|
| [README.md](./README.md) | This overview document |
| [research.md](./research.md) | **Deep case study with online research**, optimization techniques, benchmarks |
| [performance_benchmark.md](./performance_benchmark.md) | Benchmark methodology and results |

## Current Architecture Analysis

### Projectile Types

1. **Bullet (bullet.gd / Bullet.cs)** - 1352 lines GDScript, 1625 lines C#
   - Area2D-based projectile with comprehensive features
   - Features: ricochet, wall penetration, homing, breaker behavior, trails
   - Spawns via `instantiate()` on each shot
   - Destroyed via `queue_free()` on hit/timeout

2. **Shrapnel (shrapnel.gd)** - 250 lines
   - Area2D-based fragment from frag grenades
   - Features: ricochet, wall collision, trails
   - 4 pieces spawned per frag grenade explosion

3. **BreakerShrapnel (breaker_shrapnel.gd)** - 203 lines
   - Area2D-based fragment from breaker bullet detonation
   - Features: smoky trail, no ricochet (destroyed on wall hit)
   - Up to 10 pieces per breaker bullet (capped for performance)

### Current Performance Bottlenecks

1. **Instantiation Overhead**: Each bullet/shrapnel is created via `scene.instantiate()`
2. **Memory Allocation**: Per-projectile arrays for position history (trails)
3. **Signal Connections**: Each projectile connects signals in `_ready()`
4. **Resource Loading**: Caliber data and scene loading per bullet
5. **Raycasting**: Multiple raycasts per frame for ricochet/penetration logic
6. **Group Operations**: `get_tree().get_nodes_in_group()` for targeting

## Optimization Research

### Industry Best Practices for Bullet-Hell Games

Based on research from Godot community forums and documentation:

1. **Object Pooling** - Pre-instantiate projectiles and reuse them
2. **Centralized Management** - Move per-bullet logic to a single manager
3. **Reduce Per-Frame Allocations** - Declare variables outside loops
4. **Physics Layer Optimization** - Minimize collision checks
5. **Distance-Based Collision** - Use squared distance instead of physics when possible

### Existing Optimizations in Codebase

The codebase already has some optimizations:
- `BREAKER_MAX_SHRAPNEL_PER_DETONATION = 10` (cap per bullet)
- `BREAKER_MAX_CONCURRENT_SHRAPNEL = 60` (global cap)
- Reduced trail lengths and lifetimes for breaker shrapnel
- `call_deferred("add_child")` for batched scene tree changes

## Proposed Solution: ProjectilePoolManager

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     ProjectilePoolManager                        │
│                        (Autoload Singleton)                      │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────┐       │
│  │ Bullet Pool │ │ Shrapnel    │ │ BreakerShrapnel    │       │
│  │  (300 max)  │ │ Pool (150)  │ │ Pool (200)         │       │
│  └─────────────┘ └─────────────┘ └─────────────────────┘       │
│                                                                  │
│  Methods:                                                        │
│  - get_bullet() -> Bullet                                        │
│  - get_shrapnel() -> Shrapnel                                    │
│  - get_breaker_shrapnel() -> BreakerShrapnel                     │
│  - return_to_pool(projectile)                                    │
│  - warmup() - Pre-instantiate all pools                          │
│  - get_stats() -> Dictionary                                     │
└─────────────────────────────────────────────────────────────────┘
```

### Pooling Strategy

1. **Pre-instantiation**: Create all pool objects at game start
2. **Reset Instead of Recreate**: When returning to pool, reset state
3. **Overflow Handling**: If pool exhausted, use oldest active projectile
4. **Deferred Returns**: Use `call_deferred()` for thread-safe pool operations

### Projectile Interface Changes

Add these methods to each poolable projectile:

```gdscript
## Called when retrieving from pool (instead of _ready)
func activate(pos: Vector2, dir: Vector2, shooter: int) -> void

## Called when returning to pool (instead of queue_free)
func deactivate() -> void

## Reset all state for reuse
func reset_state() -> void
```

## Implementation Details

See:
- [projectile_pool_manager.gd](../../../scripts/autoload/projectile_pool_manager.gd)
- [optimized_bullet.gd](./optimized_bullet.gd) (design reference)
- [performance_benchmark.md](./performance_benchmark.md)

## Expected Performance Improvements

| Metric | Before | After (Expected) |
|--------|--------|------------------|
| Instantiation time | ~2ms per bullet | ~0.01ms (pool retrieve) |
| Max concurrent bullets | ~300-500 at 60 FPS | ~1000-2000 at 60 FPS |
| Memory allocations/frame | Many (new objects) | Minimal (reuse) |
| GC pressure | High | Low |

## References

### Godot Community Resources
- [Godot Forum: Bullet Hell Optimization](https://forum.godotengine.org/t/bullet-hell-optimization/129732)
- [Godot Forum: Object Pooling](https://forum.godotengine.org/t/object-pooling-with-bullets-of-different-hitboxes/81553)
- [Godot Forum: Collision Pairs Optimization](https://forum.godotengine.org/t/collision-pairs-optimizing-performance-of-bullet-hell-enemy-hell-games/35027)
- [Performance Optimization for Bullet Hells](https://godotforums.org/d/23940-performance-optimization-for-bullet-hells)

### Godot Plugins for Bullet-Hell
- [PerfBullets (MultiMesh + C++)](https://github.com/Moonzel/Godot-PerfBullets)
- [BlastBullets2D (Full-featured C++)](https://github.com/nikoladevelops/godot-blast-bullets-2d)

### Game Development Techniques
- [Little Polygon: Bullet Tech Breakdown](https://blog.littlepolygon.com/posts/bullets/)
- [Toptal: Collision Detection Physics](https://www.toptal.com/game/video-game-physics-part-ii-collision-detection-for-solid-objects)
- [Broad Phase Collision Detection](http://buildnewgames.com/broad-phase-collision-detection/)

### Reference Game
- [The Binding of Isaac: Rebirth Performance Guide](https://www.gamehelper.io/games/the-binding-of-isaac-rebirth/articles/the-binding-of-isaac-rebirth-performance-optimization-guide-best-settings-for-maximum-fps)
