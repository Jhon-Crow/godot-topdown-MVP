# Case Study: FPS Drop After Grenade Explosion (Issue #966)

## Problem Statement

After a grenade explosion, FPS drops significantly and remains low for some time. User reports experiencing ~10-29 FPS drops (below the 30 FPS threshold) after grenade explosions in the game.

**Original Issue (Russian):** "оптимизируй производительность" (optimize performance) - "уже после взрыва гранаты некоторое время проседает fps" (after grenade explosion, FPS drops for some time)

## Log Analysis

### Timeline Reconstruction

From the game log `game_log_20260305_222912.txt`:

| Time | Event | FPS |
|------|-------|-----|
| 22:29:14 | Game startup warmup (shader compilation) | 10 fps |
| 22:29:22 | Player throws grenade | - |
| 22:29:23 | **Grenade EXPLODES** at (560, 722) | - |
| 22:29:23 | 40 shrapnel pieces spawned | - |
| 22:29:23 | Sound propagation to 10 listeners | - |
| 22:29:23 | 3 enemies hit (multiple blood effects spawned) | - |
| 22:29:23 | ~90+ blood decals scheduled to spawn | - |
| 22:29:23 | Flashbang effects applied | - |
| 22:29:23 | Scene change initiated (respawn) | - |
| 22:29:24 | FPS drop detected | **24 fps** |
| 22:29:26 | FPS drop continues | **22 fps** |
| 22:29:31 | After another explosion | **26 fps** |
| 22:29:32 | Continued drops | **20 fps** |
| 22:29:33 | Lowest point | **14 fps** |

### Root Causes Identified

#### 1. Mass Blood Decal Instantiation (Primary Cause)

When an enemy is hit, the `spawn_blood_effect()` function schedules delayed blood decal spawns:
- **Non-lethal hit**: 10 decals scheduled
- **Lethal hit**: 20 decals scheduled

With 99 HE damage applied to enemies in the explosion radius:
- Each enemy receives multiple hits (4 HP enemy = 4 blood effects)
- Enemy1: 2 hits = 30 decals
- Enemy2: 4 hits = 60 decals
- Enemy3: 2 hits = 30 decals
- Enemy4: 1 hit = 10 decals

**Total: ~130 blood decals scheduled per explosion**, each using:
```gdscript
await tree.create_timer(delay).timeout  # Creates timer object
var decal := _blood_decal_scene.instantiate()  # Scene instantiation
scene.add_child(decal)  # Scene tree modification
```

The log confirms 90+ `BloodDecal` creation events between 22:29:23 and 22:29:24.

#### 2. Timer Object Overhead

The `_schedule_delayed_decal()` function creates a new `SceneTreeTimer` for EACH decal:
```gdscript
await tree.create_timer(delay).timeout
```

With 130 decals, this creates 130 timer objects that:
- Consume memory
- Must be processed each frame
- Eventually trigger 130 instantiation operations

#### 3. Raycasting Per Decal

Each scheduled decal performs a raycast to check line-of-sight:
```gdscript
var query := PhysicsRayQueryParameters2D.create(origin, landing_pos, WALL_COLLISION_LAYER)
var result: Dictionary = space_state.intersect_ray(query)
```

130 raycasts spread over ~1 second still impact performance.

#### 4. Shrapnel Collision Processing

40 shrapnel pieces traveling at 5000 px/s, each doing:
- Physics process every frame
- Trail updates (6 position points per shrapnel)
- Wall collision detection and ricochet calculations
- Line2D point clearing and adding

#### 5. Concurrent Explosion Light Limit

The `MAX_CONCURRENT_EXPLOSION_LIGHTS = 8` constant limits simultaneous lights, but the log shows multiple explosion sounds propagating to many listeners, suggesting potential visual effect stacking.

## Existing Optimizations

The codebase already has several optimizations:

1. **Projectile Pooling** (`projectile_pool_manager.gd`)
   - Bullets, shrapnel, and breaker shrapnel are pooled
   - Pool sizes: 300 bullets, 150 shrapnel, 200 breaker shrapnel

2. **Explosion Light Pooling** (`impact_effects_manager.gd`)
   - PointLight2D objects pooled (12 pre-created)
   - Maximum 8 concurrent explosion lights
   - Shadows disabled for brief flashes

3. **Shader Warmup** (Issue #343 fix)
   - Particle shaders pre-compiled during loading
   - Prevents first-shot lag

## Proposed Solutions

### Solution 1: Blood Decal Pooling (High Impact)

Instead of instantiating new blood decals, pool and reuse them:

```gdscript
# New constants
const BLOOD_DECAL_POOL_SIZE: int = 200
const MAX_DECALS_PER_FRAME: int = 10  # Batch limit

var _blood_decal_pool: Array[Node2D] = []
var _pending_decal_spawns: Array[Dictionary] = []
```

Benefits:
- Eliminates instantiation overhead
- Spreads decal creation across frames
- Reuses existing objects

### Solution 2: Batch Timer Processing (Medium Impact)

Replace individual timers with a batched approach:

```gdscript
var _pending_decal_spawns: Array[Dictionary] = []

func _process(delta: float) -> void:
    var spawned_this_frame := 0
    while _pending_decal_spawns.size() > 0 and spawned_this_frame < MAX_DECALS_PER_FRAME:
        var spawn_data = _pending_decal_spawns.pop_front()
        if spawn_data.time <= 0:
            _spawn_decal_immediate(spawn_data)
            spawned_this_frame += 1
        else:
            spawn_data.time -= delta
            _pending_decal_spawns.push_back(spawn_data)
            break
```

Benefits:
- Eliminates 130 timer objects
- Limits decals per frame
- Smoother FPS curve

### Solution 3: Reduce Blood Decal Count (Low Impact)

Reduce decal counts while maintaining visual effect:

```gdscript
# Before
var num_decals := 20 if is_lethal else 10

# After
var num_decals := 8 if is_lethal else 4  # 60% reduction
```

### Solution 4: Shrapnel Trail Optimization (Low Impact)

Reduce trail complexity for shrapnel:

```gdscript
# In shrapnel.gd
@export var trail_length: int = 4  # Was 6
```

## Implementation Priority

1. **Blood Decal Pooling** - Highest impact, eliminates instantiation cost
2. **Batch Timer Processing** - Medium impact, smoother performance
3. **Decal Count Reduction** - Quick win, minimal visual impact
4. **Trail Optimization** - Minor improvement

## References

### Performance Optimization Resources
- [Godot General Optimization Tips](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html)
- [GPUParticles2D Documentation](https://docs.godotengine.org/en/stable/classes/class_gpuparticles2d.html)
- [Godot 4 2D Mobile Optimization](https://www.normansoven.com/post/godot-4-2d-mobile-optimization)

### Related Issues in This Codebase
- Issue #724: Projectile optimization for bullet-hell scenarios
- Issue #343: Shader warmup for first-shot lag prevention
- Issue #937: StaticBody2D caching for fast freeze traversal

## Files Affected

- `scripts/autoload/impact_effects_manager.gd` - Blood decal spawning
- `scripts/projectiles/shrapnel.gd` - Trail optimization
- `scripts/projectiles/defensive_grenade.gd` - Shrapnel spawning
