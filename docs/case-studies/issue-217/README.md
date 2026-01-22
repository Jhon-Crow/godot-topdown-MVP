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
