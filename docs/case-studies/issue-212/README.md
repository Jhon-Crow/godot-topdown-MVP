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
4. Initial fix attempted to increase minimum spawn offset from 2px to 10px
5. User reported problem persists after initial fix (PR #224, game_log_20260122_112026.txt)

## Root Cause Analysis (Updated 2026-01-22)

### Multiple Contributing Factors Identified

Through detailed analysis of the code and logs, we identified **three distinct issues** causing pellet grouping:

### Issue 1: Negative extraOffset Bug (CRITICAL)

In `SpawnPelletWithOffset()`, when wall is detected:

```csharp
float minSpawnOffset = 10.0f;
float cloudOffset = Mathf.Max(0, extraOffset) * 0.5f;  // BUG HERE!
spawnPosition = GlobalPosition + direction * (minSpawnOffset + cloudOffset);
```

**The Bug:** `extraOffset` ranges from -15 to +15 pixels (from `GD.RandRange(-MaxSpawnOffset, MaxSpawnOffset)`).
When `extraOffset` is negative, `Mathf.Max(0, extraOffset)` returns 0, so `cloudOffset = 0`.

**Result:** Approximately 50% of pellets (those with negative extraOffset) spawn at exactly 10px,
causing them to cluster at the same position.

### Issue 2: Insufficient Minimum Spawn Distance

Even with the 10px minimum, the perpendicular separation is insufficient:
- At 10px with 7.5° spread: `10 * tan(7.5°) ≈ 1.3px` edge-to-edge separation
- At 17.5px with 7.5° spread: `17.5 * tan(7.5°) ≈ 2.3px` edge-to-edge separation

For 6-12 pellets, this creates a tight cluster that appears as "one large pellet".

### Issue 3: Inconsistent Wall Detection Per Pellet

The `CheckBulletSpawnPath(direction)` is called for each pellet with its **individual rotated direction**.
This means:
- Some pellets (those angled toward the wall) detect the wall and spawn close
- Some pellets (those angled away from wall) don't detect the wall and spawn far
- This creates an inconsistent mix of spawn distances

**Evidence from logs:**
```
[11:20:34] Point-blank shot - 100% penetration   (only 2 pellets)
[11:20:34] Distance to wall: 654.99px            (other pellets far away)
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

### Recommended Minimum Distance

For visually distinct pellets, we need at least 2-3px separation between adjacent pellets.
With 6 pellets across 15° cone:
- Inter-pellet angle ≈ 2.5°
- For 2px separation: `distance = 2 / tan(2.5°) ≈ 46px`

However, this conflicts with point-blank gameplay. A compromise:
- Minimum distance of 25px gives ~3.3px edge spread
- Still allows pellets to hit wall shortly after spawn

## Proposed Solution (v2)

### Fix 1: Use absolute value for extraOffset in blocked case
```csharp
if (isBlocked)
{
    float minSpawnOffset = 25.0f;  // Increased from 10px
    // Use absolute value to spread in both directions from minimum
    float cloudOffset = Mathf.Abs(extraOffset) * 0.5f;
    spawnPosition = GlobalPosition + direction * (minSpawnOffset + cloudOffset);
}
```

### Fix 2: Add lateral offset for visual spread
Since angular spread alone isn't enough at close range, add explicit lateral offset:
```csharp
if (isBlocked)
{
    float minSpawnOffset = 20.0f;
    // Add perpendicular offset to create visual spread at close range
    Vector2 perpendicular = new Vector2(-direction.Y, direction.X);
    float lateralOffset = extraOffset * 0.3f;  // ±4.5px lateral
    spawnPosition = GlobalPosition + direction * minSpawnOffset + perpendicular * lateralOffset;
}
```

## Files to Modify

1. `Scripts/Weapons/Shotgun.cs`
   - `SpawnPelletWithOffset()` method - lines 1056-1108

## Testing Checklist

- [ ] Fire shotgun at normal range - verify pellets spread correctly
- [ ] Fire shotgun directly against a wall (point-blank) - verify pellets still show spread
- [ ] Fire shotgun at various angles near walls - verify spread is maintained
- [ ] Verify pellets still interact correctly with wall collision
- [ ] Verify pellets can still penetrate/ricochet as expected
- [ ] Verify spread is visible in slow-motion/freeze frames

## Log Files

- `game_log_20260122_082359.txt` - First gameplay session with shotgun
- `game_log_20260122_110105.txt` - Second gameplay session with shotgun
- `game_log_20260122_112026.txt` - Third session AFTER initial fix (problem persists)

## Related Issues and PRs

- Issue #199 - Original shotgun implementation
- PR #201 - Cloud pattern implementation
- Issue #211 - Pellets not freezing in last chance mode (different issue)
- PR #220 - Fix for issue #211
- PR #224 - This fix (ongoing)

## References

- [Epic Games Shotgun Spread Tutorial](https://dev.epicgames.com/community/learning/tutorials/KJee/shotgun-spread-tutorial)
- [GameDev.net - Calculating Spread for Shotgun Shot](https://gamedev.net/forums/topic/611354-calculating-34spread34-for-shotgun-shot/4866788/)
- Real-world shotgun spread: At 1 yard, pattern is ~1 inch wide (effectively one projectile)
