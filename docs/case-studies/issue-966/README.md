# Case Study: Issue #966 - FPS Drops After Grenade Explosion

## Summary

This case study analyzes FPS drops (10-29 fps) that occur after defensive grenade explosions in the game. Initial investigation focused on blood decal spawning, but further analysis revealed multiple root causes that contribute to the performance degradation.

## Timeline of Events

### Initial Report (game_log_20260305_222912.txt)
- **22:29:14** - First FPS drop (10 fps) occurs right after particle shader warmup completes
- **22:29:23** - Player throws defensive grenade, explosion occurs
- **22:29:23-22:29:24** - Multiple FPS drops (24 fps, 22 fps) following grenade explosion
- Pattern repeats throughout gameplay with each grenade explosion

### After Attempted Fix (game_log_20260305_230043.txt)
- Blood decal pooling implemented but broken (all decals at position 0,0)
- **23:01:40** - FPS still drops to 7 fps despite "optimized" blood spawning
- Confirms blood spawning is NOT the primary cause

### Second Test Run (game_log_20260305_230201.txt)
- **23:02:03** - FPS drop (18 fps) occurs right after particle shader warmup
- Pattern confirms shader warmup is a consistent source of FPS drops

## Root Cause Analysis

### Identified Causes (Ranked by Impact)

#### 1. Ragdoll Physics Activation (PRIMARY CAUSE)
**Evidence:** Lines 839-854 in log 2 show:
```
[23:01:39] Enemy2, Enemy3, Enemy4 - Ragdoll activated
[23:01:40] FPS Drop detected: 7 fps
```

**Technical Details:**
- Each dying enemy creates 4 RigidBody2D nodes (body, head, left_arm, right_arm)
- Each dying enemy creates 3 PinJoint2D connections
- When 3 enemies die simultaneously: 12 RigidBody2D + 9 PinJoint2D created at once
- RigidBody2D creation is expensive due to physics engine setup
- Physics engine must recalculate collision pairs for all new bodies

**Source:** `scripts/components/death_animation_component.gd` lines 310-367

#### 2. Particle Shader Warmup (~1300ms)
**Evidence:** Log lines show consistent pattern:
```
[22:29:13] Particle shader warmup complete: 7 effects warmed up in 1290 ms
[22:29:14] FPS Drop detected: 10 fps
```

**Technical Details:**
- GPU shader compilation happens during warmup
- Takes 1290-1298ms across all test runs
- Causes 10-18 fps drops at level start
- Already implemented (Issue #343) but still impacts performance

**Source:** `scripts/autoload/impact_effects_manager.gd` lines 871-1041

#### 3. Shrapnel Spawning (40 projectiles at once)
**Evidence:** Log shows synchronous spawning:
```
[23:01:38] Spawned shrapnel #1 at angle 3.4 degrees
[23:01:38] Spawned shrapnel #2 at angle 21.7 degrees
... (40 total)
```

**Technical Details:**
- Defensive grenade spawns 40 shrapnel pieces synchronously
- Each shrapnel is an Area2D with collision detection
- Object pooling exists but not always used (falls back to instantiation)
- Even with pooling, activating 40 physics objects at once is expensive

**Source:** `scripts/projectiles/defensive_grenade.gd` lines 200-246

#### 4. Blood Decal Timer Creation (SECONDARY CAUSE)
**Technical Details:**
- Each blood effect schedules 10-20 delayed decal spawns
- Uses `await tree.create_timer(delay).timeout` for each decal
- With multiple enemies hit, creates 100+ individual SceneTreeTimer objects
- Timer objects add memory and processing overhead

**Source:** `scripts/autoload/impact_effects_manager.gd` lines 540-596

## Why Blood Decal Optimization Alone Failed

The initial optimization attempt focused on blood decal spawning:
1. Implemented object pooling for blood decals
2. Implemented batch processing (5 decals per frame)

However, FPS still dropped to 7 fps because:
- Ragdoll activation (12 RigidBody2D at once) was the primary cause
- Shrapnel spawning (40 Area2D at once) added significant load
- Blood optimization only addressed a secondary contributing factor

## Recommended Solutions

### Option A: Ragdoll Optimization (Highest Impact)
1. **Stagger ragdoll creation across frames**
   - Instead of creating all body parts at once, spread across 3-4 frames
   - Use a queue-based approach similar to blood decal batching

2. **Simplify ragdoll physics**
   - Reduce from 4 body parts to 2 (body + head)
   - Or use a single RigidBody2D with animated sprite

3. **Ragdoll pooling**
   - Pre-create ragdoll bodies and reuse them
   - Return to pool after death animation completes

### Option B: Shrapnel Spawning Optimization (Medium Impact)
1. **Stagger shrapnel spawning**
   - Spawn 10 shrapnel per frame instead of 40 at once
   - Spread across 4 frames (40/10 = 4 frames)

2. **Ensure pooling is always used**
   - Verify ProjectilePoolManager is available
   - Fall back to staggered instantiation only if pool exhausted

### Option C: Blood Decal Timer Optimization (Lower Impact)
1. **Replace individual timers with queue-based processing**
   - Single _process() function manages all pending decals
   - Similar to existing batch processing but without timers

2. **Limit concurrent blood effects**
   - Cap maximum blood particles during explosions
   - Reduce from 20 decals per kill to 10

## Performance Optimization Research

According to [Godot performance documentation](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html):
- Deeply nested scene hierarchies increase processing overhead
- Improperly configured collision layers cause unexpected physics interactions
- Free unused resources explicitly and use object pooling for frequently instantiated objects

From [Godot object pooling guide](https://uhiyama-lab.com/en/notes/godot/godot-object-pooling-basics/):
- Object Pooling eliminates costly "creation" and "destruction" processes
- Most useful for high-frequency, short-lived objects
- Replaces instantiation spikes with light state-reset processing

From [Godot FPS management guide](https://uhiyama-lab.com/en/notes/godot/godot-fps-management-vsync-settings/):
- Physics interpolation (native in Godot 4.3) helps smooth movement
- The asynchronicity between physics ticks and render frames causes jitter
- Spreading object creation across frames prevents concentration of load

## Files Analyzed

- `docs/case-studies/issue-966/game_log_20260305_222912.txt` - Original report (4111 lines)
- `docs/case-studies/issue-966/game_log_20260305_230043.txt` - After attempted fix (1647 lines)
- `docs/case-studies/issue-966/game_log_20260305_230201.txt` - Second test run (2011 lines)

## Related Code

- `scripts/autoload/impact_effects_manager.gd` - Blood effects and shader warmup
- `scripts/projectiles/defensive_grenade.gd` - Grenade explosion and shrapnel
- `scripts/components/death_animation_component.gd` - Ragdoll physics
- `scripts/projectiles/shrapnel.gd` - Shrapnel projectile
- `scripts/autoload/projectile_pool_manager.gd` - Object pooling system

## Conclusion

The FPS drops after grenade explosions are caused by multiple factors working together:

1. **Ragdoll activation** is the primary cause (creates 12+ physics bodies at once)
2. **Shrapnel spawning** adds additional load (40 Area2D at once)
3. **Blood decal timers** contribute but are secondary
4. **Shader warmup** causes initial FPS drop at level start (separate issue)

The most impactful fix would be to stagger ragdoll creation across multiple frames, similar to how blood decal batching was intended to work.
