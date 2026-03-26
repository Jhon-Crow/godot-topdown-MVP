# Case Study: Issue #1336 — Add Laser Sight to Sniper Enemy Rifle

**Date:** 2026-03-25
**Status:** Implemented (PR #1501)
**Related Issues:** #1163, #1171, #1334, #1336
**Previous Attempts:** PR #1341 (closed), PR #1484 (closed)

---

## Summary

Issue #1336 requests a laser sight on the sniper enemy's rifle with the explicit requirement:
> "laser must always point where the enemy will shoot (match the future tracer)"

Two previous attempts (PR #1341, PR #1484) failed due to three root causes:
- **Bug A:** Laser appeared on ALL enemies, not just snipers.
- **Bug B:** During blind fire, laser read the lerped weapon rotation instead of the actual fire direction.
- **Bug C:** Muzzle position was computed from the lerped sprite transform, creating a diagonal mismatch.

---

## Root Cause Analysis

### Bug A: Laser on All Enemies

`EnemySniperComponent` is instantiated unconditionally for **every** enemy at `enemy.gd:422`:

```gdscript
_sniper_component = EnemySniperComponent.new(); _sniper_component.enemy = self; ...
```

Any feature initialized inside the component (including the laser) applied to all enemies.

**Fix:** Add a weapon type guard in `_ready()`:
```gdscript
if int(enemy.weapon_type) == 7:  # SNIPER_RIFLE
    _create_laser_sight()
```

### Bug B: Direction Mismatch During Blind Fire

The sniper has two shooting modes with **different direction computation paths**:

| Mode | Bullet Direction | Previous Laser Direction |
|---|---|---|
| Direct fire (player visible) | `_get_weapon_forward_direction()` → `(player.pos - enemy.pos).normalized()` | Same ✅ |
| Blind fire (through cover) | `(target_pos - enemy.pos).normalized()` (exact) | `_get_weapon_forward_direction()` → lerped rotation ❌ |

During blind fire, `_rotate_toward()` uses `lerp_angle()` for smooth visual rotation, but `fire_at_predicted_position()` fires the bullet along the exact `to_target` vector. The laser was reading the intermediate lerped angle.

**Fix:** Track `_blind_fire_target` variable. When set, laser direction = `(_blind_fire_target - enemy.pos).normalized()` — the same vector used for the bullet.

### Bug C: Muzzle Start Point Mismatch

Even after fixing the laser's end-direction, the muzzle start point was computed using `_get_bullet_spawn_position()` which internally uses `_weapon_sprite.global_transform.x.normalized()` — the lerped sprite rotation. This created a diagonal Line2D from (lerped muzzle position) to (correct target direction).

**Fix:** Compute muzzle position using `weapon_forward` (the laser direction) directly:
```gdscript
muzzle_pos = weapon_sprite.global_position + weapon_forward * (MUZZLE_LOCAL_OFFSET * scale)
```

---

## Solution Design

### Architecture

The laser sight is implemented entirely within `EnemySniperComponent` (single file change). Key design decisions:

1. **Guard at creation time:** `int(enemy.weapon_type) == 7` check in `_ready()` ensures only snipers get a laser. Uses int comparison to avoid enum coercion issues between editor and release builds.

2. **Direction computed from the same data as the bullet:**
   - Blind fire → `(_blind_fire_target - enemy.pos).normalized()`
   - Direct fire → `(player.pos - enemy.pos).normalized()` (same as `_get_weapon_forward_direction()`)
   - Idle → sprite/model rotation fallback

3. **Muzzle position uses `weapon_forward`:** Both the muzzle offset and the laser end-direction use the same `weapon_forward` vector, ensuring the laser is always a straight line from gun barrel to target.

4. **Raycast for wall occlusion:** Laser stops at the first wall hit (physics layer 4).

5. **Visibility control:** Laser hides during reload and when the enemy is dead.

### Files Changed

| File | Change |
|---|---|
| `scripts/components/enemy_sniper_component.gd` | Added laser sight creation, update, direction, and muzzle position logic. Added `_blind_fire_target` tracking in `process_combat()` and `process_pursuing()`. |
| `tests/unit/test_sniper_laser_sight.gd` | New test file validating constants, guard logic, direction calculation, muzzle position, and direction consistency between laser and fire_at_predicted_position. |

---

## Key Technical Details

### Why `int(enemy.weapon_type) == 7` Instead of Enum Comparison

Previous PR #1484 discovered that Godot 4 enum coercion behaves differently between editor and release builds. Direct enum comparisons like `enemy.weapon_type == enemy.WeaponType.SNIPER_RIFLE` or `get("weapon_type")` can fail in release builds due to GDScript's dynamic typing. Using `int()` cast with the known enum value (7) is robust across all build configurations.

### Why `_process()` Instead of `_physics_process()`

The laser is a visual-only element. Using `_process()` ensures smooth updates at the rendering frame rate rather than the fixed physics tick rate, avoiding visual jitter.

### Tracer Matching Guarantee

The `_blind_fire_target` variable is set in `process_combat()` and `process_pursuing()` at the exact same code path that later calls `fire_at_predicted_position(blind_target)`. The laser reads `_blind_fire_target`, the bullet fires along `(target_pos - enemy.pos).normalized()`, and since `target_pos == _blind_fire_target`, the directions are mathematically identical.

---

## Online Research: Godot 4 Laser Sight Implementations

Common approaches for laser sights in Godot 4:
- **RayCast2D + Line2D:** The standard approach. A RayCast2D detects collision, and a Line2D draws from origin to collision point. Used by the player's sniper rifle in this project (`SniperRifle.cs` uses LaserGlowEffect).
- **Direct `intersect_ray()` per frame:** Used here. More flexible than a RayCast2D node since we compute the direction dynamically.
- **Shader-based:** Some projects use a shader for laser glow effects, but this adds complexity without benefit for a simple line.

The chosen approach (direct raycast + Line2D) is the simplest and most maintainable, matching the pattern already used for tracers in this project.

---

## Lessons Learned

1. **Direction source must match between visual and gameplay:** When a laser/crosshair shows where a bullet will go, both must read from the same data source. Using a visual representation (lerped sprite rotation) for a gameplay indicator (bullet direction) creates divergence.

2. **Muzzle position and direction must use the same reference frame:** Computing the start point in one coordinate system and the end direction in another creates diagonal artifacts.

3. **Component-level guards are more robust than instantiation-site guards:** Adding the weapon type check inside the component (rather than at the `enemy.gd` instantiation line) prevents regressions if the instantiation is moved or duplicated.
