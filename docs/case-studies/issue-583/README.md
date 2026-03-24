# Case Study: Issue #583 - Add RPG Enemy Type

## Problem Statement
Add a new enemy type armed with an RPG (rocket launcher). The enemy starts with one RPG shot, fires at the player's position, then switches to a PM (Makarov pistol) and behaves as a normal enemy. Health = 1-2 (unarmored).

## Architecture Analysis

### Current Weapon System
- `WeaponType` enum: RIFLE(0), SHOTGUN(1), UZI(2), MACHETE(3)
- Weapon config is static per enemy, set once at spawn via `_configure_weapon_type()`
- No runtime weapon switching exists in the current codebase

### Key Challenge: Runtime Weapon Switching
The current architecture assigns a weapon type at spawn and never changes it. The RPG enemy requires:
1. Start with RPG weapon → fire one rocket
2. Switch to PM (pistol) → continue as normal enemy

### Design Decision: RPG as a Special Weapon with Auto-Switch
Rather than adding a full weapon switching system (which would be overengineered), we treat the RPG as a weapon type that has a built-in "first shot is RPG, then switch to pistol" behavior.

## Solution Design

### New Components
1. **RPG WeaponType (4)** - New enum value in `WeaponType`
2. **RPG weapon config** - Entry in `WeaponConfigComponent.WEAPON_CONFIGS[4]`
3. **RpgRocket projectile** - New projectile script extending Area2D (like bullet.gd), with explosion on impact
4. **Weapon switching in enemy.gd** - After RPG shot, reconfigure to PM pistol config
5. **RPG-specific weapon config** - Uses 9x18 caliber for post-switch PM behavior

### Projectile Behavior (RPG Rocket)
- Travels slower than bullets (800 px/s) but explodes on impact
- Uses FragGrenade-like explosion logic (damage in radius)
- Effect radius: 150px (smaller than frag grenade's 225px)
- Explosion damage: 3 (enough to kill most enemies, significant to player)
- No ricochet - explodes on any contact

### Enemy Behavior
- Starts in RPG mode: `_rpg_ammo = 1`, `_is_rpg_weapon = true`
- On first shot: fires rocket projectile at player position
- After rocket fired: calls `_switch_to_pistol()` which reconfigures to PM config
- Post-switch: behaves exactly like a normal pistol enemy
- Health: min_health=1, max_health=2 (unarmored, easy to kill)

### Files Modified
| File | Change |
|------|--------|
| `scripts/objects/enemy.gd` | Add RPG enum, weapon switching logic |
| `scripts/components/weapon_config_component.gd` | Add RPG + PM weapon configs |
| `scripts/projectiles/rpg_rocket.gd` | New rocket projectile script |
| `scenes/projectiles/RpgRocket.tscn` | New rocket scene |
| `scenes/levels/CastleLevel.tscn` | Add RPG enemies to level |
| `tests/unit/test_weapon_config_component.gd` | Tests for RPG config |

## Debug Sessions Summary

| Log | Key Finding | Fix Applied |
|-----|-------------|-------------|
| game_log_20260317_074901 | `as RpgRocket` cast returns null in export | Use `has_method`/`call` |
| game_log_20260317_081404 | `load()` returns null → `bullet_scene` stays Bullet | Use `preload()` directly |
| game_log_20260317_090725 | `has_method("launch")` false before `add_child()` | Move check to after `add_child()` |
| game_log_20260317_094557 | `has_method("launch")` still false after `add_child()` — rocket spawns but doesn't fly | Use `call_deferred("launch", dir)` — eliminates `has_method` entirely |
| game_log_20260318_011519 | `[RpgRocket] Spawned:` never appears — `_ready()` in `rpg_rocket.gd` never called in export | Switch to `bullet.gd` — same script as all other working projectiles |
| game_log_20260318_032745 | Rocket flies but no explosion — `[RpgRocket]` entries absent from log entirely | Add `@export` to `is_rpg_rocket` and all RPG vars in `bullet.gd` — plain `var` cannot be set from `.tscn` |

## Root Cause of Session 17 (game_log_20260318_032745)

Despite switching to `bullet.gd`, the explosion still didn't fire. The root cause:

```gdscript
# bullet.gd — BEFORE fix (broken):
var is_rpg_rocket: bool = false   # NOT @export

# RpgRocket.tscn:
is_rpg_rocket = true              # Silently IGNORED — can't set non-@export vars from scene file
```

In Godot 4, `.tscn` scene file property assignments only work for `@export` variables. Regular `var` declarations are instance-local and cannot be set via scene serialization. Without `@export`, `is_rpg_rocket` stays `false` at runtime, so all RPG explosion logic is bypassed.

**Fix**: Add `@export` to `is_rpg_rocket` and all related RPG parameters in `bullet.gd`.

## References
- Similar pattern: MACHETE weapon (Issue #579) - weapon type with special behavior
- Explosion mechanic: FragGrenade (frag_grenade.gd) - impact explosion
- Enemy grenade system: EnemyGrenadeComponent - projectile spawning by enemies
- Godot docs: `Object.call_deferred()` — schedules method call via MessageQueue, runs after scene-tree is fully settled
