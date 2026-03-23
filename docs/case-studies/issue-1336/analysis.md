# Case Study: Issue #1336 — Sniper Enemy Laser Sight

## Problem Statement

The sniper enemy's laser sight did not align with where the bullets/tracers actually traveled. Additionally, the laser passed through the player instead of stopping at the player's body.

User feedback (translated from Russian):
1. "прицел всё ещё указывает не туда, куда летит трассер" — The laser sight still points in a different direction than the tracer flies.
2. "лазер проходит сквозь игрока" — The laser passes through the player.
3. "возможно не учитывается отклонение при стрельбе в слепую, лазер должен быть направлен туда, куда полетит трассер (строго)" — Blind fire deviation is not accounted for; the laser must strictly match the tracer.

## Timeline of Events

| Date | Event |
|------|-------|
| 2026-03-22 | Initial implementation: red laser sight added to sniper enemy |
| 2026-03-22 | PR #1341 opened, marked ready to merge |
| 2026-03-23 | Owner feedback: laser doesn't reach player on Docks map |
| 2026-03-23 | Fix: doubled laser length from 5000px to 10000px |
| 2026-03-23 | Owner feedback: laser doesn't point where tracer goes, passes through player |
| 2026-03-23 | Fix: changed raycast mask from 4 to 5 (walls+characters), excluded enemy collider |
| 2026-03-23 | Owner feedback: laser STILL doesn't match tracer direction |
| 2026-03-23 | Failed fix attempt 1: switched laser to visual barrel direction — bullets still went elsewhere |
| 2026-03-23 | Failed fix attempt 2: switched laser back to `_get_weapon_forward_direction()` — still mismatch |
| 2026-03-23 | Owner: "blind fire deviation not accounted for, laser must strictly match tracer" |
| 2026-03-23 | Unified laser, hitscan, and blind-fire to all use visual barrel direction |
| 2026-03-23 | Owner: "теперь лазера вообще нет" — laser completely invisible |
| 2026-03-23 | **Fix: re-parent laser CanvasItem nodes to enemy (CharacterBody2D) instead of EnemySniperComponent (Node), add debug logging, restore accidentally removed `bullet_damage_multiplier`** |

## Data Sources

- `logs/game_log_20260323_102814.txt` — Game log from user testing (barrel-direction fix)
- `logs/game_log_20260323_104706.txt` — Game log confirming barrel-direction fix was still wrong
- `logs/game_log_20260323_110139.txt` — Game log with blind fire deviation analysis
- `logs/game_log_20260323_112851.txt` — Game log: laser completely invisible after unification fix
- Source code analysis of `enemy.gd` and `enemy_sniper_component.gd`
- Player M16 laser implementation in `AssaultRifle.cs` for comparison

## Root Cause Analysis

### The Dual Direction System

The enemy AI has **two separate direction systems** that diverge:

1. **Visual barrel direction** (`_weapon_sprite.global_transform.x.normalized()`): The direction the weapon model visually points. Rotates smoothly via `lerp_angle()` with `MODEL_ROTATION_SPEED * delta`, creating natural-looking rotation lag.

2. **Instant aim direction** (`_get_weapon_forward_direction()`): When `_can_see_player` is true, returns `(player.pos - enemy.pos).normalized()` — a direct geometric direction that ignores model rotation. When `_can_see_player` is false, falls back to the visual barrel direction.

```gdscript
func _get_weapon_forward_direction() -> Vector2:
    # Path A: When player IS visible — instant, perfect aim
    if _player and is_instance_valid(_player) and _can_see_player:
        return (_player.global_position - global_position).normalized()
    # Path B: When player is NOT visible — visual barrel
    if _weapon_sprite:
        return _weapon_sprite.global_transform.x.normalized()
```

### Why Previous Fixes Failed

**Attempt: Laser uses `_get_weapon_forward_direction()` (same as bullets)**
- When player visible: both laser and bullet use instant direction → both skip ahead of barrel
- Result: laser and tracer match each other, but BOTH diverge from the visual barrel
- User sees: barrel points left, laser goes straight, tracer goes straight → visually broken

**Attempt: Laser uses visual barrel direction**
- Laser follows the barrel (visually correct)
- But hitscan still uses `_get_weapon_forward_direction()` → instant aim direction
- Result: laser follows barrel, tracer goes somewhere else
- User sees: laser matches barrel, but tracer doesn't match laser → still broken

**Attempt: Back to `_get_weapon_forward_direction()` for laser**
- Same as first attempt — laser matches tracer but both diverge from barrel
- For blind fire: `fire_at_predicted_position()` adds ±3° random spread to bullets
- Laser doesn't account for this spread
- Result: even more mismatch during blind fire

### The Core Problem

The **visual model** and the **shooting system** operate on different direction systems. The model rotates smoothly (cosmetic), while bullets use instant geometric aim (gameplay). The `AIM_TOLERANCE_DOT = cos(30°)` check allows the enemy to fire when the barrel is up to 30° away from the target, making the divergence large and clearly visible.

Additionally, blind fire applied ±3° random spread on top of a snap rotation to the predicted position — creating further mismatch between the visible barrel direction and actual bullet direction.

### Comparison with Player M16 Laser

