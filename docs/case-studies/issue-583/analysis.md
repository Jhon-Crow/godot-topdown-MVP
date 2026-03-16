# Case Study: Issue #583 - RPG Enemy Type

## Issue Description

Add a new enemy type armed with an RPG (rocket launcher). The enemy fires one rocket at the player's position, then switches to a PM (Makarov) pistol and fights as a normal enemy. Health: 1-2 (unarmored).

## Timeline

1. **Initial implementation** (commits f410f5d..012fb54): Added RPG and PM weapon configs (type 4 and 5), RPG rocket projectile, weapon switching logic in enemy AI, and placed 2 RPG enemies in CastleLevel.
2. **User feedback** (PR #599 comment by Jhon-Crow, 2026-02-08): "Enemy didn't get added. Instead of adding to Castle, add the new enemy to the Polygon (TestTier) level."
3. **Fix** (current commit): Moved RPG enemies from CastleLevel to TestTier (Polygon) level.

## Root Cause Analysis

The RPG enemies were technically present in CastleLevel (confirmed by game log showing `RpgEnemy1` and `RpgEnemy2` spawning at positions (2000,300) and (4200,1050)). However, the user's feedback indicates they want the enemies on the TestTier (Polygon) level instead, which is the primary testing/development level.

### Evidence from Game Log

From `game_log_20260208_193502.txt`:
- Line 351: `[CastleLevel] Child 'RpgEnemy1': script=true, has_died_signal=true`
- Line 352: `[CastleLevel] Child 'RpgEnemy2': script=true, has_died_signal=true`
- Line 412: `[RpgEnemy1] Spawned at (2000, 300), hp: 2, behavior: GUARD`
- Line 416: `[RpgEnemy2] Spawned at (4200, 1050), hp: 1, behavior: GUARD`
- Lines 852, 990: RpgEnemy2 entered COMBAT state and fired (as GUNSHOT sound)

The enemies spawned and functioned in CastleLevel, but the user requested placement on the Polygon level.

## Solution

1. Removed `RpgEnemy1` and `RpgEnemy2` from `CastleLevel.tscn`
2. Added `RpgEnemy1` (position: 3700, 1400) and `RpgEnemy2` (position: 2000, 2200) to `TestTier.tscn`
3. Updated enemy count labels and test assertions accordingly

### Placement Strategy

- **RpgEnemy1** at (3700, 1400): In the StrategicZone area (right side), near high-value targets
- **RpgEnemy2** at (2000, 2200): In CombatZone3 area (lower-center), providing variety in enemy engagement

## Files Changed

- `scenes/levels/CastleLevel.tscn` - Removed RPG enemy nodes
- `scenes/levels/TestTier.tscn` - Added RPG enemy nodes, updated enemy count label
- `scripts/levels/test_tier.gd` - Updated enemy count comment
- `tests/unit/test_level_scripts.gd` - Updated mock enemy counts and test assertions

## Second Feedback (2026-02-09)

User reported "RPG wasn't added" and provided a new game log. However, analysis of `game_log_20260209_110330.txt` confirms:

- RpgEnemy1 spawned at (3700, 1400) in TestTier ✅
- RpgEnemy2 spawned at (2000, 2200) in TestTier ✅
- RpgEnemy1 entered COMBAT state and fired (GUNSHOT range=2500 = RPG loudness) ✅
- After first shot, RpgEnemy1 subsequent shots used range=1469 (PM loudness) = weapon switch worked ✅
- RpgEnemy2 same pattern ✅

The RPG enemies ARE present and functioning. The user may have been testing with an older cached build. The weapon switching to PM is confirmed working by the different sound propagation ranges in the log.

## Merge Conflicts Resolved (2026-03-16)

Merged latest `main` branch which included changes from issues #858, #675, #934, #954, #883, #921, #636.
Resolved conflicts:
- `enemy.gd`: integrated RPG no-lead-prediction flag into new aggression logic; preserved RPG no-shell-sound into new sound cooldown logic; kept both `_switch_to_secondary_weapon` (Issue #583) and `_setup_enemy_flashlight` (Issue #824)
- `test_enemy.gd`: kept both RPG tests and new Issue #883/#921 tests
- `test_level_scripts.gd`: kept PM ammo multiplier from main + updated enemy count to 12

Also compacted `_switch_to_secondary_weapon` from 20→10 lines to stay under the 5000-line architecture limit.

## Third Feedback (2026-03-17)

User reported "новый враг должен появляться на карте Полигон / сейчас там все с m16" (new enemy should appear on the Polygon map / currently all have M16). Provided `game_log_20260317_010617.txt`.

### Analysis of game_log_20260317_010617.txt

The log confirms RPG enemies ARE spawning and functioning in TestTier:
- `[RpgEnemy1] Spawned at (3700, 1400), hp: 1, behavior: GUARD` ✅
- `[RpgEnemy2] Spawned at (2000, 2200), hp: 1, behavior: GUARD` ✅
- `Sound emitted: type=GUNSHOT, source=ENEMY (RpgEnemy1), range=2500` = RPG shot (weapon_loudness=2500) ✅
- `Sound emitted: type=GUNSHOT, source=ENEMY (RpgEnemy1), range=1469` = PM shot after switch ✅
- RpgEnemy2 same pattern ✅

### Root Cause of "everything is M16" complaint

Despite the RPG enemy logic working correctly (firing rockets, switching to PM), the **enemy weapon sprite was still showing M16**. This is because:

1. The base `Enemy.tscn` scene has `WeaponSprite` texture set to `m16_rifle_topdown.png` by default.
2. In `_configure_weapon_type()`, the sprite is only updated when `sprite_path != ""`.
3. The RPG weapon config (type 4) had `"sprite_path": ""` — leaving the default M16 sprite unchanged.

### Fix Applied

1. Created `assets/sprites/weapons/rpg_topdown.png` — a 72×18 pixel top-down RPG-7 sprite (matching ak_gl_topdown.png dimensions), showing the rocket launcher tube, warhead, pistol grip and rear exhaust bell.
2. Updated `WeaponConfigComponent` RPG entry: `"sprite_path": "res://assets/sprites/weapons/rpg_topdown.png"`.

This ensures RPG enemies visually display the rocket launcher weapon instead of the M16 rifle.

## Logs

- `game_log_20260208_193502.txt` - Game log from user testing showing RPG enemies in CastleLevel (wrong level)
- `game_log_20260209_110330.txt` - Game log confirming RPG enemies working correctly in TestTier
- `game_log_20260317_010617.txt` - Game log confirming RPG enemies in TestTier but visual sprite was M16 (now fixed)
