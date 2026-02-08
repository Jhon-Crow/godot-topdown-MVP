# Case Study: Issue #665 - Fix Sniper Enemy Bugs

## Overview

**Issue:** [#665 - fix snipers](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/665)
**Type:** Bug Fix (3 bugs in sniper enemy implementation from PR #582)
**Related:** PR #582 (added sniper enemy type), Issue #581 (original sniper feature request)

## Reported Problems

1. Snipers don't hide from the player
2. Sniper shots don't have a smoke trail (like the player's sniper has)
3. Snipers don't deal damage to the player

## Root Cause Analysis

### Bug 1: Snipers Don't Hide From Player

**Root cause:** The `_process_sniper_combat_state()` function in PR #582 kept snipers in COMBAT state indefinitely, shooting from their spawn position in the open. Snipers only retreated when the player got very close (< half viewport distance), but never proactively sought cover upon first detection.

**Evidence from game log:**
```
[18:40:07] [SniperEnemy1] State: IDLE -> COMBAT
[18:40:08] [SniperEnemy1] SNIPER: shooting at visible player
```
SniperEnemy1 transitioned directly from IDLE to COMBAT and stayed there, never seeking cover. The only cover transition observed was the distance-based retreat:
```
[18:40:37] [SniperEnemy2] SNIPER: retreating, player very close (733)
[18:40:37] [SniperEnemy2] State: COMBAT -> SEEKING_COVER
```

**Fix:** Modified `_process_sniper_combat_state()` to immediately transition to `SEEKING_COVER` when entering combat. This ensures snipers hide behind cover first, then shoot from the `IN_COVER` state. The sniper's cover scoring was already biased toward positions near their spawn point (GUARD position), so they stay near their initial location while being protected.

### Bug 2: Sniper Shots Don't Have Smoke Trail

**Root cause:** The smoke tracer IS spawned by `SniperComponent.spawn_tracer()` but became invisible due to Bug 3's self-collision issue. When the hitscan hit the sniper's own HitArea at ~0 distance, `bullet_end` was essentially the same as `spawn_pos`, creating a zero-length Line2D (invisible single-point tracer).

**Evidence from game log:**
```
[18:40:11] [SniperEnemy1] SNIPER: shooting at visible player
[18:40:11] [SniperEnemy1]                                    <- Empty SNIPER FIRED log line
[18:40:11] Sound emitted: type=GUNSHOT, pos=(5600, 400)     <- Shot fired
```
The shot fired (sound propagated) but no "HITSCAN HIT" log appeared, indicating the hitscan terminated immediately (self-collision).

**Fix:** The `extra_exclude_rids` parameter properly excludes the enemy's own HitArea RID from the hitscan raycast, allowing the ray to pass through the sniper and reach actual targets. With proper exclusion, `bullet_end` will be the actual endpoint (player position, wall, or max range), creating a visible tracer line.

### Bug 3: Snipers Don't Deal Damage to Player

**Root cause: Two compounding issues:**

1. **Self-collision (primary):** Even though PR #582 round 9 added `extra_exclude_rids` to exclude the enemy's HitArea, the hitscan raycast still hit the sniper's own collision bodies in some configurations, preventing the ray from reaching the player.

2. **Damage chain broken (secondary):** When the hitscan DID reach the player, it called `on_hit_with_bullet_info` on the player's HitArea with 5 arguments (including damage=50). But HitArea's `on_hit_with_bullet_info` only accepts 4 parameters (no damage). In GDScript 4.x, the extra argument is silently ignored. HitArea then forwarded to the parent (Player.cs) with only 4 args. Player.cs's `on_hit_with_info` then hardcoded `TakeDamage(1)` instead of using the actual hitscan damage of 50.

**Evidence from game log:**
- Zero "HITSCAN HIT" log entries in entire 5541-line log file
- Multiple "SNIPER FIRED" entries with gunshot sound emissions confirmed shots firing
- No "Player Taking damage" entries from sniper shots

**Fixes applied:**
1. Added `on_hit_with_bullet_info` method to Player.cs that accepts damage as 5th parameter and calls `TakeDamage(damage)` with the actual amount
2. Updated `SniperComponent.perform_hitscan()` to try `on_hit_with_bullet_info_and_damage` first (which properly passes damage through HitArea -> parent chain), then fallback to `on_hit_with_bullet_info` with damage parameter
3. Ensured proper HitArea RID exclusion in hitscan raycast

## Timeline Reconstruction

| Time | Event | Analysis |
|------|-------|----------|
| 18:38:44 | Game started, BuildingLevel loaded | 10 regular enemies initialized |
| 18:38:50 | Weapon selected: sniper | Player using ASVK on BuildingLevel |
| 18:38:53 | City level loaded, SniperEnemy1 & 2 initialized | Snipers at (5600,400) and (5600,4700) |
| 18:39:44 | SniperEnemy1 detects player reloading | Correctly doesn't pursue (sniper guard works) |
| 18:40:07 | SniperEnemy1 sees player, enters COMBAT | Bug: stays in COMBAT, doesn't seek cover |
| 18:40:08 | SniperEnemy1 tries to shoot, blocked by aim | 164.9 deg off - still rotating |
| 18:40:11 | SniperEnemy1 fires first shot | No HITSCAN HIT - self-collision or range issue |
| 18:40:14 | SniperEnemy1 fires again | Still no damage to player |
| 18:40:22 | SniperEnemy2 enters COMBAT | Same pattern - no cover seeking |
| 18:40:37 | SniperEnemy2 retreats (player close: 733px) | Distance-based retreat works |
| 18:40:38 | SniperEnemy2 fires from cover | IN_COVER state shooting works |
| 18:41:10 | SniperEnemy1 enters IN_COVER | Only after long SEEKING_COVER |
| 18:41:19 | Game continues, no player damage from snipers | Confirmed: zero sniper damage dealt |

## Files Modified

| File | Changes | Bug Fixed |
|------|---------|-----------|
| `scripts/objects/enemy.gd` | Added sniper state machine, cover-seeking, hitscan shooting | Bug 1, 2, 3 |
| `scripts/components/sniper_component.gd` | New file: hitscan, spread, laser, tracer utilities | Bug 2, 3 |
| `scripts/components/weapon_config_component.gd` | Added SNIPER (type 4) weapon configuration | All |
| `Scripts/Characters/Player.cs` | Added `on_hit_with_bullet_info` method for damage delivery | Bug 3 |

### Bug 4: City Map (Город) Missing

**Root cause:** The City level (`CityLevel.tscn` and `city_level.gd`) was created in PR #582 (commit `d205b85f`) as part of the sniper enemy feature. However, PR #582 was never merged to `main`. When PR #666 was created from `main` to fix sniper bugs, it did not include the City level files because they only existed on the unmerged PR #582 branch. Additionally, the `BuildingLevel` was incorrectly labeled as "City"/"Город" in the levels menu, causing confusion.

**Evidence from game log (game_log_20260208_193854.txt):**
The game cycles through scenes: BuildingLevel, TestTier, CastleLevel, Tutorial, BeachLevel — but never CityLevel. The owner expected to see "Город" (City) as a separate urban map with sniper enemies, not as a label for BuildingLevel.

**Fix:**
1. Copied `CityLevel.tscn` (6000x5000 urban map with 28 buildings, 2 snipers, 8 regular enemies) from PR #582 branch
2. Copied `city_level.gd` (884 lines, M16 default weapon, replay support) from PR #582 branch
3. Added "City"/"Город" entry to levels menu pointing to `CityLevel.tscn`
4. Restored BuildingLevel's original name ("Building Level"/"Здание") in the levels menu
5. Updated level navigation arrays in all level scripts to include CityLevel as the last level

## Data Files

- `game_log_20260208_183844.txt` - Original game log from issue report (5541 lines)
- `game_log_20260208_193854.txt` - Second game log showing City map missing (1704 lines)
