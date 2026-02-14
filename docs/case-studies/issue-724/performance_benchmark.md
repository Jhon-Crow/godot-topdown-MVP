# Performance Benchmark: Projectile Pooling (Issue #724)

## Benchmark Methodology

### Test Setup
- **Test Script**: `experiments/test_projectile_pool.gd`
- **Bullets per Test**: 100
- **Test Iterations**: 10
- **Measured Operations**:
  - Pooled: `get_bullet()` + `pool_activate()`
  - Traditional: `scene.instantiate()` + `add_child()`

### Hardware Requirements
- Results will vary based on hardware
- Run the benchmark on target deployment hardware for accurate numbers

## Expected Results

Based on community benchmarks and theoretical analysis:

| Metric | Pooled | Traditional | Improvement |
|--------|--------|-------------|-------------|
| Spawn time (100 bullets) | ~0.5-1ms | ~5-10ms | 10-20x faster |
| Memory allocations | 0 per spawn | ~50 per spawn | Significant GC reduction |
| Max bullets at 60 FPS | ~1000-2000 | ~200-400 | 5x more capacity |

## Why Pooling Works

### Traditional Instantiation Costs
1. **Scene Parsing**: PackedScene structure parsed
2. **Node Creation**: New node instances allocated
3. **Script Initialization**: `_init()` and `_ready()` called
4. **Signal Connections**: `body_entered`, `area_entered` connected
5. **Tree Operations**: `add_child()` triggers tree entry

### Pooled Activation Costs
1. **Array Pop**: O(1) retrieval from pool array
2. **State Reset**: Simple variable assignments
3. **Property Setting**: Position, direction, shooter_id
4. **Enable Processing**: `set_physics_process(true)`

### Memory Benefits
- No per-frame memory allocations
- Reduced garbage collector pressure
- Predictable memory footprint
- No memory fragmentation

## Running the Benchmark

```gdscript
# From the editor or code:
var test = load("res://experiments/test_projectile_pool.gd").new()
add_child(test)
```

Or attach the script to a Node in a test scene.

## Interpreting Results

### Good Results
- Speedup factor > 5x
- Pool reuse rate > 90%
- Bullets recycled = 0 (pool size sufficient)

### Warning Signs
- High recycle count = pool too small
- Low speedup = possible bottleneck elsewhere
- Memory growth = leaking pooled objects

## Tuning Pool Sizes

Default pool sizes in `ProjectilePoolManager` (optimized for 200+ concurrent projectiles):
- Bullets: 300 (supports 200+ active with headroom for recycling)
- Shrapnel: 150 (for multiple grenade explosions, 4 shrapnel each)
- Breaker Shrapnel: 200 (for breaker bullet chains, up to 10 per breaker)

These sizes are based on research for bullet-hell scenarios like The Binding of Isaac: Rebirth.
See [research.md](./research.md) for detailed optimization research.

Adjust based on your game's requirements:

```gdscript
# In project settings or script:
var pool_manager = get_node("/root/ProjectilePoolManager")
pool_manager.bullet_pool_size = 400  # For more intense combat
```

## Integration Checklist

- [x] ProjectilePoolManager registered as autoload
- [x] Pool warmup configured
- [x] Player uses pooled bullets via `get_bullet()` with fallback
- [x] Enemy uses pooled bullets via `get_bullet()` with fallback
- [x] Grenades use pooled shrapnel via `get_shrapnel()` with fallback
- [x] Breaker bullets use pooled shrapnel via `get_breaker_shrapnel()` with fallback
- [x] Bullets call `_destroy()` which uses `pool_deactivate()` when available
- [x] All projectile types support automatic pooling
