# Case Study: Issue #350 - Player Blood Effects Missing

## Issue Summary
**Issue URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/350

**Title (Russian):** fix кровь из игрока
**Title (English):** Fix blood from player

**Description:** Blood effects (splashes + puddles) should appear from the player when hit, just like they do for enemies.

## Timeline of Events

### 2026-01-25 Initial Investigation

1. **AI solution draft created** - Initial investigation mistakenly concluded that blood effects were already implemented in `scripts/characters/player.gd` (GDScript player)
2. **User feedback received** - User @Jhon-Crow reported "нет изменений" (no changes) and attached game log file, suggesting to "check C#"
3. **Root cause identified** - The game uses the C# Player (`Scripts/Characters/Player.cs`), not the GDScript player

## Root Cause Analysis

### The Problem
The game levels (`BuildingLevel.tscn`, `TestTier.tscn`) use the **C# Player** scene (`scenes/characters/csharp/Player.tscn`), which references the C# script `Scripts/Characters/Player.cs`.

The C# Player's damage handling methods:
- `on_hit()` - calls `TakeDamage(1)` but does NOT spawn blood effects
- `TakeDamage()` - plays hit sounds and shows visual flash, but does NOT spawn blood effects

Meanwhile, the **GDScript Player** (`scripts/characters/player.gd`) already has working blood effect code:

```gdscript
# GDScript player.gd (lines 877-886) - CORRECT IMPLEMENTATION
func on_hit_with_info(hit_direction: Vector2, caliber_data: Resource) -> void:
    # ...
    if impact_manager and impact_manager.has_method("spawn_blood_effect"):
        impact_manager.spawn_blood_effect(global_position, hit_direction, caliber_data, is_lethal)
```

The C# Player was missing this functionality entirely.

### Evidence from Game Logs

The game log (`game_log_20260125_055229.txt`) shows:

**Enemy hits produce blood effects:**
```
[05:52:45] [ENEMY] [Enemy3] ImpactEffectsManager found, calling spawn_blood_effect
[05:52:45] [INFO] [ImpactEffects] spawn_blood_effect called at (689.3335, 750.0616), dir=(1, 0), lethal=false
[05:52:45] [INFO] [ImpactEffects] Blood particle effect instantiated successfully
```

**Player damage events do NOT produce blood effects:**
```
[05:52:33] [INFO] [PenultimateHit] Player damaged: 1.0 damage, current health: 1.0
```
(Notice no `spawn_blood_effect` call for player hits)

### Architecture Discrepancy

| Component | GDScript Version | C# Version |
|-----------|------------------|------------|
| Player scene | `scenes/characters/Player.tscn` | `scenes/characters/csharp/Player.tscn` |
| Player script | `scripts/characters/player.gd` | `Scripts/Characters/Player.cs` |
| Has `on_hit_with_info`? | Yes | No (before fix) |
| Calls `spawn_blood_effect`? | Yes | No (before fix) |
| **Used in game levels?** | No | **Yes** |

## Solution

### Changes Made to `Scripts/Characters/Player.cs`

1. **Added hit direction tracking:**
```csharp
private Vector2 _lastHitDirection = Vector2.Right;
private Godot.Resource? _lastCaliberData = null;
```

2. **Added `on_hit_with_info` method** to match GDScript API:
```csharp
public void on_hit_with_info(Vector2 hitDirection, Godot.Resource? caliberData)
{
    _lastHitDirection = hitDirection;
    _lastCaliberData = caliberData;
    TakeDamage(1);
}
```

3. **Modified `on_hit()` to call `on_hit_with_info`:**
```csharp
public void on_hit()
{
    on_hit_with_info(Vector2.Right, null);
}
```

4. **Added `SpawnBloodEffect` method:**
```csharp
private void SpawnBloodEffect(bool isLethal)
{
    var impactManager = GetNodeOrNull("/root/ImpactEffectsManager");
    if (impactManager != null && impactManager.HasMethod("spawn_blood_effect"))
    {
        impactManager.Call("spawn_blood_effect", GlobalPosition, _lastHitDirection, _lastCaliberData, isLethal);
    }
}
```

5. **Called `SpawnBloodEffect` from `TakeDamage()`** for both lethal and non-lethal hits

## Verification

After the fix, when the player is hit, the game log should show:
```
[Player] Spawning blood effect at (X, Y), dir=(dx, dy), lethal=true/false (C#)
[INFO] [ImpactEffects] spawn_blood_effect called at (X, Y), dir=(dx, dy), lethal=true/false
[INFO] [ImpactEffects] Blood particle effect instantiated successfully
[INFO] [ImpactEffects] Blood decals scheduled: 10/20 to spawn at particle landing times
```

## Lessons Learned

1. **Check which implementation is actually used** - When a codebase has both GDScript and C# implementations, verify which one is referenced in the scene files
2. **Read game logs carefully** - The logs clearly showed enemy blood effects working but no player blood effects
3. **Cross-language consistency** - When maintaining parallel GDScript/C# implementations, features must be added to both

## Files Modified

- `Scripts/Characters/Player.cs` - Added blood effect spawning on hit

## Files Added

- `docs/case-studies/issue-350/README.md` - This case study document
- `docs/case-studies/issue-350/game_log_20260125_055229.txt` - Original game log from user

## Related Files (Reference)

- `scripts/characters/player.gd` - GDScript player (has working blood effect code)
- `scripts/objects/enemy.gd` - Enemy (has working blood effect code)
- `scripts/autoload/impact_effects_manager.gd` - Manages blood effect spawning
- `scripts/objects/hit_area.gd` - Hit detection forwarding
