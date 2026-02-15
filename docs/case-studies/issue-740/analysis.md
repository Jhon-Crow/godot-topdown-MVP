# Case Study: Issue #740 - Breaker Bullet Shrapnel Spawning Behind Walls

## Issue Summary

**Title:** fix пули с превзрывателем (Fix breaker bullets with proximity fuse)

**Description:** Currently, fragments from breaker bullets can spawn behind the wall that the bullet hit.

**Reporter:** Issue #740

**Related Issues:** #678 (original breaker bullet implementation)

## Problem Statement

When a breaker bullet detonates near a wall (at 60px distance), the spawned shrapnel fragments can appear behind the wall, making them able to hit enemies or travel through solid obstacles incorrectly.

## Timeline/Sequence of Events

From the game log analysis (`game_log_20260210_220326.txt`):

1. **22:03:26** - Game starts, breaker bullets feature initialized
2. **22:03:27** - Grenade manager loaded (FragGrenade scene)
3. **22:03:31** - First breaker bullets activation logged: "Breaker bullets active — bullets will detonate 60px before walls"
4. **22:03:32** - First explosion effect spawned at (283.9472, 1002.239) with radius=15, using shadow-based wall occlusion
5. **Multiple subsequent detonations** throughout the log at various positions near walls

The log shows the breaker system is working as designed for detonation detection, but does not capture the shrapnel spawning positions (which is where the bug occurs).

## Root Cause Analysis

After analyzing the codebase, the root cause is identified in `/scripts/projectiles/bullet.gd`:

### Current Breaker Bullet Flow

1. **Detonation Check** (`_check_breaker_detonation()`, line ~1095):
   - Raycasts 60px ahead in bullet direction
   - If wall detected within 60px → triggers detonation at bullet's `global_position`

2. **Detonation** (`_breaker_detonate()`, line 1134):
   - Detonation position = current bullet `global_position`
   - Spawns explosion effect at this position
   - Calls `_breaker_spawn_shrapnel(detonation_pos)`

3. **Shrapnel Spawning** (`_breaker_spawn_shrapnel()`, line 1270):
   ```gdscript
   for i in range(shrapnel_count):
       var random_angle := randf_range(-half_angle_rad, half_angle_rad)
       var shrapnel_direction := direction.rotated(random_angle)

       # Create shrapnel instance
       var shrapnel := _breaker_shrapnel_scene.instantiate()

       # BUG IS HERE:
       shrapnel.global_position = center + shrapnel_direction * 5.0  # Line 1309
       shrapnel.direction = shrapnel_direction
   ```

### The Problem

The issue occurs at **line 1309** in `bullet.gd`:

```gdscript
shrapnel.global_position = center + shrapnel_direction * 5.0
```

**Why this causes shrapnel behind walls:**

1. The bullet detonates at distance X from the wall (where X ≤ 60px)
2. The `center` is the bullet's current position (60px or less from wall)
3. Each shrapnel direction is randomized within ±30° cone (60° total)
4. Each shrapnel spawns at `center + shrapnel_direction * 5.0`
5. **Problem:** When `shrapnel_direction` points toward the wall (within the cone), the 5px offset moves the shrapnel spawn position **closer to or even through the wall**

**Scenario Visualization:**

```
Wall                 Bullet (60px from wall)
|                         O  →  (bullet direction toward wall)
|                        /|\
|                       / | \   (shrapnel cone ±30°)
|                      /  |  \
|                     s₁  s₂  s₃
|
| Some shrapnel (s₁) spawns 5px toward wall = only 55px from wall
| If bullet is closer (e.g., 10px), shrapnel could spawn at 5px from wall
| or even inside/behind the wall if angle is extreme
```

### Additional Contributing Factors

1. **No wall check on spawn position:** The code does not verify if the shrapnel spawn position is valid (not inside a wall)

2. **No line-of-sight check for shrapnel direction:** Unlike the explosion damage (which uses `_breaker_has_line_of_sight()`), shrapnel spawning doesn't check if the direction would immediately hit a wall

3. **Shrapnel behavior after spawn:** Once spawned, shrapnel from `breaker_shrapnel.gd`:
   - Line 133: Destroys itself when hitting walls (good)
   - But if spawned behind a wall, it's already on the wrong side

## Proposed Solutions

### Solution 1: Wall-Aware Shrapnel Spawn Position (Recommended)

Before spawning each shrapnel piece, check if the spawn position would be inside a wall:

```gdscript
for i in range(shrapnel_count):
    var random_angle := randf_range(-half_angle_rad, half_angle_rad)
    var shrapnel_direction := direction.rotated(random_angle)

    # Calculate potential spawn position
    var spawn_offset := 5.0
    var spawn_pos := center + shrapnel_direction * spawn_offset

    # Check if spawn position is inside a wall
    if _is_position_inside_wall(spawn_pos):
        # Skip this shrapnel or adjust position
        continue

    var shrapnel := _breaker_shrapnel_scene.instantiate()
    shrapnel.global_position = spawn_pos
    shrapnel.direction = shrapnel_direction
    # ... rest of code
```

