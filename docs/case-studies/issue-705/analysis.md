# Case Study: Issue #705 - Fix AK

## Timeline

- **2026-02-09 03:57**: Game log captured showing AK (AKGL) weapon usage on Power Fantasy difficulty
- **2026-02-09**: Issue #705 filed reporting two bugs with the AK weapon

## Issue Description (translated from Russian)

1. On Power Fantasy difficulty, the laser should appear (like all other weapons have)
2. No spread after the first 2 bullets

## Root Cause Analysis

### Bug 1: Missing Laser Sight on Power Fantasy Difficulty

**Root cause**: PR #703 (fixing issue #702) intentionally removed the laser sight from the AK weapon entirely, changing the weapon description to "No laser sight" and removing all laser-related code. However, this was too aggressive — while the AK doesn't have a laser by default, in Power Fantasy mode all weapons should display a blue laser sight. Other weapons like MiniUzi and AssaultRifle correctly implement this by checking `DifficultyManager.should_force_blue_laser_sight()` in their `_Ready()` method.

**Evidence from game log**: The log confirms Power Fantasy mode is active (`[PowerFantasy] Starting power fantasy effect`), the AK is equipped (`[Player.Weapon] Equipped AKGL`), but no laser-related log entries appear for the AKGL.

**Fix**: Added Power Fantasy laser sight support to AKGL.cs, following the same pattern used by MiniUzi.cs:
- Added `_laserSight`, `_laserGlow`, `_laserSightEnabled`, `_laserSightColor` fields
- In `_Ready()`, check `should_force_blue_laser_sight()` and create laser if true
- In `_Process()`, update laser sight position each frame
- Added `CreateLaserSight()` and `UpdateLaserSight()` methods with raycast-based obstacle detection and glow effect

### Bug 2: No Spread After First 2 Bullets

**Root cause**: The spread threshold comparison used strict greater-than (`>`) instead of greater-than-or-equal (`>=`). With `SpreadThreshold = 2` and `_shotCount` being 0-based (incremented AFTER `ApplySpread` returns), the effective behavior was:

- Shot 1: `_shotCount = 0`, checks `0 > 2` → false (no progressive spread)
- Shot 2: `_shotCount = 1`, checks `1 > 2` → false (no progressive spread)
- Shot 3: `_shotCount = 2`, checks `2 > 2` → false (no progressive spread!)
- Shot 4: `_shotCount = 3`, checks `3 > 2` → true (progressive spread starts)

This means progressive spread didn't begin until the 4th shot, not the 3rd as intended by `SpreadThreshold = 2`.

**Fix**: Changed `_shotCount > SpreadThreshold` to `_shotCount >= SpreadThreshold` in both `ApplySpread()` and `TriggerScreenShake()`, so progressive spread now correctly begins at shot 3 (after the first 2 accurate shots).

## Weapon Comparison Reference

| Property | M16/AR | AK GL | Silenced Pistol | Mini UZI |
|----------|--------|-------|-----------------|----------|
| Default Laser | Red | None | Green | None |
| Power Fantasy Laser | Blue | Blue (fixed) | Blue | Blue |
| Spread Threshold | 3 shots | 2 shots | N/A | 0 shots |
| Max Recoil | 5° | 6° | 10° | 8° |

## Files Modified

- `Scripts/Weapons/AKGL.cs`: Added Power Fantasy laser sight, fixed spread threshold comparison

## Data Files

- `game_log_20260209_035702.txt`: Original game log from issue reporter
