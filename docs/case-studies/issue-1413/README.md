# Case Study: Issue #1413 — Bullets Blocked by Dead Enemy Bodies

## Summary

After killing an enemy, bullets fired at or through the spot where the body lies are
blocked and destroyed before reaching targets behind it. This wastes ammunition and
makes combat feel unresponsive.

---

## Timeline / Sequence of Events

### Normal case (alive enemy)

1. Player fires bullet → `Bullet` (Area2D) moves through scene.
2. Bullet's `body_entered` signal fires when it overlaps with `Enemy` (CharacterBody2D,
   layer 2).
3. `_on_body_entered` in `bullet.gd` checks `body.has_method("is_alive") and body.is_alive()`
   → true, so enemy takes damage via `HitArea`.
4. Bullet is destroyed or ricochets per normal rules.

### Bug case (dead enemy with ragdoll)

1. Enemy dies: `_on_death()` sets `_is_alive = false`.
2. `_disable_hit_area_collision()` disables `HitArea` via `set_deferred` (next frame).
3. Death animation starts; at ~60% of fall animation, ragdoll activates.
4. `DeathAnimationComponent._create_ragdoll_body()` creates `RigidBody2D` parts with:
   - `collision_layer = 32` (layer 6, "targets")
   - `collision_mask = 4` (layer 3, obstacles only)
5. **BUG**: The bullet's `collision_mask = 39 = 0b100111` includes bit 5 (layer 6).
   So bullets collide with ragdoll `RigidBody2D` bodies.
6. Bullet's `_on_body_entered` fires for the ragdoll `RigidBody2D`.
7. `body.has_method("is_alive")` returns **false** (ragdoll has no `is_alive()` method).
8. The dead-enemy pass-through check is skipped.
9. Ragdoll body is not a `StaticBody2D` or `TileMap`, and doesn't match any special case.
10. Bullet falls through to `_destroy()` at the end of `_on_body_entered` → **bullet destroyed**.

### Secondary issue (same frame death + bullet)

If a bullet is fired in the same physics frame that an enemy dies, the `set_deferred`
`HitArea` disable hasn't taken effect yet. However, `_is_alive = false` is set
synchronously, so `on_hit_with_bullet_info` checks `is_alive()` and ignores the hit.
This secondary path is already handled correctly.

---

## Root Cause

**`DeathAnimationComponent` creates `RigidBody2D` ragdoll parts on collision layer 32
(layer 6 "targets"), which is included in the bullet's collision mask. These ragdoll
bodies have no `is_alive()` method, so the dead-enemy bullet pass-through check in
`bullet.gd:_on_body_entered` is skipped and bullets are destroyed on impact.**

### Evidence from game log (`game_log_20260324_085359.txt`)

- `[08:56:32] [ENEMY] [Enemy2] Enemy died` → death sequence begins
- `[08:56:32] [INFO] [DeathAnim] Started - Angle: -14.9 deg, Index: 11` → ragdoll will
  activate at ~60% of fall animation (~480ms later)
- After ragdoll activation, any bullet entering the ragdoll's collision area is destroyed

---

## Collision Layer Map (from `project.godot`)

| Layer | Bit | Name        |
|-------|-----|-------------|
| 1     | 0   | player      |
| 2     | 1   | enemies     |
| 3     | 2   | obstacles   |
| 4     | 3   | pickups     |
| 5     | 4   | projectiles |
| 6     | 5   | targets     |
| 7     | 6   | decorative  |

**Bullet collision_mask = 39 = 0b100111** → layers 1, 2, 3, 6
**Ragdoll collision_layer = 32 = 0b100000** → layer 6 ✓ (in bullet mask — triggers collision)

---

## Fix

### `scripts/components/death_animation_component.gd`

Add ragdoll bodies to the `"dead_enemy_ragdoll"` group immediately after creation:

```gdscript
rb.add_to_group("dead_enemy_ragdoll")
```

### `scripts/projectiles/bullet.gd` — `_on_body_entered`

Add a pass-through check for ragdoll parts before the fall-through to `_destroy()`:

```gdscript
# Issue #1413: Pass through ragdoll body parts of dead enemies.
if body.is_in_group("dead_enemy_ragdoll"):
    return  # Pass through dead enemy ragdoll parts
```

---

## Alternative Solutions Considered

| Option | Pros | Cons |
|--------|------|------|
| Change ragdoll layer to 0 (no layer) | Simple one-liner | Ragdolls wouldn't interact with obstacles |
| Change ragdoll layer to 64 (decorative) | Not in bullet mask | Layer semantics are misleading |
| Group-based check (chosen) | Explicit, self-documenting, no layer changes | Requires two-file change |

---

## Files Changed

- `scripts/components/death_animation_component.gd` — mark ragdoll bodies with group
- `scripts/projectiles/bullet.gd` — pass through `dead_enemy_ragdoll` group members

## Tests

- `tests/integration/test_enemy_death_bullet_passthrough.gd` — existing tests verify
  HitArea collision is disabled on death and `is_alive()` works correctly
- New test added to cover ragdoll group pass-through case
