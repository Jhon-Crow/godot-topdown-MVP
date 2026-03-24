# Case Study: Issue #1125 — Add Sniper Enemy to Docks Map

## Issue Summary

**Title:** добавь врага с снайперской винтовкой (Add enemy with sniper rifle)

**Description:** Replace one enemy in the top-right part of the Docks map with a sniper enemy. This enemy should use the same rifle as the player (ASVK) with tracer effect and wall penetration.

## Codebase Analysis

### Project: Godot Top-Down MVP

A top-down shooter built in Godot 4 with GDScript and C#. The project features:
- Multiple enemy types with configurable `WeaponType` enum
- Player-wielded ASVK sniper rifle with bolt-action mechanics, tracer effects, and wall penetration
- Separate `WeaponConfigComponent` that maps weapon type enums to game parameters

### Existing Enemy System

**`scripts/objects/enemy.gd`**
- `WeaponType` enum: `{ RIFLE=0, SHOTGUN=1, UZI=2, MACHETE=3, MACHINE_GUN=4 }`
- `weapon_type` export property drives `_configure_weapon_type()` which loads from `WeaponConfigComponent`
- Enemy shoots via `_shoot()` → `_execute_shoot()` → `_shoot_single_bullet()` → `_spawn_projectile()`
- `_spawn_projectile()` supports C# bullet types: sets `Direction`, `ShooterId`, `ShooterPosition` properties

**`scripts/components/weapon_config_component.gd`**
- Static dictionary mapping int weapon type → config dict
- Config keys: `shoot_cooldown`, `bullet_speed`, `magazine_size`, `bullet_spawn_offset`, `weapon_loudness`, `sprite_path`, `bullet_scene_path`, `casing_scene_path`, `caliber_path`, `is_shotgun`, spread params
- Additional keys for special types: `is_melee`, `total_magazines`, `reload_time`

### Existing Sniper Rifle (Player)

**`Scripts/Weapons/SniperRifle.cs`**
- Bolt-action mechanic (Left→Down→Up→Right arrow keys)
- Fires `SniperBullet` (C# class)
- Creates smoky tracer Line2D programmatically on each shot
- 12.7x108mm ammunition, 50 damage per shot

**`scenes/projectiles/csharp/SniperBullet.tscn`**
- `Speed = 10000.0` (near-instant)
- `Lifetime = 3.0s`
- `Damage = 50.0`
- `TrailLength = 0` (no trail in current scene)
- `MaxWallPenetrations = 2` (penetrates up to 2 walls)
- `collision_mask = 39` (hits walls, enemies, player)

**`Scripts/Projectiles/SniperBullet.cs`**
- Passes through enemies (applies damage via HitArea, continues flying)
- Penetrates walls (up to `MaxWallPenetrations`)
- Supports tracer via child `Trail` Line2D node (loaded via `GetNodeOrNull<Line2D>("Trail")`)
- Sets `Rotation` from `Direction` on `_Ready()`

### Docks Map Layout

**`scenes/levels/DocksLevel.tscn`**
- Map bounds: 64 to 5064 (x), 64 to 4064 (y)
- Areas: CranePlatform (top-left ~400,500), ContainerYardA (top-right ~3750-4500, 350-500), LoadingDock (right-center), ContainerYardB (left-bottom), WarehouseA/B
- Top-right enemies (ContainerYardA):
  - `ContainerYardA_Rifle1` at (3750, 350), weapon_type=0 (RIFLE), patrol
  - `ContainerYardA_Rifle2` at (4100, 500), weapon_type=0 (RIFLE), guard
  - `ContainerYardA_Shotgun` at (4500, 420), weapon_type=1 (SHOTGUN), guard

## Solution Design

### Approach

1. **Add `SNIPER_RIFLE = 5` to `WeaponType` enum** in `enemy.gd`
2. **Add sniper config entry (key `5`)** to `weapon_config_component.gd`:
   - Uses `scenes/projectiles/csharp/SniperBullet.tscn` as bullet scene
   - Slow fire rate (bolt-action simulation: `shoot_cooldown = 3.0`)
   - High bullet speed (10000), 5-round magazine
   - Sprite: `asvk_topdown.png`
   - ASVK tracer: requires a `SniperBulletEnemy.tscn` scene with Trail node
3. **Create `SniperBulletEnemy.tscn`** — copy of SniperBullet.tscn with a Trail Line2D child and `TrailLength = 15` for visible tracer
4. **Replace `ContainerYardA_Shotgun`** (rightmost top-right enemy at 4500, 420) with sniper enemy (weapon_type=5)
5. **Add sound handling** in `_execute_shoot()` for `SNIPER_RIFLE` weapon type

### Why This Approach

- Minimally invasive: adds a new enum value without touching existing types
- Reuses existing SniperBullet C# class (penetration + enemy pass-through built-in)
- The enemy's `_spawn_projectile()` already handles C# bullet interop
- Slow cooldown (3.0s) simulates bolt-action behavior at enemy difficulty level
- Top-right enemy (4500, 420) is furthest right and highest — perfect "sniper perch" position

### Alternative Approaches Considered

1. **Reuse SniperBullet.tscn without Trail** — simpler but no visible tracer
2. **Modify existing enemy scenes** — more complex, not needed
3. **Create a separate SniperEnemy scene** — overkill, weapon_type config is sufficient

## Implementation Plan

1. Add `SNIPER_RIFLE = 5` to enum in `scripts/objects/enemy.gd`
2. Add config for key `5` in `scripts/components/weapon_config_component.gd`
3. Create `scenes/projectiles/csharp/SniperBulletEnemy.tscn` with Trail node
4. Update audio in `scripts/objects/enemy.gd` `_execute_shoot()` for sniper sound
5. Update `get_type_name()` in `weapon_config_component.gd`
6. Replace `ContainerYardA_Shotgun` with sniper enemy in `DocksLevel.tscn`
7. Update enemy count label from 20 to reflect new enemy
