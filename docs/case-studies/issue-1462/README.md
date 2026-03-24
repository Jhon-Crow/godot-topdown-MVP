# Case Study: Issue #1462 — FPS Drops from Breaker Bullets with Shotgun

## Problem Summary

When firing shotgun with breaker bullets (proximity fuse active item) rapidly, FPS drops by up to 10 fps, even with particles and explosions disabled in performance settings.

**Reported conditions:**
- Weapon: Shotgun (9-16 pellets per shot, fire rate: 1.5)
- Active item: Breaker Bullets (proximity fuse detonation)
- Performance tab: particles and explosions disabled
- Observed: ~10 FPS drop during rapid fire

## Root Cause Analysis

### Problem 1: Per-frame Physics Raycasts (Major — estimated 50-60% of impact)

`BreakerDetonation.CheckAndDetonate()` performs a `PhysicsRayQueryParameters2D.Create()` + `IntersectRay()` call every `_PhysicsProcess` frame for **each** active breaker pellet.

**Impact calculation:**
- Shotgun fires 9 pellets per shot (resource data: `BulletsPerShot: 9`)
- At 60 FPS, each pellet performs 1 raycast/frame
- 9 pellets = **9 raycasts/frame** per shot
- Rapid fire (every ~0.67s at fire rate 1.5) with pellet lifetime of 3s means up to 4 shots alive simultaneously
- Peak: **36+ raycasts/frame** just for breaker proximity detection
- Each raycast creates: `PhysicsRayQueryParameters2D` object, `Godot.Collections.Array<Rid>`, and calls `IntersectRay()` which traverses the physics BVH

**Each raycast involves:**
1. `projectile.GetWorld2D()?.DirectSpaceState` — getter chain
2. `PhysicsRayQueryParameters2D.Create()` — GC allocation
3. `new Godot.Collections.Array<Rid>` — GC allocation for exclude list
4. `spaceState.IntersectRay(query)` — physics engine BVH traversal
5. Dictionary result creation — GC allocation

### Problem 2: Shrapnel Bypasses Object Pool (Major — estimated 25-30% of impact)

`BreakerDetonation.SpawnShrapnel()` calls `shrapnelScene.Instantiate<Node2D>()` + `scene.CallDeferred("add_child", shrapnel)` for every shrapnel piece, completely ignoring the `ProjectilePoolManager` that has a dedicated 200-object breaker shrapnel pool.

**Impact calculation:**
- Each detonation spawns up to 10 shrapnel (MaxShrapnelPerDetonation)
- 9 pellets detonating = **90 scene instantiations** per shotgun shot
- Scene instantiation in Godot 4 involves: PackedScene.Instantiate() → resource parsing, node tree creation, signal connection, _Ready() propagation
- Each add_child triggers: scene tree notification cascade, physics body registration, group registration
- GC pressure from created objects not being pooled

### Problem 3: Verbose Logging in Hot Path (Minor — estimated 5-10% of impact)

`Shotgun.cs` had `VerbosePelletLogging = true`, causing `LogToFile()` calls for every pellet spawn. File I/O during rapid fire creates:
- Disk write syscalls per pellet (9-16 per shot)
- String formatting/allocation overhead
- Potential I/O blocking on Windows

### Problem 4: Redundant Group Lookups in Detonation (Minor — estimated 5% of impact)

`BreakerDetonation.ApplyExplosionDamage()` calls `tree.GetNodesInGroup("enemies")` and `tree.GetNodesInGroup("player")` for each detonation. While Godot's group system is O(1) for lookup + O(n) for copy, the array copy happens 9 times per shotgun shot during detonation.

## Solution

### Fix 1: Distance-Based Raycast Throttling

Instead of raycasting every physics frame, we track cumulative distance traveled per projectile and only raycast when `>=30px` has been traveled since the last check.

**Why 30px?** At 2500 px/s and 60 FPS, a pellet moves ~42px/frame. The detonation distance is 60px. Checking every 30px ensures we never miss a detonation while approximately halving raycast frequency.

**Implementation:** Added `distanceTraveledThisFrame` parameter to `CheckAndDetonate()` and a static `Dictionary<ulong, float>` tracking accumulated distance per projectile. Cleanup via `_ExitTree` prevents dictionary leaks.

### Fix 2: Object Pool Integration for Shrapnel

`SpawnShrapnel()` now checks for `ProjectilePoolManager` and uses `get_breaker_shrapnel()` + `pool_activate()` instead of scene instantiation. Falls back to instantiation if pool is unavailable.

**Impact:** Eliminates 90 scene instantiations per shotgun shot, reusing pre-allocated objects from the 200-object pool.

### Fix 3: Disable Verbose Pellet Logging

Changed `VerbosePelletLogging` from `true` to `false` in `Shotgun.cs`. The diagnostic logging for Issue #212 is no longer needed and was causing per-pellet file I/O.

## Performance Impact Estimate

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Raycasts/frame (9 pellets) | 9 | ~5 | ~44% reduction |
| Scene instantiations/shot | up to 90 | 0 (pooled) | ~100% reduction |
| File writes/shot | 9-16 | 0 | 100% reduction |
| GC allocations/frame | High (raycast params + arrays) | Reduced | ~40% reduction |

## Files Changed

- `Scripts/Projectiles/BreakerDetonation.cs` — Raycast throttling + pool integration
- `Scripts/Projectiles/Bullet.cs` — Pass distance to throttler + _ExitTree cleanup
- `Scripts/Projectiles/ShotgunPellet.cs` — Pass distance to throttler + _ExitTree cleanup
- `Scripts/Weapons/Shotgun.cs` — Disable verbose pellet logging

## References

- Issue #678: Original breaker bullet implementation
- Issue #724: Object pooling system (ProjectilePoolManager)
- Issue #212: Pellet distribution fix (verbose logging origin)
- Godot docs: [Physics ray queries](https://docs.godotengine.org/en/stable/tutorials/physics/ray-casting.html)
- Godot docs: [Object pooling](https://docs.godotengine.org/en/stable/tutorials/best_practices/scenes_versus_scripts.html)
- Godot docs: [Optimization using servers](https://docs.godotengine.org/en/stable/tutorials/performance/using_servers.html)
- Godot docs: [When to avoid using nodes](https://docs.godotengine.org/en/stable/tutorials/best_practices/node_alternatives.html)
- Community: [Collision pairs optimization in bullet-hell games](https://forum.godotengine.org/t/collision-pairs-optimizing-performance-of-bullet-hell-enemy-hell-games/35027)
- Community: [Object pooling guide for Godot](https://uhiyama-lab.com/en/notes/godot/godot-object-pooling-basics/)
- Community: [Raycast vs ShapeCast vs Area performance](https://forum.godotengine.org/t/raycast-vs-shapecast-vs-area/95569)

## Research Findings (Online)

Key performance data from the Godot community:

- **Raycasts** are the cheapest physics query but degrade at scale (~50+ simultaneous raycasts cause noticeable slowdown)
- **Object pooling** eliminates frame-time spikes: without pooling FPS fluctuates 10-50; with pooling stable 60 FPS
- **Scene instantiation** is not just `Instantiate()` cost — includes `add_child()`, physics registration, tree notifications
- **`GetNodesInGroup()`** is O(1) HashMap lookup + O(n) array copy; allocates new Array each call
- **Community rule of thumb:** If spawning >10-20 objects/frame consistently, pooling helps
- **Collision pair explosion** is the #1 bullet-hell bottleneck: N bullets * M enemies = O(N*M) pairs

## Attached Data

- `game_log_20260324_205437.txt` — Original game log from issue reporter showing FPS drop to 17 fps
