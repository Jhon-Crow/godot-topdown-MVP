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

## Bug Report: Illusion Copies Not Appearing (2026-03-18)

### Symptom
Player-reported: grenade deploys but illusion copies do not appear for most enemies.
Log file: `game_log_20260318_042237.txt`

### Log Evidence
```
[04:23:33] [ChemicalCloud] Spawning 2 illusion copies for enemy at (1610.048, 245.8553)
[04:23:33] [IllusionEnemy] Illusion created at (1648.977, 241.6154) (duration=20s)
[04:23:33] [ChemicalCloud] Illusion copy 2 spawned
[04:23:34] [ChemicalCloud] Player already under illusion effect — cloud has no effect
[04:23:34] [ChemicalCloud] Player already under illusion effect — cloud has no effect
... (repeats for entire 20-second cloud lifetime)
```

### Root Cause
In `status_effects_manager.gd`, `apply_illusion_to_enemy()` sets `_player_illusion_timer = duration`
(line 150) **as a side effect** of marking the first enemy under illusion. This immediately causes
`is_player_under_illusion()` to return `true`.

`chemical_cloud.gd` called `_is_player_under_illusion_effect()` at the top of
`_apply_effect_to_enemies_in_cloud()`. On the very next periodic tick (0.5 s after initial spawn),
and for all subsequent cloud ticks, the guard fired and blocked all illusion spawning.

Timeline:
1. Cloud spawns, initial `_apply_effect_to_enemies_in_cloud()` fires
2. First enemy in cloud: `apply_illusion_to_enemy()` → `_player_illusion_timer = 20` ← BUG
3. 0.5s later: periodic tick → guard `is_player_under_illusion() == true` → returns early
4. All remaining enemies (and enemies that walk into cloud later) never get copies

### Fix
Requirement 9 ("если игрок уже под эффектом — враги кидают дефолтные гранаты") means:
**prevent enemies from throwing a new chemical grenade** while the effect is active.
It does NOT mean a deployed cloud should stop spawning copies.

Fix: remove the `is_player_under_illusion()` guard from `ChemicalCloud._apply_effect_to_enemies_in_cloud()`.
The guard remains only in `EnemyGrenadeComponent._choose_grenade_scene()`.

Files changed:
- `scripts/effects/chemical_cloud.gd` — removed `_is_player_under_illusion_effect()` helper and its call from `_apply_effect_to_enemies_in_cloud()`

---

## Bug Report #2: Illusion Copies Still Not Appearing (2026-03-18)

### Symptom

After fixing Bug #1, the player reported that illusion copies still do not appear visually in game.
Log files: `game_log_20260318_045415.txt`, `game_log_20260318_050002.txt`

### Log Evidence

From `game_log_20260318_045415.txt`:
```
[04:55:26] [ChemicalCloud] Spawning 4 illusion copies for enemy at (1278.724, 532.7821)
[04:55:26] [IllusionEnemy] Enemy copy spawned, health=1, damage=5% of normal
[04:55:26] [IllusionEnemy] Illusion created at (1343.949, 520.9557) (duration=20s)
[04:55:26] [ENEMY] [Enemy] Spawned at (2687.898, 1041.911), hp: 1, behavior: GUARD
[04:55:26] [ENEMY] [Enemy] Spawned at (2548.667, 1203.949), hp: 1, behavior: GUARD
[04:55:26] [ENEMY] [Enemy] Spawned at (2485.896, 1080.894), hp: 1, behavior: GUARD
[04:55:26] [ENEMY] [Enemy] Spawned at (2578.493, 984.053), hp: 1, behavior: GUARD
```

Key observations:
- `IllusionEnemy` log says "Illusion created at (1343.949, 520.9557)" — near the original enemy ✓
- BUT inner Enemy nodes log "Spawned at (2687.898, 1041.911)" etc. — **over 1300 pixels away**
- The illusion copies ARE being instantiated (code runs), but they appear at the wrong location

From `game_log_20260318_050002.txt`:
```
[05:06:23] [ChemicalCloud] _ready() called at (1706.905, 979.3198)
[05:06:26] [ChemicalCloud] Spawning 1 illusion copies for enemy at (1682.03, 1264.508)
[05:06:26] [IllusionEnemy] Enemy copy spawned, health=1, damage=5% of normal
[05:06:26] [IllusionEnemy] Illusion created at (1737.631, 1273.438) (duration=20s)
[05:06:26] [ENEMY] [Enemy] Spawned at (3475.262, 2546.875), hp: 1, behavior: GUARD
```

The inner enemy node spawned at `(3475.262, 2546.875)` — approximately 2× the intended position.

### Root Cause Analysis

**Godot scene tree position semantics: `global_position` before `add_child` does not work.**

In `illusion_enemy.gd:_spawn_enemy_copy()`, the original code was:

```gdscript
_enemy_node.global_position = original_enemy.global_position + spawn_offset  # line 93
global_position = _enemy_node.global_position                                  # line 94
# ... more configuration ...
add_child(_enemy_node)                                                          # line 119
```

