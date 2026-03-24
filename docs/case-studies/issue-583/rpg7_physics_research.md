# RPG-7 Physics Research

## Real-World Data

| Property | Value | Notes |
|---|---|---|
| Initial muzzle velocity | 115–120 m/s | Propelled by booster/expeller charge |
| Motor ignition distance | 10–11 m downrange | Safety feature: fires after leaving tube |
| Sustained max velocity | 294–295 m/s | After sustainer motor fully spools up |
| Motor burn range | ~500 m | Sustainer active for first 500 m |
| Motor burn duration | ~2–3 s (derived) | Not officially published |
| Acceleration during burn | ~60–90 m/s² (~6–9g) | Derived from velocity delta over burn time |
| Effective range (stationary) | 500 m | Motor still burning, best accuracy |
| Effective range (moving) | 300 m | Practical combat limit |
| Self-destruct time | 4.5 s | Fuze detonates at 4.5 s if no impact |
| Self-destruct distance | ~920 m | Approximate range at self-destruct |

## Key Characteristics

1. **Two-phase propulsion**: Initial low velocity (115 m/s), then rocket motor accelerates to 295 m/s
2. **Straight stabilized flight**: Fin-stabilized with slow controlled spin — does NOT tumble
3. **No free rotation**: The rocket maintains its nose-forward orientation throughout flight
4. **No physics drift**: Fins provide gyroscopic stability — crosswind deflection is minimal at game scales
5. **Motor ignites at safe distance**: ~10 m from muzzle (irrelevant at game scale but good flavor)

## Game Scale Conversion

Game uses pixels-per-second. Assuming 1 pixel ≈ 1 cm (typical 2D top-down games):
- Real-world 115 m/s ≈ 11,500 px/s (too fast for game)
- Gameplay-scaled initial speed: ~300 px/s
- Gameplay-scaled max speed: ~900 px/s
- Motor burn time in game: ~0.8–1.5 s

## Sources

- Wikipedia: https://en.wikipedia.org/wiki/RPG-7
- Small Arms Defense Journal: https://sadefensejournal.com/the-rpg-7-system-primer/4/
- GlobalSecurity.org: https://www.globalsecurity.org/military/world/russia/rpg-7-specs.htm
- HowStuffWorks: https://science.howstuffworks.com/rpg3.htm

## Problem Analysis: Why Rocket Behaved Like a Plastic Bottle

Previous implementation used `RigidBody2D` with `linear_velocity`. RigidBody2D applies Godot's physics engine which:
1. Allows angular velocity / free rotation on collision
2. Applies physics damping even with `linear_damp=0`
3. Physics forces can deflect trajectory on collision with other bodies
4. `continuous_cd` mode adds collision response forces

**Solution**: Use `Area2D` with manual position update (same as `bullet.gd`) for straight controlled flight.
The Area2D approach:
- `position += direction * speed * delta` — straight line, no physics deflection
- No rotation from physics forces (rocket keeps nose-forward orientation)
- `area_entered` + `body_entered` signals for collision detection
- Explicit acceleration in `_physics_process` for the motor burn phase

## Acceleration Model for Game

```
Phase 1 (launch): speed = LAUNCH_SPEED (e.g., 300 px/s)
Phase 2 (motor burn, first MOTOR_BURN_TIME seconds):
    speed += MOTOR_ACCELERATION * delta
    speed = min(speed, MAX_SPEED)
Phase 3 (coasting): speed stays at MAX_SPEED (no drag in top-down view)
```

This matches real RPG-7 two-phase propulsion and gives the player visible rocket trail
acceleration that feels physically correct.
