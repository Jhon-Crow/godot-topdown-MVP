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

### Phase 7: Third User Feedback (2026-01-22T08:25:34Z)

User @Jhon-Crow tested the solution again and reported three issues:

1. **"враги ходят спиной вперёд и стреляют из спины"**
   - Translation: Enemies walk backwards and shoot from their back
   - The enemy model faces the wrong direction when moving/aiming

2. **"m16 у врагов должна быть такого же размера что и у игрока (меньше чем сейчас)"**
   - Translation: M16 on enemies should be the same size as the player's (smaller than current)
   - The weapon sprite is too large

Attached game logs:
- `game_log_20260122_112258.txt`
- `game_log_20260122_112342.txt`
- `game_log_20260122_112428.txt`

### Phase 8: Root Cause Analysis and Fix (2026-01-22)

## Root Cause Analysis (Phase 7-8)

### Issue 5: Enemies Walk Backwards and Shoot from Back

**Root Cause:** The enemy sprites were created facing **LEFT** (PI radians), while the player sprites face **RIGHT** (0 radians).

The rotation code set:
```gdscript
var target_angle := face_direction.angle()
_enemy_model.rotation = target_angle
```

When the face_direction points toward the player (e.g., to the right = 0 radians), and the sprites are drawn facing left (PI radians), the enemy appears to be facing away from where they're aiming.

**Visual Explanation:**
- Player sprites: Character drawn facing → (right, angle 0)
- Enemy sprites: Character drawn facing ← (left, angle PI)
- When rotation = 0 (facing right), player faces right ✓, enemy faces left ✗

**Fix Applied:**
1. Added PI to the target rotation angle to compensate for sprite orientation:
   ```gdscript
   # Enemy sprites face LEFT (PI radians offset from player sprites which face RIGHT)
   var target_angle := face_direction.angle() + PI
   _enemy_model.rotation = target_angle
   ```

2. Updated flipping logic to use the original face_direction angle:
   ```gdscript
   var face_angle := face_direction.angle()
   var aiming_left := absf(face_angle) > PI / 2
   ```

### Issue 6: M16 Weapon Sprite Too Large

**Root Cause:** The enemy uses `m16_rifle_topdown.png` (64x16 pixels), which when scaled at 1.3x becomes ~83x21 pixels.

The player's weapon is **integrated into the arm sprites** (player_left_arm.png is 20x8 and includes the rifle grip). The player's rifle portion, when scaled 1.3x, appears much smaller than the separate enemy weapon sprite.

**Comparison:**
- Player: Arms (20x8) × 1.3 scale = 26×10 effective pixels, weapon integrated
- Enemy: Separate rifle (64x16) × 1.3 scale = 83×21 effective pixels

**Fix Applied:**
1. Changed Enemy.tscn to use `m16_topdown_small.png` (32x8 pixels) instead of `m16_rifle_topdown.png` (64x16 pixels)

2. Updated weapon sprite offset from `Vector2(20, 0)` to `Vector2(10, 0)` (proportional to new sprite size)

3. Updated `_get_bullet_spawn_position()` muzzle offset calculation:
   ```gdscript
   # Old: 44px for 64px sprite with 20px offset
   # New: 22px for 32px sprite with 10px offset
   var muzzle_offset := 22.0 * enemy_model_scale
   ```

## Summary of All Issues and Fixes

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| 1. Enemy smaller than player | Missing 1.3x scale multiplier | Added `enemy_model_scale` export and scale in `_ready()` |
| 2. No walking animation | Old script references + missing animation code | Updated references, added `_update_walk_animation()` |
| 3. Weapon at 90° angle | Competing rotation systems | Removed `_update_weapon_sprite_rotation()` call |
| 4. Bullets from center | Spawning from enemy position | Added `_get_bullet_spawn_position()` using weapon mount |
| 5. Walking backwards | Enemy sprites face opposite direction (PI offset) | Added PI to rotation angle |
| 6. M16 too large | Using 64px sprite vs player's integrated smaller rifle | Changed to `m16_topdown_small.png` (32px) |

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

9. **Match Sprite Orientations:** When creating new character sprites based on existing ones, ensure they face the same direction (typically RIGHT = 0 radians in 2D games). If sprites face opposite directions, the rotation code needs to compensate with a PI offset.

10. **Compare Proportions with Reference:** When adding separate weapon sprites, compare the final rendered size (after scaling) with how weapons appear on reference characters (player). The player's integrated weapon was much smaller than the separate 64px rifle sprite.

### Phase 9: Fourth User Feedback (2026-01-22T11:47:16Z)

User @Jhon-Crow tested the solution again and reported two issues:

1. **"теперь оружие врагов вообще не отображается"**
   - Translation: Now enemy weapons are not displayed at all
   - The smaller weapon sprite `m16_topdown_small.png` was not visible

2. **"сломался особый последний шанс (пули игрока перестали останавливаться)"**
   - Translation: The special last chance is broken (player bullets stopped stopping)
   - The Last Chance effect was not properly freezing bullets

Attached game log:
- `game_log_20260122_114716.txt`

### Phase 10: Root Cause Analysis and Fix (2026-01-22)

## Root Cause Analysis (Phase 9-10)

### Issue 7: Enemy Weapons Not Displaying

