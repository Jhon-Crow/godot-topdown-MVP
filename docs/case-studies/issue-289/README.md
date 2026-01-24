# Case Study: Issue #289 - Add Shell Casings to Enemy Weapons

## Issue Overview

**Issue Number**: #289
**Title**: добавь гильзы оружию врагов (Add shell casings to enemy weapons)
**Status**: Open
**Created**: 2026-01-23
**Reporter**: Jhon-Crow

### Issue Description (Original in Russian)
```
сейчас у оружия игрока есть гильзы
добавь гилзы оружию врагов
(сейчас у них m16)
```

**Translation**:
> Currently, the player's weapon has shell casings.
> Add shell casings to enemy weapons.
> (They currently have M16)

### Additional Requirements
The issue also requests comprehensive documentation:
- Download all logs and data related to the issue
- Compile data to `./docs/case-studies/issue-{id}` folder
- Perform deep case study analysis
- Search online for additional facts and data
- Reconstruct timeline/sequence of events
- Find root causes of the problem
- Propose possible solutions

## Timeline / Sequence of Events

### Development History

1. **Player Weapon System Development**
   - Implemented in C# using `BaseWeapon.cs` abstract class
   - Location: `Scripts/AbstractClasses/BaseWeapon.cs`
   - Includes `SpawnCasing()` method (lines 390-436) that:
     - Instantiates visual shell casings from `CasingScene`
     - Calculates realistic ejection physics
     - Applies velocity and spin
     - Sets caliber-based appearance

2. **Shell Casing Effect Development**
   - Scene: `scenes/effects/Casing.tscn`
   - Script: `scripts/effects/casing.gd`
   - Uses RigidBody2D for realistic physics
   - Features:
     - Ejection with randomized velocity (300-450 px/sec)
     - Angular velocity for realistic spin
     - Auto-landing after 2 seconds
     - Caliber-based visual appearance
     - Optional lifetime for cleanup

3. **Enemy AI Development**
   - Implemented in GDScript: `scripts/objects/enemy.gd`
   - Direct bullet spawning in `_shoot()` method (line 3723)
   - Sound effects only - no visual casings
   - Reasons for separate implementation:
     - Enemy AI is complex (4000+ lines)
     - Different architecture from player
     - Doesn't inherit from BaseWeapon.cs

4. **Issue Discovery (2026-01-23)**
   - User noticed visual inconsistency
   - Player weapons spawn visible shell casings
   - Enemy weapons only play casing sounds
   - Missing visual feedback reduces immersion

## Root Cause Analysis

### Primary Cause: Architectural Divergence

The root cause is an **architectural inconsistency** between player and enemy weapon systems:

#### Player Weapon Architecture
```
Player → BaseWeapon.cs → SpawnCasing() → Casing.tscn
  ↓          (C#)            ↓              ↓
Inherits    Abstract      Visual         RigidBody2D
            Class         Effect         Physics
```

#### Enemy Weapon Architecture
```
Enemy.gd → _shoot() → Bullet only + Sound effects
  (GDScript)   ↓          ↓                ↓
  4000+      Custom    No visual      Audio only
  lines      Logic     casing
```

### Contributing Factors

1. **Language Boundary**: Player weapons use C#, enemy uses GDScript
   - Makes code reuse more difficult
   - Requires GDScript implementation of casing spawning

2. **Code Duplication**: Enemy has custom shooting logic
   - Doesn't leverage BaseWeapon.cs
   - Casing spawning logic needs to be duplicated in GDScript

3. **Development Phases**: Features added at different times
   - Shell casings might have been added to player weapons later
   - Enemy shooting system already complete, not updated

4. **Missing Export Variable**: Enemy.gd doesn't have:
   ```gdscript
   @export var casing_scene: PackedScene
   ```

### Why This Matters

**Visual Consistency**:
- Players see casings from their own weapons
- Enemies shooting should also eject visible casings
- Enhances realism and visual feedback

**Gameplay Polish**:
- Small details like shell casings improve immersion
- Helps players track enemy fire visually
- Adds to the tactical feel of combat

**Performance Consideration**:
- RigidBody2D casings are lightweight
- Auto-landing and optional lifetime prevent buildup
- Already proven working in player weapons

## Analysis of Existing Casing System

### Casing.gd Implementation (`scripts/effects/casing.gd`)

**Key Features**:
1. **Physics-based ejection** (RigidBody2D)
2. **Auto-landing mechanism** (2 seconds)
3. **Caliber-specific appearance** (5.45x39mm, 9x19mm, Buckshot)
4. **Optimized performance** (disables physics after landing)
5. **Optional lifetime** (can self-destruct)

**Technical Details**:
```gdscript
- Base: RigidBody2D
- Collision: Layer 0, Mask 4 (obstacles only)
- Physics: gravity_scale = 0.0 (top-down), linear_damp = 3.0
- Sprite: Caliber-based texture or color modulation
```

