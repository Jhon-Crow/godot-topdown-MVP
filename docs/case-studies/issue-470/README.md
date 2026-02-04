# Case Study: Issue #470 - Grenade Visual Effects Passing Through Walls

## Issue Summary
- **Issue**: #470
- **Title**: визуальный и обычный эффект наступательной гранаты не должен проходить сквозь стены (как это работает для вспышки)
- **Translation**: "Visual and normal effect of offensive grenade should not pass through walls (as it works for flashbang)"
- **Status**: Fixed
- **Root Cause**: Architecture mismatch between GDScript and C# code paths

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

### Phase 2: User Testing & Bug Report
1. **User Feedback**: "визуал не изменился" (visual hasn't changed)
2. **Evidence**: Game log `game_log_20260204_094613.txt` showed:
   - `[GrenadeTimer] Spawned C# explosion effect at (217.2414, 1847.0286)`
   - No mention of `spawn_explosion_effect` from GDScript
   - No mention of wall occlusion checks

### Phase 3: Root Cause Analysis
The critical insight from the log was that **C# code was spawning effects**, not GDScript.

**Key Log Entry**:
```
[09:46:23] [INFO] [GrenadeTimer] Spawned C# explosion effect at (217.2414, 1847.0286)
```

This revealed that in **exported builds**, the C# `GrenadeTimer.cs` component handles all grenade explosion logic, NOT the GDScript files. This is documented in Issue #432:

> "GDScript methods called via C# Call() silently fail in exported builds"

## Root Cause

### Architecture Overview

The grenade system has two parallel implementations:
1. **GDScript** (`frag_grenade.gd`, `flashbang_grenade.gd`): Works in editor, may fail in exports
2. **C# Component** (`GrenadeTimer.cs`): Reliable fallback for exported builds

### The Bug

The initial fix added wall occlusion to **GDScript only**:
- `impact_effects_manager.gd`: Added `spawn_explosion_effect()` with wall checks
- `frag_grenade.gd`: Called `impact_manager.spawn_explosion_effect()`

But in exported builds:
- `GrenadeTimer.cs::SpawnExplosionEffect()` creates effects directly
- This method had **NO wall occlusion checks**
- It bypassed `ImpactEffectsManager.gd` entirely

### Code Path Comparison

**Editor (GDScript works):**
```
frag_grenade.gd::_on_explode()
  -> _spawn_explosion_effect()
    -> ImpactEffectsManager.spawn_explosion_effect()
      -> _player_has_line_of_sight_to()  <-- Wall check!
        -> Spawns flash only if visible
```

**Exported Build (C# takes over):**
```
GrenadeTimer.cs::Explode()
  -> SpawnExplosionEffect()
    -> CreateExplosionFlash()  <-- NO wall check!
      -> Flash always spawns
```

## The Fix

Added wall occlusion check to `GrenadeTimer.cs::SpawnExplosionEffect()`:

```csharp
private void SpawnExplosionEffect(Vector2 position)
{
    // FIX for Issue #470: Check if player has line of sight to the explosion
    if (!PlayerHasLineOfSightTo(position))
    {
        LogToFile($"[GrenadeTimer] Visual effect blocked by wall - player cannot see explosion at {position}");
        return;
    }

    CreateExplosionFlash(position);
    LogToFile($"[GrenadeTimer] Spawned C# explosion effect at {position}");
}

private bool PlayerHasLineOfSightTo(Vector2 targetPosition)
{
    // Find player
    var players = GetTree().GetNodesInGroup("player");
    Node2D? playerNode = null;
    foreach (var player in players)
    {
        if (player is Node2D node)
        {
            playerNode = node;
            break;
        }
    }

    // Fallback to direct node lookup
    if (playerNode == null)
    {
        var currentScene = GetTree().CurrentScene;
        playerNode = currentScene?.GetNodeOrNull<Node2D>("Player");
    }

    if (playerNode == null) return true; // No player, show effect

    // Raycast to check for walls
    var spaceState = playerNode.GetWorld2D()?.DirectSpaceState;
    if (spaceState == null) return true;

    var query = PhysicsRayQueryParameters2D.Create(targetPosition, playerNode.GlobalPosition);
    query.CollisionMask = 4; // Layer 3 = obstacles/walls
    query.CollideWithBodies = true;
    query.CollideWithAreas = false;

    var result = spaceState.IntersectRay(query);
    return result.Count == 0; // No hit = player can see
}
```

## Lessons Learned

### 1. Dual-Language Architecture Requires Dual Testing
When a project has both GDScript and C# implementations for the same feature:
- Test in **both** editor AND exported builds
- Features must be implemented in **both** code paths
- Log messages help identify which code path is executing

### 2. "Works in Editor" != "Works in Export"
Issue #432 documented that GDScript methods called via C# `Call()` silently fail in exports. This means:
- Any feature relying on GDScript calls may not work in production
- C# components need to implement features directly, not delegate to GDScript

### 3. Log Analysis is Critical
The bug was identified because:
- The log showed `[GrenadeTimer]` (C#) not `[FragGrenade]` (GDScript)
- The message "Spawned C# explosion effect" confirmed the code path
- Searching for expected log messages (like "wall blocked") revealed they weren't appearing

### 4. Follow the Execution Path
When a fix doesn't work:
1. Add logging to trace execution
2. Check which code is actually running
3. Verify assumptions about architecture
4. Look for parallel/fallback implementations

## Files Modified

| File | Change |
|------|--------|
| `Scripts/Projectiles/GrenadeTimer.cs` | Added `PlayerHasLineOfSightTo()` and wall check in `SpawnExplosionEffect()` |

## Testing Checklist

- [ ] Throw frag grenade with player behind wall - visual should NOT appear
- [ ] Throw frag grenade with player in line of sight - visual should appear
- [ ] Test in both editor and exported build
- [ ] Verify log message "Visual effect blocked by wall" appears when appropriate
- [ ] Verify log message "Spawned C# explosion effect" only appears when player can see

## Related Issues

- **#432**: GDScript Call() fails in exports - explains why C# component exists
- **#470**: This issue - visual effects passing through walls

## Attachments

- `game_log_20260204_094613.txt` - Original user log showing the bug
