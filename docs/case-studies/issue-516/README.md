# Case Study: Issue #516 — Enemy Weapon Spread + Bullet Direction Bug

## Timeline

1. **Issue #516 reported**: Enemies have no weapon spread. UZI should have rapidly increasing spread (same as player).
2. **PR #517 created**: Added progressive weapon spread to enemies matching player's system.
3. **User feedback (round 1)**: "M16 bullets start flying exactly to the right (not in barrel direction)."
4. **First fix attempt**: Updated `_spawn_projectile()` to call `add_child()` first and use C# setter methods. However, **only `_shoot()` used `_spawn_projectile()`**.
5. **User feedback (round 2)**: "Enemy bullets still fly strictly to the right." — Game log `game_log_20260207_014250.txt` still showed `shooter_id=0` and `dir=(1, 0)`.
6. **Root cause found**: Two additional shooting functions (`_shoot_with_inaccuracy()` and `_shoot_burst_shot()`) bypassed `_spawn_projectile()` entirely, using direct bullet instantiation with the old broken pattern.

## Original Issue: No Enemy Weapon Spread

### Problem
Enemy single-bullet weapons (rifle, UZI) fired with **zero spread**, making them unrealistically accurate. The player's weapons all have progressive spread systems.

### Fix
Added progressive spread parameters to `weapon_config_component.gd` and spread calculation to `_shoot_single_bullet()` in `enemy.gd`. The spread mirrors the player's system:
- **Rifle**: threshold=3, initial=0.5°, increment=0.6°/shot, max=4.0°
- **UZI**: threshold=0, initial=6.0°, increment=5.4°/shot, max=60.0° after 10 shots
- **Shotgun**: no progressive spread (uses existing pellet spread system)

## Discovered Bug: Bullets Flying Right (Vector2.RIGHT)

### Evidence from Game Logs

**Log 1**: `game_log_20260206_212633.txt` (8738 lines) — Before first fix attempt
**Log 2**: `game_log_20260207_014250.txt` (3643 lines) — After first fix attempt (still broken)

Key observations from Log 2 (after the first fix):
- 64 bullets with `shooter_id=0` and `shooter_position=(0, 0)` — C# Bullet defaults, indicating property setting failed
- Player hit with `dir=(1, 0)` (Vector2.RIGHT) while enemies were in RETREATING state
- Enemies transitioning COMBAT → RETREATING right before buggy bullets appear
- Bullets at extreme X positions (~2460-2500) flying horizontally right

### Root Cause Analysis

The enemy has **three** separate shooting functions:

| Function | Called from | Used `_spawn_projectile()`? |
|---|---|---|
| `_shoot()` | COMBAT, IN_COVER, SUPPRESSED, PURSUING states | Yes (after first fix) |
| `_shoot_with_inaccuracy()` | RETREATING state (backing up to cover) | **No** — created bullets directly |
| `_shoot_burst_shot()` | ONE_HIT retreat burst, cover alarm bursts | **No** — created bullets directly |

The first fix only updated `_spawn_projectile()`, which is only called by `_shoot()`. The other two functions duplicated the bullet creation code with the old broken pattern:

```gdscript
# OLD pattern in _shoot_with_inaccuracy() and _shoot_burst_shot():
var bullet := bullet_scene.instantiate()
bullet.global_position = bullet_spawn_pos
bullet.direction = direction              # May fail silently for C# bullets
bullet.shooter_id = get_instance_id()     # May fail silently for C# bullets
bullet.shooter_position = bullet_spawn_pos # May fail silently for C# bullets
get_tree().current_scene.add_child(bullet) # add_child LAST (too late for C# interop)
```

Since enemies in RETREATING states use `_shoot_with_inaccuracy()` and `_shoot_burst_shot()`, their bullets always flew right.

The M16 RIFLE uses `res://scenes/projectiles/csharp/Bullet.tscn` (C# `Bullet.cs`), which defaults `Direction = Vector2.Right` and `ShooterId = 0`. When the GDScript-to-C# property assignment fails silently, bullets fly right with no shooter attribution.

### Fix Applied

1. **`_spawn_projectile()` (first fix, commit 73e4936)**:
   - Call `add_child(p)` first so C# `_Ready()` initializes the node
   - Use `SetDirection()`, `SetShooterId()`, `SetShooterPosition()` setter methods when available
   - Fall back to property assignment for GDScript bullets

2. **`_shoot_with_inaccuracy()` and `_shoot_burst_shot()` (second fix)**:
   - Replaced duplicated bullet creation code with calls to `_spawn_projectile()`
   - All bullet spawning now goes through a single code path with correct C# interop

### Why the First Fix Was Incomplete

The `_spawn_projectile()` function was correctly fixed, but only `_shoot()` called it. The game log evidence pointed to the real problem: enemies in RETREATING state (lines 340-347 of Log 2 show Enemy4 transitioning COMBAT → RETREATING right before a `dir=(1, 0)` bullet hit). The RETREATING state uses `_shoot_with_inaccuracy()`, which bypassed the fix entirely.

## Files Changed

- `scripts/objects/enemy.gd` — Progressive spread + `_spawn_projectile` interop fix + unified bullet spawning
- `scripts/components/weapon_config_component.gd` — Spread parameters per weapon type
- `tests/unit/test_enemy.gd` — 8 regression tests for spread system

## Key Lessons

1. **Single code path for bullet creation**: All shooting functions should use `_spawn_projectile()` to ensure consistent behavior. Code duplication across multiple shooting functions led to this bug.
2. **Cross-language interop**: When calling C# methods/properties from GDScript, prefer dedicated setter methods over direct property assignment.
3. **Node lifecycle**: Setting properties on C# nodes after `add_child()` ensures `_Ready()` has run and the node is fully initialized.
4. **Default values matter**: C# Bullet defaults `Direction = Vector2.Right` and `ShooterId = 0`. If property setting fails silently, bullets fly right with no shooter attribution.
5. **Test all enemy states**: The bug only manifested in RETREATING/ONE_HIT states, not in COMBAT. Testing must cover all AI states that involve shooting.
