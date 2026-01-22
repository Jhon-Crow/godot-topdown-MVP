# Case Study: Issue #217 - Add Enemy Character Models

## Overview

**Issue:** [#217 - добавить модельки врагов](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/217)
**Pull Request:** [#221](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/221)
**Date Created:** 2026-01-22
**Status:** In Progress (Follow-up after user feedback)

## Timeline of Events

### Phase 1: Initial Issue Creation (2026-01-22T06:10:35Z)

User @Jhon-Crow created issue #217 with the following requirements:

> "сделай модельки врагов на основе модельки игрока, но основной цвет должен быть чёрный, с белыми черепами(на предплечий или шлеме)."

Translation: Create enemy models based on the player model, but the main color should be black, with white skulls (on the forearms or helmet).

### Phase 2: Initial AI Solution Draft (2026-01-22T06:44:32Z - 2026-01-22T07:23:40Z)

The AI solver (Claude) created an initial solution draft that:

1. Created modular enemy sprites in `assets/sprites/characters/enemy/`:
   - `enemy_body.png` - Black body sprite (28x24 pixels)
   - `enemy_head.png` - Black head/helmet with white skull (14x18 pixels)
   - `enemy_left_arm.png` - Left arm with skull on forearm (20x8 pixels)
   - `enemy_right_arm.png` - Right arm with skull on forearm (20x8 pixels)
   - `enemy_combined_preview.png` - Preview image (64x64 pixels)

2. Updated `scenes/objects/Enemy.tscn` to use the new modular structure:
   - Added EnemyModel node with Body, Head, LeftArm, RightArm sprites
   - Added WeaponMount with WeaponSprite (M16 rifle)
   - Matched the structure used by `scenes/characters/Player.tscn`

3. Added sprite generation script `experiments/create_enemy_sprites.py`

**Cost (Initial Draft):**
- Public pricing estimate: $2.158082 USD
- Calculated by Anthropic: $1.534885 USD
- Difference: -$0.623197 (-28.88%)

### Phase 3: User Feedback (2026-01-22T07:35:33Z)

User @Jhon-Crow tested the solution and provided feedback:

1. **"сделай модельки больше (такого же размера как моделька игрока)"**
   - Translation: Make the models bigger (same size as the player model)

2. **"добавь анимацию ходьбы такую же, как у игрока (переиспользуй)"**
   - Translation: Add walking animation same as the player (reuse it)

3. **Request for Case Study Documentation:**
   - Download all logs and data related to the issue
   - Compile to `./docs/case-studies/issue-{id}` folder
   - Perform deep case study analysis with timeline and root causes

### Phase 4: Root Cause Analysis and Fix (2026-01-22T07:36:08Z - Current)

## Root Cause Analysis

### Issue 1: Enemy Models Are Smaller Than Player Models

**Root Cause:** The sprite PNG files were created with identical dimensions to the player sprites:
- Body: 28x24 pixels (same as player)
- Head: 14x18 pixels (same as player)
- Arms: 20x8 pixels (same as player)

However, the Player script (`scripts/characters/player.gd`) applies a **scale multiplier** of 1.3x:

```gdscript
## Scale multiplier for the player model (body, head, arms).
## Default is 1.3 to make the player slightly larger.
@export var player_model_scale: float = 1.3

# In _ready():
if _player_model:
    _player_model.scale = Vector2(player_model_scale, player_model_scale)
```

The enemy script (`scripts/objects/enemy.gd`) did not have this scaling applied to the EnemyModel node.

**Fix Applied:**
1. Added `enemy_model_scale` export variable (default 1.3) to enemy.gd
2. Added @onready reference to EnemyModel node
3. Applied scale in _ready() function: `_enemy_model.scale = Vector2(enemy_model_scale, enemy_model_scale)`

### Issue 2: Enemy Has No Walking Animation

**Root Cause:** The Enemy.tscn scene was updated with modular sprites (EnemyModel/Body, etc.) but the enemy.gd script still referenced the old flat structure:

```gdscript
# Old (broken) references:
@onready var _sprite: Sprite2D = $Sprite2D
@onready var _weapon_sprite: Sprite2D = $WeaponSprite

# New structure in scene file:
# EnemyModel/Body (Sprite2D)
# EnemyModel/Head (Sprite2D)
# EnemyModel/LeftArm (Sprite2D)
# EnemyModel/RightArm (Sprite2D)
# EnemyModel/WeaponMount/WeaponSprite (Sprite2D)
```

The Player script has a complete walking animation system that creates bobbing motion for body parts during movement, using sine waves:

```gdscript
# From player.gd:
func _update_walk_animation(delta: float, input_direction: Vector2) -> void:
    var is_moving := input_direction != Vector2.ZERO or velocity.length() > 10.0

    if is_moving:
        # Body bobs up and down
        var body_bob := sin(_walk_anim_time * 2.0) * 1.5 * walk_anim_intensity
        # Head bobs slightly less
        var head_bob := sin(_walk_anim_time * 2.0) * 0.8 * walk_anim_intensity
        # Arms swing opposite to each other
        var arm_swing := sin(_walk_anim_time) * 3.0 * walk_anim_intensity
        # Apply offsets...
```

The Enemy script had no walking animation system.

**Fix Applied:**
1. Updated @onready references to match new scene structure:
   - `_enemy_model: Node2D = $EnemyModel`
   - `_body_sprite: Sprite2D = $EnemyModel/Body`
   - `_head_sprite: Sprite2D = $EnemyModel/Head`
   - `_left_arm_sprite: Sprite2D = $EnemyModel/LeftArm`
   - `_right_arm_sprite: Sprite2D = $EnemyModel/RightArm`
   - `_weapon_sprite: Sprite2D = $EnemyModel/WeaponMount/WeaponSprite`
   - `_weapon_mount: Node2D = $EnemyModel/WeaponMount`

2. Added walking animation variables:
   - `walk_anim_speed: float = 12.0` (export)
   - `walk_anim_intensity: float = 1.0` (export)
   - `_walk_anim_time: float = 0.0`
   - `_is_walking: bool = false`
   - `_base_body_pos`, `_base_head_pos`, `_base_left_arm_pos`, `_base_right_arm_pos`

3. Added `_update_walk_animation(delta)` function (copied from player.gd and adapted)

4. Added `_update_enemy_model_rotation()` function to rotate model based on:
   - Player direction (if can see player)
   - Movement direction (otherwise)

5. Updated `_show_hit_flash()` and `_update_health_visual()` to use all sprite parts

6. Added `_set_all_sprites_modulate(color)` helper function

## Technical Insights

### Godot Scene Structure Mismatch

When modifying a scene's node hierarchy, all script references must be updated to match. The Enemy scene was updated to use a modular EnemyModel structure (matching Player), but the script still referenced the old flat structure.

**Best Practice:** When changing scene node hierarchy:
1. Update all @onready references in the script
2. Update any get_node() calls
3. Update any relative paths in code
4. Test that all visual features (color changes, animations) still work

### Walking Animation System Design

The walking animation uses a simple but effective approach:
- Sine waves with different frequencies create natural bobbing
- Body bobs at 2x frequency (double-step effect)
- Arms swing at 1x frequency, opposite to each other
- Head bobs slightly less than body for natural feel
- Smooth interpolation back to base positions when stopped

### Model Scale vs Sprite Scale

Godot offers multiple ways to scale sprites:
1. **Node2D.scale** - Scales all children uniformly
2. **TextureRect/Sprite2D scale** - Scales individual sprites
3. **Actual PNG dimensions** - Physical pixel size

For modular character models, applying scale to the parent container (PlayerModel/EnemyModel) is preferred as it:
- Maintains relative positions of body parts
- Allows easy adjustment via export variable
- Keeps sprite pixel art crisp at the source resolution

## Files Modified in Fix

### scripts/objects/enemy.gd
1. Added @onready references for EnemyModel and all sprite parts
2. Added walking animation exports: `walk_anim_speed`, `walk_anim_intensity`, `enemy_model_scale`
3. Added walking animation variables
4. Added `_update_walk_animation(delta)` function
5. Added `_update_enemy_model_rotation()` function
6. Updated `_show_hit_flash()` to use all sprites
7. Updated `_update_health_visual()` to use all sprites
8. Added `_set_all_sprites_modulate(color)` helper

### Phase 5: Second User Feedback (2026-01-22T11:03:24Z)

User @Jhon-Crow tested the solution again and reported two issues:

1. **"оружие врагов на 90 градусов от врага (слева)"**
   - Translation: Enemy weapon is at 90 degrees from the enemy (to the left)
   - Similar issue to a past player model bug

2. **"пули не летят из оружия врага"**
   - Translation: Bullets are not flying from enemy weapon
   - Bullets spawn from enemy center instead of weapon muzzle

### Phase 6: Root Cause Analysis and Fix (2026-01-22)

## Root Cause Analysis (Phase 5-6)

### Issue 3: Enemy Weapon Rotated 90 Degrees to the Left

**Root Cause:** The enemy script had TWO competing rotation systems:

1. `_update_enemy_model_rotation()` - Rotates the EnemyModel (including weapon) to face the player
2. `_update_weapon_sprite_rotation()` - Attempted to set weapon sprite rotation independently

The problem was in `_update_weapon_sprite_rotation()`:
```gdscript
# The comment was WRONG - weapon sprite is NOT a child of "enemy body"
# It's actually: Enemy -> EnemyModel -> WeaponMount -> WeaponSprite
_weapon_sprite.rotation = aim_angle - rotation  # Uses Enemy's rotation, not EnemyModel's!
```

The code used `rotation` (Enemy CharacterBody2D's rotation) instead of `_enemy_model.rotation`. Since:
- EnemyModel already rotates to face the target
- WeaponSprite is a child of EnemyModel/WeaponMount
- The weapon should just inherit EnemyModel's rotation

The additional rotation calculation was causing a 90-degree offset.

**Fix Applied:**
1. Removed the `_update_weapon_sprite_rotation()` call from `_physics_process`
2. The weapon now correctly inherits rotation from EnemyModel

### Issue 4: Bullets Not Spawning from Weapon Muzzle

**Root Cause:** The `_shoot()` function spawned bullets from enemy CENTER:
```gdscript
bullet.global_position = global_position + direction * bullet_spawn_offset
```

This was visually incorrect - bullets should appear to come from the rifle's barrel.

**Fix Applied:**
1. Added helper function `_get_bullet_spawn_position(direction: Vector2) -> Vector2`:
   ```gdscript
   func _get_bullet_spawn_position(direction: Vector2) -> Vector2:
       var muzzle_offset := 44.0 * enemy_model_scale  # Scale with enemy model
       if _weapon_mount:
           return _weapon_mount.global_position + direction * muzzle_offset
       else:
           return global_position + direction * bullet_spawn_offset
   ```

2. Updated all three shooting functions to use this helper:
   - `_shoot()`
   - `_shoot_with_inaccuracy()`
   - `_shoot_burst_shot()`

3. Updated `shooter_position` to use muzzle position for accurate distance calculations

## Lessons Learned

1. **Maintain Consistency Between Scene and Script:** When updating scene structure (adding EnemyModel with children), the script must be updated to reference the new node paths.

2. **Reuse Existing Systems:** The walking animation system from player.gd was well-designed and could be reused almost directly for enemies, demonstrating good code architecture.

3. **Check for Scale Multipliers:** Visual size in Godot depends not just on sprite dimensions but also on node scale. The player had a 1.3x scale multiplier that was easy to overlook.

4. **Modular Character Design:** Using a parent Node2D (PlayerModel/EnemyModel) with child sprites for body parts enables:
   - Easy scaling of the entire character
   - Per-part animations (walking, aiming)
   - Per-part visual effects (hit flash, health color)

5. **Test Visual Features:** After structural changes, all visual features should be tested:
   - Health color interpolation
   - Hit flash effect
   - Walking animation
   - Model rotation when aiming

6. **Avoid Competing Rotation Systems:** When using hierarchical node structures, be careful not to apply rotations at multiple levels. The EnemyModel already handles rotation - adding an independent weapon rotation caused conflicts.

7. **Understand Node Hierarchy for Relative Calculations:** When calculating relative positions/rotations, use the correct parent node's values. Using `rotation` (CharacterBody2D) instead of `_enemy_model.rotation` caused the 90-degree offset.

8. **Spawn Projectiles from Visual Origin:** Bullets should spawn from where players expect them - the weapon's muzzle, not the character's center. This improves visual consistency and player feedback.

## Related Files

- [issue-data.json](./issue-data.json) - Original issue data
- [pr-data.json](./pr-data.json) - Pull request metadata
- [pr-conversation-comments.json](./pr-conversation-comments.json) - PR discussion comments
- [pr-review-comments.json](./pr-review-comments.json) - PR review comments
- [pr-diff.txt](./pr-diff.txt) - PR diff showing all changes
- [logs/solution-draft-log-initial.txt](./logs/solution-draft-log-initial.txt) - Initial AI solution draft log
