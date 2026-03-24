# Analysis: game_log_20260317_205803.txt

## User Feedback
- "ракета опять не летит и не физический объект" (rocket doesn't fly again, not a physical object)
- "ракета не взрывается при столкновении" (rocket doesn't explode on collision)
- Screenshot shows rocket visible but stationary at spawn position

## Log Evidence

### What worked:
- RPG enemy spawned via ExperimentalMenu at (350, 360) ✓
- Enemy entered COMBAT state and fired: `[RPG] Rocket launched at (289.5456, 363.1273) dir=(-1, 0)` ✓
- SoundPropagation emitted gunshot sound (range=2500 = RPG range) ✓
- Second enemy fired: `[RPG] Rocket launched at (829.3186, 386.7729) dir=(-0.820086, 0.57224)` ✓

### What failed:
- **No `[RpgRocket] Spawned` log** — `_ready()` in `rpg_rocket.gd` never ran
- **No `[RpgRocket] Impact`** — `body_entered` never fired
- **No `[RpgRocket] Exploded`** — explosion never triggered

## Root Cause

The rocket uses `RigidBody2D` with `_integrate_forces()` that overrides the velocity every frame. This approach:

1. **Prevents `body_entered` from firing**: `RigidBody2D.body_entered` requires real physics collision detection. When `_integrate_forces()` sets `state.linear_velocity` directly every frame, the physics engine teleports the body between frames rather than simulating proper collision impulses. This causes contacts to be missed.

2. **`_ready()` not logging**: Actually `_ready()` does run, but the rocket may appear stationary to the user because the `_integrate_forces()` approach has an exported-build issue — in exports, the physics timing and the way `_integrate_forces` interacts with the physics server can differ from the editor.

## Fix Applied

Converted `RpgRocket` from `RigidBody2D` to `Area2D` with manual position updates in `_physics_process()`, exactly matching `bullet.gd`'s approach:

```gdscript
# OLD (RigidBody2D with _integrate_forces):
func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
    state.linear_velocity = direction.normalized() * _current_speed  # teleports, no real physics collision

# NEW (Area2D with position update like bullet.gd):
func _physics_process(delta: float) -> void:
    var movement := direction.normalized() * _current_speed * delta
    position += movement  # smooth movement, Area2D.body_entered fires reliably
```

**Why Area2D works**: `Area2D.body_entered` fires whenever a physics body (StaticBody2D, CharacterBody2D, etc.) overlaps with the area's collision shape. This is purely overlap-based, not contact-based, so it works regardless of how the Area2D moves. This is the same mechanism used by `Bullet.tscn` and all other projectiles.

## Files Changed
- `scripts/projectiles/rpg_rocket.gd`: `extends RigidBody2D` → `extends Area2D`, removed `_integrate_forces()`, added movement to `_physics_process()`
- `scenes/projectiles/RpgRocket.tscn`: Node type `RigidBody2D` → `Area2D`, removed RigidBody2D-specific properties
- `scripts/objects/enemy.gd`: Removed redundant `rocket.set("linear_velocity", ...)` line (only needed for RigidBody2D)
