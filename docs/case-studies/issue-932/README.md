# Case Study: Issue #932 — Fix Force Field (Силовое поле)

## Issue Description

**Report**: "fix силовое поле"

1. Силовое поле должно ловить пули — они должны прилипать на границе поля, как в остановленном времени при особом последнем шансе.
2. Когда силовое поле исчезает — пули должны разлетаться в разные стороны от игрока.

(Translation: 1. The force field should catch bullets — they should stick to the boundary of the field, as in stopped time at a special last chance. 2. When the force field disappears — the bullets should fly off in different directions away from the player.)

---

## Background

This is the fourth consecutive issue on the force field feature:
- **#676**: Force field not activating at all (missing `InitForceField()` in `Player.cs`)
- **#906**: Requested bullet trapping + bubble visual
- **#912**: Force field not trapping bullets (C# `QueueFree()` race condition + `has()` vs `in` GDScript bug)
- **#932**: Bullet boundary snapping — bullets should visually stick to the EDGE of the field, not float inside it

---

## Root Cause Analysis

### Feature Request #1: Bullets should snap to the boundary

The existing `_trap_bullet()` in `force_field_effect.gd` (as of PR #913) correctly:
- Stops the bullet's physics process
- Stores it in `_trapped_bullets`

However, it does NOT reposition the bullet to the boundary of the force field.

When a bullet enters the `Area2D` (which has radius 35px), it is detected at whatever position it happens to be when the physics engine fires the `area_entered` signal. This can be anywhere from just barely inside the boundary to deep inside the field. The bullet freezes in place visually, which is not the intended "time stopped, stuck at the edge" effect.

**Fix**: After stopping the bullet, calculate the point on the field boundary ring in the bullet's incoming direction and move the bullet there. The boundary position is:
```
boundary_pos = global_position + direction_to_bullet.normalized() * FIELD_RADIUS
```

This creates the visual effect of bullets hovering at the edge of the shield like a time-stop.

### Feature Request #2: Bullets scatter outward on field deactivation

This was already implemented in `_release_trapped_projectiles()` / `_release_projectile()` as of PR #913. Each trapped bullet is given:
- `direction = (bullet_position - center).normalized()` — outward direction
- `speed = BULLET_RELEASE_SPEED` — release speed (800 px/s for bullets)
- Physics process re-enabled

This feature was functional but not fully testable without the boundary snapping fix, because bullets wouldn't be at expected positions on the boundary.

---

## Implementation

### Modified file: `scripts/effects/force_field_effect.gd`

Added `_snap_to_boundary()` call inside `_trap_bullet()` and `_trap_shrapnel()` after stopping movement:

```gdscript
func _snap_to_boundary(projectile: Node2D) -> void:
    var from_center := projectile.global_position - global_position
    var direction_to_proj := from_center.normalized()
    # If projectile is at or very near center, use its movement direction
    if from_center.length_squared() < 1.0 and "direction" in projectile:
        direction_to_proj = projectile.direction.normalized()
    # Place at boundary
    projectile.global_position = global_position + direction_to_proj * FIELD_RADIUS
```

This ensures trapped bullets always sit on the field boundary ring, creating the "time stopped at the edge" visual effect.

---

## Files Modified

1. `scripts/effects/force_field_effect.gd` — Add `_snap_to_boundary()` and call it from `_trap_bullet()` and `_trap_shrapnel()`

---

## Key Facts

- **FIELD_RADIUS**: 35px — the force field boundary radius
- **Boundary snap**: `global_position + direction_to_bullet.normalized() * FIELD_RADIUS`
- The release behavior (scatter outward) was already implemented correctly in `_release_projectile()`
- C# bullets (Bullet.cs, ShotgunPellet.cs) already have `IsForceFieldArea()` checks to prevent `QueueFree()` when entering force field area (from PR #913)
- GDScript bullet (`bullet.gd`) naturally doesn't destroy itself when entering force field area because it only calls `_destroy()` when `area.has_method("on_hit")`, and the force field area does not have that method
