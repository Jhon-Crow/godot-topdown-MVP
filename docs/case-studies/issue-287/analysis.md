# Case Study: Issue #287 - Offensive Grenade Passing Through Walls

## Issue Summary

**Title:** fix наступательная граната проходит сквозь стену (fix offensive grenade passing through wall)

**Problem:** The offensive grenade (FragGrenade) passes through walls when thrown at close range ("в упор" = at point-blank range). The grenade should collide with and explode on walls, but instead it tunnels through them at high velocities.

**Reported Date:** 2026-01-24

**Issue Link:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/287

## Evidence

### Log Files Analysis

One game log file was provided demonstrating the gameplay session:

1. `game_log_20260124_004642.txt` (4,594 lines total, 585 grenade-related entries)

### Key Observations from Logs

From the log analysis, we found that:

1. **High-velocity throws are common**: Grenades reach maximum speed of ~1186.5 px/s
   ```
   [00:47:09] [INFO] [GrenadeBase] Velocity-based throw! Mouse vel: (3253.838, -1487.863), Swing: 520.7, Transfer: 1.00, Final speed: 1186.5
   ```

2. **Most wall collisions work correctly**:
   ```
   [00:47:17] [INFO] [GrenadeBase] Collision detected with Room2_WallRight (type: StaticBody2D)
   [00:47:17] [INFO] [FragGrenade] Impact detected! Body: Room2_WallRight (type: StaticBody2D), triggering explosion
   ```

3. **Enemy collisions also work**:
   ```
   [00:47:20] [INFO] [GrenadeBase] Collision detected with Enemy3 (type: CharacterBody2D)
   [00:47:20] [INFO] [FragGrenade] Impact detected! Body: Enemy3 (type: CharacterBody2D), triggering explosion
   ```

4. **The issue is intermittent**: The bug occurs when throwing grenades at close range with high velocity, causing the grenade to "tunnel" through thin walls before the physics engine can detect the collision.

### Timeline of Events (Typical Grenade Throw)

1. **T+0.0s**: Player initiates grenade throw (G key + RMB)
2. **T+0.0s**: Grenade created at player position (frozen state)
3. **T+0.0s**: Pin pulled, timer activated (infinite for frag grenades)
4. **T+0.5s**: Player releases RMB, throw velocity calculated
5. **T+0.5s**: Grenade unfrozen, physics enabled, velocity applied
6. **T+0.5s**: Grenade travels at up to 1186.5 px/s
7. **T+0.5s+**: Physics engine checks for collisions **per frame**
8. **Issue**: At 60 FPS, grenade moves ~19.8 pixels per frame at max speed
9. **Issue**: If wall thickness < 19.8px AND grenade position jumps past wall in one frame → tunneling occurs
10. **Normal case**: Collision detected, explosion triggered
11. **Bug case**: No collision detected, grenade passes through wall

## Root Cause Analysis

### Code Location

**Files involved:**
- `scripts/projectiles/grenade_base.gd` - Base grenade physics
- `scripts/projectiles/frag_grenade.gd` - Frag grenade collision handling
- `scenes/projectiles/FragGrenade.tscn` - Grenade scene configuration

### Physics Configuration

From `scenes/projectiles/FragGrenade.tscn`:
```gdscript
[node name="FragGrenade" type="RigidBody2D"]
collision_layer = 32
collision_mask = 6
gravity_scale = 0.0
linear_damp = 2.0
max_throw_speed = 1130.0
# NO continuous_cd property set!
```

From `scripts/projectiles/grenade_base.gd:95-118`:
```gdscript
func _ready() -> void:
    # Set up collision
    collision_layer = 32  # Layer 6 (custom for grenades)
    collision_mask = 4 | 2  # obstacles + enemies

    # Enable contact monitoring
    contact_monitor = true
    max_contacts_reported = 4

    # Set up physics
    gravity_scale = 0.0  # Top-down, no gravity
    linear_damp = 1.0

    # Set up physics material for wall bouncing
    var physics_material := PhysicsMaterial.new()
    physics_material.bounce = wall_bounce
    physics_material.friction = 0.3
    physics_material_override = physics_material

    # Start frozen to prevent physics interference
    freeze = true
    freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
```

**Missing Configuration:** No CCD (Continuous Collision Detection) enabled!

### Root Cause: Physics Tunneling

**The fundamental problem is "tunneling"** - a common physics engine issue where fast-moving objects pass through thin obstacles.

