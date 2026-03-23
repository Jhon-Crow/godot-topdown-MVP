# Case Study: Issue #1336 — Sniper Enemy Laser Sight

## Problem Statement

The sniper enemy's laser sight did not align with where the bullets/tracers actually traveled. Additionally, the laser passed through the player instead of stopping at the player's body.

User feedback (translated from Russian):
1. "прицел всё ещё указывает не туда, куда летит трассер" — The laser sight still points in a different direction than the tracer flies.
2. "лазер проходит сквозь игрока" — The laser passes through the player.

## Timeline of Events

| Date | Event |
|------|-------|
| 2026-03-22 | Initial implementation: red laser sight added to sniper enemy (commit 91ba5fdd) |
| 2026-03-22 | PR #1341 opened, marked ready to merge |
| 2026-03-23 | Owner feedback: laser doesn't reach player on Docks map |
| 2026-03-23 | Fix: doubled laser length from 5000px to 10000px (commit f62ffe1d) |
| 2026-03-23 | Owner feedback: laser doesn't point where tracer goes, passes through player |
| 2026-03-23 | Fix: changed raycast mask from 4 to 5 (walls+characters), excluded enemy collider (commit b943d0f0) |
| 2026-03-23 | Owner feedback: laser STILL doesn't match tracer direction |
| 2026-03-23 | Root cause analysis and definitive fix (this commit) |

## Data Sources

- `game_log_20260323_102814.txt` — Game log from user testing session
- Source code analysis of `enemy.gd` and `enemy_sniper_component.gd`
- Player M16 laser implementation in `AssaultRifle.cs` for comparison

## Root Cause Analysis

### The Direction Calculation Bug

The laser sight used `enemy._get_weapon_forward_direction()` to determine where to point. This function has **two different code paths** depending on `_can_see_player`:

```gdscript
func _get_weapon_forward_direction() -> Vector2:
    # Path A: When player IS visible
    if _player and is_instance_valid(_player) and _can_see_player:
        return (_player.global_position - global_position).normalized()
    # Path B: When player is NOT visible
    if _weapon_sprite:
        return _weapon_sprite.global_transform.x.normalized()
```

**Path A** returns a geometric direction from the enemy's body center to the player's position. This is an **instantaneous, perfect aim direction** that ignores where the visual weapon barrel is actually pointing.

**Path B** returns the weapon sprite's transform-based direction, which follows the enemy model's smooth rotation via `_update_enemy_model_rotation()`.

### Why This Causes a Mismatch

The enemy model rotates smoothly toward the player using `MODEL_ROTATION_SPEED * delta` interpolation (see `_update_enemy_model_rotation()`, line 930 of `enemy.gd`). At any given frame, the model's visual facing angle may differ from the true angle to the player because:

1. **Smooth rotation lag**: The model hasn't finished turning yet
2. **Corner peeking**: The model rotates through a corner-check angle
3. **Blind-fire**: During blind-fire, `fire_at_predicted_position()` snaps the model to a predicted position (line 155-156), which is different from both the player's actual position and Path A's computation

The **tracer** (spawned by `shoot_sniper_hitscan()`) uses the same `_get_weapon_forward_direction()`, so in theory it matches the laser. However, the **visual appearance** differs because:

- The tracer is a brief flash (2 second fade) starting from the muzzle, making small angular differences hard to notice
- The laser is persistent and visible every frame, making the divergence from the **visual barrel direction** obvious to the player

### Why the Laser Appeared to Pass Through the Player

The laser's start position was computed from `_get_bullet_spawn_position(direction)` which, when `_can_see_player` is true, uses the direction-to-player to offset from the weapon sprite position:

```gdscript
weapon_forward = (_player.global_position - global_position).normalized()
result = _weapon_sprite.global_position + weapon_forward * scaled_muzzle_offset
```

If the model faces angle A (e.g., 150 degrees) but the player is at angle B (e.g., 145 degrees), the start position is offset from the weapon sprite in the wrong direction. Combined with the direction pointing at the player from the body center (not the muzzle), the laser line could visually appear to pass through the player's sprite rather than stopping at their collision shape.

### Comparison with Player M16 Laser

The player's M16 assault rifle laser (in `AssaultRifle.cs`) uses `_aimDirection` which tracks the mouse cursor — this is the **actual weapon aim direction**, not a computed geometric direction. The M16 laser always visually matches the barrel because both follow the same rotation.

## Solution

Changed `update_laser_sight()` to use `_weapon_sprite.global_transform.x.normalized()` (the visual barrel direction) instead of `_get_weapon_forward_direction()`. This ensures:

1. The laser always follows the visual weapon barrel direction
2. When the model smoothly rotates, the laser rotates with it
3. During blind-fire, the laser follows the model snap
4. The muzzle position is computed consistently with the barrel direction

### Collision Layer Reference

| Layer | Bit Value | Used For |
|-------|-----------|----------|
| 1 | 1 | Player character |
| 2 | 2 | Enemy characters |
| 3 | 4 | Walls/Obstacles |
| 5 | 16 | Projectiles |

Laser raycast mask: **5** (binary `101`) = Layer 1 (player) + Layer 3 (walls)

## Lessons Learned

1. **Visual consistency over computational accuracy**: For visual elements like laser sights, the direction should match the visual state of the weapon (model transform), not a mathematically computed direction. The player sees the model, not the computation.

2. **Function reuse pitfall**: `_get_weapon_forward_direction()` was designed for bullet spawning (where computational accuracy matters), but reusing it for a visual effect caused a mismatch because the function's "perfect aim" shortcut (Path A) bypasses the visual model state.

3. **Multi-path functions are fragile**: Having different behavior paths based on `_can_see_player` makes the function harder to reason about. The laser would look correct sometimes (when the model happened to face the player) and wrong other times (during rotation), making the bug intermittent and hard to reproduce.
