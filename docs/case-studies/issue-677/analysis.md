# Case Study: Issue #677 - Homing Bullets Active Item

## Issue Summary

**Title:** добавь активный предмет - пули с наведением (Add active item - homing bullets)
**Author:** Jhon-Crow
**Repository:** Jhon-Crow/godot-topdown-MVP

### Requirements (translated from Russian)

When activated with Space key, player's bullets start steering toward the nearest enemy:
- Bullets can change trajectory up to **110 degrees** in each direction
- **6 charges** per battle
- Effect lasts **1 second**

## Existing Systems Analysis

### Active Item System (`scripts/autoload/active_item_manager.gd`)
- Autoload singleton managing item selection via `ActiveItemType` enum
- Currently has: `NONE` (0), `FLASHLIGHT` (1)
- Data dictionary with name, icon_path, description
- Signals: `active_item_changed(new_type)`
- Armory UI integration for selection

### Bullet System (`scripts/projectiles/bullet.gd`)
- Area2D-based projectile with constant speed (2500 px/s)
- Direction-based movement in `_physics_process()`
- Features: ricochet, penetration, trail effects, damage multipliers
- Shooter tracking via `shooter_id`
- Player bullet detection via `_is_player_bullet()`

### Player System (`scripts/characters/player.gd`)
- Shoots bullets toward mouse cursor
- `_shoot()` creates bullet instances with direction, speed, shooter_id
- Space key mapped to `flashlight_toggle` input action
- Flashlight active item is handled via `_handle_flashlight_input()`
- Active item initialization checks `ActiveItemManager`

### Enemy System (`scripts/objects/enemy.gd`)
- Enemies are in the `"enemies"` group
- Have `is_alive()` method for death checking
- Complex AI with multiple tactical states

## Solution Design

### Approach: Steering-based homing with timer

The homing system modifies bullet behavior during `_physics_process()` to steer toward the nearest enemy. This approach:
1. Adds a `HOMING_BULLETS` type to `ActiveItemManager`
2. Adds homing logic to `bullet.gd` (activated by player.gd when active item is equipped)
3. Adds activation/charge management to `player.gd`

### Key Design Decisions

1. **Steering method:** Use velocity steering (like KidsCanCode recipe) - calculate desired direction to nearest enemy, apply steering force to gradually turn the bullet. This produces natural-looking curved trajectories.

2. **110° max turn:** Limit total accumulated turn angle to 110° from original firing direction. This prevents bullets from doing U-turns.

3. **Nearest enemy detection:** Each frame, the bullet finds the nearest alive enemy from the `"enemies"` group.

4. **1-second duration:** Homing bullets activate for 1 second after pressing Space. During this time, ALL player bullets get homing capability.

5. **6 charges per battle:** Track charges in player.gd, decrement on Space press.

6. **Space key sharing:** Space is already used for flashlight. Since active items are mutually exclusive (you pick one in the armory), this is not a conflict.

## Implementation Plan

### Files to modify:
1. `scripts/autoload/active_item_manager.gd` - Add `HOMING_BULLETS` type
2. `scripts/projectiles/bullet.gd` - Add homing steering logic
3. `scripts/characters/player.gd` - Add homing activation, charge management
4. `tests/unit/test_active_item_manager.gd` - Add tests for new type
5. New: `tests/unit/test_homing_bullets.gd` - Unit tests for homing logic

### References
- [Homing Missile - Godot 4 Recipes](https://kidscancode.org/godot_recipes/4.x/ai/homing_missile/index.html)
- [Godot PerfBullets plugin](https://github.com/Moonzel/Godot-PerfBullets) - has homing weight parameter
- [IranosMorloy/godot-homing-missile](https://github.com/IranosMorloy/godot-homing-missile)
