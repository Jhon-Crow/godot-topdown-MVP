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

## Bug Report #3: Illusion Copies Still Not Appearing — Area2D Overlap Detection (2026-03-18)

### Symptom

After fixing Bug #1 and Bug #2, the player reports illusion copies still do not appear.
Log file: `game_log_20260318_062925.txt`

### Log Evidence

```
[06:38:30] [ChemicalCloud] _ready() called at (2078.525, 1361.246)
[06:38:30] [ChemicalCloud] Particle system created successfully
[06:38:30] [ChemicalCloud] Cloud spawned at (2078.525, 1361.246), radius=300, duration=20s, particles=true
...
[06:38:47] [ChemicalCloud] Stopped particle emission, cloud dissipating
[06:38:53] [ChemicalCloud] Cloud dissipated at (2078.525, 1361.246)
```

**There are zero log lines showing any illusion spawning.** The cloud ran its full 20-second duration without detecting any enemies. `_apply_effect_to_enemies_in_cloud()` called `_detection_area.get_overlapping_bodies()` on every 0.5s tick but always received an empty array.

### Root Cause Analysis

**`Area2D.get_overlapping_bodies()` does not reliably detect bodies that were already present when the Area2D was added to the scene tree.**

In Godot 4, `Area2D` overlap detection works via physics contact pairs. When the `ChemicalCloud` is spawned (via `get_tree().current_scene.add_child(cloud)` in `chemical_gas_grenade.gd`), the `Area2D` is created dynamically in `_setup_detection_area()`. Bodies that are already inside the radius at the time of spawn are NOT retroactively reported as overlapping — Godot's physics engine only creates contact pairs for bodies that enter the area after the area's physics shape is registered.

Additionally, the `body_entered` signal was not connected in the original implementation.

Contributing factors:
1. **No `body_entered` signal**: Bodies entering the cloud after spawn were only detected via `get_overlapping_bodies()` in the 0.5s periodic tick, which is unreliable.
2. **`get_overlapping_bodies()` unreliable for pre-existing bodies**: Bodies already in the radius when cloud spawned would not be detected.
3. **Enemies evaded the landing zone**: In this specific log session, Enemy8 and Enemy9 were actively fleeing from the grenade (EVADING_GRENADE state) and left the radius before the cloud activated. This confirmed the need for `body_entered` signal for enemies who enter later.
4. **No logged evidence of failed detection**: Before the fix, `_apply_effect_to_enemies_in_cloud()` had no logging of how many bodies were found, making the problem invisible in logs.

### Fix

Replace `Area2D.get_overlapping_bodies()` with `PhysicsDirectSpaceState2D.intersect_shape()` (physics shape query):

```gdscript
func _apply_effect_to_enemies_in_cloud() -> void:
    var space_state := get_world_2d().direct_space_state
    var shape := CircleShape2D.new()
    shape.radius = cloud_radius

    var query := PhysicsShapeQueryParameters2D.new()
    query.shape = shape
    query.transform = Transform2D(0.0, global_position)
    query.collision_mask = 2  # Enemies (layer 2)
    query.collide_with_bodies = true
    query.collide_with_areas = false

    var results := space_state.intersect_shape(query, 32)
    # results always accurate, regardless of when enemies entered the area
```

Additionally:
- Connected `body_entered` signal for immediate detection when enemies walk into the cloud.
- Added a 3-frame startup delay (`_frames_until_first_tick`) so physics can settle before first scan.
- Added detailed logging: every tick logs how many bodies were found.

**Why `intersect_shape()` is more reliable**: Unlike `Area2D.get_overlapping_bodies()`, which depends on the physics engine's contact pair tracking (only updated when bodies enter/exit), `intersect_shape()` performs a one-shot physics query at the current frame. It correctly finds all bodies within the shape radius regardless of when they arrived there.

Files changed:
- `scripts/effects/chemical_cloud.gd` — replaced `get_overlapping_bodies()` with `intersect_shape()`, added `body_entered` signal, added detection logging, added frame delay for physics settle