**Root Cause:** The smaller weapon sprite `m16_topdown_small.png` (32x8 pixels) was being obscured by:
1. Very small size compared to body parts
2. z-index of 2 being lower than arms (z-index 4)
3. Dark color (30, 30, 30 RGB) making it hard to see

The original larger sprite `m16_rifle_topdown.png` (64x16 pixels) was clearly visible.

**Fix Applied:**
1. Reverted `Enemy.tscn` to use the original larger sprite `m16_rifle_topdown.png`
2. Restored weapon offset from `Vector2(10, 0)` back to `Vector2(20, 0)`
3. Updated `_get_bullet_spawn_position()` muzzle offset from 22px back to 44px

### Issue 8: Last Chance Effect Not Freezing Bullets

**Root Cause:** The feature branch `issue-217-6e363ec134f9` was created before recent fixes were merged to main. The branch was missing commits:
- `154652e` - Fix Mini UZI direction and Last Chance mode bullet freezing
- `830769a` - Fix shotgun pellets not freezing in last chance mode

These commits added proper detection for pellets and other bullet types in `last_chance_effects_manager.gd`:
```gdscript
# Before (missing pellet detection):
if "bullet" in script_path.to_lower():

# After (with pellet detection):
if "bullet" in script_path.to_lower() or "pellet" in script_path.to_lower():
```

**Fix Applied:**
1. Merged main branch into feature branch to incorporate latest fixes
2. The Last Chance effect now properly detects and freezes all bullet types

## Updated Summary of All Issues and Fixes

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| 1. Enemy smaller than player | Missing 1.3x scale multiplier | Added `enemy_model_scale` export and scale in `_ready()` |
| 2. No walking animation | Old script references + missing animation code | Updated references, added `_update_walk_animation()` |
| 3. Weapon at 90° angle | Competing rotation systems | Removed `_update_weapon_sprite_rotation()` call |
| 4. Bullets from center | Spawning from enemy position | Added `_get_bullet_spawn_position()` using weapon mount |
| 5. Walking backwards | Enemy sprites face opposite direction (PI offset) | Added PI to rotation angle |
| 6. M16 too large | Using 64px sprite vs player's integrated smaller rifle | Changed to `m16_topdown_small.png` (32px) |
| 7. Weapon not visible | Smaller sprite obscured by body parts | Reverted to original larger sprite `m16_rifle_topdown.png` |
| 8. Last Chance not freezing bullets | Branch missing pellet detection fix from main | Merged main branch with latest fixes |

## Additional Lessons Learned

11. **Test Visual Changes with Actual Gameplay:** The smaller weapon sprite looked correct in isolation but was invisible during actual gameplay due to overlapping body parts and z-index ordering.

12. **Keep Feature Branches Updated:** Long-running feature branches may miss important fixes from main. Regularly merging main ensures all bug fixes are incorporated.

13. **Consider Visual Contrast:** Dark sprites on dark backgrounds or small sprites under other elements may become invisible. Test visual changes at runtime, not just in the editor.

14. **Balance Visual Accuracy vs. Visibility:** Sometimes gameplay clarity is more important than visual accuracy. A larger weapon sprite that's visible is better than a "correctly sized" sprite that can't be seen.

### Phase 11: Fifth User Feedback (2026-01-22T12:11:26Z)

User @Jhon-Crow tested the solution again and reported:

1. **"враги всё ещё стреляют не из оружия"**
   - Translation: Enemies still shoot not from their weapon
   - Bullets appear to spawn from incorrect position, not from the weapon muzzle

Attached game log:
- `game_log_20260122_120806.txt`

### Phase 12: Root Cause Analysis and Fix (2026-01-22)

## Root Cause Analysis (Phase 11-12)

### Issue 9: Bullets Not Spawning From Weapon Muzzle

**Root Cause:** The `_get_bullet_spawn_position()` function had two fundamental problems:

1. **Direction Mismatch:** The function used the `direction` parameter (direction from enemy center to player/target) to calculate muzzle offset. However, when the enemy model is rotated, the weapon's actual forward direction in world space is different from this direction parameter, especially when lead prediction is enabled.

2. **Timing Issue:** In `_physics_process()`, the execution order was:
   ```
   1. _process_ai_state(delta)  // Shooting happens here
   2. _update_enemy_model_rotation()  // Model rotation updated AFTER
   ```

   This meant when `_shoot()` was called, the enemy model rotation (and thus `_weapon_mount.global_position`) was from the **previous frame**, but the `direction` parameter was calculated for the **current frame's** target position. This caused a positional mismatch between where the weapon visually points and where bullets actually spawn.

**The Math:**
- Enemy sprites face LEFT in local space (PI radians from "right")
- Enemy model rotation is `face_direction.angle() + PI`
- Weapon's forward direction in world space: `Vector2(-1, 0).rotated(enemy_model.rotation)`
- This transforms local-left to world-space direction

When the rotation and direction calculations happen in different frames or use different target positions (due to lead prediction), the bullet spawn position doesn't align with the visual weapon position.

**Fix Applied:**
1. Changed `_get_bullet_spawn_position()` to calculate the weapon's actual forward direction from `_enemy_model.rotation` instead of using the passed `direction` parameter:
   ```gdscript
   # Before (incorrect):
   return _weapon_mount.global_position + direction * muzzle_offset

   # After (correct):
   var weapon_forward := Vector2(-1, 0).rotated(_enemy_model.rotation)
   return _weapon_mount.global_position + weapon_forward * muzzle_offset
   ```

