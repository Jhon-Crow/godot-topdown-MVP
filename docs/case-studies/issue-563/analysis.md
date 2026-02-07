# Case Study: Issue #563 - Fix ASVK

## Issue Summary

The ASVK sniper rifle had two bugs:
1. **Enemies on the smoke line should take damage instantly** - Instead, the bullet physically traveled at 10,000 pixels/second, causing a noticeable delay before distant enemies took damage.
2. **Smoke line should not appear beyond wall penetration limit** - The smoke tracer extended 5,000 pixels unconditionally, even through walls that the bullet could not penetrate (max 2 walls).

## Timeline

- **2026-02-07 14:04:10** - Game log session 1 started, ASVK weapon selected
- **2026-02-07 14:04:32** - First ASVK shot fired (SniperRifle sound propagation logged)
- **2026-02-07 14:04:53** - Enemy7 hit with 50 damage (died from 3 HP -> -47)
- **2026-02-07 14:04:59** - Enemy8 hit with 50 damage (died from 2 HP -> -48)
- **2026-02-07 14:06:17** - Game log session 2 started
- Multiple shots fired but several missed or hit walls

## Root Cause Analysis

### Bug 1: Non-instant damage

The ASVK used a **projectile-based** damage system via `SniperBullet.cs`:

```
SniperRifle.Fire() -> base.Fire() -> SpawnBullet() -> creates SniperBullet Area2D
SniperBullet._PhysicsProcess() moves at 10,000 px/s
SniperBullet.OnAreaEntered() deals damage on collision
```

Even at 10,000 pixels/second, a target 2,000 pixels away would experience a 200ms delay. This is perceptible and inconsistent with the expectation of a high-velocity anti-materiel rifle round.

**Evidence from logs:**
- Shot fired at 14:04:53 from position (313, 960)
- Enemy7 at position (1606, 893) - distance ~1,300 pixels
- At 10,000 px/s, this is a ~130ms delay before hit

### Bug 2: Unlimited smoke tracer

In `SniperRifle.SpawnSmokyTracer()` (original code):

```csharp
float tracerLength = 5000.0f; // Far enough to reach any map edge
Vector2 endPosition = fromPosition + direction * tracerLength;
```

The tracer extended 5,000 pixels in the fire direction with **no wall detection**. The bullet could only penetrate 2 walls (`MaxWallPenetrations = 2`), but the smoke tracer would visually extend through any number of walls, creating a misleading visual.

## Solution

### Approach: Hitscan with wall-limited smoke tracer

Replaced the projectile-based system with a **hitscan** (instant raycast) approach:

1. **`PerformHitscan()`** - New method that uses sequential `DirectSpaceState.IntersectRay()` calls to:
   - Find all walls and enemies along the bullet path
   - Apply damage **instantly** to enemies within the valid path
   - Track wall penetrations (stops at `MaxWallPenetrations + 1` = 3rd wall)
   - Return the endpoint where the bullet stops

2. **`SpawnSmokyTracer()`** - Modified to accept the hitscan endpoint instead of using a hardcoded 5,000px length. The smoke tracer now terminates at the point where the bullet stopped.

3. **`SpawnBullet()`** - Skipped during hitscan fire via `_skipBulletSpawn` flag. The method is retained for backward compatibility.

4. **`Fire()`** - Orchestrates the hitscan flow:
   - Calls `base.Fire()` with `_skipBulletSpawn = true` (handles ammo, fire timer, signals)
   - Performs hitscan for instant damage
   - Spawns smoke tracer limited to bullet's actual path
   - Spawns muzzle flash and sound effects

### Files Changed

- `Scripts/Weapons/SniperRifle.cs` - Main changes (hitscan implementation)

### Key Design Decisions

1. **Sequential raycasting** - Godot's `IntersectRay` returns only the first hit. To find all objects along the path, we perform sequential raycasts, excluding previously-hit objects via their RIDs.

2. **Collision mask** - The hitscan uses mask `6` (layers 2 + 3) to detect both enemy bodies (CharacterBody2D, layer 2) and walls (StaticBody2D/TileMap, layer 3). Enemy HitAreas are Area2D which aren't detected by body raycasts, so we detect the enemy CharacterBody2D directly and call `take_damage()` on it.

3. **Damage deduplication** - A `HashSet<ulong>` tracks damaged enemy instance IDs to prevent double-damage in edge cases.

4. **Safety limit** - The raycast loop has a 50-iteration safety limit to prevent infinite loops.

## Verification

- Build succeeds with 0 errors (36 pre-existing warnings)
- All pre-existing warnings are unchanged
- No new functionality removed
