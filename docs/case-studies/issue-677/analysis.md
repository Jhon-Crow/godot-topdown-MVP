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

## Bug Investigation (2026-02-09)

### Problem Report
The repository owner (Jhon-Crow) reported that the homing bullets feature "doesn't work" when tested
in an exported build (Windows, Godot 4.3-stable). A game log was provided:
`logs/game_log_20260209_013835.txt`

### Timeline of Events (from game log)
1. **01:38:35** — Game starts on BuildingLevel
2. **01:38:36** — `[Player.Flashlight] No flashlight selected in ActiveItemManager` — Player init runs, no active item
3. **01:38:39** — Player opens Armory menu
4. **01:38:43** — `[ActiveItemManager] Active item changed from None to Homing Bullets` — Homing Bullets selected
5. **01:38:43** — Scene reloads (BuildingLevel). Player re-initializes.
6. **01:38:43** — `[Player.Flashlight] No flashlight selected in ActiveItemManager` — Flashlight check runs (correctly returns false)
7. **01:38:43** — **NO homing initialization log appears** — `_init_homing_bullets()` silently failed
8. **01:38:48–01:39:34** — Player shoots bullets, none show homing behavior

### Root Cause Analysis
The `_init_homing_bullets()` function had **silent guard returns** — it would exit without logging if:
- `active_item_manager` was null
- `has_method("has_homing_bullets")` returned false
- `has_homing_bullets()` returned false

Unlike `_init_flashlight()` which logged at every guard point, `_init_homing_bullets()` had no diagnostic
logging, making it impossible to tell which guard was failing.

The most likely failure point was the `has_method("has_homing_bullets")` guard. In Godot exported builds,
method availability can differ from the editor. Additionally, the function was more fragile than necessary
since `_init_flashlight()` in the same codebase does not use a `has_method` guard for `has_flashlight()`.

### Additional Issues Found
1. **Missing armory icon** — `icon_path` was empty string `""`, showing "?" placeholder
2. **Missing activation sound** — No audio feedback when pressing Space to activate
3. **No diagnostic logging** — Silent failures made debugging impossible

### Fix Applied
1. Added diagnostic logging at every guard point in `_init_homing_bullets()` (matching flashlight pattern)
2. Added homing bullets icon: `res://assets/sprites/weapons/homing_bullets_icon.png` (64x48 RGBA PNG)
3. Added sci-fi activation sound: `res://assets/audio/homing_activation.wav`
4. Added `_setup_homing_audio()` and `_play_homing_sound()` to player.gd
5. Sound plays when Space is pressed to activate homing effect
