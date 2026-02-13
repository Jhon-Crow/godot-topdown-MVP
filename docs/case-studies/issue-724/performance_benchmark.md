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

Default pool sizes in `ProjectilePoolManager`:
- Bullets: 100
- Shrapnel: 50
- Breaker Shrapnel: 80

Adjust based on your game's requirements:

```gdscript
# In project settings or script:
var pool_manager = get_node("/root/ProjectilePoolManager")
pool_manager.bullet_pool_size = 200  # For more intense combat
```

## Integration Checklist

- [ ] ProjectilePoolManager registered as autoload
- [ ] Call `warmup()` during loading screen
- [ ] Weapons use `get_bullet()` instead of `instantiate()`
- [ ] Bullets call `pool_deactivate()` instead of `queue_free()`
- [ ] Monitor stats in debug builds