2. Moved `_update_enemy_model_rotation()` to execute BEFORE `_process_ai_state()`:
   ```gdscript
   # Before:
   _process_ai_state(delta)  # Shooting here uses old rotation
   _update_enemy_model_rotation()  # Rotation updated too late

   # After:
   _update_enemy_model_rotation()  # Rotation updated first
   _process_ai_state(delta)  # Shooting uses current rotation
   ```

## Updated Summary of All Issues and Fixes

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| 1. Enemy smaller than player | Missing 1.3x scale multiplier | Added `enemy_model_scale` export and scale in `_ready()` |
| 2. No walking animation | Old script references + missing animation code | Updated references, added `_update_walk_animation()` |
| 3. Weapon at 90° angle | Competing rotation systems | Removed `_update_weapon_sprite_rotation()` call |
| 4. Bullets from center | Spawning from enemy position | Added `_get_bullet_spawn_position()` using weapon mount |
| 5. Walking backwards | Enemy sprites face opposite direction (PI offset) | Added PI to rotation angle |
| 6. M16 too large | Using 64px sprite vs player's integrated smaller rifle | Changed to `m16_topdown_small.png` (32px) |
| 7. Weapon not visible | Smaller sprite obscured by body parts | Reverted to original larger sprite `m16_rifle_topdown.png` |
| 8. Last Chance not freezing bullets | Branch missing pellet detection fix from main | Merged main branch with latest fixes |
| 9. Bullets not from weapon muzzle | Direction mismatch and execution order issue | Use weapon's actual rotation for muzzle direction; moved rotation update before shooting |

## Additional Lessons Learned

11. **Test Visual Changes with Actual Gameplay:** The smaller weapon sprite looked correct in isolation but was invisible during actual gameplay due to overlapping body parts and z-index ordering.

12. **Keep Feature Branches Updated:** Long-running feature branches may miss important fixes from main. Regularly merging main ensures all bug fixes are incorporated.

13. **Consider Visual Contrast:** Dark sprites on dark backgrounds or small sprites under other elements may become invisible. Test visual changes at runtime, not just in the editor.

14. **Balance Visual Accuracy vs. Visibility:** Sometimes gameplay clarity is more important than visual accuracy. A larger weapon sprite that's visible is better than a "correctly sized" sprite that can't be seen.

15. **Execution Order Matters:** When multiple systems depend on each other (rotation system, shooting system), the order of execution in the game loop is critical. The rotation system must update BEFORE the shooting system accesses the rotated positions.

16. **Use Actual State, Not Parameters:** When calculating positions based on rotated objects, use the object's actual rotation state rather than parameters that might be calculated differently (e.g., with lead prediction). This ensures visual consistency between what the player sees and what the code produces.

17. **Consider Lead Prediction Effects:** When implementing features like bullet lead prediction, the shooting direction may differ from the visual aim direction. The bullet spawn position should match where the weapon visually points, not where the bullet is aimed.

## Related Files

- [issue-data.json](./issue-data.json) - Original issue data
- [pr-data.json](./pr-data.json) - Pull request metadata
- [pr-conversation-comments.json](./pr-conversation-comments.json) - PR discussion comments
- [pr-review-comments.json](./pr-review-comments.json) - PR review comments
- [pr-diff.txt](./pr-diff.txt) - PR diff showing all changes
- [logs/solution-draft-log-initial.txt](./logs/solution-draft-log-initial.txt) - Initial AI solution draft log
- [logs/game_log_20260122_112258.txt](./logs/game_log_20260122_112258.txt) - Game log from phase 7 testing
- [logs/game_log_20260122_112342.txt](./logs/game_log_20260122_112342.txt) - Game log from phase 7 testing
- [logs/game_log_20260122_112428.txt](./logs/game_log_20260122_112428.txt) - Game log from phase 7 testing
- [logs/game_log_20260122_114716.txt](./logs/game_log_20260122_114716.txt) - Game log from phase 9 testing
- [logs/game_log_20260122_120806.txt](./logs/game_log_20260122_120806.txt) - Game log from phase 11 testing
- [logs/game_log_20260122_122412.txt](./logs/game_log_20260122_122412.txt) - Game log from phase 13 testing

### Phase 13: Sixth User Feedback (2026-01-22T12:25:39Z)

User @Jhon-Crow tested the solution again and reported:

1. **"враги всё ещё чаще всего стреляют не из оружия"**
   - Translation: Enemies still mostly shoot not from their weapon
   - Bullets continue to spawn from incorrect position despite previous fix

Attached game log:
- `game_log_20260122_122412.txt`

### Phase 14: Deep Root Cause Analysis and Fix (2026-01-22)

## Root Cause Analysis (Phase 13-14)

### Issue 10: Bullets STILL Not Spawning From Weapon Muzzle

**Root Cause:** The previous fix (Phase 12) used `Vector2(-1, 0)` for the weapon's local forward direction, but this was fundamentally INCORRECT.

The issue is a **coordinate system mismatch** between the weapon sprite orientation and the assumed forward direction:

1. **Weapon sprite orientation:** The M16 rifle sprite (`m16_rifle_topdown.png`) is drawn with the **muzzle pointing RIGHT** (+X direction in local space).

2. **Previous code assumption:** The code assumed `Vector2(-1, 0)` as the weapon's forward direction in local space, meaning it expected the muzzle to point LEFT (-X direction).

