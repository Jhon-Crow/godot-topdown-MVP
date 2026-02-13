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

## Root Cause Analysis (February 2026 Update)

### Issue 1: Missing Breaker Shrapnel

**Symptom:** Breaker bullet shrapnel was visually absent from gameplay.

**Root Cause:** The ProjectilePool was created with methods `get_breaker_shrapnel()` and `return_breaker_shrapnel()`, but:
1. The `_breaker_spawn_shrapnel()` function in `bullet.gd` was still using direct `instantiate()` instead of the pool
2. The `_is_pooled` flag was **never set to true** when projectiles were retrieved from the pool
3. When pooled projectiles called `deactivate()`, it checked `_is_pooled`, which was always `false`, so it fell back to `queue_free()` instead of returning to the pool

### Issue 2: F-1 Grenade Performance Lag

**Symptom:** Significant lag when the F-1 (defensive) grenade exploded.

**Root Cause:**
1. F-1 grenade spawns 40 shrapnel pieces at once using `shrapnel_scene.instantiate()`
2. Each instantiation is expensive (scene parsing, node creation, script initialization)
3. The pool was implemented but `defensive_grenade.gd` was never updated to use it
4. Same issue affected `frag_grenade.gd` and `vog_grenade.gd`

### Timeline of Events

1. **Initial PR (commit 788d2323):** ProjectilePool autoload was created with proper methods, cached references were added to projectile scripts, `deactivate()` methods were added, but:
   - Pool methods were never actually called by spawning code
   - `_is_pooled` flag was never set when getting projectiles from pool

2. **User Feedback:** Repository owner reported both bugs - missing breaker shrapnel and F-1 lag

3. **Root Cause Discovery:** Code analysis revealed the pool was "dead code" - implemented but not integrated

## Fix Implementation

### Fix 1: Set `_is_pooled` Flag in Pool

In `projectile_pool.gd`, added `projectile.set("_is_pooled", true)` when getting projectiles:

```gdscript
# Mark as pooled so deactivate() returns to pool instead of queue_free()
bullet.set("_is_pooled", true)
```

### Fix 2: Update Grenade Shrapnel Spawning

In `defensive_grenade.gd`, `frag_grenade.gd`, and `vog_grenade.gd`:

```gdscript
# Issue #724: Use ProjectilePool for better performance
var projectile_pool: Node = get_node_or_null("/root/ProjectilePool")
var use_pool := projectile_pool != null and projectile_pool.has_method("get_shrapnel")

# Create shrapnel instance (from pool or instantiate)
var shrapnel: Area2D = null
if use_pool:
    shrapnel = projectile_pool.get_shrapnel(scene)
if shrapnel == null and shrapnel_scene != null:
    # Fallback to direct instantiation if pool fails
    shrapnel = shrapnel_scene.instantiate()
```

### Fix 3: Update Breaker Bullet Shrapnel Spawning

In `bullet.gd` `_breaker_spawn_shrapnel()`:

```gdscript
# Issue #724: Use ProjectilePool for better performance
var use_pool := _projectile_pool != null and _projectile_pool.has_method("get_breaker_shrapnel")

# Create shrapnel instance (from pool or instantiate)
var shrapnel: Area2D = null
if use_pool:
    shrapnel = _projectile_pool.get_breaker_shrapnel(scene)
```

### Fix 4: Increase Pool Sizes

Increased shrapnel pool sizes to accommodate F-1 grenade (40 shrapnel at once):
- `MIN_SHRAPNEL_POOL_SIZE`: 32 → 48
- `MAX_SHRAPNEL_POOL_SIZE`: 128 → 200

## Expected Performance Impact

Based on community research and benchmarks:

| Metric | Before Pooling | After Pooling |
|--------|----------------|---------------|
| FPS during F-1 explosion | Significant drop | Stable 60 FPS |
| Memory allocation spikes | Every shrapnel spawn | Pre-allocated at startup |
| GC pressure | High (40 instantiate + queue_free per explosion) | Minimal (reuse existing objects) |

## Lessons Learned

1. **Integration Testing:** When implementing optimization systems, verify they are actually being used by the code paths they're meant to optimize
2. **Flag Initialization:** When pooled objects have a `_is_pooled` flag, ensure it's set when retrieving from pool
3. **Graceful Fallback:** Implement fallback to direct instantiation when pool is unavailable for robustness

## Sources

- [Collision Pairs: optimizing performance of bullet hell games - Godot Forum](https://forum.godotengine.org/t/collision-pairs-optimizing-performance-of-bullet-hell-enemy-hell-games/35027)
- [Bullet Hell Optimization - Godot Forum](https://forum.godotengine.org/t/bullet-hell-optimization/129732)
- [Object Pooling in Game Development: The Complete Guide - Medium](https://medium.com/@mikaznavodya/object-pooling-in-game-development-the-complete-guide-8c52bef04597)
- [Why Your Game Crashes When You Fire 100 Bullets: Mastering Object Pooling - Outscal](https://outscal.com/blog/unreal-engine-object-pooling)
- [Complete Guide to Object Pooling for Godot Performance](https://uhiyama-lab.com/en/notes/godot/godot-object-pooling-basics/)
- [Performance drops when instantiating thousands of objects - Godot Forum](https://forum.godotengine.org/t/performance-drops-when-instantiating-thousands-of-objects/105227)
- [Godot-PerfBullets Plugin](https://github.com/Moonzel/Godot-PerfBullets)
- Existing codebase: `scripts/autoload/audio_manager.gd` (object pool example)