### BaseWeapon.cs SpawnCasing Method

Located at `Scripts/AbstractClasses/BaseWeapon.cs:390-436`

**Algorithm**:
1. Calculate spawn position (50% of bullet offset)
2. Calculate perpendicular ejection direction (90° from shoot direction)
3. Add randomness (±17°)
4. Set velocity (300-450 px/sec random)
5. Add angular velocity (±15 rad/sec)
6. Set caliber data for appearance
7. Add to scene tree

**Key Code**:
```csharp
Vector2 weaponRight = new Vector2(-direction.Y, direction.X);
float randomAngle = (float)GD.RandRange(-0.3f, 0.3f);
Vector2 ejectionDirection = weaponRight.Rotated(randomAngle);
float ejectionSpeed = (float)GD.RandRange(300.0f, 450.0f);
casing.LinearVelocity = ejectionDirection * ejectionSpeed;
```

## Proposed Solutions

### Solution 1: Direct GDScript Implementation (Recommended)

**Add casing spawning to enemy.gd**

**Pros**:
- No architectural changes needed
- Follows existing enemy code patterns
- Can be tested and verified easily
- Minimal risk of breaking existing functionality

**Cons**:
- Code duplication (casing logic exists in BaseWeapon.cs)
- Future changes need updates in both places

**Implementation Steps**:
1. Add `@export var casing_scene: PackedScene` to enemy.gd
2. Create `_spawn_casing()` method mirroring BaseWeapon.cs logic
3. Call from `_shoot()` method after bullet spawning
4. Configure Enemy.tscn to reference Casing.tscn
5. Test with multiple enemies firing simultaneously

**Estimated Complexity**: Low
**Risk Level**: Low

### Solution 2: Create Shared Weapon Component

**Extract weapon firing to separate GDScript component**

**Pros**:
- Reduces code duplication
- Easier maintenance
- Could be reused for future weapons

**Cons**:
- Requires refactoring enemy.gd
- Higher risk of breaking existing behavior
- More testing required
- May affect AI behavior timing

**Implementation Steps**:
1. Create `weapon_component.gd` with firing logic
2. Refactor enemy.gd to use component
3. Update all enemy scenes
4. Extensive testing of AI behaviors

**Estimated Complexity**: High
**Risk Level**: Medium-High

### Solution 3: Hybrid Approach

**Use GDScript autoload/singleton for casing spawning**

**Pros**:
- Centralized casing spawning logic
- Callable from both C# and GDScript
- No major refactoring needed

**Cons**:
- Adds another global system
- Slightly less performant (global call)

**Implementation Steps**:
1. Create `casing_manager.gd` autoload
2. Implement spawn_casing() method
3. Call from enemy.gd and eventually BaseWeapon.cs
4. Update project.godot with autoload

**Estimated Complexity**: Medium
**Risk Level**: Low-Medium

## Recommended Approach

**Solution 1 (Direct GDScript Implementation)** is recommended because:

1. ✅ **Lowest Risk**: Minimal changes to existing systems
2. ✅ **Fastest Implementation**: Single file changes
3. ✅ **Easy to Test**: Verify casings spawn when enemies shoot
4. ✅ **Follows Patterns**: Consistent with how enemy.gd works now
5. ✅ **User Request**: Directly addresses the issue without over-engineering