3. **Combined with PI offset:** The enemy model rotation includes a `+ PI` offset to compensate for body sprites facing left. When this rotation is applied to the wrong local forward direction, the result is doubly incorrect.

**Visual Analysis of the Rifle Sprite:**
```
[m16_rifle_topdown.png - 64x16 pixels]
Stock          Grip        Barrel        Muzzle
  ←              ←            ←             →
[-X in local space]                    [+X in local space]
```

The muzzle is at the RIGHT side of the sprite (+X direction), not the left.

**Additionally**, the `_weapon_sprite.offset = Vector2(20, 0)` shifts the sprite further to the RIGHT. The muzzle position calculation must account for:
- Sprite center: at node position
- Sprite offset: +20 pixels in +X direction
- Half sprite width: +32 pixels in +X direction
- Total: muzzle is at +52 pixels from node position in local +X direction

**The Critical Bug:** The previous fix also didn't account for the **Y-axis flip** that occurs when enemies aim left. When `_enemy_model.scale.y = -1`, the coordinate system is flipped, which affects how rotation transforms local coordinates to world coordinates.

**Fix Applied:**

1. Changed to use `_weapon_sprite.global_transform.x` instead of manual rotation calculation:
   ```gdscript
   # Before (incorrect):
   var weapon_forward := Vector2(-1, 0).rotated(_enemy_model.rotation)

   # After (correct):
   var weapon_global_forward := _weapon_sprite.global_transform.x.normalized()
   ```

   The `global_transform.x` property gives the weapon's local +X axis in **world coordinates**, automatically accounting for:
   - All parent rotations (Enemy → EnemyModel → WeaponMount → WeaponSprite)
   - All parent scales (including Y flip when aiming left)
   - The actual hierarchical transform chain

2. Changed to use `_weapon_sprite.global_position` instead of `_weapon_mount.global_position`:
   ```gdscript
   # The weapon sprite is the actual visual element, so use its position
   return _weapon_sprite.global_position + weapon_global_forward * scaled_muzzle_offset
   ```

3. Updated the muzzle offset calculation:
   ```gdscript
   # Muzzle is at: sprite_offset.x + sprite_width/2 = 20 + 32 = 52 pixels in local +X
   var muzzle_local_offset := 52.0
   var scaled_muzzle_offset := muzzle_local_offset * enemy_model_scale
   ```

**Why This Works:**
- `global_transform.x` is a property of all Node2D objects that gives the local +X axis direction in world space
- It correctly handles all transforms in the hierarchy: translation, rotation, AND scale (including negative scale for flipping)
- This approach is more robust than manually calculating the direction, as it automatically adapts to any scene hierarchy changes

## Updated Summary of All Issues and Fixes

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| 1. Enemy smaller than player | Missing 1.3x scale multiplier | Added `enemy_model_scale` export and scale in `_ready()` |
| 2. No walking animation | Old script references + missing animation code | Updated references, added `_update_walk_animation()` |
| 3. Weapon at 90° angle | Competing rotation systems | Removed `_update_weapon_sprite_rotation()` call |
| 4. Bullets from center | Spawning from enemy position | Added `_get_bullet_spawn_position()` using weapon mount |
| 5. Walking backwards | Enemy sprites face opposite direction (PI offset) | Added PI to rotation angle |
| 6. M16 too large | Using 64px sprite vs player's integrated smaller rifle | Changed to `m16_topdown_small.png` (32px) |
| 7. Weapon not visible | Smaller sprite obscured by body parts | Reverted to original larger sprite `m16_rifle_topdown.png` |
| 8. Last Chance not freezing bullets | Branch missing pellet detection fix from main | Merged main branch with latest fixes |
| 9. Bullets not from weapon muzzle | Direction mismatch and execution order issue | Use weapon's actual rotation for muzzle direction; moved rotation update before shooting |
| 10. Bullets STILL not from muzzle | Wrong local forward direction (used -X instead of +X) and Y-flip not handled | Use `global_transform.x` for correct world-space forward direction |

## Additional Lessons Learned (Phase 13-14)

18. **Sprite Orientation Matters:** When calculating forward directions for sprites, first verify which direction the sprite actually faces. A rifle sprite with the muzzle pointing right uses `Vector2(1, 0)` as local forward, not `Vector2(-1, 0)`.

19. **Use Transform Properties, Not Manual Calculations:** Godot's `global_transform` properties (`x`, `y`, `origin`) correctly account for the entire transform hierarchy including scale flips. Using `global_transform.x.normalized()` is more robust than manually applying rotations.

20. **Y-Scale Flip Affects Coordinate System:** When a node has negative Y scale (for horizontal flipping), the relationship between local and world coordinates changes. Manual rotation calculations may not account for this, but `global_transform` does.

21. **Verify Assumptions About Sprite Orientation:** Before writing transformation code, view the actual sprite asset to confirm its orientation. Comments saying "sprites face LEFT" should be verified against the actual sprite file.

22. **Test Edge Cases:** The bullet spawn issue was most visible when enemies faced certain directions (particularly when Y-flip was active). Testing with enemies facing all directions would have revealed the issue sooner.

### Phase 15: Seventh User Feedback (2026-01-22T09:37:13Z)

User @Jhon-Crow tested the solution again and reported two issues:

1. **"когда игрок стреляет вверх он наносит себе урон"**
   - Translation: When the player shoots upward they damage themselves
   - Player bullets hitting the player's own hitbox

2. **"пули из оружия врагов должны вылетать по направлению ствола"**
   - Translation: Bullets from enemy weapons should fly in the direction of the barrel
   - Enemy bullets fly from the muzzle but in any direction, not aligned with the weapon barrel

Attached game logs:
- `game_log_20260122_123430.txt`
- `game_log_20260122_123547.txt`

### Phase 16: Root Cause Analysis and Fix (2026-01-22)

## Root Cause Analysis (Phase 15-16)

### Issue 11: Player Self-Damage When Shooting Upward

**Root Cause:** The C# `Bullet.cs` class had properties that couldn't be properly set via Godot's `Node.Set()` method from the C# `BaseWeapon.cs` shooter.

The property binding chain:
1. `BaseWeapon.cs` calls `bullet.Set("shooter_id", owner.GetInstanceId())`
2. Godot tries to find a property named `shooter_id` (snake_case)
3. C# `Bullet.cs` has `public ulong ShooterId { get; set; }` (PascalCase)
4. Without the `[Export]` attribute, Godot cannot find the property via snake_case name
5. `ShooterId` remains at default value `0`
6. Self-damage check fails: `if (ShooterId == body.GetInstanceId())` never matches

**Evidence from logs:** The game logs showed bullets with `shooter_id=0` and `shooter_position=(0, 0)`, which should have been set to the player's instance ID and position.

**Fix Applied:**
Added `[Export]` attribute to three properties in `Scripts/Projectiles/Bullet.cs`:

```csharp
// Before:
public Vector2 Direction { get; set; } = Vector2.Right;
public ulong ShooterId { get; set; } = 0;
public Vector2 ShooterPosition { get; set; } = Vector2.Zero;

// After:
[Export]
public Vector2 Direction { get; set; } = Vector2.Right;

[Export]
public ulong ShooterId { get; set; } = 0;

[Export]
public Vector2 ShooterPosition { get; set; } = Vector2.Zero;
```

The `[Export]` attribute in Godot's C# API:
- Exposes the property to the Godot editor
- Makes the property accessible via `Node.Set()` and `Node.Get()` with snake_case naming
- Enables cross-language property setting between GDScript and C#

### Issue 12: Enemy Bullets Not Flying in Barrel Direction

**Root Cause:** The bullet spawn position was correctly calculated from the weapon muzzle (using `global_transform.x`), but the bullet's **direction** was still calculated as the direction from enemy center to player.

In `enemy.gd` `_shoot()` function:
```gdscript
# Bullet spawns from correct muzzle position
var bullet_spawn_pos := _get_bullet_spawn_position(direction)

# BUT direction was calculated to point at player, not barrel forward
var direction := (target_position - global_position).normalized()
bullet.direction = direction  # Wrong! Uses direction to player, not barrel direction
```

This caused a visual mismatch:
- Weapon sprite points at the player (correct visual)
- Bullet spawns from muzzle (correct position)
- Bullet flies toward player center (but muzzle may not point exactly at player center due to position offset)

**Fix Applied:**
1. Added new helper function `_get_weapon_forward_direction()`:
```gdscript
## Returns the weapon's forward direction in world coordinates.
## This is the direction the weapon barrel is actually pointing.
## Uses the weapon sprite's global transform to account for rotation and scale (including Y flip).
## @returns: Normalized direction vector the weapon is pointing.
func _get_weapon_forward_direction() -> Vector2:
    if _weapon_sprite and _enemy_model:
        # Use the weapon sprite's global transform to get its actual forward direction.
        # The weapon sprite points RIGHT (+X) in its local space.
        # global_transform.x gives us the weapon's local +X axis in world coordinates,
        # accounting for both rotation AND scale (including Y flip).
        return _weapon_sprite.global_transform.x.normalized()
    else:
        # Fallback: calculate direction to player
        if _player and is_instance_valid(_player):
            return (_player.global_position - global_position).normalized()
        return Vector2.RIGHT  # Default fallback
```

2. Updated all shooting functions to use weapon forward direction:
   - `_shoot()` - main shooting function
   - `_shoot_with_inaccuracy()` - shooting during retreat with spread
   - `_shoot_burst_shot()` - burst fire with arc spread

3. Updated `_should_shoot_at_target()` to check bullet spawn clearance using weapon direction:
```gdscript
# Before:
var direction := (target_position - global_position).normalized()
if not _is_bullet_spawn_clear(direction):

# After:
var weapon_direction := _get_weapon_forward_direction()
if not _is_bullet_spawn_clear(weapon_direction):
```

