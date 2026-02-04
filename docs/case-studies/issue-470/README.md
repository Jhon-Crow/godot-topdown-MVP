# Case Study: Issue #470 - Grenade Visual Effects Passing Through Walls

## Issue Summary
- **Issue**: #470
- **Title**: визуальный и обычный эффект наступательной гранаты не должен проходить сквозь стены (как это работает для вспышки)
- **Translation**: "Visual and normal effect of offensive grenade should not pass through walls (as it works for flashbang)"
- **Status**: Fixed
- **Root Cause**: Multiple issues - architecture mismatch, then overly simplistic wall detection logic

## Timeline of Events

### Phase 1: Initial Problem Report
- **Problem**: Frag grenade visual effects were visible through walls
- **Expected**: Effects should be blocked by walls

### Phase 2: First Fix Attempt (GDScript)
Added wall occlusion methods to `impact_effects_manager.gd`.
- **Result**: FAILED - User reported "визуал не изменился" (visual hasn't changed)
- **Cause**: Exported builds use C# `GrenadeTimer.cs`, not GDScript

### Phase 3: Second Fix Attempt (C# Path)
Added `PlayerHasLineOfSightTo()` to `GrenadeTimer.cs` with simple raycast.
- **Result**: FAILED - User reported "теперь эффекты обеих гранат не видны" (now effects of both grenades are not visible)
- **Cause**: Raycast was too strict - blocked ALL obstacles including small furniture

### Phase 4: Third Fix Attempt (Distance Tolerance)
Added tolerance: if obstacle is within 100px of player, assume it's small furniture and allow effect.
- **Result**: PARTIAL FAILURE - User reported "то видна то не видна вспышка. вспышка всё ещё проходит сквозь стены"
- **Translation**: "sometimes flash is visible, sometimes not. flash still passes through walls"
- **Cause**: Distance-based tolerance is fundamentally flawed - if player stands WITH THEIR BACK to a wall, the wall hits close to player but SHOULD block the effect

### Phase 5: Final Fix (Node Path Detection)
**NEW APPROACH**: Instead of distance-based tolerance, distinguish between walls and cover by checking the node's **scene tree path**:
- Objects under `Environment/Cover/` (desks, tables, cabinets) → **don't block** (furniture doesn't block flash)
- Objects under `Environment/Walls/` or `Environment/InteriorWalls/` → **block** (actual walls)

## Root Cause Analysis

The fundamental problem with the distance-based approach:

```
SCENARIO 1: Player near furniture (should NOT block)
   +-------+
   | Player|  <-- Furniture 50px away
   +-------+
           ^
        Explosion on other side - SHOULD see flash

SCENARIO 2: Player backed against wall (SHOULD block)
   +-------+
   | Player|  <-- Wall 50px behind player
   +-------+
           ^
        Explosion on other side - should NOT see flash
```

Both scenarios have an obstacle close to the player (< 100px), but:
- Scenario 1: Small furniture - flash visible over/around it
- Scenario 2: Major wall - flash should be completely blocked

The distance-based tolerance **cannot distinguish** between these cases.

## Solution: Node Path Detection

The game level organizes obstacles into clear categories:
```
BuildingLevel
├── Environment
│   ├── Walls/           ← Major walls (block flash)
│   │   ├── WallTop
│   │   ├── WallBottom
│   │   └── ...
│   ├── InteriorWalls/   ← Interior walls (block flash)
│   │   ├── Room1_WallBottom
│   │   └── ...
│   └── Cover/           ← Furniture (allow flash)
│       ├── Desk1
│       ├── Table1
│       └── Cabinet1
```

By checking the **node path** of the hit collider, we can correctly classify:
- Path contains `/Cover/` → furniture → show effect
- Path contains `/Walls/` or `/InteriorWalls/` → wall → block effect

```csharp
// C# implementation
var collider = result["collider"].AsGodotObject();
if (collider is Node hitNode)
{
    string nodePath = hitNode.GetPath().ToString();

    // Cover objects don't block the visual effect
    if (nodePath.Contains("/Cover/"))
    {
        return true;  // Show effect
    }

    // Walls block the visual effect
    if (nodePath.Contains("/Walls/") || nodePath.Contains("/InteriorWalls/"))
    {
        return false;  // Block effect
    }
}
```

## Key Insights

### 1. Scene Organization Matters
The level's scene tree organization (`Cover/` vs `Walls/`) provides semantic meaning that collision layers alone don't capture.

### 2. Distance-Based Heuristics Fail
Simple distance checks can't distinguish between "small obstacle near player" and "major wall behind player".

### 3. Test Edge Cases
The original fix worked for:
- Player in open area → effect visible
- Player behind distant wall → effect blocked

But failed for:
- Player backed against wall → effect wrongly visible (wall counted as "close furniture")

### 4. Dual Codebase Requires Dual Fixes
Both C# (`GrenadeTimer.cs`) and GDScript (`impact_effects_manager.gd`) need the same fix for consistent behavior in editor vs export.

## Files Modified

| File | Change |
|------|--------|
| `Scripts/Projectiles/GrenadeTimer.cs` | Replaced distance-based tolerance with node path detection |
| `scripts/autoload/impact_effects_manager.gd` | Same node path detection logic in GDScript |

## Testing Checklist

- [ ] Throw grenade with player in line of sight → visual should appear
- [ ] Throw grenade with player behind WALL → visual should NOT appear
- [ ] Throw grenade with player behind desk/table/cabinet → visual SHOULD appear
- [ ] Test in both editor and exported build
- [ ] Verify log messages correctly identify "Cover" vs "Walls"

## Log Messages to Look For

**Cover hit (effect visible):**
```
[GrenadeTimer] Raycast hit cover object 'Desk1' at (x, y) - showing effect (furniture doesn't block flash)
```

**Wall hit (effect blocked):**
```
[GrenadeTimer] Wall 'Room1_WallBottom' blocks view between explosion at (x, y) and player at (x, y)
```

## Related Issues

- **#432**: GDScript Call() fails in exports - explains why C# component exists
- **#470**: This issue - visual effects passing through walls

## Attachments

- `game_log_20260204_094613.txt` - Original log showing C#/GDScript mismatch
- `game_log_20260204_163238.txt` - Log showing overly strict raycast blocking all effects
- `game_log_20260204_164608.txt` - Log showing distance-based tolerance failures
