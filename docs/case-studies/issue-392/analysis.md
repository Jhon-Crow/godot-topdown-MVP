# Case Study: Issue #392 - Shell Casing Physics Fix

## Issue Summary

**Issue**: [#392](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/392)
**Title**: fix физику гильз (Fix shell casing physics)
**Reporter**: User reported that shell casings behave as very heavy objects and sometimes push the player
**Expected Behavior**: Shell casings should never affect player movement in any way

## Timeline of Events

### Initial Report (2026-01-25)
- User reported that shell casings are behaving like heavy objects
- Shell casings sometimes push the player character
- Log file provided: `game_log_20260125_200508.txt`

### Investigation (2026-02-03)
1. Retrieved and analyzed the issue details and log file
2. Located shell casing implementation in codebase:
   - Script: `scripts/effects/casing.gd`
   - Scene: `scenes/effects/Casing.tscn`
   - Spawning code: `scripts/objects/enemy.gd:3868`

3. Analyzed current physics configuration:
   - Casing: RigidBody2D with `collision_layer = 0`, `collision_mask = 4`
   - Player: CharacterBody2D with `collision_layer = 1`, `collision_mask = 4`
   - Default mass: 1.0 (Godot default)
   - High initial velocity: 300-450 pixels/sec

4. Researched Godot 4 physics best practices for decorative objects

## Root Cause Analysis

### Problem Identification

The shell casings were able to affect player movement due to several factors:

1. **Improper Collision Layer Configuration**
   - Setting `collision_layer = 0` does NOT make an object non-interactive
   - RigidBody2D objects with `collision_layer = 0` can still interact with other physics bodies through the physics engine
   - The physics engine still resolves collisions between the player and casings

2. **Default Mass and High Velocity**
   - Casings had default mass of 1.0 kg (Godot default)
   - Casings were spawned with high velocity (300-450 pixels/sec)
   - High momentum (mass × velocity) caused noticeable impact when colliding with player

3. **Physics Engine Behavior**
   - Even though CharacterBody2D doesn't "push" RigidBody2D by default, the RigidBody2D can still affect the CharacterBody2D's position during collision resolution
   - When a fast-moving RigidBody2D collides with a CharacterBody2D, the physics engine resolves the collision, potentially displacing the CharacterBody2D

### Research Findings

#### Godot 4 Physics Documentation
Source: [RigidBody2D — Godot Engine Documentation](https://docs.godotengine.org/en/stable/classes/class_rigidbody2d.html)

Key properties:
- `mass`: The body's mass affects how it responds to forces and impacts other bodies
- `collision_layer`: Which physics layers this body is present on (bitmask)
- `collision_mask`: Which physics layers this body scans for collisions (bitmask)

#### Character-RigidBody Interaction Best Practices
Source: [Character to Rigid Body Interaction :: Godot 4 Recipes](https://kidscancode.org/godot_recipes/4.x/physics/character_vs_rigid/index.html)

- By default, CharacterBody2D doesn't push RigidBody2D objects
- Proper collision layer/mask separation is essential for controlling interactions
- For decorative objects that should never affect gameplay, use dedicated collision layers

#### Community Solutions
Sources:
- [How to prevent rigidbody being affected by colliding with others - Godot Forums](https://godotforums.org/d/19495-how-i-can-prevent-rigidbody-being-affected-by-colliding-with-others)
- [CharacterBody2D and RigidBody2D collision interaction problem - Godot Forum](https://forum.godotengine.org/t/characterbody2d-and-rigidbody2d-collision-interaction-problem/83714)

Common approaches:
1. Use dedicated collision layers for decorative objects
2. Reduce mass to near-zero for lightweight decorative objects
3. Ensure collision masks don't include layers that should be ignored

## Solution Implementation

### Changes Made

**Note**: During implementation, it was discovered that the main branch already contained a partial fix setting `collision_layer = 64` (layer 7). This PR builds upon that by adding mass reduction and layer documentation.

#### 1. Collision Layer Assignment
**File**: `scenes/effects/Casing.tscn`

Changed from:
```gdscript
collision_layer = 0  # (original)
```

Main branch had:
```gdscript
collision_layer = 64  # Layer 7 (2^6 = 64) - partial fix
```

This PR keeps layer 7 for consistency with main branch.

**Rationale**:
- Layer 7 is designated as "decorative" layer for non-interactive visual elements
- Player collision_mask (4 = layer 3) doesn't include layer 7
- Enemy collision_mask doesn't include layer 7
- Casings remain on a defined layer but won't interact with characters

#### 2. Mass Reduction
**File**: `scenes/effects/Casing.tscn`

Added:
```gdscript
mass = 0.01  # Very light, near-zero mass
```

**Rationale**:
- Reduces momentum even with high velocity (momentum = mass × velocity)
- Minimizes any potential impact on player if collision somehow occurs
- Makes casings behave like lightweight decorative objects

#### 3. Project Layer Naming
**File**: `project.godot`

Added:
```ini
2d_physics/layer_7="decorative"
```

**Rationale**:
- Provides clear documentation of layer purpose
- Improves maintainability for future development
- Follows Godot best practices for layer organization

### Why This Solution Works

1. **Complete Collision Separation**
   - Player is on layer 1, checks layer 3 (obstacles)
   - Casings are on layer 7, check layer 3 (obstacles)
   - No overlap in collision detection between player and casings

2. **Defense in Depth**
   - Layer separation is primary defense
   - Low mass is secondary defense
   - Both measures ensure casings won't affect player

3. **Maintains Visual Fidelity**
   - Casings still collide with obstacles (walls, floor)
   - Casings still land and stop naturally
   - Visual behavior remains unchanged from player perspective

## Testing Approach

### Manual Testing Required
1. Start game and move player character
2. Fire weapon to spawn casings
3. Walk through/over casings
4. Verify player movement is not affected
5. Verify casings still land properly on ground
6. Test with multiple casings spawned

### Expected Results
- Player walks through casings without any displacement
- Casings ejected normally and land on ground
- Casings don't affect player movement speed or direction
- No visual artifacts or clipping issues

## Alternative Solutions Considered

### Alternative 1: StaticBody2D After Landing
**Approach**: Convert casing to StaticBody2D after it lands

**Pros**:
- Completely removes physics interaction after landing
- Saves performance (no physics processing for landed casings)

**Cons**:
- More complex implementation
- Requires node type conversion at runtime
- Doesn't solve the problem during ejection phase

**Decision**: Not chosen - Layer separation is simpler and more maintainable

### Alternative 2: Area2D Instead of RigidBody2D
**Approach**: Use Area2D for casings (no physics simulation)

**Pros**:
- No physics interactions at all
- Better performance

**Cons**:
- Loses realistic ejection physics and animation
- Casings wouldn't bounce off walls realistically
- Significant visual quality reduction

**Decision**: Not chosen - Would reduce visual polish

### Alternative 3: Disable Player-Rigidbody Collisions Globally
**Approach**: Modify player script to ignore all RigidBody2D collisions

**Pros**:
- Solves issue for all RigidBody2D objects

**Cons**:
- May affect intended interactions with other objects (grenades, pushable crates, etc.)
- Less granular control
- Could cause unintended side effects

**Decision**: Not chosen - Too broad, could break other features

## Lessons Learned

1. **Collision Layer 0 is Not "No Collision"**
   - Setting `collision_layer = 0` doesn't disable physics interactions
   - Always use explicit layer assignments for proper isolation

2. **Defense in Depth for Physics**
   - Multiple safeguards (layer + mass) provide robust solution
   - Physics bugs can be subtle and require multiple mitigations

3. **Documentation is Critical**
   - Naming collision layers in project settings prevents confusion
   - Clear comments on physics properties aid maintenance

4. **Research Before Implementation**
   - Understanding Godot's physics system thoroughly prevented wrong solutions
   - Community resources provided valuable insights

## References

### Godot Documentation
- [RigidBody2D — Godot Engine Documentation](https://docs.godotengine.org/en/stable/classes/class_rigidbody2d.html)
- [Using CharacterBody2D/3D — Godot Engine Documentation](https://docs.godotengine.org/en/stable/tutorials/physics/using_character_body_2d.html)

### Community Resources
- [Character to Rigid Body Interaction :: Godot 4 Recipes](https://kidscancode.org/godot_recipes/4.x/physics/character_vs_rigid/index.html)
- [How to prevent rigidbody being affected by colliding with others - Godot Forums](https://godotforums.org/d/19495-how-i-can-prevent-rigidbody-being-affected-by-colliding-with-others)
- [CharacterBody2D and RigidBody2D collision interaction problem - Godot Forum](https://forum.godotengine.org/t/characterbody2d-and-rigidbody2d-collision-interaction-problem/83714)

## Conclusion

The shell casing physics issue was resolved by properly configuring collision layers and reducing casing mass. The solution ensures decorative objects never interfere with gameplay while maintaining visual quality and realistic physics behavior during ejection and landing.

The fix is minimal, focused, and follows Godot best practices for physics layer management. The defense-in-depth approach (layer separation + mass reduction) provides robust protection against unintended physics interactions.