## Updated Summary of All Issues and Fixes

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| 1. Enemy smaller than player | Missing 1.3x scale multiplier | Added `enemy_model_scale` export and scale in `_ready()` |
| 2. No walking animation | Old script references + missing animation code | Updated references, added `_update_walk_animation()` |
| 3. Weapon at 90° angle | Competing rotation systems | Removed `_update_weapon_sprite_rotation()` call |
| 4. Bullets from center | Spawning from enemy position | Added `_get_bullet_spawn_position()` using weapon mount |
| 5. Walking backwards | Enemy sprites face opposite direction (PI offset) | Added PI to rotation angle |
| 6. M16 too large | Using 64px sprite vs player's integrated smaller rifle | Changed to `m16_topdown_small.png` (32px) |
| 7. Weapon not visible | Smaller sprite obscured by body parts | Reverted to original larger sprite `m16_rifle_topdown.png` |
| 8. Last Chance not freezing bullets | Branch missing pellet detection fix from main | Merged main branch with latest fixes |
| 9. Bullets not from weapon muzzle | Direction mismatch and execution order issue | Use weapon's actual rotation for muzzle direction; moved rotation update before shooting |
| 10. Bullets STILL not from muzzle | Wrong local forward direction (used -X instead of +X) and Y-flip not handled | Use `global_transform.x` for correct world-space forward direction |
| 11. Player self-damage when shooting upward | C# Bullet properties missing [Export] attribute, preventing cross-language property binding | Added [Export] to Direction, ShooterId, ShooterPosition in Bullet.cs |
| 12. Enemy bullets not flying in barrel direction | Bullet direction calculated to player, not weapon forward | Added `_get_weapon_forward_direction()` and updated all shooting functions |

## Additional Lessons Learned (Phase 15-16)

23. **Cross-Language Property Binding in Godot:** When using C# with Godot, properties must have the `[Export]` attribute to be accessible via `Node.Set()` and `Node.Get()` with snake_case names. Without it, cross-language property setting silently fails.

24. **Bullet Direction vs Spawn Position:** The spawn position and travel direction are independent calculations. Even with correct spawn position, the travel direction must also be correct for visual consistency.

25. **Consistency Across All Shooting Functions:** When fixing shooting behavior, ensure ALL shooting functions are updated (main shoot, inaccurate shoot, burst shoot, etc.), not just the primary one.

26. **Use Same Logic for Validation and Execution:** The bullet spawn clearance check (`_should_shoot_at_target`) should use the same direction calculation as the actual shooting, otherwise the validation may pass but the shot may still visually look wrong.

### Phase 17: Eighth User Feedback (2026-01-22T12:52:28Z)

User @Jhon-Crow tested the solution again and reported:

1. **"игрок всё ещё наносит себе урон когда стреляет вверх"**
   - Translation: Player still damages themselves when shooting upward
   - Despite adding [Export] attribute in Phase 16, player bullets still cause self-damage

Attached game log:
- `game_log_20260122_125115.txt`

### Phase 18: Deep Root Cause Analysis and Fix (2026-01-22)

## Root Cause Analysis (Phase 17-18)

### Issue 13: Player STILL Self-Damages When Shooting Upward (Continued)

**Root Cause:** While Phase 16 added the `[Export]` attribute to C# Bullet properties, analysis of the game log revealed that **94 bullets had `shooter_id=0`** - indicating the properties were still not being set correctly.

The issue is that `Node.Set("shooter_id", value)` in Godot does not reliably map snake_case property names to PascalCase C# properties, even with the `[Export]` attribute. The Godot-to-C# property binding via `Set()` method has inconsistent behavior.

**Evidence from log analysis:**
```
Total bullets: 206
Bullets with shooter_id=0: 94
Bullets with valid shooter_id: 112
```

The 94 bullets with `shooter_id=0` were C# bullets (identifiable by their log format), spawned by the player through `BaseWeapon.cs`.

**Technical Explanation:**
1. `BaseWeapon.cs` calls `bullet.Set("shooter_id", owner.GetInstanceId())`
2. `Node.Set()` attempts to find a property with snake_case name `shooter_id`
3. The C# property `ShooterId` (PascalCase) should map to `shooter_id` (snake_case) via `[Export]`
4. However, this mapping is unreliable - sometimes it works, sometimes it doesn't
5. When it fails, `ShooterId` stays at default value `0`
6. Self-damage check `if (ShooterId == body.GetInstanceId())` never matches because player's ID is never `0`

**Fix Applied:**

Instead of relying on `Node.Set()` property binding, we added explicit setter methods that can be called via `Node.Call()`:

1. Added setter methods to `Scripts/Projectiles/Bullet.cs`:
```csharp
/// <summary>
/// Sets the shooter ID to prevent self-damage.
/// Called by the weapon to identify the shooter node.
/// </summary>
/// <param name="shooterId">Instance ID of the shooter node.</param>
public void SetShooterId(ulong shooterId)
{
    ShooterId = shooterId;
}

/// <summary>
/// Sets the shooter's position at firing time.
/// Used for distance-based penetration calculations.
/// </summary>
/// <param name="position">Global position of the shooter when firing.</param>
public void SetShooterPosition(Vector2 position)
{
    ShooterPosition = position;
}
```

2. Updated `Scripts/AbstractClasses/BaseWeapon.cs` to use method calls with fallback:
```csharp
// Set shooter ID to prevent self-damage
var owner = GetParent();
if (owner != null)
{
    // Try method call first (for C# bullets), fall back to property set (for GDScript bullets)
    if (bullet.HasMethod("SetShooterId"))
    {
        bullet.Call("SetShooterId", owner.GetInstanceId());
    }
    else
    {
        bullet.Set("shooter_id", owner.GetInstanceId());
    }
}

// Set shooter position for distance-based penetration calculations
if (bullet.HasMethod("SetShooterPosition"))
{
    bullet.Call("SetShooterPosition", GlobalPosition);
}
else
{
    bullet.Set("shooter_position", GlobalPosition);
}
```

