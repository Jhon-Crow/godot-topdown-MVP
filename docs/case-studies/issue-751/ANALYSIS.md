# Case Study: Issue #751 — Drilling Bullets Active Item Bug

## Overview

The "Drilling Bullets" active item was implemented in PR #1058 (commit `9d57ef19`).
After initial implementation, the item **failed to work** with the following weapons:
- Makarov PM
- Shotgun
- Mini UZI
- Silenced Pistol
- Sniper Rifle (ASVK)
- Revolver (RSh-12)

It worked only with the Assault Rifle (M16) and AK-GL.

## Timeline

| Time | Event |
|------|-------|
| 2026-03-16 20:34 | Initial implementation committed (PR #1058) |
| 2026-03-16 20:37 | AI agent marks PR "Ready to merge" |
| 2026-03-17 18:25 | Repo owner Jhon-Crow reports the item doesn't work for 6 weapons |
| 2026-03-17 19:05 | New AI work session started to investigate |

## Root Cause Analysis

### Bug 1: `TileMap` vs `TileMapLayer` (Primary — affects all weapons)

**File**: `Scripts/Projectiles/Bullet.cs`, `Scripts/Projectiles/ShotgunPellet.cs`

**Code before fix**:
```csharp
if (IsDrillingBullet && (body is StaticBody2D || body is TileMap))
{
    return; // Wall ignored
}
```

**Root cause**: In Godot 4.3+, the `TileMap` node was deprecated and replaced with `TileMapLayer`.
The LabyrinthLevel and BuildingLevel use `TileMapLayer` for their wall tiles. Since `TileMapLayer`
is a different C# type from `TileMap`, the `body is TileMap` check always evaluated to `false`
for the actual wall nodes in the game.

This caused ALL bullets to stop at TileMapLayer walls regardless of the `IsDrillingBullet` flag.
The `StaticBody2D` check still worked for static body obstacles, but the level walls are
implemented as `TileMapLayer` nodes.

**Evidence from GrenadeTimer.cs** (line 378-379 already had the fix):
```csharp
// Note: Check TileMap for legacy Godot 4 and TileMapLayer for newer versions
if (body is StaticBody2D || body is TileMap || body is TileMapLayer || body is CharacterBody2D)
```

**Fix**: Added `|| body is TileMapLayer` to all drilling-bullet wall bypass checks in:
- `Bullet.cs`
- `ShotgunPellet.cs`
- `SniperRifle.cs` (all 4 hitscan loop instances)

### Bug 2: SniperRifle hitscan bypass (Affects Sniper Rifle)

**File**: `Scripts/Weapons/SniperRifle.cs`

**Root cause**: The Sniper Rifle uses hitscan (instant raycast) instead of spawning actual
bullet projectiles. When firing, `_skipBulletSpawn = true` is set, causing `base.SpawnBullet()`
to return immediately without:
1. Setting `IsDrillingBullet` on any projectile (no projectile is spawned)
2. Decrementing `DrillingBulletsRemaining`
3. Checking whether walls should be bypassed

The `PerformHitscan()` method independently raycasts through the scene. It was not aware of
the drilling bullets state and always applied normal wall-penetration logic.

**Fix**:
1. Modified `PerformHitscan()` and `ComputeHitscanEndpoint()` to skip wall stopping when
   `DrillingBulletsRemaining > 0`
2. Added explicit `DrillingBulletsRemaining--` decrement in `Fire()` after a successful shot,
   since `SpawnBullet()` is bypassed

## Why AssaultRifle and AKGL Worked

These weapons do NOT override `SpawnBullet()`. They use `base.Fire()` → `base.SpawnBullet()`.
The base `SpawnBullet()` sets `IsDrillingBullet = true` on the bullet.

For bullets to actually pass through walls, the `OnBodyEntered` handler needs to check
`IsDrillingBullet`. For TileMapLayer walls, this check failed (Bug 1).

So actually, AssaultRifle and AKGL were also broken — the bullets got the flag but still
stopped at `TileMapLayer` walls. The fix for Bug 1 fixes all weapons simultaneously.

## Weapons and Their Code Paths

| Weapon | Override? | Fix needed |
|--------|-----------|------------|
| AssaultRifle | No | Bug 1 (TileMapLayer in Bullet.cs) |
| AKGL | No | Bug 1 |
| MiniUzi | No | Bug 1 |
| MakarovPM | `SpawnBullet()` override | Bug 1 |
| SilencedPistol | `SpawnBullet()` override | Bug 1 |
| Shotgun | Custom `Fire()` + `SpawnPelletWithOffset()` | Bug 1 (ShotgunPellet.cs) |
| Revolver | No `SpawnBullet()` override | Bug 1 |
| SniperRifle | `_skipBulletSpawn = true` + hitscan | Bug 1 + Bug 2 |

## Changes Made

1. `Scripts/Projectiles/Bullet.cs` — Added `|| body is TileMapLayer` to drilling bypass check
2. `Scripts/Projectiles/ShotgunPellet.cs` — Added `|| body is TileMapLayer` to drilling bypass check
3. `Scripts/Weapons/SniperRifle.cs`:
   - `PerformHitscan()`: Skip walls when `DrillingBulletsRemaining > 0`
   - `ComputeHitscanEndpoint()`: Same for dry-run (time-stop support)
   - `ComputeBreakerHitscanEndpoint()`: Added `TileMapLayer` support
   - `PerformBreakerHitscan()`: Added `TileMapLayer` support
   - `Fire()`: Explicit `DrillingBulletsRemaining--` for hitscan path
4. `assets/sprites/weapons/drilling_bullets_icon.png` — Replaced placeholder with unique
   64×64 icon depicting a bullet with a drill tip (brass body + steel drill cone + cyan accents)

## Attached Evidence

- `game_log_20260317_212405.txt` — Log showing drilling bullets used with AssaultRifle
- `game_log_20260317_212630.txt` — Log showing drilling bullets used with Shotgun, MiniUzi,
  SilencedPistol, SniperRifle, Revolver, and AKGL
