# Case Study: Issue #581 - Sniper Enemy Type

## Overview

**Issue:** [#581 - добавить новый тип врагов - снайпер](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/581)
**Type:** New Feature
**Priority:** Enhancement

## Requirements

### Sniper Enemy Specifications
1. **Weapon:** ASVK with red laser sight
2. **Positioning:** Stays in the farthest cover while maintaining ability to hit potential player positions
3. **Movement:** Does NOT approach the player; stays stationary in cover
4. **Intelligence:** Learns positions where the player was seen or is suspected to be
5. **Accuracy/Spread:**
   - Through 1 wall: 10 degrees spread (5 degrees each side)
   - Through 2 walls: 15 degrees spread
   - Direct line of sight at 2 viewports distance: 0 degrees (perfect accuracy)
   - Direct line of sight at 1 viewport distance: 3 degrees spread
   - Direct line of sight under 1 viewport distance: 5 degrees spread
6. **Rotation:** Very slow turning (same as player with ASVK)

### City Map Specifications
- Large map with uniform box-like buildings
- Contains 2 sniper enemies placed strategically

## Architecture Analysis

### Existing Systems to Leverage

#### Enemy AI System (`scripts/objects/enemy.gd`)
- Complete state machine with 11 states (IDLE, COMBAT, SEEKING_COVER, IN_COVER, etc.)
- Built-in cover detection via 16 raycasts
- Memory system (`EnemyMemory`) for tracking player position
- `PlayerPredictionComponent` for movement prediction
- Weapon configuration via `WeaponConfigComponent`
- Progressive spread system (Issue #516)

#### Player's ASVK Implementation (`Scripts/Weapons/SniperRifle.cs`)
- Hitscan shooting with wall penetration (up to 2 walls)
- Slow rotation (0.04x normal sensitivity = ~25x slower)
- Smoke tracer visual effect
- 12.7x108mm caliber (50 damage per hit)
- 5000px max range

#### Cover System (`scripts/components/cover_component.gd`)
- 16-directional raycast cover detection
- Distance-based scoring
- Hidden position preference weighting

### Design Decisions

1. **Extend existing enemy.gd** rather than creating a separate class
   - Add SNIPER weapon type (enum value 3) to WeaponType
   - Add sniper-specific behavior flags and overrides
   - Minimizes code duplication while leveraging existing tactical AI

2. **Hitscan shooting for sniper enemy** (GDScript implementation)
   - Similar to C# SniperRifle but adapted for enemy AI
   - Wall penetration counting with spread adjustment
   - Smoke tracer spawning via existing effect system

3. **Red laser sight** via Line2D
   - Always visible (not limited to Power Fantasy mode)
   - Red color to differentiate from player's blue laser

4. **Cover selection** biased toward maximum distance from player
   - Override cover scoring to prefer farthest positions
   - Only select cover with line-of-fire to player area

## Implementation Plan

### Phase 1: Weapon Configuration
- Add SNIPER (3) to WeaponType enum
- Add SNIPER config to WeaponConfigComponent
- Configure: slow fire rate, high damage, wall penetration

### Phase 2: Sniper AI Behavior
- Add sniper-specific state processing
- Override cover selection to prefer distant positions
- Implement slow rotation matching player ASVK
- Add hitscan shooting with wall penetration
- Implement distance/wall-based spread system
- Add red laser sight

### Phase 3: City Map
- Create large map with grid-like building layout
- Place 2 sniper enemies in strategic positions
- Setup navigation mesh for pathfinding

## Bug Fixes (Post-Implementation)

### Bug 1: Camera Limited to 4128x3088 (Map is 6000x5000)

**Root Cause**: `Player.tscn` has hardcoded Camera2D limits:
```
limit_right = 4128
limit_bottom = 3088
```
CityLevel is 6000x5000 pixels but never overrides these defaults. CastleLevel (also a large map) solves this by calling `_configure_camera()` which sets limits to +/-10M.

**Fix**: Added `_configure_camera()` to `city_level.gd`, matching CastleLevel's pattern.

### Bug 2: Snipers Never Shoot (Critical)

**Root Cause**: In `enemy.gd:3832`, the `_shoot()` function starts with:
```gdscript
if bullet_scene == null or _player == null:
    return
```
Snipers use hitscan (no projectile scene), so their weapon_config has `bullet_scene_path = ""`. This means `bullet_scene` is never loaded and stays `null`. The function always returns early before reaching the sniper hitscan code at line 3868.

**Evidence from game logs**: SniperEnemy1 and SniperEnemy2 spawn correctly (`Spawned at (5600, 400)`) but only ever do `idle_scan` - never transitioning to firing states. Regular enemies (GuardEnemy, PatrolEnemy) fire normally because they have valid bullet scenes.

**Fix**: Changed the guard to skip the null check for snipers:
```gdscript
if _player == null:
    return
if not _is_sniper and bullet_scene == null:
    return
```

### Bug 3: Buildings Are Solid Blocks (Not Enterable)

**Root Cause**: All 28 buildings in CityLevel were `StaticBody2D` nodes with a single solid `CollisionShape2D` covering the entire footprint (300x300 or 200x200 pixels). Players and enemies cannot enter them.

**Fix**: Replaced each solid building with 4 wall segments (16px thick):
- Doorway side: 60px gap (large) / 50px gap (small) for entry
- Opposite side: 2 shooting slits (20px gaps, too small to walk through)
- Other 2 sides: Solid walls
- Interior: Dark floor for visual contrast

## Round 4: `EnemyMemory.get_position()` Does Not Exist

**Game log:** `game_log_round4_20260207_213620.txt`
**User report:** "снайпер не стреляет и не перемещается. лазера не видно." (sniper does not shoot and does not move. laser is not visible.)

### Evidence from Game Log

- SniperEnemy1 enters COMBAT at 21:36:35, rotation converges perfectly (139.4 degrees matches 139.4 degrees)
- Visibility oscillates between P1:visible and P2:combat_state (player near wall edges)
- ZERO shooting events, ZERO hitscan events, ZERO laser log entries in entire session
- Other enemies (GuardEnemy, PatrolEnemy) fire normally with bullet logs

### Root Cause

In `SniperComponent.process_combat_state()` (line 244) and `process_in_cover_state()` (line 301), the code calls `enemy._memory.get_position()`. However, `EnemyMemory` extends `RefCounted` and has NO `get_position()` method — the correct access is the property `enemy._memory.suspected_position`.

This caused a GDScript runtime error on EVERY frame when `_can_see_player` was false:
```
Invalid call. Nonexistent function 'get_position' in base 'RefCounted (EnemyMemory)'
```

Since snipers are positioned behind walls from the player, `_can_see_player` is false most of the time. The runtime error aborted the `process_combat_state()` function before reaching the shooting code.

When `_can_see_player` briefly flickered to true (player at wall edges), the direct line-of-sight shooting path (line 258-262) was reached, but these frames were too brief for the full shoot chain to succeed.

### Why This Bug Was Introduced

The `SniperComponent` was extracted from `enemy.gd` to reduce file size. During extraction, `enemy._memory.suspected_position` was incorrectly changed to `enemy._memory.get_position()`, possibly from an auto-complete suggestion for the `get_position()` method that exists on `Node2D` but not on `RefCounted`-based classes.

### Fix Applied

- Changed `enemy._memory.get_position()` to `enemy._memory.suspected_position` in 3 locations in `sniper_component.gd`
- Added diagnostic logging to sniper shooting code path for future debugging

### Summary of All Rounds

| Round | Root Cause | Impact |
|-------|-----------|--------|
| Round 1 | `_shoot()` blocking on `bullet_scene == null` for hitscan snipers | Snipers never fired (fixed). Also: camera limits too small (fixed), buildings not enterable (fixed) |
| Round 2 | `_should_shoot_at_target()` blocking snipers with wall checks | Snipers blocked by wall-penetration logic (fixed). Also: laser double-rotation (fixed), cover retreat only under fire (fixed) |
| Round 3 | `_detection_delay_elapsed` never updated in sniper states | Snipers never passed detection delay gate (fixed). Also: laser too faint (fixed) |
| Round 4 | `enemy._memory.get_position()` — nonexistent method on `RefCounted` | Runtime error crashed shoot function every frame when player not visible (fixed) |

## Game Logs

See `logs/` directory for the original game log files from the issue author's testing.

## References

- ASVK rifle: Russian anti-materiel rifle, 12.7x108mm caliber
- Existing player ASVK implementation: `Scripts/Weapons/SniperRifle.cs` (1796 lines)
- Enemy AI base: `scripts/objects/enemy.gd` (3878 lines)
- Weapon configs: `scripts/components/weapon_config_component.gd`
