# Case Study: Issue #1123 — Add Armored Skin Enemy to Double Corridor Map

## Issue Summary

**Title:** добавь врага с Бронированной кожей
**Request:** Add an enemy with the Armored Skin item (same effect as the player's) to the Double Corridor map (RevolverLevel).

## Relevant Codebase Components

### Existing Armored Skin (Player) — Issue #1045
- **`scripts/characters/player.gd`**: Contains `_armored_skin_active`, `_init_armored_skin()`, `_spawn_armored_skin_shards()`.
- **`scripts/projectiles/armored_skin_shard.gd`**: `ArmoredSkinShard` class — glass/crystal shard projectile.
- **`scenes/projectiles/ArmoredSkinShard.tscn`**: Scene for the shard.
- **Effect**: +1 max HP at spawn. When hit at ≤2 HP, spawns 20 glass shards in all directions (1 dmg each, no ricochet, no wall penetration, no self-damage).

### Enemy System
- **`scripts/objects/enemy.gd`**: Main enemy AI script (~4900+ lines). Export vars control behavior. Existing pattern for special items: `has_force_field` export + `EnemyForceFieldComponent` node.
- **`scripts/components/enemy_force_field_component.gd`**: Reference implementation for extracting enemy item logic into a reusable component.

### Double Corridor Map
- **`scenes/levels/RevolverLevel.tscn`**: The "Double Corridor" level. Contains `Environment/Enemies` node with named enemy instances.
- **`scripts/levels/revolver_level.gd`**: Level script — auto-detects all enemies in `Environment/Enemies`.

## Solution Design

Following the established pattern (`has_force_field` → `EnemyForceFieldComponent`):

1. **New export**: `has_armored_skin: bool = false` in `enemy.gd`.
2. **New component**: `EnemyArmoredSkinComponent` in `scripts/components/`.
   - `apply_hp_bonus(current, max)` → returns `[current+1, max+1]`.
   - `try_spawn_shards(current_health)` → spawns 20 shards if `current_health ≤ 2`.
   - Reuses existing `ArmoredSkinShard.tscn`.
3. **Wiring in `enemy.gd`**: Component initialized in `_ready()` after `_initialize_health()`; `try_spawn_shards()` called in `on_hit_with_bullet_info()`.
4. **New enemy in RevolverLevel.tscn**: `ArmoredSkinEnemy` at position (1700, 1050) near the existing `ForceFieldEnemy`, with `has_armored_skin = true`.

## Files Changed

| File | Change |
|------|--------|
| `scripts/components/enemy_armored_skin_component.gd` | **New** — component encapsulating armored skin logic |
| `scripts/objects/enemy.gd` | Added `has_armored_skin` export, component var, init in `_ready()`, shard trigger in `on_hit_with_bullet_info()` |
| `scenes/levels/RevolverLevel.tscn` | Added `ArmoredSkinEnemy` node |
| `tests/unit/test_enemy_armored_skin.gd` | **New** — unit tests |

## Design Decisions

- **Reuse shard scene**: The existing `ArmoredSkinShard.tscn` is reused unchanged. The `source_id` is set to the enemy's instance ID so shards don't hit the enemy itself.
- **Component pattern**: Keeps `enemy.gd` from growing further and is consistent with the codebase convention.
- **Enemy placement**: Positioned near `ForceFieldEnemy` at (1700, 1050) — in the final zone with other difficult enemies, providing a natural challenge escalation.
- **Effect parity**: Exactly mirrors the player's Armored Skin: +1 HP at spawn, 20 shards at ≤2 HP on hit.
