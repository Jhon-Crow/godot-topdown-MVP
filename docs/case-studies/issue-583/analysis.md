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

## Logs

- `game_log_20260208_193502.txt` - Game log from user testing showing RPG enemies in CastleLevel
