# Online Research: Interactive Shell Casing Physics

## Research Overview

This document compiles online research findings for implementing interactive shell casings in Godot 4. Research was conducted on 2026-01-25 to identify best practices, common patterns, and potential solutions for making RigidBody2D shell casings bounce realistically when players and enemies walk over them.

## Research Questions

1. How to make RigidBody2D objects interactive with CharacterBody2D in Godot 4?
2. What are the best practices for implementing bounce physics in top-down games?
3. How to trigger collision-based sound effects for small physics objects?
4. What physics parameters create realistic shell casing behavior?

## Key Findings

### 1. CharacterBody2D and RigidBody2D Interaction

#### Default Behavior Problem
According to the [official Godot documentation](https://docs.godotengine.org/en/stable/tutorials/physics/using_character_body_2d.html), by default a CharacterBody2D moved with `move_and_slide()` or `move_and_collide()` **will not push any RigidBody2D** it collides with. The RigidBody2D behaves just like a StaticBody2D - the CharacterBody2D only stops and slides.

**Key Quote:**
> "CharacterBody2D doesn't exert any force when it collides with something, it only stops and slides."

Source: [Using CharacterBody2D/3D — Godot Engine (stable) documentation](https://docs.godotengine.org/en/stable/tutorials/physics/using_character_body_2d.html)

#### Solution Pattern: Push Force Implementation
The [Character to Rigid Body Interaction recipe](https://kidscancode.org/godot_recipes/4.x/physics/character_vs_rigid/) provides a proven solution:

**Implementation Steps:**
1. Define a `push_force` variable in your CharacterBody2D
2. In `_physics_process()`, iterate through slide collisions after `move_and_slide()`
3. Check if the collider is a RigidBody2D
4. Apply a central impulse using the collision normal

**Example Code Pattern:**
```gdscript
@export var push_force = 80.0

func _physics_process(delta):
    # ... movement code ...
    move_and_slide()

    for i in get_slide_collision_count():
        var collision = get_slide_collision(i)
        var collider = collision.get_collider()
        if collider is RigidBody2D:
            var push_dir = -collision.get_normal()
            collider.apply_central_impulse(push_dir * push_force)
```

Source: [Character to Rigid Body Interaction :: Godot 4 Recipes](https://kidscancode.org/godot_recipes/4.x/physics/character_vs_rigid/)

#### Important Considerations
- **Force Scaling**: Push force must be adjusted relative to RigidBody2D mass
- **Too High**: Causes objects to clip through walls
- **Too Low**: Objects don't move at all
- **Recommended**: Start with 80-100 and adjust based on object mass

Source: [How to push a RigidBody2D with a CharacterBody2D](https://forum.godotengine.org/t/how-to-push-a-rigidbody2d-with-a-characterbody2d/2681)

### 2. RigidBody2D Bouncing Physics

#### Physics Material Properties
According to [RigidBody2D documentation](https://kidscancode.org/godot_recipes/4.x/kyn/rigidbody2d/index.html), RigidBody2D has a `physics_material_override` property that controls bounce behavior:

**Key Properties:**
- **Bounce (Restitution)**: Controls how much energy is retained on collision (0.0 = no bounce, 1.0 = perfect bounce)
- **Friction**: Controls sliding resistance (0.0 = ice, 1.0 = rubber)
- **Rough**: Affects friction calculation mode

For realistic shell casings:
- Bounce: 0.3-0.5 (metal on hard surfaces has moderate bounce)
- Friction: 0.4-0.6 (metal slides but not freely)

Source: [RigidBody2D :: Godot 4 Recipes](https://kidscancode.org/godot_recipes/4.x/kyn/rigidbody2d/index.html)

#### Collision Layers Critical
Multiple forum discussions emphasize that **collision layers and masks must be properly configured** for RigidBody2D to interact with other objects.

**Common Setup:**
- RigidBody2D collision_layer: 5 (items layer)
- RigidBody2D collision_mask: 1 (characters) + 4 (walls)
- CharacterBody2D collision_layer: 1 (characters)
- CharacterBody2D collision_mask: 4 (walls) + 5 (items)

Source: [CharacterBody2D and RigidBody2D collision interaction problem](https://forum.godotengine.org/t/characterbody2d-and-rigidbody2d-collision-interaction-problem/83714)

### 3. Collision Detection for Sound Effects

#### Area2D body_entered Pattern
The [official Area2D documentation](https://docs.godotengine.org/en/stable/tutorials/physics/using_area_2d.html) describes using `body_entered` signal for collision detection without physics response.

**Pattern for Shell Casings:**
1. Add Area2D as child of RigidBody2D (casing)
2. Set Area2D collision layer to match parent
3. Connect `body_entered` signal to sound trigger function
4. Check collision velocity to prevent sound spam

**Important Gotcha:**
> "`body_entered` only emits for CollisionObject2D nodes (e.g., KinematicBody2D, RigidBody2D). For Area2D (triggers), use `area_entered` instead."

Source: [Using Area2D — Godot Engine (stable) documentation](https://docs.godotengine.org/en/stable/tutorials/physics/using_area_2d.html)

#### Velocity-Based Sound Triggering
According to [Sound Effects in Godot tutorial](https://www.coding.academy/blog/sound-effects-in-godot), collision sounds should be velocity-gated:

**Best Practice:**
```gdscript
func _on_body_entered(body: Node2D):
    var impact_velocity = linear_velocity.length()
    if impact_velocity < SOUND_THRESHOLD:
        return  # Too slow, no sound

    audio_player.play()
```

**Recommended Threshold:** 50-100 pixels/second for small objects like casings

Source: [Sound Effects in Godot — CODING ACADEMY](https://www.coding.academy/blog/sound-effects-in-godot)

### 4. Realistic Bounce Physics

#### Real-World Shell Casing Behavior
From general game physics research:

**Physical Properties:**
- **Mass**: Typical rifle casing ~10-15 grams
- **Material**: Brass (elastic modulus ~100 GPa)
- **Coefficient of Restitution**: 0.3-0.5 against concrete/metal
- **Terminal Spin**: Casings spin due to ejection mechanism, dampens over time

Source: [Physics Simulation - Game Development Fundamentals](https://oboe.com/learn/game-development-fundamentals-1botmyi/physics-simulation-ruble7)

#### Bounce Implementation in Games
[Mastering Game Physics article](https://30dayscoding.com/blog/game-physics-implementing-realistic-simulations) emphasizes:

**Key Principles:**
1. **Reflection Physics**: Bounce direction = reflect velocity around collision normal
2. **Energy Loss**: Each bounce reduces velocity by (1 - restitution)
3. **Angular Damping**: Rotation slows over time due to air resistance
4. **Rest Detection**: Stop physics when velocity drops below threshold

For top-down games specifically:
- Gravity can be disabled (0.0 gravity_scale)
- Friction becomes more important than in platformers
- Angular damping prevents perpetual spinning

Source: [Mastering Game Physics: Implementing Realistic Simulations](https://30dayscoding.com/blog/game-physics-implementing-realistic-simulations)

### 5. Performance Considerations

#### Sleeping and Rest Detection
According to RigidBody2D discussions, objects should "sleep" when stationary to save CPU:

**Godot's Built-in Sleep System:**
- RigidBody2D automatically sleeps when velocity drops below threshold
- Sleeping bodies don't consume physics calculations
- Bodies wake on collision

**For Shell Casings:**
- Set `can_sleep = true` (default)
- Use auto-landing after timeout to force sleep
- Consider `sleeping` property for manual control

Source: [RigidBody2D :: Godot 4 Recipes](https://kidscancode.org/godot_recipes/4.x/kyn/rigidbody2d/index.html)

### 6. Common Pitfalls and Solutions

#### Issue: Collision Not Detected
**Symptom:** CharacterBody2D and RigidBody2D don't interact
**Causes:**
1. Collision layers/masks not matching
2. RigidBody2D on layer 0 (none)
3. CharacterBody2D not checking for RigidBody2D in collision loop

**Solution:** Verify with Godot's debug collision shapes visualization

Source: [Collision Detection between CharacterBody2D and RigidBody2D not working](https://github.com/godotengine/godot/issues/70671)

#### Issue: RigidBody2D Pushed Through Walls
**Symptom:** High push force causes casings to clip through walls
**Causes:**
1. Impulse too strong relative to mass
2. Collision detection mode set to "Discrete" instead of "Continuous"
3. Wall collision layer not in RigidBody2D mask

**Solution:**
- Lower push force
- Add mass to RigidBody2D
- Ensure proper collision masking

Source: [CharacterBody2D and RigidBody2D collision interaction problem](https://forum.godotengine.org/t/characterbody2d-and-rigidbody2d-collision-interaction-problem/83714)

#### Issue: Sound Spam
**Symptom:** Continuous sound playing during rolling/sliding
**Causes:**
1. No velocity threshold check
2. No cooldown timer between sounds
3. Collision detection firing multiple times per frame

**Solution:**
```gdscript
var sound_cooldown: float = 0.0
const SOUND_COOLDOWN_TIME = 0.1  # 100ms between sounds

func _physics_process(delta):
    sound_cooldown = max(0.0, sound_cooldown - delta)

func _on_collision(body):
    if sound_cooldown > 0.0:
        return
    sound_cooldown = SOUND_COOLDOWN_TIME
    play_sound()
```

Source: Community best practices from [Godot Forum discussions](https://forum.godotengine.org/t/characterbody2d-rigidbody2d-interaction/72851)

## Alternative Approaches Considered

### Approach 1: Convert Casings to CharacterBody2D
**Concept:** Use CharacterBody2D with motion_mode = MOTION_MODE_FLOATING instead of RigidBody2D

**Pros:**
- Easier collision detection
- More predictable behavior
- Can use move_and_slide() for movement

**Cons:**
- Loses realistic physics simulation
- Requires manual velocity/bounce implementation
- Not natural for passive objects

**Verdict:** Not recommended for casings (they should be passive physics objects)

Source: [Movable Objects - True Top-Down 2D](https://catlikecoding.com/godot/true-top-down-2d/3-movable-objects/)

### Approach 2: Area2D-Only Detection
**Concept:** Use only Area2D without RigidBody2D physics

**Pros:**
- Simpler collision detection
- Lower CPU usage
- No physics quirks

**Cons:**
- No automatic physics simulation
- Must manually animate movement
- Loses bounce/spin effects

**Verdict:** Not suitable (requirement is "realistic bounce")

### Approach 3: Hybrid RigidBody2D + Area2D
**Concept:** RigidBody2D for physics, Area2D child for collision detection

**Pros:**
- Gets both physics and detection
- Clean separation of concerns
- Best of both worlds

**Cons:**
- Slightly more complex scene tree
- Two collision shapes to maintain

**Verdict:** **RECOMMENDED** - This is the industry-standard pattern

Source: Multiple Godot tutorials and official recipes

## Implementation Recommendations

### Recommended Solution Architecture

Based on the research, the optimal implementation should:

1. **Keep RigidBody2D Foundation**
   - Preserves existing physics simulation
   - Minimal changes to current system

2. **Add Area2D Child for Detection**
   - Separate collision detection from physics
   - Use for sound triggering

3. **Implement CharacterBody2D Push**
   - Add collision iteration in player/enemy _physics_process
   - Apply impulse when colliding with casings

4. **Add Physics Material**
   - Bounce: 0.3-0.4 (moderate metal bounce)
   - Friction: 0.5-0.6 (metal sliding)

5. **Velocity-Gated Sound System**
   - Threshold: 75 px/s minimum
   - Cooldown: 0.1s between sounds
   - Use collision normal to determine impact type

### Physics Parameters Table

| Parameter | Recommended Value | Rationale |
|-----------|------------------|-----------|
| mass | 0.1 | Light object, easy to push |
| bounce (restitution) | 0.35 | Realistic metal bounce |
| friction | 0.55 | Metal slides but has resistance |
| linear_damp | 3.0 | Already good (current) |
| angular_damp | 5.0 | Already good (current) |
| push_force | 50.0 | Light objects need less force |
| sound_threshold | 75.0 | Minimum velocity for sound |
| sound_cooldown | 0.1 | Prevent spam |

## Godot Version Compatibility

**Target Version:** Godot 4.3+ (current project version)

**API Changes to Note:**
- Godot 4 uses `get_slide_collision()` instead of `get_slide_collision(i)`
- RigidBody2D uses `apply_central_impulse()` (same as Godot 3)
- Area2D signals unchanged from Godot 3

**No Breaking Changes:** All researched patterns compatible with Godot 4.3

## Conclusion

The research confirms that making shell casings interactive requires:

1. **Proper collision layer configuration** - Critical for detection
2. **Manual push force implementation** - CharacterBody2D won't push by default
3. **Velocity-based sound triggering** - Prevents sound spam
4. **Physics material with bounce** - Creates realistic bouncing

All components are well-documented in Godot 4, with proven community patterns available. The hybrid RigidBody2D + Area2D approach is the industry standard and recommended solution.

## Sources

### Official Godot Documentation
- [Using CharacterBody2D/3D — Godot Engine (stable)](https://docs.godotengine.org/en/stable/tutorials/physics/using_character_body_2d.html)
- [Using Area2D — Godot Engine (stable)](https://docs.godotengine.org/en/stable/tutorials/physics/using_area_2d.html)
- [Physics introduction — Godot Engine (stable)](https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html)

### Community Resources
- [Character to Rigid Body Interaction :: Godot 4 Recipes](https://kidscancode.org/godot_recipes/4.x/physics/character_vs_rigid/)
- [RigidBody2D :: Godot 4 Recipes](https://kidscancode.org/godot_recipes/4.x/kyn/rigidbody2d/index.html)
- [Sound Effects in Godot — CODING ACADEMY](https://www.coding.academy/blog/sound-effects-in-godot)

### Forum Discussions
- [How to push a RigidBody2D with a CharacterBody2D](https://forum.godotengine.org/t/how-to-push-a-rigidbody2d-with-a-characterbody2d/2681)
- [CharacterBody2D and RigidBody2D collision interaction problem](https://forum.godotengine.org/t/characterbody2d-and-rigidbody2d-collision-interaction-problem/83714)
- [Collision Detection between CharacterBody2D and RigidBody2D](https://github.com/godotengine/godot/issues/70671)

### Game Physics Theory
- [Physics Simulation - Game Development Fundamentals](https://oboe.com/learn/game-development-fundamentals-1botmyi/physics-simulation-ruble7)
- [Mastering Game Physics: Implementing Realistic Simulations](https://30dayscoding.com/blog/game-physics-implementing-realistic-simulations)

### Alternative Approaches
- [Movable Objects - True Top-Down 2D](https://catlikecoding.com/godot/true-top-down-2d/3-movable-objects/)

---

*Research completed: 2026-01-25*
*Research conducted by: AI Issue Solver*