**Helper function:**
```gdscript
func _is_position_inside_wall(pos: Vector2) -> bool:
    var space_state := get_world_2d().direct_space_state
    # Check a small radius around the position
    var query := PhysicsPointQueryParameters2D.new()
    query.position = pos
    query.collision_mask = 4  # Obstacles layer
    var result := space_state.intersect_point(query, 1)
    return not result.is_empty()
```

### Solution 2: Line-of-Sight Check for Shrapnel Direction

Only spawn shrapnel in directions that have clear line of sight from the detonation point:

```gdscript
for i in range(shrapnel_count):
    var random_angle := randf_range(-half_angle_rad, half_angle_rad)
    var shrapnel_direction := direction.rotated(random_angle)

    # Check if this direction has clear path (at least 10px)
    var test_distance := 10.0
    if not _breaker_has_line_of_sight(center, center + shrapnel_direction * test_distance):
        # Wall in the way, skip this shrapnel
        continue

    # ... spawn shrapnel
```

### Solution 3: Spawn Behind Detonation Point (Conservative)

Spawn all shrapnel slightly behind the detonation point (opposite to bullet direction) to ensure they're never closer to the wall:

```gdscript
# Move spawn center back from wall by 10px
var safe_center := center - direction * 10.0

for i in range(shrapnel_count):
    var random_angle := randf_range(-half_angle_rad, half_angle_rad)
    var shrapnel_direction := direction.rotated(random_angle)

    var shrapnel := _breaker_shrapnel_scene.instantiate()
    shrapnel.global_position = safe_center + shrapnel_direction * 5.0
    shrapnel.direction = shrapnel_direction
    # ... rest
```

**Trade-off:** This may look less realistic (explosion appears to move backward).

### Solution 4: Hybrid Approach (Most Robust)

Combine multiple checks:
1. Spawn at a safe base position (slightly back from detonation)
2. Check each shrapnel spawn position for wall collision
3. Check each shrapnel direction for immediate wall collision
4. Skip or adjust shrapnel that would clip through walls

## Recommended Implementation

**Solution 1 (Wall-Aware Spawn Position)** is recommended because:
- ✅ Directly addresses the root cause
- ✅ Maintains realistic explosion behavior
- ✅ Minimal performance impact (point queries are fast)
- ✅ Allows shrapnel in all valid directions
- ✅ Simple to test and verify

## Testing Strategy

1. **Unit Tests:** Add tests to verify shrapnel spawn positions are not inside walls
2. **Visual Tests:** Create experiment scene with walls at various distances (5px, 10px, 30px, 60px)
3. **Edge Cases:**
   - Bullet detonating very close to wall (< 10px)
   - Bullet detonating at exact 60px distance
   - Bullet detonating near corner walls (multiple walls nearby)
   - Bullet detonating parallel to wall

## Related Code Files

- `/scripts/projectiles/bullet.gd` - Main breaker bullet logic (needs fix)
- `/scripts/projectiles/breaker_shrapnel.gd` - Shrapnel behavior (correct, no changes needed)
- `/tests/unit/test_breaker_bullet.gd` - Existing tests (need new test cases)
- `/scripts/characters/player.gd` - Breaker activation logic (correct, no changes needed)

## Performance Considerations

- Point queries for wall detection: ~0.1ms per shrapnel piece
- Max 10 shrapnel per detonation → max 1ms overhead
- Acceptable impact given the bug severity

## External Research

### Similar Issues in Game Engines

Research on similar projectile collision and spawn position validation issues in game engines reveals:

1. **Projectile Pass-Through Problem** ([Unreal Engine Forums](https://forums.unrealengine.com/t/projectiles-going-through-objects-without-overlapping-even-with-continuous-collision-detection-on/148653)):
   - Common issue where high-speed projectiles pass through thin walls
   - Even with continuous collision detection (CCD), spawn positions near walls can cause problems
   - Recommendation: Validate spawn positions before instantiating objects

2. **Godot Physics Query Methods** ([Godot Forums](https://godotforums.org/d/27192-using-physics2dshapequeryparameters-to-check-for-collisions)):
   - `Physics2DShapeQueryParameters` can check if spawn positions are inside obstacles
   - `PhysicsPointQueryParameters2D` is optimal for point-based collision checks
   - Recommended for validating object placement before spawning

3. **Raycast-Based Validation** ([GDQuest Raycast Guide](https://www.gdquest.com/library/raycast_introduction/)):
   - Raycasts are efficient for checking collision-free paths
   - Can validate both spawn position and initial trajectory
   - Minimal performance overhead for spawn-time validation

4. **Best Practice**: Game developers commonly use point queries or shape queries to validate spawn positions, especially for explosions and particle effects near geometry boundaries.

### Sources:
- [Projectiles going through objects - Unreal Engine Forums](https://forums.unrealengine.com/t/projectiles-going-through-objects-without-overlapping-even-with-continuous-collision-detection-on/148653)
- [Using Physics2DShapeQueryParameters - Godot Forums](https://godotforums.org/d/27192-using-physics2dshapequeryparameters-to-check-for-collisions)
- [Understanding raycasts in Godot - GDQuest](https://www.gdquest.com/library/raycast_introduction/)
- [Godot Physics Introduction](https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html)