---

---

## Bug Report #4: Chemical Grenade Still Not Working + New Requirements (2026-03-21)

### Symptom

Player reported two issues after the 4th round of fixes:
1. Illusion copies still appear to not work (or die immediately after spawning).
2. New requirement: regular enemies should NOT throw chemical grenades — only a new dedicated "gas mask enemy" should.

Log file: `game_log_20260321_005517.txt`

### Log Evidence

The log confirms the chemical cloud DOES work correctly:
```
[00:56:09] [ChemicalGasGrenade] Chemical gas released at (833.2012, 298.3842)!
[00:56:09] [ChemicalCloud] Cloud spawned at (833.2012, 298.3842), radius=300, duration=20s
[00:56:13] [ChemicalCloud] Enemy entered cloud: Enemy4 at (868.889, 620.5388)
[00:56:13] [ChemicalCloud] Spawning 2 illusion copies for enemy Enemy4
[00:56:13] [IllusionEnemy] Enemy copy spawned, health=1, damage=5%% of normal
[00:56:13] [IllusionEnemy] Illusion created at (921.2605, 614.7928) (duration=20s)
[00:56:13] [ENEMY] [Enemy] Spawned at (924.9938, 614.7797), hp: 1, behavior: GUARD
[00:56:13] [ENEMY] [Enemy] Spawned at (823.6152, 624.5719), hp: 1, behavior: GUARD
...
[00:56:13] [ENEMY] [Enemy] Hit: dmg=1, hp=1/1->0/1
[00:56:13] [ENEMY] [Enemy] Enemy died
[00:56:13] [IllusionEnemy] Illusion copy destroyed
```

### Root Cause of "Not Working" Perception

Illusion copies ARE spawning correctly at the right positions. However, they are immediately shot and killed by the player. The copies spawn at `(924.99, 614.78)` and `(823.61, 624.57)` — near the original enemy — but the player was already shooting in that area and the copies took a single hit and disappeared instantly.

This is correct behavior (one-shot kill) but looks like "not working" because copies don't survive long enough to be noticeable.

The user also noted the range should be **2–5 copies** (updated from the original 1–4).

### New Requirements (from comment 2026-03-20)

The user clarified additional requirements for Issue #1129:

1. **Regular enemies** (including Grenadier) should NOT throw chemical grenades.
2. A new **Gas Mask Enemy** type should be added with:
   - 4 chemical grenades
   - In combat state: throws grenades at the player before shooting
   - Cooldown: 4 seconds if player not under effect, or wait until effect expires if player is under effect
3. The new enemy should be **registered in the EnemiesTableMenu** but NOT placed on any map yet.
4. Illusion copy count updated to **2–5** (from 1–4).

### Fix

1. Removed chemical grenade logic from `EnemyGrenadeComponent` (regular enemies now only throw their default grenade).
2. Removed chemical grenade substitution from `GrenadierGrenadeComponent`.
3. Created `GasMaskGrenadeComponent` — dedicated component with 4 chemical grenades, combat-priority throwing, illusion-aware cooldown.
4. Added `is_gas_mask` export flag to `enemy.gd`.
5. Created `GasMaskEnemy.tscn` — same as `Enemy.tscn` but with green tint and `is_gas_mask = true`.
6. Registered gas mask enemy in `EnemiesTableMenu` (not placed on any maps).
7. Updated illusion copy count from `randi_range(1, 4)` to `randi_range(2, 5)`.

Files changed:
- `scripts/components/enemy_grenade_component.gd` — removed chemical grenade fields and logic
- `scripts/components/grenadier_grenade_component.gd` — removed chemical grenade substitution
- `scripts/components/gas_mask_grenade_component.gd` — new component (created)
- `scripts/objects/enemy.gd` — added `is_gas_mask` export, gas mask component setup
- `scenes/objects/GasMaskEnemy.tscn` — new scene (created)
- `scripts/ui/enemies_table_menu.gd` — added GasMask column
- `scripts/effects/chemical_cloud.gd` — updated copy count 1–4 → 2–5
- `scripts/projectiles/chemical_gas_grenade.gd` — updated docstring