3. Updated `Scripts/Characters/Player.cs` SpawnBullet method similarly:
```csharp
// Set bullet direction
if (bullet.HasMethod("SetDirection"))
{
    bullet.Call("SetDirection", direction);
}
else
{
    bullet.Set("direction", direction);
}

// Set shooter ID to prevent self-damage
if (bullet.HasMethod("SetShooterId"))
{
    bullet.Call("SetShooterId", GetInstanceId());
}
else
{
    bullet.Set("shooter_id", GetInstanceId());
}
```

**Why This Fix Works:**
- `Node.Call()` invokes methods directly by name, which is more reliable than property binding
- Method names don't require case conversion (SetShooterId is called exactly as named)
- The `HasMethod()` check ensures backward compatibility with GDScript bullets that use property setters
- This pattern (try method, fallback to property) handles both C# and GDScript bullets correctly

## Updated Summary of All Issues and Fixes

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| 1. Enemy smaller than player | Missing 1.3x scale multiplier | Added `enemy_model_scale` export and scale in `_ready()` |
| 2. No walking animation | Old script references + missing animation code | Updated references, added `_update_walk_animation()` |
| 3. Weapon at 90° angle | Competing rotation systems | Removed `_update_weapon_sprite_rotation()` call |
| 4. Bullets from center | Spawning from enemy position | Added `_get_bullet_spawn_position()` using weapon mount |
| 5. Walking backwards | Enemy sprites face opposite direction (PI offset) | Added PI to rotation angle |
| 6. M16 too large | Using 64px sprite vs player's integrated smaller rifle | Changed to `m16_topdown_small.png` (32px) |
| 7. Weapon not visible | Smaller sprite obscured by body parts | Reverted to original larger sprite `m16_rifle_topdown.png` |
| 8. Last Chance not freezing bullets | Branch missing pellet detection fix from main | Merged main branch with latest fixes |
| 9. Bullets not from weapon muzzle | Direction mismatch and execution order issue | Use weapon's actual rotation for muzzle direction; moved rotation update before shooting |
| 10. Bullets STILL not from muzzle | Wrong local forward direction (used -X instead of +X) and Y-flip not handled | Use `global_transform.x` for correct world-space forward direction |
| 11. Player self-damage when shooting upward | C# Bullet properties missing [Export] attribute | Added [Export] to Direction, ShooterId, ShooterPosition in Bullet.cs |
| 12. Enemy bullets not flying in barrel direction | Bullet direction calculated to player, not weapon forward | Added `_get_weapon_forward_direction()` and updated all shooting functions |
| 13. Player STILL self-damaging | `Node.Set()` unreliably maps snake_case to PascalCase C# properties | Added explicit setter methods (`SetShooterId`, `SetShooterPosition`) and use `Call()` instead of `Set()` |

## Additional Lessons Learned (Phase 17-18)

27. **Prefer Method Calls Over Property Binding for Cross-Language Code:** In Godot's C#/GDScript interop, calling methods via `Node.Call()` is more reliable than setting properties via `Node.Set()`. Method names don't require case conversion and work consistently.

28. **Don't Trust Silent Failures:** The `[Export]` attribute should have made properties accessible via snake_case names, but it didn't always work. When a fix doesn't solve the problem, investigate deeper rather than assuming the approach was correct.

29. **Analyze Logs Quantitatively:** Instead of just looking for errors, count occurrences. Finding "94 bullets with shooter_id=0" out of 206 bullets revealed the systematic failure that spot-checking might have missed.

30. **Use HasMethod/Call Pattern for Compatibility:** When code must work with both C# and GDScript objects, use `HasMethod()` to check for method availability, then `Call()` for C# objects and `Set()` as fallback for GDScript objects.

31. **Case Sensitivity Matters in Cross-Language Binding:** Godot's property binding between C# (PascalCase convention) and GDScript (snake_case convention) is not always reliable. Explicit method calls bypass this issue entirely.

### Phase 19: Ninth User Feedback (2026-01-22T10:34:45Z)

User @Jhon-Crow tested the solution again and reported:

1. **"враги стреляют мимо, промахиваются примерно на 45 градусов. их линия прицела должна совпадать с линией огня."**
   - Translation: Enemies miss, off by about 45 degrees. Their aiming line should match their firing line.
   - Enemy bullets fly ~45 degrees away from where the weapon is visually pointing

Attached game log:
- `game_log_20260122_133325.txt`

### Phase 20: Root Cause Analysis and Fix (2026-01-22)

## Root Cause Analysis (Phase 19-20)

### Issue 14: Enemies Miss by ~45 Degrees - Aim Line Doesn't Match Fire Line

**Root Cause:** The `_get_weapon_forward_direction()` and `_get_bullet_spawn_position()` functions used `_weapon_sprite.global_transform.x.normalized()` to get the weapon's forward direction. However, this approach fails when the enemy model has **negative Y scale** (for aiming left).

When the enemy aims left (angle > π/2 or < -π/2), the code applies vertical flip by setting:
```gdscript
_enemy_model.scale = Vector2(enemy_model_scale, -enemy_model_scale)  # Y is negative
```

This negative Y scale creates a **reflected coordinate system**. In a reflected coordinate system:
- The visual appearance is correct (sprite looks right)
- But `global_transform.x` is **mirrored**, returning the opposite of the expected direction
- This causes bullets to fly ~45-90 degrees off from where the weapon visually points