The player's M16 assault rifle laser (in `AssaultRifle.cs`) uses:
```csharp
Vector2 laserDirection = _aimDirection.Rotated(_recoilOffset);
```
The M16 laser follows the actual aim direction WITH recoil offset. Both the laser and the bullet use the same aim direction, and the weapon model directly follows the mouse cursor without interpolation lag. This means the M16 laser naturally matches both the barrel and the bullet.

## Correct Solution

**Unified all sniper shooting systems to use the visual barrel direction.** This ensures the laser, hitscan tracer, and blind-fire bullets all go in the same direction — the direction the barrel is actually pointing.

### Changes Made

1. **`get_visual_barrel_direction()`** — New function in `EnemySniperComponent` that always returns `_weapon_sprite.global_transform.x.normalized()`, the actual visual barrel direction.

2. **`_get_barrel_spawn_position()`** — New function that computes muzzle position from the visual barrel transform (unlike `_get_bullet_spawn_position()` which uses instant aim when player visible).

3. **Laser** (`update_laser_sight()`) — Now uses `get_visual_barrel_direction()` instead of `_get_weapon_forward_direction()`.

4. **Hitscan** (`shoot_sniper_hitscan()`) — Called from `_execute_shoot()` with the visual barrel direction and spawn position, so the tracer matches the laser.

5. **`_execute_shoot()` in enemy.gd** — For snipers specifically: computes barrel direction via `_sniper_component.get_visual_barrel_direction()`, checks barrel aim tolerance, and passes barrel direction to hitscan. Also adds a barrel-specific aim check so the sniper only fires when the barrel is actually pointed at the target.

6. **Blind fire** (`fire_at_predicted_position()`) — Removed model snap rotation and ±3° random spread. Now uses `get_visual_barrel_direction()` directly. The barrel is already smoothly rotating toward the predicted position via `_rotate_toward()`, providing natural inaccuracy.

### Why This Works

All three shooting paths now use the same direction source:
- **Laser**: `get_visual_barrel_direction()` → visual barrel
- **Hitscan**: barrel direction passed from `_execute_shoot()` → visual barrel
- **Blind fire**: `get_visual_barrel_direction()` → visual barrel

The visual barrel direction is the single source of truth. The laser shows it continuously, the hitscan tracer shows it when fired, and blind-fire bullets follow it too. The sniper is now slightly less accurate (no more instant aim bypassing model rotation), but the laser sight accurately shows where the shot will go — which is the whole point of having a laser sight.

### Collision Layer Reference

| Layer | Bit Value | Used For |
|-------|-----------|----------|
| 1 | 1 | Player character |
| 2 | 2 | Enemy characters |
| 3 | 4 | Walls/Obstacles |

Laser raycast mask: **5** (binary `101`) = Layer 1 (player) + Layer 3 (walls)

## Round 6: Laser Completely Invisible

### Problem
After the unification fix (commit a8f1dd54), the laser sight became completely invisible. No laser was visible at all during gameplay.

### Analysis
The laser `Line2D` nodes were created as children of `EnemySniperComponent`, which extends `Node` (NOT `Node2D`). In Godot 4.3, `CanvasItem` nodes (like `Line2D`) added as children of a plain `Node` may silently fail to render, even with `top_level = true`.

The rendering chain was: `Enemy (CharacterBody2D)` → `SniperComponent (Node)` → `Line2D (top_level=true)`. While the `Line2D` had a `CanvasItem` ancestor (the Enemy), the intermediate `Node` breaks the canvas item inheritance chain in some Godot versions.

The player's M16 laser (`AssaultRifle.cs`) avoids this by adding the `Line2D` directly to the weapon node (`AddChild(_laserSight)`), which is a `Node2D`.

### Fix
Re-parent laser nodes to `enemy` (the `CharacterBody2D`) instead of `self` (the `EnemySniperComponent` Node). This ensures the `Line2D` is a direct child of a `CanvasItem`, guaranteeing proper rendering.

Also added debug logging to `_create_laser_sight()` and `update_laser_sight()` to help diagnose future issues.

### Additional Fix: Accidental Removal of `bullet_damage_multiplier`
The unification commit accidentally removed the `@export var bullet_damage_multiplier` and its usage in `_spawn_projectile()`. This has been restored.

## Lessons Learned

1. **Visual model and shooting must use the same direction**: When a laser sight is present, it reveals any gap between the visual barrel and the actual aim direction. The only correct fix is to make all systems — laser, bullets, and visual model — agree on direction.

2. **Don't fight the visual model**: Using instant geometric aim while the model rotates smoothly creates a fundamental contradiction that no amount of laser logic can resolve. The solution is to make the bullets follow the barrel, not vice versa.

3. **Remove compensating complexity**: Blind fire had ±3° spread added on top of a snap rotation. By using the visual barrel direction (which already provides natural inaccuracy through smooth interpolation), the extra spread and snap become unnecessary.

4. **Study the reference implementation**: The player's M16 laser works because both the laser and bullets use the same aim direction with no model interpolation lag. The sniper fix achieves the same result by unifying the direction source.

5. **CanvasItem nodes need CanvasItem parents**: In Godot 4, `Line2D` (a `CanvasItem`) should be parented to another `CanvasItem` (like `Node2D`, `CharacterBody2D`) rather than a plain `Node`. While `top_level = true` handles transform independence, the rendering pipeline needs a proper canvas item chain for reliable rendering.

6. **Watch for unrelated regressions**: The unification commit accidentally removed `bullet_damage_multiplier` — an unrelated exported variable. Always diff against the base branch to check for accidental removals.
