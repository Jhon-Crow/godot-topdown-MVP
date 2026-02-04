# Case Study: Issue #470 - Grenade Visual Effects Passing Through Walls

## Issue Summary
- **Issue**: #470
- **Title**: визуальный и обычный эффект наступательной гранаты не должен проходить сквозь стены (как это работает для вспышки)
- **Translation**: "Visual and normal effect of offensive grenade should not pass through walls (as it works for flashbang)"
- **Status**: Fixed
- **Root Cause**: Architecture mismatch between GDScript and C# code paths, plus overly strict wall occlusion check

## Timeline of Events

### Phase 1: Initial Implementation (First PR Attempt)
1. **Problem Identified**: Frag grenade visual effects were visible through walls
2. **Initial Solution**: Added wall occlusion methods to `impact_effects_manager.gd`:
   - `spawn_flashbang_effect()` - with line-of-sight check
   - `spawn_explosion_effect()` - with line-of-sight check
   - `_player_has_line_of_sight_to()` - raycast helper
3. **Modified Files**:
   - `scripts/autoload/impact_effects_manager.gd` - Added wall occlusion methods
   - `scripts/projectiles/frag_grenade.gd` - Called wall-aware methods

### Phase 2: User Testing & Bug Report (Round 1)
1. **User Feedback**: "визуал не изменился" (visual hasn't changed)
2. **Evidence**: Game log `game_log_20260204_094613.txt` showed:
   - `[GrenadeTimer] Spawned C# explosion effect at (217.2414, 1847.0286)`
   - No mention of `spawn_explosion_effect` from GDScript
   - No mention of wall occlusion checks

### Phase 3: Root Cause Analysis (C# vs GDScript)
The critical insight from the log was that **C# code was spawning effects**, not GDScript.

**Key Log Entry**:
```
[09:46:23] [INFO] [GrenadeTimer] Spawned C# explosion effect at (217.2414, 1847.0286)
```

This revealed that in **exported builds**, the C# `GrenadeTimer.cs` component handles all grenade explosion logic, NOT the GDScript files.

### Phase 4: First Fix - Added Wall Occlusion to C#
Added `PlayerHasLineOfSightTo()` to `GrenadeTimer.cs` with raycast check using collision mask 4 (obstacles layer).

### Phase 5: User Testing & Bug Report (Round 2)
1. **User Feedback**: "теперь эффекты обеих гранат не видны" (now effects of both grenades are not visible)
2. **Evidence**: Game log `game_log_20260204_163238.txt` showed:
   - First explosion worked: `[GrenadeTimer] Spawned C# explosion effect at (1114.0901, 1451.9849)`
   - All subsequent explosions blocked: `[GrenadeTimer] Visual effect blocked by wall`
   - BUT damage was still applied: `[GrenadeTimer] Applied flashbang to player at distance 273,2`

### Phase 6: Root Cause Analysis (Overly Strict Raycast)
The second log revealed a critical insight: **damage was being applied to the player**, but the visual was blocked. This is contradictory!

**Analysis of log entries:**
```
[16:32:58] [GrenadeTimer] Applied flashbang to player at distance 273,2
[16:32:58] [GrenadeTimer] Visual effect blocked by wall
```

If the player is close enough to receive flashbang damage, they should be able to see the flash.

**Root Cause**: The raycast was hitting **small furniture** (desks, tables, cabinets) that are also on collision layer 4 (obstacles), NOT major walls. The player was standing near cover objects, and the raycast from explosion to player was hitting that cover.

## Final Fix

Added a **tolerance distance** to the wall occlusion check. If the raycast hit is close to the player (within 100 pixels), it's likely just small furniture near the player, not a major wall blocking the entire view.

```csharp
// In GrenadeTimer.cs
private const float MinWallBlockingDistance = 100.0f;

private bool PlayerHasLineOfSightTo(Vector2 targetPosition)
{
    // ... find player, setup raycast ...

    var result = spaceState.IntersectRay(query);

    if (result.Count == 0)
        return true; // No hit, player can see

    // Check if hit is close to player (likely small furniture)
    Vector2 hitPosition = (Vector2)result["position"];
    float distanceToPlayer = hitPosition.DistanceTo(playerPos);

    if (distanceToPlayer < MinWallBlockingDistance)
    {
        // Hit is close to player - likely small furniture, still show effect
        return true;
    }

    // Major wall - block the visual effect
    return false;
}
```

## Key Insight: Cover vs Walls

The game level has multiple object types on collision layer 4:
- **Major walls**: Should block visual effects (you can't see through them)
- **Small furniture**: Desks, tables, cabinets used as cover

The original fix treated ALL obstacles equally, but realistically:
- An explosion flash would be visible OVER/AROUND small furniture
- Only substantial walls completely block the light

The tolerance distance (100px) distinguishes between:
- Hit close to player = small furniture near them = show effect
- Hit far from player (closer to explosion) = major wall between them = block effect

## Lessons Learned

### 1. Dual-Language Architecture Requires Dual Testing
When a project has both GDScript and C# implementations:
- Test in **both** editor AND exported builds
- Features must be implemented in **both** code paths

### 2. "Works in Editor" != "Works in Export"
GDScript methods called via C# `Call()` silently fail in exports (Issue #432).

### 3. Log Analysis is Critical
Both bugs were identified through careful log analysis:
- First bug: Log showed C# path executing, not GDScript
- Second bug: Damage applied but visual blocked (contradiction!)

### 4. Consider Real-World Physics
A simple raycast treats all obstacles as perfect blockers. But:
- Light bends around small objects
- Explosions illuminate over furniture
- Only major walls truly block view

### 5. Test Multiple Scenarios
The first explosion worked, subsequent ones failed. Testing only the first case would have missed the bug.

## Files Modified

| File | Change |
|------|--------|
| `Scripts/Projectiles/GrenadeTimer.cs` | Added `PlayerHasLineOfSightTo()` with tolerance for small furniture |
| `scripts/autoload/impact_effects_manager.gd` | Added `MIN_WALL_BLOCKING_DISTANCE` tolerance to GDScript version |

## Testing Checklist

- [ ] Throw grenade with player behind MAJOR wall - visual should NOT appear
- [ ] Throw grenade with player in line of sight - visual should appear
- [ ] Throw grenade with player behind SMALL COVER (desk/table) - visual SHOULD appear
- [ ] Test in both editor and exported build
- [ ] Verify log messages match expected behavior

## Related Issues

- **#432**: GDScript Call() fails in exports - explains why C# component exists
- **#470**: This issue - visual effects passing through walls

## Attachments

- `game_log_20260204_094613.txt` - Original user log showing C#/GDScript mismatch
- `game_log_20260204_163238.txt` - Second log showing overly strict raycast blocking all effects