**Technical Explanation:**

A 2D transform with negative Y scale creates a "mirrored" or "reflected" coordinate system. The `global_transform` property includes scale information, so:

1. When Y scale is positive (aiming right):
   - `global_transform.x` = correct weapon forward direction ✓

2. When Y scale is negative (aiming left):
   - The transform basis vectors are reflected
   - `global_transform.x` = mirrored direction ✗
   - Bullets fly in the wrong direction

**Evidence:** The ~45 degree offset is the angle between the intended direction (toward player) and the mirrored direction. The exact offset depends on the enemy's rotation angle.

**Fix Applied:**

Changed both functions to calculate direction from `_enemy_model.rotation` using `Vector2.from_angle()` instead of using `global_transform.x`:

1. Updated `_get_weapon_forward_direction()`:
```gdscript
# Before (broken with Y flip):
return _weapon_sprite.global_transform.x.normalized()

# After (works correctly with Y flip):
return Vector2.from_angle(_enemy_model.rotation)
```

2. Updated `_get_bullet_spawn_position()`:
```gdscript
# Before (broken with Y flip):
var weapon_global_forward := _weapon_sprite.global_transform.x.normalized()

# After (works correctly with Y flip):
var weapon_forward := Vector2.from_angle(_enemy_model.rotation)
```

**Why This Fix Works:**
- `_enemy_model.rotation` is the angle set by `_update_enemy_model_rotation()` to face the player/target
- `Vector2.from_angle(rotation)` creates a unit vector pointing in that direction
- This approach is **independent of scale**, so it works correctly regardless of Y flip state
- The player uses the same approach: calculating direction from angle to target, not from transform

**Comparison with Player Code:**
The player's `_shoot()` function calculates direction directly:
```gdscript
var shoot_direction := (mouse_pos - global_position).normalized()
```
It does NOT use `global_transform.x`, which explains why the player doesn't have this issue.

## Updated Summary of All Issues and Fixes

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| 1. Enemy smaller than player | Missing 1.3x scale multiplier | Added `enemy_model_scale` export and scale in `_ready()` |
| 2. No walking animation | Old script references + missing animation code | Updated references, added `_update_walk_animation()` |
| 3. Weapon at 90° angle | Competing rotation systems | Removed `_update_weapon_sprite_rotation()` call |
| 4. Bullets from center | Spawning from enemy position | Added `_get_bullet_spawn_position()` using weapon mount |
| 5. Walking backwards | Enemy sprites face opposite direction (PI offset) | Added PI to rotation angle |
| 6. M16 too large | Using 64px sprite vs player's integrated smaller rifle | Changed to `m16_topdown_small.png` (32px) |
| 7. Weapon not visible | Smaller sprite obscured by body parts | Reverted to original larger sprite `m16_rifle_topdown.png` |
| 8. Last Chance not freezing bullets | Branch missing pellet detection fix from main | Merged main branch with latest fixes |
| 9. Bullets not from weapon muzzle | Direction mismatch and execution order issue | Use weapon's actual rotation for muzzle direction; moved rotation update before shooting |
| 10. Bullets STILL not from muzzle | Wrong local forward direction (used -X instead of +X) and Y-flip not handled | Use `global_transform.x` for correct world-space forward direction |
| 11. Player self-damage when shooting upward | C# Bullet properties missing [Export] attribute | Added [Export] to Direction, ShooterId, ShooterPosition in Bullet.cs |
| 12. Enemy bullets not flying in barrel direction | Bullet direction calculated to player, not weapon forward | Added `_get_weapon_forward_direction()` and updated all shooting functions |
| 13. Player STILL self-damaging | `Node.Set()` unreliably maps snake_case to PascalCase C# properties | Added explicit setter methods and use `Call()` instead of `Set()` |
| 14. Enemies miss by ~45 degrees | `global_transform.x` is mirrored when Y scale is negative (aiming left) | Use `Vector2.from_angle(_enemy_model.rotation)` instead of `global_transform.x` |

## Additional Lessons Learned (Phase 19-20)

32. **Negative Scale Affects Transform Basis Vectors:** When using negative scale for sprite flipping, the `global_transform.x` and `global_transform.y` basis vectors are reflected/mirrored. This breaks direction calculations that rely on these vectors.

33. **Use Angle-Based Direction Calculation for Flipped Sprites:** When sprites can be flipped via negative scale, calculate directions using `Vector2.from_angle(rotation)` rather than `global_transform.x`. The rotation property is not affected by scale.

34. **Test All Aim Directions:** Bugs related to coordinate transformations often only manifest in certain directions. Test with enemies facing all directions: up, down, left (with Y flip), right (without Y flip).

35. **Compare Working Code Patterns:** When fixing a bug, compare with similar code that works correctly (e.g., player shooting). The player calculated direction directly from angle, not from transform - this pattern should have been used for enemies too.

36. **Transform Properties Include Scale:** `global_transform.x.normalized()` does NOT just give rotation - it includes scale effects. For direction calculations, either ensure scale is always positive, or use rotation-based calculations that ignore scale.

## Related Files

- [logs/game_log_20260122_125115.txt](./logs/game_log_20260122_125115.txt) - Game log from phase 17 testing showing shooter_id=0 pattern
- [game_log_20260122_133325.txt](./game_log_20260122_133325.txt) - Game log from phase 19 testing showing 45-degree aiming offset
