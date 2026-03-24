# Case Study: Issue #1133 — Shoot Down RPG Rocket

## Problem Statement

Issue #1133 requests the ability to **shoot down an RPG rocket** by dealing any damage to it
(with a bullet, grenade fragment, or explosion). The RPG rocket was implemented in Issue #583.

## Analysis

### Existing Implementation (Issue #583)

The RPG rocket is implemented as an `Area2D` node using `bullet.gd` with `is_rpg_rocket = true`.
The scene is `res://scenes/projectiles/RpgRocket.tscn`.

Key properties of the rocket:
- `collision_layer = 16` (layer 5: projectiles)
- `collision_mask = 39` (layers 1+2+4+32: player, enemies, obstacles, targets)
- No health — it explodes on any solid contact (walls, enemies, player)
- No `on_hit` method — cannot receive incoming damage

### Root Cause of Missing Feature

The rocket was missing two things:

1. **No health system**: The rocket had no HP variable, so it couldn't take damage before exploding.
2. **Collision mask excludes projectiles**: `collision_mask = 39` does not include layer 5 (projectiles, value 16), so bullets (on layer 16) pass through the rocket's `Area2D` without triggering any interaction.

### How Bullet-to-Bullet Collision Works in Godot

In Godot 4, `Area2D.area_entered` fires when one Area2D overlaps another, **provided**:
- Both areas have overlapping `collision_layer` / `collision_mask` bits.
- Specifically: Area A's `collision_layer` must match Area B's `collision_mask`, AND vice versa.

Bullets are on `collision_layer = 16` (layer 5).
The rocket's `collision_mask = 39` did not include 16, so the bullet's `area_entered` signal never
fired when crossing the rocket.

### Fix

1. **Add `rpg_health` export variable** to `bullet.gd` (default 1 HP — one hit to shoot down).
2. **Add `on_hit` / `on_hit_with_info` / `on_hit_with_bullet_info_and_damage` methods** so the rocket
   can receive incoming damage from bullets, shrapnel, and explosions.
3. **Update `RpgRocket.tscn` collision_mask** from `39` to `55` (adds layer 5 = projectiles = 16)
   so that bullets' `area_entered` fires when overlapping the rocket.
4. **Set `rpg_health = 1`** in `RpgRocket.tscn` — one hit destroys the rocket (no explosion).

### Collision Layer Reference

| Layer | Name       | Bit value |
|-------|------------|-----------|
| 1     | player     | 1         |
| 2     | enemies    | 2         |
| 3     | obstacles  | 4         |
| 4     | pickups    | 8         |
| 5     | projectiles| 16        |
| 6     | targets    | 32        |

Old rocket mask: `39` = 1+2+4+32 = player + enemies + obstacles + targets
New rocket mask: `55` = 1+2+4+16+32 = player + enemies + obstacles + projectiles + targets

## Solution

See changes in `scripts/projectiles/bullet.gd` and `scenes/projectiles/RpgRocket.tscn`.

### Behavior After Fix

- Any bullet, shrapnel, or explosion `on_hit` call reaching the rocket reduces its health.
- When health reaches 0, the rocket is **destroyed without exploding** (no AOE damage).
- A small visual flash indicates the intercept.
- Log message: `[RpgRocket] Intercepted at pos=... remaining_health=0`

## References

- Issue #583: RPG enemy implementation (original rocket system)
- `scripts/projectiles/bullet.gd` — main projectile script (handles both bullets and RPG rockets)
- `scenes/projectiles/RpgRocket.tscn` — RPG rocket scene
- Godot 4 docs: [Area2D collision detection](https://docs.godotengine.org/en/stable/classes/class_area2d.html)
