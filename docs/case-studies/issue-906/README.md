# Issue #906 Case Study: Force Field Update

## Issue Description

Update the force field item with three new behaviors:

1. **Bullet trapping**: Bullets touching the force field should stop and be held by the field (instead of disappearing/reflecting).
2. **Bullet release**: When the force field deactivates, all held bullets should scatter in different directions away from the player.
3. **Visual bubble effect**: The visual effect of the field should look more like a bubble.

## Current Implementation Analysis

### Force Field Files
- `scripts/effects/force_field_effect.gd` - Main controller script
- `scripts/shaders/force_field.gdshader` - Shader for visual effect
- `scenes/effects/ForceFieldEffect.tscn` - Scene file (minimal, just Node2D + script)

### Current Force Field Behavior (Issue #676)
- Activated by holding Space key with a depletable 8-second charge
- Glowing blue energy ring around the player
- **Reflects** all bullets and shrapnel (changes their direction)
- Grenades bounce off without detonating
- Visual: pulsing blue ring with rotating energy lines

### Current Bullet Architecture (bullet.gd)
- Bullets are `Area2D` nodes
- Have `direction: Vector2` and `speed: float` properties
- Pool managed via `ProjectilePoolManager`
- `_destroy()` method handles proper pool return or `queue_free()`
- `_physics_process()` moves bullets each frame via `position += direction * speed * delta`

### Key Observations
1. The force field's `_on_projectile_entered()` currently calls `_reflect_bullet()` which changes the bullet's direction.
2. To **trap** bullets: we need to **freeze** bullets in place (stop their physics_process movement) and **reparent** them to the force field or track their positions.
3. To **release** bullets: on `deactivate()`, iterate through all held bullets and apply random outward velocity.
4. The bullet's `speed` can be set to 0 to stop movement, and `direction` can be set to an outward direction when releasing.

## Solution Design

### Approach 1: Freeze bullets in-place
- When a bullet enters the force field, set its `speed = 0` and store a reference.
- On deactivate, set each bullet's `direction` to point away from player and restore `speed`.
- **Pros**: Simple, no reparenting needed.
- **Cons**: Bullets continue to exist in-world at their last position; if force field moves, bullets don't follow.

### Approach 2: Hide and track bullets (chosen approach)
- When a bullet enters, set it invisible and disable its physics process.
- Track the bullet positions relative to player.
- On deactivate, re-enable bullets with outward direction.
- **Pros**: Clean suspension of bullet state.
- **Cons**: Slightly more complex.

### Approach 3: Use Godot's freeze for RigidBody2D (not applicable)
- Bullets are `Area2D`, not `RigidBody2D`, so physics freeze doesn't apply directly.

## Chosen Implementation Plan

### Step 1: Bullet Trap Mechanic
In `force_field_effect.gd`:
- Add `_trapped_bullets: Array` to track held bullets.
- In `_on_projectile_entered()`: instead of reflecting, call new `_trap_bullet(bullet)`.
- `_trap_bullet()`: disable bullet physics process (stop movement), mark with a flag.

### Step 2: Bullet Release on Deactivation
- Override `deactivate()` to call `_release_trapped_bullets()` before completing deactivation.
- `_release_trapped_bullets()`: iterate `_trapped_bullets`, set direction to `(bullet.global_position - global_position).normalized()`, restore speed, re-enable physics process.
- Clear `_trapped_bullets` array.

### Step 3: Bubble Visual Effect
Modify `force_field.gdshader`:
- Replace the rotating energy lines with a fresnel/bubble effect.
- Use radial gradient with strong edge glow (like a soap bubble).
- Add iridescent color shift.
- Keep pulsing animation but make it subtler.

### Step 4: Edge Cases
- Handle bullet cleanup: if bullet is destroyed while trapped (e.g., via other means), remove from array.
- Handle charge depletion: same as manual deactivation — release bullets.
- Pool compatibility: set `set_physics_process(false)` without calling `_destroy()`.

## References

- [Godot 4 Area2D documentation](https://docs.godotengine.org/en/stable/classes/class_area2d.html)
- [Godot 4 Node.set_physics_process()](https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-set-physics-process)
- Related PRs: #791 (force field initial implementation, Issue #676)
- Bubble shader inspiration: Fresnel effect with edge highlight