**Problem**: In Godot 4, `global_position` only works when a node is **in the scene tree**. Setting `_enemy_node.global_position` before `add_child` is equivalent to setting `_enemy_node.position` (local position) because the node has no parent yet and cannot compute a world transform.

When `add_child(_enemy_node)` is called:
1. `_enemy_node` enters the scene tree as a child of `IllusionEnemy`.
2. `Enemy._ready()` fires immediately.
3. `Enemy._ready()` calls `_initial_position = global_position` (line 397 of `enemy.gd`).
4. At this point, `IllusionEnemy.global_position` has NOT been updated yet (it still defaults to `(0,0)` or whatever position was set on the `IllusionEnemy` node by `ChemicalCloud` before entering the scene tree).
5. So `_enemy_node.global_position = IllusionEnemy.global_position + _enemy_node.position`. Since `_enemy_node.position` was set to the target position pre-tree (via `global_position = target` pre-tree), the actual world position becomes `IllusionEnemy_world_pos + target_local_pos`, which is **double-offset**.

### Timeline of Events (Pre-Fix)

1. `ChemicalCloud._spawn_illusion_copies()` runs.
2. `illusion = IllusionEnemy.new()` — creates node, not yet in scene.
3. `illusion.spawn_offset = spread_vector` — sets a local field.
4. `illusion.original_enemy = enemy` — sets reference.
5. `get_tree().current_scene.add_child(illusion)` — adds IllusionEnemy to scene. `IllusionEnemy._ready()` fires:
   - `_spawn_enemy_copy()` called.
   - `_enemy_node.global_position = original_enemy.global_position + spawn_offset` — **sets local `position`** because `_enemy_node` is not in scene tree yet! `global_position` maps to `position` pre-tree.
   - `global_position = _enemy_node.global_position` — reads back what was set as position (wrong).
   - `add_child(_enemy_node)` — Enemy's `_ready()` fires, captures wrong `_initial_position`.
   - Enemy logs "Spawned at (wrong_position)".

### Why Copies Appeared to "Not Appear" to the Player

The copies DO spawn — but at a wrong location far from the original enemy (double-offset, typically 1000–2500 pixels away). From the player's perspective standing near the original enemy, the copies are completely invisible (off-screen). This explains the "illusion copies not appearing" report.

### Fix

Move position assignment to **after** `IllusionEnemy` enters the scene tree (from `ChemicalCloud`), which happens **before** `_ready()` is called, but since `IllusionEnemy` is added via `get_tree().current_scene.add_child(illusion)` first, `IllusionEnemy` IS in the tree when `_ready()` runs. Therefore, setting `self.global_position` inside `_spawn_enemy_copy()` (before `add_child(_enemy_node)`) works correctly.

```gdscript
# BEFORE add_child: IllusionEnemy is already in scene tree (added by ChemicalCloud)
# so global_position assignment works correctly here.
var target_pos := original_enemy.global_position + spawn_offset
global_position = target_pos   # sets IllusionEnemy world position correctly

add_child(_enemy_node)
# _enemy_node.position = (0,0) relative to IllusionEnemy
# → _enemy_node.global_position = target_pos when Enemy._ready() fires
# → _initial_position = target_pos ✓
```

Key principle: **In Godot 4, `global_position` on a node only works after it enters the scene tree.** Setting `global_position` before `add_child` silently falls back to setting `position` (local coordinates with no parent = same as world, but only if no parent transform exists).

Files changed:
- `scripts/characters/illusion_enemy.gd` — moved `global_position = target_pos` assignment to before `add_child(_enemy_node)`, removed redundant pre-tree `global_position` assignment

### Additional Findings from Logs

- Bug #1 fix (commit `cfb3c1c8`) was correct: the first log (`045415`) shows multiple enemies now getting copies (4 for one enemy, 1+2 for others), confirming no more early-exit from `is_player_under_illusion()`.
- The second bug (wrong positions) was pre-existing alongside bug #1 but only became apparent after bug #1 was fixed — previously most copies were silently blocked, so the position issue never had a chance to be noticed.
- Enemy copies with `hp: 1` correctly log after spawn, confirming `min_health = 1` / `max_health = 1` assignment works.
- When original enemy dies, `IllusionEnemy._on_original_died()` fires and `_cleanup()` removes copies — confirmed working in both logs.

---

## References

- AggressionGasGrenade pattern: `scripts/projectiles/aggression_gas_grenade.gd`
- AggressionCloud pattern: `scripts/effects/aggression_cloud.gd`
- Enemy death: `scripts/objects/enemy.gd:_on_death()`
- Grenade component: `scripts/components/enemy_grenade_component.gd`
- Status effects: `scripts/autoload/status_effects_manager.gd`
- Godot 4 docs — Node2D.global_position: https://docs.godotengine.org/en/stable/classes/class_node2d.html#class-node2d-property-global-position
  - "The global position of this node. Unlike position, this reflects the actual position in the world, taking parents' transforms into account."
  - Implication: before entering scene tree, no parent transform → `global_position` behaves as `position`.
