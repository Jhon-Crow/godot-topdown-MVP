# Case Study: Issue #152 - Dust Effect Not Spawning from Player Bullets

## Issue Summary
**Issue:** Dust particles do not appear when player bullets hit walls.
**Reporter:** @Jhon-Crow
**Status:** Fixed
**Root Cause:** Bilingual project architecture - C# bullet implementation missing dust effect call

## Timeline of Events

### Initial Investigation (First Fix Attempt)
1. Issue reported: dust effects not spawning when player bullets hit walls
2. Initial analysis examined `scripts/projectiles/bullet.gd` (GDScript)
3. Found bug in GDScript: `_spawn_wall_hit_effect()` was called AFTER ricochet check
4. When bullet ricocheted (100% base probability), the dust spawn was skipped due to early return
5. Fix applied to GDScript: moved dust spawn BEFORE ricochet logic

### Problem Persisted
1. User reported fix still not working
2. User asked: "is this related to bilingual project (GS and C#)?"
3. This was the crucial hint pointing to the actual root cause

### Deep Investigation
1. Analyzed project structure - discovered dual implementations:
   - `scripts/projectiles/bullet.gd` - GDScript bullet
   - `Scripts/Projectiles/Bullet.cs` - C# bullet
2. Traced the scene references:
   - `project.godot` defines `BuildingLevel.tscn` as main scene
   - `BuildingLevel.tscn` uses `scenes/characters/csharp/Player.tscn`
   - C# Player uses `scenes/weapons/csharp/AssaultRifle.tscn`
   - C# AssaultRifle uses `scenes/projectiles/csharp/Bullet.tscn`
   - C# Bullet scene references `Scripts/Projectiles/Bullet.cs`

### Root Cause Identified
The game was using the **C# bullet implementation**, not the GDScript one. The C# `Bullet.cs` never had the `SpawnWallHitEffect()` method call - it was never implemented there in the first place.

## Code Analysis

### GDScript Implementation (bullet.gd)
```gdscript
# After fix - correctly spawns dust before ricochet check
if body is StaticBody2D or body is TileMap:
    _spawn_wall_hit_effect(body)  # Always spawn dust
    if _try_ricochet(body):
        return
```

### C# Implementation (Bullet.cs) - BEFORE FIX
```csharp
// Missing dust effect call entirely!
if (body is StaticBody2D || body is TileMap)
{
    if (TryRicochet(body))
    {
        return; // No dust spawned
    }
}
```

### C# Implementation (Bullet.cs) - AFTER FIX
```csharp
// Now includes dust effect spawning
if (body is StaticBody2D || body is TileMap)
{
    SpawnWallHitEffect(body);  // Always spawn dust
    if (TryRicochet(body))
    {
        return;
    }
}
```

## Project Architecture Notes

This project uses a **bilingual architecture** with both GDScript and C# implementations:

```
scenes/
├── projectiles/
│   ├── Bullet.tscn (uses bullet.gd)
│   └── csharp/
│       └── Bullet.tscn (uses Bullet.cs)
├── weapons/
│   ├── AssaultRifle.tscn (uses GDScript)
│   └── csharp/
│       └── AssaultRifle.tscn (uses C#)
├── characters/
│   ├── Player.tscn (uses GDScript)
│   └── csharp/
│       └── Player.tscn (uses C#)
```

The main game (`BuildingLevel.tscn`) uses the C# character path, which chains to C# weapons and C# bullets.

## Lessons Learned

1. **Always verify which implementation is actually in use** - In bilingual projects, fixing one implementation doesn't fix the other
2. **Trace the full scene reference chain** - The actual code path depends on scene instantiation hierarchy
3. **User hints are valuable** - The question about "bilingual project" was the key to finding the real issue
4. **Keep implementations in sync** - When the project has parallel implementations, features must be added to both

## Files Changed

1. `scripts/projectiles/bullet.gd` - Fixed dust effect ordering (GDScript)
2. `Scripts/Projectiles/Bullet.cs` - Added `SpawnWallHitEffect()` method (C#)

## Verification

After the fix:
- Dust particles appear when bullets hit walls in the C# implementation
- Dust appears even when bullets ricochet
- No regression in existing ricochet behavior

## Attachments

- `game_log_20260121_035204.txt` - Game log from user testing showing no dust effect events