---

## Bug Report #5: GasMaskEnemy Not Added to Any Level Spawner (2026-03-22)

### Symptom

User reported: "в спавнер газовый враг не добавился" — the gas mask enemy was not added to the spawner. The `GasMaskEnemy.tscn` scene existed and was fully functional, but it was never placed on any playable level map.

### Root Cause Analysis

In Bug Report #4, the fix created the `GasMaskEnemy.tscn` scene and registered it in `EnemiesTableMenu`, but explicitly noted "NOT placed on any map yet." The `ENEMY_FEATURES` dictionary in `enemies_table_menu.gd` had `GasMask = false` for all levels, and a comment stated:
```
## GasMask enemy (Issue #1129) is registered here but NOT placed on any map yet.
```

This was an intentional decision at the time (the user's comment during Bug #4 said "The new enemy should be registered in the EnemiesTableMenu but NOT placed on any map yet"), but the issue remained open, and the user expected the enemy to be placed on a level as part of the full implementation.

### How Enemies Are Placed in Levels

The project uses two methods for placing enemies:

1. **Scene-based placement** (most levels): Enemy instances are placed directly in level `.tscn` files with their special flags set as node properties. Example: `BuildingLevel.tscn` has an enemy node with `is_grenadier = true`.

2. **Separate scene files** (RadioJammerEnemy, GasMaskEnemy): Specialized enemy scenes are referenced as `ext_resource` and instantiated directly. Example: `DecadenceLevel.tscn` loads `RadioJammerEnemy.tscn` and places a `RadioJammer` node.

3. **Runtime spawning** (ArenaLevel, RoguelikeLevel): Enemies are instantiated at runtime from `Enemy.tscn` and configured programmatically. These do NOT support specialized enemy scenes.

### Fix

Added 2 GasMaskEnemy instances to **FactoryLevel** (the industrial factory map):
- Replaced `Enemy5` at position `(1800, 250)` with `GasMaskEnemy1`
- Replaced `Enemy11` at position `(300, 1700)` with `GasMaskEnemy2`
- These positions are in different areas of the factory for good spatial distribution

Factory was chosen because:
- It's a later-game level with heavily armored enemies (4-6 HP), appropriate difficulty for chemical grenades
- Thematically, "gas mask" enemies fit an industrial factory setting
- It had no special enemy types yet (no grenadier, teleporter, etc.)

Additionally updated:
- `enemies_table_menu.gd`: Set `GasMask = true` for FactoryLevel, removed "NOT placed" comment
- `levels_menu.gd`: Updated Factory description to mention gas mask enemies

Files changed:
- `scenes/levels/FactoryLevel.tscn` — added `GasMaskEnemy.tscn` ext_resource, replaced 2 enemies with GasMaskEnemy instances
- `scripts/ui/enemies_table_menu.gd` — set GasMask=true for Factory, removed placeholder comment
- `scripts/ui/levels_menu.gd` — updated Factory level description

---

## Timeline Summary

| Date | Event |
|------|-------|
| 2026-03-18 | Issue #1129 created: add chemical grenade to enemies |
| 2026-03-18 | Bug #1: Illusion copies blocked by premature `is_player_under_illusion()` guard |
| 2026-03-18 | Bug #2: Illusion copies spawning at wrong positions (Godot `global_position` pre-tree) |
| 2026-03-18 | Bug #3: Area2D overlap detection unreliable; switched to `intersect_shape()` |
| 2026-03-21 | Bug #4: New requirements — dedicated GasMaskEnemy type, 2–5 copies, no chemical for regular enemies |
| 2026-03-22 | Bug #5: GasMaskEnemy not placed on any level — added to FactoryLevel |
| 2026-03-22 | Bug #6: GasMaskEnemy not in experimental spawner dropdown — added as item #9 |
| 2026-03-22 | Bug #7: Infinite recursion — illusion copies spawning copies of copies (exponential growth) |
| 2026-03-22 | Bug #7 fix: Added metadata check `get_meta("is_illusion", false)` to `chemical_cloud.gd` |
| 2026-03-22 | Visual: Added gas mask head sprite (`gas_mask_head.png`) with green goggles and filter canister |

---

## Bug Report #7: Infinite Recursion — Illusion Copies Spawning Copies

**Symptom**: After a chemical grenade explodes, hundreds/thousands of enemy copies flood the screen, causing extreme lag and eventual crash. See `screenshot_recursion.png`.

**Root Cause**: The `ChemicalCloud._apply_illusion_to_enemy()` method checked `enemy.has_method("is_illusion")` to skip illusion copies. However:

1. The `IllusionEnemy` wrapper node (Node2D) has `is_illusion()` method → correctly skipped
2. But the inner `_enemy_node` (CharacterBody2D on collision layer 2) is what physics queries actually find
3. The inner node only has **metadata** `"is_illusion": true` (set in `illusion_enemy.gd:89`) — NOT the method
4. So the inner node passes the guard check and spawns MORE illusion copies
5. Those new copies' inner nodes are also found by the next physics tick → exponential growth

**Fix**: Added metadata check alongside the method check:
```gdscript
if enemy.get_meta("is_illusion", false):
    return
```

Also added early return in `_on_body_entered()` for bodies with `is_illusion` metadata to prevent signal-based detection of illusion copies.

**Game log**: `game_log_20260322_172130.txt` — log ends abruptly at 403 lines (game crashed from memory exhaustion).

---

## Visual Fix: Gas Mask Head Sprite

The GasMaskEnemy previously used the standard `enemy_head.png` with only a green color tint. User feedback: "на газовом враге не видно противогаза" (gas mask not visible on the gas mask enemy).

**Fix**: Created `assets/sprites/characters/enemy/gas_mask_head.png` — a 14x18 pixel sprite matching the original enemy head dimensions but with:
- Two circular green goggles (olive rims, green glass, dark green pupils)
- Bridge strap between goggles
- Filter canister (snout) below the goggles

Updated `GasMaskEnemy.tscn` to reference the new sprite.

---

## Bug Report #8: Illusion copies only for cloud-radius enemies + copies damage enemies

**Date**: 2026-03-22
**Reporter**: Jhon-Crow (PR comment #47)
**Symptom**: Illusion copies only appear near enemies inside the gas cloud radius. Also, illusion copies can damage other enemies and other illusion copies (should only damage the player).

**Feedback** (translated from Russian):
- "иллюзорные копи должны появляться у всех врагов на карте" — illusion copies must appear for ALL enemies on the map
- "иллюзорные копии не должны наносить урон врагам или другим иллюзорным копиям (только игроку)" — illusion copies must not damage enemies or other illusion copies (only the player)

**Root cause 1**: `ChemicalCloud._apply_effect_to_enemies_in_cloud()` used `PhysicsShapeQueryParameters2D` with `cloud_radius` to find enemies. Only enemies physically inside the 300px cloud radius received illusion copies.

**Fix 1**: Changed to `get_tree().get_nodes_in_group("enemies")` — now iterates over ALL enemies on the map regardless of distance from the cloud. Removed the line-of-sight check since the effect is map-wide.

**Root cause 2**: `bullet.gd` had no check for illusion-sourced bullets. The inner enemy node of `IllusionEnemy` fires bullets normally, and those bullets damage any enemy they hit.

**Fix 2**: Added `_is_illusion_bullet()` helper to `bullet.gd` that checks if the shooter has `is_illusion` metadata or if the shooter's parent is an `IllusionEnemy`. In `_on_area_entered()`, if the bullet is from an illusion and the target is not in the "player" group, skip damage entirely.

**Files changed**:
- `scripts/effects/chemical_cloud.gd` — `_apply_effect_to_enemies_in_cloud()` now finds all enemies via scene tree group
- `scripts/projectiles/bullet.gd` — added `_is_illusion_bullet()` and guard in `_on_area_entered()`

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
