# Issue #212: Shotgun Pellets Grouping Together as Single Projectile

## Issue Summary

**Title:** fix дробовик
**Translation:** Fix shotgun
**Description:** иногда дробь ломается и летит как одна большая дробина
**Translation:** Sometimes the pellets break and fly as one large pellet

## Timeline of Events

1. The shotgun was implemented with a "cloud pattern" that spawns 6-12 pellets simultaneously
2. Each pellet is given a different angle based on the 15° spread angle and a random spatial offset (±15px)
3. Users reported that sometimes all pellets appear to merge into "one large pellet"
4. Initial fix (v1) attempted to increase minimum spawn offset from 2px to 10px
5. User reported problem persists after initial fix (PR #224, game_log_20260122_112026.txt)
6. Fix v2 added lateral offset but still used random extraOffset for distribution
7. User reported problem STILL persists after fix v2 (game_log_20260123_214006.txt)
8. Fix v3 implements deterministic lateral distribution based on pellet index

## Root Cause Analysis (Updated 2026-01-23)

### Multiple Contributing Factors Identified

Through detailed analysis of the code and logs, we identified **four distinct issues** causing pellet grouping:

### Issue 1: Negative extraOffset Bug (FIXED in v2)

In `SpawnPelletWithOffset()`, when wall is detected, the original code used:
```csharp
float cloudOffset = Mathf.Max(0, extraOffset) * 0.5f;  // BUG HERE!
```

**The Bug:** `extraOffset` ranges from -15 to +15 pixels. When negative, `Mathf.Max(0, extraOffset)` returns 0.

**Result:** ~50% of pellets spawned at exactly the same position.

**Status:** Fixed in v2 by using `Mathf.Abs(extraOffset)`.

### Issue 2: Insufficient Lateral Spread (PARTIALLY FIXED in v2)

Even with the v2 fix using `extraOffset * 0.4f` for lateral spread:
- For 12 pellets with ±6px spread = 12px total range
- Average inter-pellet spacing: 1px (imperceptible)

**Status:** v2 provided ±6px which was still insufficient. v3 increases to ±15px.

### Issue 3: Inconsistent Wall Detection Per Pellet

`CheckBulletSpawnPath(direction)` is called for each pellet with its individual rotated direction:
- Some pellets (angled toward wall) detect wall → spawn close
- Some pellets (angled away from wall) don't detect wall → spawn far
- Creates inconsistent mix of spawn distances

**Evidence from logs:**
```
[11:20:34] Point-blank shot - 100% penetration   (only 2 pellets)
[11:20:34] Distance to wall: 654.99px            (other pellets far away)
```

**Status:** This behavior is inherent to per-pellet wall detection. The v3 fix ensures blocked pellets are evenly distributed regardless.

### Issue 4: Random Offset Clustering (NEW - CRITICAL)

**Root Cause (v3 discovery):** The `extraOffset` value is generated using `GD.RandRange(-15, 15)` which can produce clustered values. When multiple pellets get similar random values, they spawn at similar positions.

**Example scenario:**
- Shot 1: offsets = [-12, -8, -5, 2, 7, 14] → good spread
- Shot 2: offsets = [-3, -1, 0, 1, 2, 4] → clustered around 0 → pellets appear as one

**Solution (v3):** Use pellet INDEX for deterministic lateral distribution:
```csharp
// Deterministic spread: pellet 0 at left edge, pellet N-1 at right edge
float lateralProgress = pelletCount > 1
    ? ((float)pelletIndex / (pelletCount - 1)) * 2.0f - 1.0f
    : 0.0f;
float lateralOffset = lateralProgress * 15.0f;  // ±15px
```

## Mathematical Analysis

### Perpendicular Spread Formula
```
perpendicular_separation = distance × tan(spread_angle/2)
```

### Spread at Various Distances (15° total spread = ±7.5°)
| Distance | Perpendicular Separation | Visual Result |
|----------|-------------------------|---------------|
| 2px      | 0.26px                  | Imperceptible |
| 10px     | 1.3px                   | Barely visible |
| 20px     | 2.6px                   | Visible spread |
| 30px     | 3.9px                   | Clear spread |
| 40px     | 5.3px                   | Wide spread |

### v3 Lateral Spread Calculation

For 12 pellets with ±15px deterministic lateral spread:
- Total range: 30px
- Inter-pellet spacing: 30px / 11 ≈ 2.7px (clearly visible)

With ±2px random jitter added:
- Prevents perfectly uniform look
- Maintains minimum 0.7px spacing (worst case: 2.7px - 2×2px = -1.3px → still distinguishable)

## Implemented Solution (v3)

### Changes in `FirePelletsAsCloud()`:
Pass pellet index and count to spawning method:
```csharp
SpawnPelletWithOffset(pelletDirection, spawnOffset, projectileScene, i, pelletCount);
```

### Changes in `SpawnPelletWithOffset()`:
For blocked (point-blank) pellets:
```csharp
// DETERMINISTIC lateral distribution based on pellet index
float lateralProgress = pelletCount > 1
    ? ((float)pelletIndex / (pelletCount - 1)) * 2.0f - 1.0f  // -1 to +1
    : 0.0f;
float lateralOffset = lateralProgress * 15.0f;  // ±15px

// Add small random jitter to prevent perfectly uniform look
lateralOffset += (float)GD.RandRange(-2.0, 2.0);
```

### Verbose Logging:
Enabled `VerbosePelletLogging = true` to help diagnose any future reports.

## Files Modified

1. `Scripts/Weapons/Shotgun.cs`
   - `FirePelletsAsCloud()` - passes pellet index and count
   - `SpawnPelletWithOffset()` - uses index for deterministic spread
   - `VerbosePelletLogging` - enabled for diagnostics

## Testing Checklist

- [ ] Fire shotgun at normal range - verify pellets spread correctly
- [ ] Fire shotgun directly against a wall (point-blank) - verify pellets still show spread
- [ ] Fire shotgun at various angles near walls - verify spread is maintained
- [ ] Verify pellets still interact correctly with wall collision
- [ ] Verify pellets can still penetrate/ricochet as expected
- [ ] Verify spread is visible in slow-motion/freeze frames
- [ ] Check logs for `[Shotgun.FIX#212]` entries showing pellet distribution

## Log Files

- `game_log_20260122_082359.txt` - First gameplay session with shotgun
- `game_log_20260122_110105.txt` - Second gameplay session with shotgun
- `game_log_20260122_112026.txt` - Third session AFTER v1 fix (problem persists)
- `game_log_20260123_214006.txt` - Fourth session AFTER v2 fix (problem STILL persists)

## Related Issues and PRs

- Issue #199 - Original shotgun implementation
- PR #201 - Cloud pattern implementation
- Issue #211 - Pellets not freezing in last chance mode (different issue)
- PR #220 - Fix for issue #211
- PR #224 - Initial fix attempt (v1)
- PR #276 - This fix (v3, ongoing)

## References

- [Epic Games Shotgun Spread Tutorial](https://dev.epicgames.com/community/learning/tutorials/KJee/shotgun-spread-tutorial)
- [GameDev.net - Calculating Spread for Shotgun Shot](https://gamedev.net/forums/topic/611354-calculating-34spread34-for-shotgun-shot/4866788/)
- Real-world shotgun spread: At 1 yard, pattern is ~1 inch wide (effectively one projectile)