The code duplication is acceptable given:
- The two systems (C# player weapons, GDScript enemy AI) are architecturally different
- Premature abstraction would add complexity
- Future unification can happen if more weapons need this

## Implementation Plan

### Phase 1: Add Casing Export and Method
1. Add `@export var casing_scene: PackedScene` variable
2. Implement `_spawn_casing(direction: Vector2, weapon_forward: Vector2)` method
3. Replicate BaseWeapon.cs ejection physics in GDScript

### Phase 2: Integrate with Shooting
1. Call `_spawn_casing()` from `_shoot()` method
2. Pass bullet direction and weapon forward vector
3. Ensure timing matches (spawn with bullet)

### Phase 3: Scene Configuration
1. Update `scenes/objects/Enemy.tscn`
2. Set `casing_scene` to `res://scenes/effects/Casing.tscn`
3. Verify all enemy instances updated

### Phase 4: Testing
1. Test single enemy firing
2. Test multiple enemies firing simultaneously
3. Verify casing physics (ejection, landing, cleanup)
4. Check performance with many casings
5. Verify caliber appearance (5.45x39mm for M16)

### Phase 5: Documentation
1. Add comments to new code
2. Update this case study with results
3. Document any edge cases found

## Additional Research

### Online Resources Consulted

Based on web search for "Godot shell casings bullet casings 2D top-down shooter implementation RigidBody2D 2026":

**Bullet Implementation Guides**:
- [Bullet Scene :: Godot 4 Recipes](https://kidscancode.org/godot_recipes/4.x/games/first_2d/first_2d_04/index.html)
- [Shooting projectiles :: Godot 4 Recipes](https://kidscancode.org/godot_recipes/4.x/2d/2d_shooting/index.html)
- [Ballistic bullet :: Godot 3 Recipes](https://kidscancode.org/godot_recipes/3.x/2d/ballistic_bullet/index.html)

**RigidBody2D Discussion**:
- [Rigidbody2d or Kinematicbody2d - Godot Forum](https://forum.godotengine.org/t/rigidbody2d-or-kinematicbody2d/19452)
- [Rigidbody2d or Kinematicbody2d - Godot Engine Q&A](https://ask.godotengine.org/64867/rigidbody2d-or-kinematicbody2d)

**Key Findings**:
- RigidBody2D is appropriate for shell casings (physics, gravity, collision)
- Top-down shooters commonly use Area2D for bullets, RigidBody2D for effects
- Ejection physics should include velocity, angular velocity, and collision
- Performance consideration: disable physics after landing

### Best Practices for Shell Casings

1. **Physics Setup**:
   - RigidBody2D with gravity_scale = 0 (top-down)
   - Linear damping for gradual slowdown
   - Angular damping for spin decay

2. **Performance**:
   - Disable physics after landing
   - Optional lifetime for automatic cleanup
   - Collision mask limited to obstacles only

3. **Visual Quality**:
   - Caliber-specific sprites or colors
   - Random initial rotation
   - Ejection angle perpendicular to shot

4. **Realism**:
   - Velocity: 300-450 px/sec (visible but not distracting)
   - Ejection angle randomness: ±17° (natural variation)
   - Angular velocity: ±15 rad/sec (spinning)

## Technical Specifications

### M16 (5.45x39mm) Specifications
- **Weapon Type**: Assault Rifle
- **Fire Rate**: 10 rounds/second (0.1s cooldown)
- **Magazine Size**: 30 rounds
- **Bullet Speed**: 2500 px/sec
- **Caliber**: 5.45x39mm
- **Casing Appearance**: Brass color (default rifle casing)

### Caliber Data Reference
Located at `resources/calibers/caliber_545x39.tres`
- Used for M16/assault rifles
- Defines casing sprite and properties
- Should be passed to casing instance

## Related Files

### Core Files
- `scripts/objects/enemy.gd` - Enemy AI and shooting logic
- `Scripts/AbstractClasses/BaseWeapon.cs` - Player weapon base class
- `scripts/effects/casing.gd` - Shell casing physics and appearance
- `scenes/effects/Casing.tscn` - Shell casing scene

### Configuration Files
- `scenes/objects/Enemy.tscn` - Enemy scene (needs casing_scene export)
- `scenes/weapons/csharp/AssaultRifle.tscn` - Player M16 (has casing_scene)
- `resources/calibers/caliber_545x39.tres` - Caliber data for M16

### Reference Files
- `Scripts/Weapons/AssaultRifle.cs` - Player M16 implementation
- `scripts/autoload/audio_manager.gd` - Manages shell casing sounds

## Performance Impact

### Expected Impact: Minimal

**Current Casing System (Player Only)**:
- Already spawns RigidBody2D casings
- Auto-landing at 2 seconds reduces active physics objects
- Proven to work without performance issues

**With Enemy Casings**:
- Enemies typically fire less frequently than player
- Same optimization (auto-landing, physics disable)
- Casings use simple collision shape (Rectangle 4x14)

**Worst Case Scenario**:
- 10 enemies × 10 rounds/sec = 100 casings/sec maximum
- With 2-second landing, ~200 active casings maximum
- RigidBody2D is optimized for this use case
- Can add optional lifetime if needed

## Success Criteria

The implementation will be considered successful when:

1. ✅ Enemy M16 weapons spawn visible shell casings when firing
2. ✅ Casings eject perpendicular to shooting direction (realistic)
3. ✅ Casings have proper physics (velocity, spin, landing)
4. ✅ Casings use correct appearance (5.45x39mm brass)
5. ✅ No performance degradation during combat
6. ✅ Casings properly land and stop moving after 2 seconds
7. ✅ Shell casing sound still plays (existing behavior)
8. ✅ Multiple enemies can spawn casings simultaneously
9. ✅ CI tests pass
10. ✅ Visual consistency with player weapon casings

## Conclusion

Issue #289 identifies a visual inconsistency where player weapons spawn shell casings but enemy weapons don't. The root cause is architectural divergence - player weapons use BaseWeapon.cs (C#) with built-in casing support, while enemies use custom GDScript shooting logic without visual casings.

The recommended solution is to implement casing spawning directly in enemy.gd by:
1. Adding a casing_scene export variable
2. Creating a _spawn_casing() method based on BaseWeapon.cs
3. Calling it from the existing _shoot() method

This approach is low-risk, easy to implement, and directly solves the user's request without over-engineering.

---

**Case Study Compiled**: 2026-01-23
**Issue Status**: In Progress
**Pull Request**: #290
**Branch**: issue-289-3628d1536804
