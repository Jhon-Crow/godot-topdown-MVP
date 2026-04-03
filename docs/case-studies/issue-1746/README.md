# Case Study: Issue #1746 — Enemy Collision Blocks Projectiles After Death

## Summary

After an enemy is killed, its collision area remains active for a short time, blocking
projectiles that are fired at or through the position where the enemy died. This causes
bullets to be consumed by the dead enemy body, wasting ammunition and disrupting combat
flow.

Issue text (original, Russian): *«сейчас после смерти враг его колизия некоторое время
блокирует заряды»*  
Translation: *"currently after death the enemy's collision blocks projectiles for some time"*

---

## Relationship to Issue #1413

Issue #1413 addressed a specific variant of this problem: **ragdoll body parts** (created
during death animation) blocking bullets because `RigidBody2D` nodes have no `is_alive()`
method. That fix added the `dead_enemy_ragdoll` group check in `bullet.gd`.

Issue #1746 addresses the **root cause** more broadly: the HitArea collision is not
disabled immediately when the enemy dies, meaning any bullet that enters the HitArea in
the same or next physics frame before deferred disabling takes effect still triggers the
hit handler.

---

## Timeline / Sequence of Events

### Normal case (alive enemy)

1. Player fires bullet → `Bullet` (Area2D, `collision_layer=16`, `collision_mask=39`) moves.
2. Bullet's `_on_area_entered` fires when it overlaps `HitArea` (Area2D, `collision_layer=2`,
   `collision_mask=16`).
3. `bullet.gd:_on_area_entered` calls `area.on_hit_with_bullet_info(...)` → enemy takes damage.
4. Bullet is destroyed.

### Bug case (enemy just died — same/next frame)

1. Bullet A kills enemy: `on_hit_with_bullet_info` → health ≤ 0 → `_on_death()` called.
2. `_on_death()`:
   - Sets `_is_alive = false` **synchronously** ✓
   - Calls `_disable_hit_area_collision()` which uses `set_deferred(...)` → executes **next frame**.
3. Bullet B (already in flight) enters `HitArea` in the **same physics frame** as Bullet A.
4. `_on_area_entered` fires for Bullet B.
5. **Before the fix**: No `is_alive()` check existed in `_on_area_entered`. Bullet B
   continues to `area.on_hit_with_bullet_info(...)`.
6. `on_hit_with_bullet_info` checks `if not _is_alive: return` → correctly ignores the hit.
7. **However**, bullet B was still **destroyed** by `_destroy()` at the end of
   `_on_area_entered` because the code path did not return early enough.

### After the fix

The fix adds an early `is_alive()` check in `bullet.gd:_on_area_entered` **before** the
bullet is destroyed:

```gdscript
# Check if the parent is dead - bullets should pass through dead entities
if parent and parent.has_method("is_alive") and not parent.is_alive():
    return  # Pass through dead entities
```

This ensures bullets pass through the dead enemy's HitArea even when the deferred
`set_deferred("collision_layer", 0)` hasn't taken effect yet.

---

## Root Cause Analysis

### Primary root cause

**Godot's `set_deferred` creates a one-frame gap between death and collision disabling.**

When `_on_death()` is called:
- `_is_alive = false` — synchronous (takes effect immediately)
- `_hit_collision_shape.set_deferred("disabled", true)` — deferred (next frame)
- `_hit_area.set_deferred("collision_layer", 0)` — deferred (next frame)
- `_hit_area.set_deferred("monitorable", false)` — deferred (next frame)

Godot's [known issue #62506](https://github.com/godotengine/godot/issues/62506) and
[#100687](https://github.com/godotengine/godot/issues/100687) confirm that Area2D
collision layer changes only take effect after the current physics step, making immediate
`collision_layer = 0` assignments unreliable during physics callbacks.

### Secondary root cause (Issue #1413 — already fixed)

Death animation creates `RigidBody2D` ragdoll parts with `collision_layer=32` (bit 5,
"targets" layer). The bullet's `collision_mask=39=0b100111` includes this bit, so bullets
physically interact with ragdoll parts. Since ragdoll `RigidBody2D` nodes have no
`is_alive()` method, the old dead-enemy check was silently skipped.

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

**Enemy CharacterBody2D**: `collision_layer=2, collision_mask=6`  
**HitArea**: `collision_layer=2, collision_mask=16`  
**Bullet**: `collision_layer=16, collision_mask=39=0b100111` (layers 1, 2, 3, 6)  
**Ragdoll**: `collision_layer=32=0b100000` (layer 6 — in bullet mask)

---

## Fix

### Multi-layered approach in `scripts/objects/enemy.gd`

`_disable_hit_area_collision()` uses all available Godot Area2D disabling approaches:

```gdscript
func _disable_hit_area_collision() -> void:
    if _hit_collision_shape:
        _hit_collision_shape.set_deferred("disabled", true)   # Approach 1: shape
    if _hit_area:
        _hit_area.set_deferred("collision_layer", 0)          # Approach 2: layers
        _hit_area.set_deferred("collision_mask", 0)
        _hit_area.set_deferred("monitorable", false)          # Approach 3: monitoring
        _hit_area.set_deferred("monitoring", false)
```

`is_alive()` returns `false` **immediately** (synchronous), acting as a fast-path guard
before any deferred calls take effect.

### Early check in `scripts/projectiles/bullet.gd:_on_area_entered`

Added before the bullet processes the hit:

```gdscript
# Check if the parent is dead - bullets should pass through dead entities
# This is a fallback check in case the collision shape/layer disabling
# doesn't take effect immediately (see Godot issues #62506, #100687)
if parent and parent.has_method("is_alive") and not parent.is_alive():
    return  # Pass through dead entities
```

### Ragdoll fix in `scripts/projectiles/bullet.gd:_on_body_entered` (Issue #1413)

```gdscript
if body.is_in_group("dead_enemy_ragdoll"):
    return  # Pass through dead enemy ragdoll parts
```

---

## Alternative Solutions Considered

| Option | Pros | Cons |
|--------|------|------|
| Use immediate (non-deferred) collision disable | No frame gap | Godot crashes/warns when physics properties changed during callback |
| Move `is_alive()` check to `HitArea.on_hit` | Single place | HitArea doesn't own the alive state |
| Change bullet collision mask to exclude enemy layer | Prevents all body-level collisions | Breaks alive-enemy hit detection |
| **Synchronous `_is_alive=false` + deferred layer clear + `is_alive()` guard in bullet** (chosen) | No crashes, robust, multi-layered | Requires checks in multiple places |

---

## Files Changed

- `scripts/objects/enemy.gd` — `_disable_hit_area_collision()` and `_enable_hit_area_collision()`, `is_alive()` function
- `scripts/projectiles/bullet.gd` — `is_alive()` guard in `_on_area_entered` and `_on_body_entered`
- `scripts/components/death_animation_component.gd` — ragdoll `dead_enemy_ragdoll` group (Issue #1413)

## Tests

- `tests/integration/test_enemy_death_bullet_passthrough.gd` — comprehensive test suite:
  - HitArea disabled after death (collision shape, layers, monitorable/monitoring)
  - `is_alive()` returns `false` immediately (synchronous, no await needed)
  - HitArea re-enabled on respawn
  - Dead enemy ignores additional hit calls
  - Ragdoll group pass-through (Issue #1413)
