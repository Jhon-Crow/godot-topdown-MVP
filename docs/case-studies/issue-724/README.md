# Issue #724: Projectile Optimization for Bullet-Hell Scenarios

## Issue Summary

**Original Request (Russian):**
> оптимизируй пули и осколки, не урезая количество и функционал.
> (сделай оптимизацию для ситуации булетхелла).

**Translation:**
> Optimize bullets and shrapnel without reducing quantity or functionality.
> (Make optimization for bullet-hell scenarios).

## Current Implementation Analysis

### Bullet (`scripts/projectiles/bullet.gd`)

The current bullet implementation is feature-rich with:
- Speed: 2500 pixels/second
- Lifetime: 3 seconds
- Trail effect with 8 points
- Ricochet system with probability calculations
- Wall penetration system
- Homing capabilities (optional)
- Breaker bullet detonation system
- Multiple damage calculation methods

**Performance Concerns:**
1. Each bullet is a separate `Area2D` node with its own script instance
2. Trail updates happen every `_physics_process()` call per bullet
3. Multiple raycast operations for ricochet/penetration detection
4. Dynamic array operations for trail position history
5. Audio manager lookups via `get_node_or_null()` every impact

### Shrapnel (`scripts/projectiles/shrapnel.gd`)

- Speed: 5000 pixels/second (2x bullet speed)
- Lifetime: 2 seconds
- 3 ricochets max
- Trail with 6 points
- 1 damage per hit

### Breaker Shrapnel (`scripts/projectiles/breaker_shrapnel.gd`)

Already has some optimizations from Issue #678:
- Added to `breaker_shrapnel` group for counting
- Maximum 10 shrapnel per detonation
- Maximum 60 concurrent breaker shrapnel globally
- Reduced lifetime (0.8s) and trail length (6 points)
- Uses `call_deferred("add_child", shrapnel)` for batch scene tree changes

## Research Findings

### Godot-Specific Optimization Techniques

Based on research from the Godot community:

1. **Object Pooling** - Reuse projectile instances instead of creating/destroying
   - Pre-allocate bullets at game start
   - Reset and reuse instead of `queue_free()` + `instantiate()`
   - The AudioManager already implements this pattern for audio players

2. **Centralized Bullet Manager** - Move logic from individual scripts to manager
   - Distance squared comparisons in single manager achieved 300-400 bullets vs 160 with individual Area2D physics
   - Reduces per-instance computational overhead

3. **Collision Pair Optimization**
   - Disable collision shapes for off-screen projectiles
   - Distance-based collision disabling (10x performance improvement reported)
   - Separate physics layers for different collision types

4. **Variable Declaration Optimization**
   - Declare loop variables outside iteration body
   - Reduces per-frame memory allocation

5. **PhysicsServer Direct Access**
   - Use PhysicsServer2D directly for bulk collision management
   - Skip scene tree overhead for simple collision checks

6. **MultiMesh Rendering**
   - Use MultiMeshInstance2D for rendering many similar objects
   - Shader-based transformations instead of node updates

### Industry Best Practices

From game development resources:

1. **Pool Sizing** - Tune initial pool size to expected concurrent projectiles
   - Avoid over-allocation (100 pooled but only 10 on screen = 90 idle)
   - Allow dynamic expansion when needed

2. **Deactivation Instead of Destruction**
   - Disable visibility and collision
   - Reset movement variables
   - Return to pool for reuse

## Proposed Solutions

### Solution 1: Implement ProjectilePool Autoload

Create a centralized object pool for all projectile types:
- Pre-instantiate bullets and shrapnel at game start
- Provide `get_bullet()` / `return_bullet()` API
- Track active projectile count for monitoring

### Solution 2: Centralized ProjectileManager

Move projectile update logic to a single manager:
- Batch process all active projectiles in single `_physics_process()`
- Use native arrays instead of per-node scene tree
- Centralize collision checking with spatial hashing

### Solution 3: Distance-Based Optimization

Add smart collision disabling:
- Disable collision for projectiles far from all potential targets
- Use squared distance comparisons (avoid sqrt)
- Implement viewport culling for off-screen projectiles

### Solution 4: Trail Optimization

Optimize visual trail effects:
- Reduce trail update frequency (every 2-3 frames instead of every frame)
- Use fixed-size arrays instead of dynamic Array[Vector2]
- Consider shader-based trails for high projectile counts

### Solution 5: Cached Node References

Cache frequently accessed nodes:
- Store AudioManager reference once in `_ready()`
- Store ImpactEffectsManager reference
- Avoid repeated `get_node_or_null()` calls

## Implementation Priority

1. **High Impact, Low Effort:**
   - Cached node references
   - Variable declaration optimization
   - Distance-based collision disabling

2. **High Impact, Medium Effort:**
   - Object pooling for bullets and shrapnel
   - Trail update frequency reduction

3. **High Impact, High Effort:**
   - Centralized ProjectileManager with batch processing
   - MultiMesh rendering

## Sources

- [Collision Pairs: optimizing performance of bullet hell games - Godot Forum](https://forum.godotengine.org/t/collision-pairs-optimizing-performance-of-bullet-hell-enemy-hell-games/35027)
- [Bullet Hell Optimization - Godot Forum](https://forum.godotengine.org/t/bullet-hell-optimization/129732)
- [Object Pooling in Game Development: The Complete Guide - Medium](https://medium.com/@mikaznavodya/object-pooling-in-game-development-the-complete-guide-8c52bef04597)
- [Why Your Game Crashes When You Fire 100 Bullets: Mastering Object Pooling - Outscal](https://outscal.com/blog/unreal-engine-object-pooling)
- Existing codebase: `scripts/autoload/audio_manager.gd` (object pool example)
