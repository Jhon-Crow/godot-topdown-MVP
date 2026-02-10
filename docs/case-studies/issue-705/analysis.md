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

### Bug 2: No Spread Applied to Bullets At All

**User feedback (2026-02-09 10:01)**: "прицел скачет, но пули летят ровно" (the sight jumps, but bullets fly straight - there's still no spread)

**Evidence from game log (game_log_20260209_100032.txt)**: Bullet positions at hit time show minimal variation:
```
bullet_pos=(504.48782, 354.08575)
bullet_pos=(504.53595, 354.8273)
bullet_pos=(504.5749, 355.4412)  <- all converge to nearly identical positions
```
Despite firing 30+ bullets, the Y coordinate converges to ~355.44 and stays there, confirming bullets fly to the same point.

**Root cause**: The `ApplySpread()` method had a fundamental bug - it calculated random spread values but only used them to update `_recoilOffset` for the NEXT shot's laser position. The actual bullet direction for the CURRENT shot received only the accumulated `_recoilOffset`, not any per-shot random spread.

Original code flow:
1. `result = direction.Rotated(_recoilOffset)` - applies accumulated recoil
2. Calculate `spreadRadians` and random `recoilAmount`
3. `_recoilOffset += recoilDirection * recoilAmount * 0.5f` - only updates offset for NEXT shot
4. Return `result` - bullet fires with NO random spread, just accumulated offset

This means:
- The laser sight would visually "jump" because `_recoilOffset` changes each frame
- But bullets would all fly to nearly the same point since they only used the accumulated offset, not individual random spread per shot

**Fix**: Modified `ApplySpread()` to apply random spread to the bullet direction for THIS shot:
```csharp
// Generate random spread for THIS shot (Issue #705 fix)
float randomSpread = (float)GD.RandRange(-spreadRadians, spreadRadians);
result = result.Rotated(randomSpread);
```

Now each bullet gets random deviation within the spread angle, creating visible spread patterns.

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

- `game_log_20260209_035702.txt`: Original game log from issue reporter (laser sight missing)
- `game_log_20260209_100032.txt`: Second game log showing laser is now visible but bullets still fly straight