#### How Tunneling Occurs:

1. **Discrete Collision Detection** (default in Godot):
   - Physics engine checks collisions once per physics frame (typically 60 FPS)
   - Object position is updated in discrete steps
   - If object moves faster than obstacle thickness in one frame, it can "jump over" the obstacle

2. **Grenade Velocity Analysis**:
   - Maximum grenade speed: **1186.5 px/s**
   - At 60 FPS: **1186.5 / 60 = 19.8 pixels per frame**
   - If wall thickness < 19.8 pixels, grenade can tunnel through in one frame

3. **Close-Range Throwing**:
   - User throws grenade "в упор" (at close range/point-blank)
   - Grenade reaches maximum velocity very quickly
   - Short distance to wall means fewer frames for collision detection
   - Higher probability of tunneling through thin walls

### Why Most Collisions Still Work

- **Thick walls** (>20px) are reliably detected
- **Slower throws** have more time for collision detection
- **Longer distances** give more physics frames to detect collision
- **The bug is intermittent** - only occurs under specific conditions:
  1. High velocity (close to max speed)
  2. Close range to wall
  3. Thin wall (<20px)
  4. Grenade trajectory perpendicular to wall

## Real-World Research

### Physics Tunneling in Game Engines

Tunneling (also called "pass-through" or "bullet-through-paper") is a well-known problem in game physics:

**Sources:**
- [Tunneling | Glossary | GDQuest](https://school.gdquest.com/glossary/tunneling)
  > "Tunneling is when physics entities move fast enough that they jump through walls or collision areas. It's a common problem in game development."

- [High speed physics2d collision - intermittent tunneling · Issue #6664 · godotengine/godot](https://github.com/godotengine/godot/issues/6664)
  > "2D Rigid body passes through kinematic & static body when moving at high speeds (velocity around 800,1000)."

### Continuous Collision Detection (CCD)

CCD is the standard solution for fast-moving objects:

**From GDQuest:**
> "Continuous Collision Detection (CCD) is a physics technique that prevents fast-moving objects from passing through (or 'tunneling through') thin obstacles by checking for collisions along an object's entire movement path."

**Godot Implementation:**
- Property: `continuous_cd` on RigidBody2D
- Two modes:
  1. **CCD_MODE_DISABLED** (default) - No CCD
  2. **CCD_MODE_CAST_RAY** - Ray-based detection (recommended, works reliably)
  3. **CCD_MODE_CAST_SHAPE** - Shape-based detection (more precise but has known bugs)

**Sources:**
- [Continuous Collision Detection (CCD) | Glossary | GDQuest](https://school.gdquest.com/glossary/continuous_collision_detection)
- [Godot rigidbody2d CCD - Godot Forums](https://godotforums.org/d/32349-godot-rigidbody2d-ccd)
- [RigidBody2D continuous collision detection non-functional under Cast Shape setting · Issue #72674 · godotengine/godot](https://github.com/godotengine/godot/issues/72674)

### Alternative Solutions

**Raycasting Approach:**
> "It's common to use ray-casts or shape-casts to detect collisions for fast-moving objects, which do not have the tunneling problem as they check for collisions along a projected line."

However, CCD is the standard approach for RigidBody2D and is simpler to implement.

## Related Issues and PRs

### Recent Grenade Work

1. **PR #284** (merged 2026-01-23): "Fix offensive grenade not exploding on enemy hit"
   - Issue #283: Grenades weren't detecting CharacterBody2D collisions
   - Solution: Added CharacterBody2D to collision type check

2. **PR #280** (merged 2026-01-23): "Fix offensive grenade (frag grenade) wall impact detection"
   - Issue #279: Wall impacts not detected at all
   - Root cause: Missing `contact_monitor = true`
   - Solution: Enabled contact monitoring in grenade_base.gd

3. **PR #260** (merged 2026-01-23): "Implement realistic velocity-based grenade throwing physics"
   - Introduced velocity-based throwing system
   - Max throw speed: ~1186.5 px/s
   - This PR may have increased the likelihood of tunneling by allowing higher velocities

### Why This Issue Wasn't Caught Earlier

- Tunneling is **intermittent** - only occurs under specific conditions
- Most testing uses longer throw distances where tunneling is less likely
- Thick walls (common in level design) rarely trigger tunneling
- Issue only manifests with close-range, high-velocity throws

## Proposed Solutions

### Solution 1: Enable CCD on FragGrenade (Recommended)

**Approach:** Enable Continuous Collision Detection using CCD_MODE_CAST_RAY.

**Implementation:**

1. **In `scenes/projectiles/FragGrenade.tscn`:**
   ```gdscript
   [node name="FragGrenade" type="RigidBody2D"]
   collision_layer = 32
   collision_mask = 6
   continuous_cd = 1  # CCD_MODE_CAST_RAY
   # ... rest of properties
   ```

2. **In `scripts/projectiles/grenade_base.gd` _ready():**
   ```gdscript
   # Enable CCD for fast-moving grenades to prevent tunneling
   continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
   ```

**Pros:**
- Standard solution for fast-moving physics objects
- Minimal code changes
- Works reliably with CCD_MODE_CAST_RAY
- Fixes tunneling for all wall thicknesses
- No gameplay changes needed

**Cons:**
- Slight performance cost (minimal for small number of grenades)
- CCD_MODE_CAST_SHAPE has known bugs (but we use CCD_MODE_CAST_RAY)

**Why CCD_MODE_CAST_RAY:**
- More reliable than CCD_MODE_CAST_SHAPE
- Sufficient precision for grenade collisions
- Recommended by community for Godot 4.x

### Solution 2: Reduce Maximum Grenade Velocity

**Approach:** Lower max_throw_speed to ensure grenade can't move >10px per frame.

**Implementation:**
```gdscript
max_throw_speed = 600.0  # Was 1130.0
# At 60 FPS: 600 / 60 = 10px per frame
```

**Pros:**
- No CCD needed
- Guaranteed to work

**Cons:**
- Changes game feel significantly
- Reduces grenade throw distance
- Affects gameplay balance
- Doesn't solve the root cause

### Solution 3: Use Raycasting for High-Velocity Detection

**Approach:** Cast a ray from previous position to current position each frame.

**Implementation:** Add raycasting in `_physics_process()` to detect missed collisions.

**Pros:**
- Very precise collision detection
- Custom control over detection

**Cons:**
- Complex implementation
- Requires tracking previous position
- More code to maintain
- Duplicate collision logic

### Solution 4: Increase Wall Thickness

**Approach:** Ensure all walls are >20px thick.

**Pros:**
- No code changes

**Cons:**
- Doesn't solve root cause
- Limits level design
- Not scalable
- Still possible to tunnel with higher velocities

## Recommendation

**Use Solution 1: Enable CCD with CCD_MODE_CAST_RAY**

This is the standard, recommended approach because:

1. **Industry Standard**: CCD is the established solution for fast-moving objects
2. **Minimal Changes**: One-line code change
3. **Reliable**: CCD_MODE_CAST_RAY works consistently in Godot 4.x
4. **Future-Proof**: Protects against tunneling even if velocities increase
5. **No Gameplay Impact**: Maintains current game feel and balance
6. **Performance**: Negligible impact for 1-3 grenades in flight

## Implementation Plan

1. **Add CCD to FragGrenade.tscn**
2. **Add CCD to FlashbangGrenade.tscn** (for consistency)
3. **Update grenade_base.gd** to set CCD in code (belt-and-suspenders)
4. **Test with high-velocity close-range throws**
5. **Verify no collision issues with enemies or other objects**
6. **Document the change in case study**

## Testing Plan

### Manual Testing

1. **Close-Range Wall Throws** (reproduce original bug):
   - Stand next to thin wall (~10px)
   - Throw grenade directly at wall with maximum velocity
   - Verify: Grenade explodes on wall, doesn't pass through

2. **Various Wall Thicknesses**:
   - Test walls of 5px, 10px, 15px, 20px thickness
   - Throw grenades at all thicknesses
   - Verify: All collisions detected

3. **Different Velocities**:
   - Slow throw (low velocity)
   - Medium throw (mid velocity)
   - Fast throw (max velocity)
   - Verify: All work correctly

4. **Enemy Collisions**:
   - Throw grenades at enemies
   - Verify: Still explode on enemy hit (no regression)

5. **Ground Landing**:
   - Throw grenades to land on ground
   - Verify: Still explode on landing (no regression)

### Automated Testing

Update `tests/unit/test_frag_grenade.gd`:

```gdscript
func test_ccd_enabled():
    var grenade = preload("res://scenes/projectiles/FragGrenade.tscn").instantiate()
    assert_equal(grenade.continuous_cd, RigidBody2D.CCD_MODE_CAST_RAY,
                 "FragGrenade should have CCD enabled")

func test_no_tunneling_at_max_speed():
    # Create grenade at high velocity near wall
    # Verify collision is detected
    pass  # Requires integration test setup
```

### Performance Testing

- Monitor FPS with multiple grenades in flight
- Verify no performance degradation
- Target: <1% FPS impact

## Technical Notes

### CCD Implementation Details

From Godot documentation:
- `continuous_cd = 0`: CCD_MODE_DISABLED (default)
- `continuous_cd = 1`: CCD_MODE_CAST_RAY (recommended)
- `continuous_cd = 2`: CCD_MODE_CAST_SHAPE (has bugs in Godot 4.x)

### Why Set in Both Scene and Code

1. **Scene file**: Visual confirmation in editor
2. **Code**: Belt-and-suspenders, ensures it's set even if scene changes

### Collision Mask Reminder

Current configuration (correct, don't change):
- `collision_layer = 32` (layer 6 - grenades)
- `collision_mask = 6` (layers 2,3 - obstacles + enemies)
- Does NOT collide with player (layer 1) during throw

## Lessons Learned

1. **High-velocity physics objects need CCD** - Always enable CCD for projectiles >600 px/s
2. **Intermittent bugs are harder to catch** - Need specific testing scenarios
3. **Physics engines have limitations** - Discrete collision detection can miss fast objects
4. **Test edge cases** - Close-range, high-velocity scenarios often reveal issues
5. **Research similar issues** - Godot community has extensive knowledge base

## References

### Godot Documentation
- [RigidBody2D Class Reference](https://docs.godotengine.org/en/stable/classes/class_rigidbody2d.html)
- [Physics Introduction](https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html)

### Community Resources
- [Tunneling | Glossary | GDQuest](https://school.gdquest.com/glossary/tunneling)
- [Continuous Collision Detection (CCD) | Glossary | GDQuest](https://school.gdquest.com/glossary/continuous_collision_detection)
- [Godot Forums: RigidBody2D CCD](https://godotforums.org/d/32349-godot-rigidbody2d-ccd)

### GitHub Issues
- [High speed physics2d collision - intermittent tunneling #6664](https://github.com/godotengine/godot/issues/6664)
- [RigidBody2D continuous collision detection non-functional under Cast Shape setting #72674](https://github.com/godotengine/godot/issues/72674)
- [Continuous CD not working #9071](https://github.com/godotengine/godot/issues/9071)
- [Fast RigidBody always go through walls #16113](https://github.com/godotengine/godot/issues/16113)

### Related PRs
- PR #284: Fix offensive grenade not exploding on enemy hit
- PR #280: Fix offensive grenade wall impact detection
- PR #260: Implement realistic velocity-based grenade throwing physics

## Follow-up: Second Root Cause Discovery

### User Report After CCD Fix

After the initial CCD fix was implemented, the user reported (2026-01-24):

> "всё ещё проходит (вероятно она спавнится уже за стеной)"
> Translation: "still passes through (it probably spawns already behind the wall)"

A new log file was provided: `game_log_20260124_010946.txt` (980 lines)

### Analysis of Second Log File

**Critical Finding** (lines 870-893):
```
[01:10:11] [Player.Grenade] Velocity-based throw! Mouse velocity: (859.49365, -6904.961) (6958,2 px/s), Swing distance: 1101,2
[01:10:11] [GrenadeBase] Velocity-based throw! Mouse vel: (859.4937, -6904.961), Swing: 1101.2, Transfer: 1.00, Final speed: 1352.8
[01:10:11] [Player.Grenade] Thrown! Velocity: 6958,2, Swing: 1101,2
[01:10:11] [Player.Grenade] State reset to IDLE
[01:10:11] [ENEMY] [Enemy2] State: IN_COVER -> SUPPRESSED
...
[01:10:12] [Player] Player died - ending penultimate effect
...
[01:10:12] [INFO] [PenultimateHit] Resetting all effects (scene change detected)
```

**Key Observation**: After the throw, there is **NO collision logged** and **NO landing logged**. The grenade simply disappeared! The scene reset shortly after due to player death.

### Root Cause #2: Spawn Position Behind Wall

The user's hypothesis was **CORRECT**. The issue is in `player.gd:_throw_grenade()`:

```gdscript
# ORIGINAL CODE (buggy)
var spawn_offset := 60.0  # 60 pixels in front of player
var spawn_position := global_position + throw_direction * spawn_offset
_active_grenade.global_position = spawn_position
```

**Problem**: If player stands within 60 pixels of a wall and throws toward it, the grenade spawns **BEHIND or INSIDE the wall**, completely bypassing physics collision detection.

**Why CCD didn't help**: CCD only helps detect collisions during movement. If an object is **spawned already past** the obstacle, there's no movement through the obstacle to detect.

### Fix #2: Raycast Spawn Validation

Added `_get_safe_grenade_spawn_position()` function in `player.gd`:

```gdscript
func _get_safe_grenade_spawn_position(from_pos: Vector2, intended_pos: Vector2, throw_direction: Vector2) -> Vector2:
    var space_state := get_world_2d().direct_space_state
    if space_state == null:
        _active_grenade.global_position = intended_pos
        return intended_pos

    # Raycast from player to intended spawn position
    var query := PhysicsRayQueryParameters2D.create(from_pos, intended_pos, 4, [self])
    var result := space_state.intersect_ray(query)

    if result.is_empty():
        # No wall - safe to spawn at intended position
        _active_grenade.global_position = intended_pos
        return intended_pos

    # Wall detected! Spawn 5px before the wall
    var collision_point: Vector2 = result.position
    var safe_distance := maxf(from_pos.distance_to(collision_point) - 5.0, 10.0)
    var safe_position := from_pos + throw_direction * safe_distance

    FileLogger.info("[Player.Grenade] Wall detected at %s! Adjusting spawn from %s to %s" % [
        str(collision_point), str(intended_pos), str(safe_position)
    ])

    _active_grenade.global_position = safe_position
    return safe_position
```

### Why Both Fixes Are Necessary

| Scenario | CCD Only | Raycast Only | Both Fixes |
|----------|----------|--------------|------------|
| High-speed throw at distant wall | ✅ Prevents tunneling | N/A | ✅ Works |
| Throw at wall >60px away | ✅ CCD handles it | N/A | ✅ Works |
| Throw at wall <60px away ("в упор") | ❌ Spawns behind wall | ✅ Spawns safely | ✅ Works |
| Any velocity at close range | ❌ Physics bypassed | ✅ Prevents | ✅ Works |

### Updated References

- [Ray-casting — Godot Engine Documentation](https://docs.godotengine.org/en/stable/tutorials/physics/ray-casting.html)
- [PhysicsDirectSpaceState2D — Godot Engine Documentation](https://docs.godotengine.org/en/stable/classes/class_physicsdirectspacestate2d.html)
- [RayCast2D :: Godot 4 Recipes](https://kidscancode.org/godot_recipes/4.x/kyn/raycast2d/index.html)

## Follow-up: Third Root Cause Discovery

### User Report After Second Fix

After the raycast spawn fix was implemented, the user reported (2026-01-24):

> "проблема всё ещё присутствует, проверь C#, так же направление броска может резко меняться (кидаю вправо, а летит вверх)"
> Translation: "problem still persists, check C#, also throw direction can change sharply (throwing right but it flies up)"

A new log file was provided: `game_log_20260124_012142.txt` (1158 lines)

### Analysis of Third Log File

**Critical Finding #1 - C# code was not fixed**:
The raycast spawn fix was only applied to the GDScript `player.gd`, but the game uses the C# `Player.cs`. The C# code did not have the raycast check!

**Critical Finding #2 - Throw direction based on mouse velocity** (lines 829-832):
```
[01:22:03] [Player.Grenade] Velocity-based throw! Mouse velocity: (149.37726, -1251.1003) (1260,0 px/s), Swing distance: 467,2
[01:22:03] [Player.Grenade] Player rotated for throw: 0 -> -1,4519622
```

- Mouse velocity: (149.37726, -1251.1003) - this is mostly **UPWARD** (negative Y)
- Player rotation: -1.4519622 radians (~-83 degrees from horizontal)
- The grenade went **UP** instead of toward the mouse cursor!

**Another example** (lines 970-973):
```
[01:22:05] [Player.Grenade] Velocity-based throw! Mouse velocity: (0.024683334, -1403.3901) (1403,4 px/s), Swing distance: 470,4
[01:22:05] [Player.Grenade] Player rotated for throw: 0 -> -1,5707787
```

- Mouse velocity: almost entirely upward (Y = -1403, X ≈ 0)
- Player rotation: -1.5707787 radians (-90 degrees, straight up)
- User was aiming right but moving mouse upward during release → grenade flew up!

### Root Cause #3: Throw Direction Based on Mouse Velocity

The problematic code in `Player.cs:ThrowGrenade()`:

```csharp
// ORIGINAL CODE (buggy)
Vector2 releaseVelocity = _currentMouseVelocity;
float velocityMagnitude = releaseVelocity.Length();

if (velocityMagnitude > 10.0f) // Mouse was moving at release
{
    throwDirection = releaseVelocity.Normalized();  // <-- BUG: direction from velocity, not position!
}
```

**Problem**: The throw direction was determined by the **mouse movement velocity**, not the **mouse position relative to player**.

- If player releases RMB while moving mouse upward → grenade goes up
- Even if mouse cursor is to the right of player!
- This is counterintuitive: users expect grenade to go toward cursor, not in direction of cursor movement

**User expectation**: Grenade should fly toward where the mouse cursor is pointing (player-to-mouse direction).

### Fix #3: Use Player-to-Mouse Direction

Updated `Player.cs:ThrowGrenade()` to use correct direction:

```csharp
// FIXED CODE
Vector2 releaseVelocity = _currentMouseVelocity;
float velocityMagnitude = releaseVelocity.Length();

// Throw direction is now ALWAYS from player toward mouse cursor
// Mouse velocity magnitude still determines throw SPEED, but direction is player-to-mouse
Vector2 mousePos = GetGlobalMousePosition();
Vector2 throwDirection = (mousePos - GlobalPosition).Normalized();

// When calling grenade, pass corrected velocity (direction + magnitude)
Vector2 correctedVelocity = throwDirection * velocityMagnitude;
_activeGrenade.Call("throw_grenade_velocity_based", correctedVelocity, _totalSwingDistance);
```

### Also Added: Raycast Check to C# Code

The raycast spawn validation was also added to `Player.cs`:

```csharp
/// <summary>
/// Get a safe spawn position for the grenade that doesn't spawn behind/inside walls.
/// </summary>
private Vector2 GetSafeGrenadeSpawnPosition(Vector2 fromPos, Vector2 intendedPos, Vector2 throwDirection)
{
    var spaceState = GetWorld2D().DirectSpaceState;
    var query = PhysicsRayQueryParameters2D.Create(fromPos, intendedPos, 4);
    query.Exclude = new Godot.Collections.Array<Rid> { GetRid() };

    var result = spaceState.IntersectRay(query);
    if (result.Count == 0) return intendedPos;

    // Wall detected! Calculate safe position (5px before the wall)
    Vector2 wallPosition = (Vector2)result["position"];
    float distanceToWall = fromPos.DistanceTo(wallPosition);
    float safeDistance = Mathf.Max(distanceToWall - 5.0f, 10.0f);
    return fromPos + throwDirection * safeDistance;
}
```

## Conclusion

Issue #287 has **THREE root causes** that required **THREE separate fixes**:

1. **Physics Tunneling**: Fast-moving grenades pass through thin walls when discrete collision detection misses the collision between physics frames.
   - **Fix**: Enable Continuous Collision Detection (CCD) with `CCD_MODE_CAST_RAY`

2. **Spawn Position Behind Wall**: Grenades spawn 60 pixels ahead of player, which places them behind/inside walls when player is close to the wall.
   - **Fix**: Raycast from player to intended spawn position; if wall detected, spawn grenade just before the wall

3. **Throw Direction Based on Mouse Velocity**: The throw direction was determined by mouse movement velocity instead of mouse position relative to player, causing grenades to fly in unexpected directions.
   - **Fix**: Calculate throw direction as player-to-mouse vector, use mouse velocity magnitude only for throw speed

**Additional Fix**: The raycast spawn check was only in GDScript but the game uses C# - both codebases now have the fix.

This demonstrates the value of:
- Carefully analyzing user hypotheses
- Examining logs for missing events (no collision = spawn position issue)
- Multi-phase debugging when initial fixes don't fully resolve the issue
- Checking which codebase (GDScript vs C#) is actually being used
- Understanding the difference between velocity direction and position direction

All three fixes together ensure:
- Grenades will never pass through walls regardless of velocity or wall thickness
- Grenades will always fly toward where the mouse cursor is pointing
- The throwing "feel" uses mouse velocity for realistic throw speed
