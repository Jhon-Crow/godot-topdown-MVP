# Case Study: Issue #1129 — Enemy Chemical Grenade with Illusion Copies

## Problem Statement

Add a new chemical grenade for enemies with the following behavior:
1. With 50% chance, an enemy throws a chemical grenade instead of the default grenade.
2. The grenade looks and emits gas like the player's gas grenade, but gas is caustic yellow.
3. Effect: all enemies create illusory copies (1–4 per enemy), lasting 20 seconds.
4. Illusory copies look and act like normal enemies but are one-shot by any weapon/shrapnel.
5. All weapons of illusory copies deal 5% of normal damage.
6. Illusory copies do not stop bullets/shrapnel (projectiles pass through, no damage loss).
7. All illusory copies of an enemy disappear if the original enemy is killed.
8. When grenade effect expires, all illusory copies disappear.
9. If the player is already under the effect of such a grenade, all enemies throw default grenades.

## Codebase Analysis

### Existing Grenade Architecture

The project has a well-structured grenade system:

- **`GrenadeBase`** (`scripts/projectiles/grenade_base.gd`): Abstract base for all grenades.
  - Timer-based or impact-based detonation.
  - `_explode()` / `_on_explode()` override hooks for subclasses.
  - Physics-based throwing with multiple throw methods.
- **`AggressionGasGrenade`** (`scripts/projectiles/aggression_gas_grenade.gd`): Player's gas grenade.
  - Spawns `AggressionCloud` on explosion.
  - Uses reddish blink effect, hiss sound, no shrapnel.
- **`AggressionCloud`** (`scripts/effects/aggression_cloud.gd`): Cloud area effect.
  - `Area2D` with `CircleShape2D` for collision detection.
  - `GPUParticles2D` visual (fallback `Sprite2D`).
  - Applies status effect via `StatusEffectsManager.apply_aggression()`.

### Existing Status Effects System

- **`StatusEffectsManager`** (`scripts/autoload/status_effects_manager.gd`): Autoload singleton.
  - Manages `blindness`, `stun`, `aggression` effects per entity (by instance ID).
  - Provides `apply_X()`, `is_X()`, `get_X_remaining()`, `clear_effects()` methods.
  - Tint-based visual feedback.

### Enemy Grenade Component

- **`EnemyGrenadeComponent`** (`scripts/components/enemy_grenade_component.gd`):
  - Manages grenade throwing logic (7 triggers, cooldown, distance checks).
  - `_execute_throw()` instantiates the `grenade_scene` and calls `throw_grenade()`.
  - Currently uses a single `grenade_scene` (set via `enemy.gd` export).

### Enemy System

- **`enemy.gd`** (`scripts/objects/enemy.gd`, ~5000 lines):
  - `_setup_grenade_component()` creates `EnemyGrenadeComponent` with exported config.
  - `grenade_scene` export determines what grenade is thrown.
  - `_on_death()` triggers cleanup.
  - Enemies are in `"enemies"` group.

## Design Decisions

### 1. Chemical Grenade: New Subclass of GrenadeBase

Following the `AggressionGasGrenade` pattern, we create `ChemicalGasGrenade` that:
- Visually mirrors `AggressionGasGrenade` (same shape/size) but with yellow gas.
- Spawns a `ChemicalCloud` effect on explosion.

### 2. Chemical Cloud: New Node2D Effect

Following `AggressionCloud` pattern:
- Yellow/caustic particle color instead of reddish.
- On explosion, applies `illusion` status effect to all enemies in radius via `StatusEffectsManager`.
- Spawns 1–4 illusory copies per enemy (via `IllusionEnemy`).
- Tracks effect expiry and clears all illusions when expired.
- Checks if player is already under illusion effect → if yes, cloud has no effect.

### 3. IllusionEnemy: Lightweight Enemy Wrapper

- Instanced from `Enemy.tscn` but configured as illusion:
  - `_health = 1` (one-shot by any weapon).
  - All damage dealt by weapons = 5% of normal.
  - Bullets and shrapnel pass through (no collision on physics layer or handled via metadata).
  - Added to `"enemies"` group so existing AI still sees them.
  - Linked to `_original_enemy` — if original dies, illusions disappear.
- Implementation: new script `illusion_enemy.gd` that wraps a spawned enemy node.

### 4. EnemyGrenadeComponent: 50% Chemical Chance

- Add `chemical_grenade_scene: PackedScene` and `chemical_grenade_chance: float = 0.5` exports.
- In `_execute_throw()`, if `chemical_grenade_chance` roll succeeds AND player is not under illusion effect → use `chemical_grenade_scene` instead of `grenade_scene`.
- Checking "player is under illusion effect" requires a global flag in `StatusEffectsManager` or a new `IllusionEffectManager` autoload.

### 5. Illusion Effect Tracking in StatusEffectsManager

- Add `apply_illusion(player, duration)` and `is_under_illusion(player)` methods.
- The player node (obtained via group `"player"`) is the tracked entity.

## Potential Issues and Mitigations

| Issue | Mitigation |
|-------|-----------|
| Illusion enemies are indistinguishable from real enemies | By design (that's the gameplay effect) |
| Performance: too many illusion enemies | Cap at 4 copies per enemy; clean up on death |
| Bullet passthrough implementation | Use `collision_layer = 0` or metadata flag checked by bullet/shrapnel |
| Illusion copies shooting back | They should shoot with 5% damage — reuse existing weapon system |
| Original enemy death detecting | Connect `died` signal from original to cleanup illusions |

## Implementation Plan

1. `scripts/projectiles/chemical_gas_grenade.gd` — new `ChemicalGasGrenade` class
2. `scenes/projectiles/ChemicalGasGrenade.tscn` — scene with yellow sprite
3. `scripts/effects/chemical_cloud.gd` — new `ChemicalCloud` class
4. `scenes/effects/ChemicalCloudEffect.tscn` — scene
5. `scripts/characters/illusion_enemy.gd` — `IllusionEnemy` wrapper
6. `scenes/characters/IllusionEnemy.tscn` — scene referencing Enemy.tscn structure
7. `scripts/autoload/status_effects_manager.gd` — add illusion effect tracking
8. `scripts/components/enemy_grenade_component.gd` — add chemical grenade logic
9. `tests/unit/test_chemical_grenade.gd` — unit tests
10. `tests/unit/test_illusion_enemy.gd` — unit tests

## References

- AggressionGasGrenade pattern: `scripts/projectiles/aggression_gas_grenade.gd`
- AggressionCloud pattern: `scripts/effects/aggression_cloud.gd`
- Enemy death: `scripts/objects/enemy.gd:_on_death()`
- Grenade component: `scripts/components/enemy_grenade_component.gd`
- Status effects: `scripts/autoload/status_effects_manager.gd`
