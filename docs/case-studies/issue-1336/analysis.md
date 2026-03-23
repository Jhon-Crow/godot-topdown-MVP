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
| 2026-03-23 | Failed fix: switched laser to visual barrel direction (commit 79f1d51b) |
| 2026-03-23 | Owner feedback: "снайпер стреляет не туда, где прицел" — bullets still go elsewhere |
| 2026-03-23 | Correct fix: laser uses _get_weapon_forward_direction() + _get_bullet_spawn_position() to match bullet trajectory |

## Data Sources

- `game_log_20260323_102814.txt` — Game log from user testing session (barrel-direction fix)
- `game_log_20260323_104706.txt` — Game log confirming barrel-direction fix was still wrong
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

## Failed Fix Attempt: Visual Barrel Direction

The first fix (commit 79f1d51b) changed the laser to use `_weapon_sprite.global_transform.x` — the visual barrel direction. The rationale was "visual consistency": the laser should follow the model rotation.

**This was wrong.** The bullets use `_get_weapon_forward_direction()` which returns the direct-to-player direction (not the visual barrel). So the laser now followed the visual barrel, but bullets flew in a different direction (directly at the player). The user correctly reported: "снайпер стреляет не туда, где прицел" (sniper shoots where the laser isn't).

The core insight: the laser is a **gameplay UI element** that shows the player where they will be shot. It must match the **actual bullet trajectory**, not the visual model state.

## Correct Solution

Changed `update_laser_sight()` to use `enemy._get_weapon_forward_direction()` and `enemy._get_bullet_spawn_position(direction)` — the **same functions** that `_execute_shoot()` uses for bullet direction and spawn position. This ensures:

1. The laser points exactly where the next bullet will fly
2. The laser starts from the same muzzle position as bullet spawning
3. Both laser and bullets share the same `_can_see_player` logic, so they always agree

### Collision Layer Reference

| Layer | Bit Value | Used For |
|-------|-----------|----------|
| 1 | 1 | Player character |
| 2 | 2 | Enemy characters |
| 3 | 4 | Walls/Obstacles |
| 5 | 16 | Projectiles |

Laser raycast mask: **5** (binary `101`) = Layer 1 (player) + Layer 3 (walls)

## Additional Data

- `game_log_20260323_102814.txt` — Game log from testing the failed barrel-direction fix
- `game_log_20260323_104706.txt` — Game log confirming laser still didn't match bullet direction

## Lessons Learned

1. **Laser must match bullet trajectory, not visual model**: A laser sight is a gameplay indicator showing "you will be shot here." It must use the exact same direction calculation as bullets, even if that direction differs from the visual barrel orientation.

2. **Function reuse is the correct approach here**: Unlike the initial analysis which treated `_get_weapon_forward_direction()` as a "pitfall," using the same function for both laser and bullets is the correct design — it guarantees they always agree.

3. **Visual barrel ≠ actual aim direction**: In this codebase, the model rotates smoothly with interpolation lag, but bullets skip ahead to aim directly at the player. The laser must follow the bullets, not the visual model. This is a design choice in the game (enemies have "perfect aim" once they see you, with rotation being cosmetic).
