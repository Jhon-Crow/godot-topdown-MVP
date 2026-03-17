# Case Study: Issue #751 — Drilling Bullets Active Item Bug

## Overview

The "Drilling Bullets" active item was implemented in PR #1058 (commit `9d57ef19`).
After initial testing by the owner, the item **failed to work** with the following weapons:
- Makarov PM
- Shotgun
- Mini UZI
- Silenced Pistol
- Sniper Rifle (ASVK)
- Revolver (RSh-12)

It worked only with the Assault Rifle (M16) and AK-GL.

After a first fix pass (session 2026-03-17 19:05), the Sniper Rifle was confirmed working
but PM, Shotgun, UZI, Silenced Pistol, and Revolver remained broken.

## Timeline

| Time | Event |
|------|-------|
| 2026-03-16 20:34 | Initial implementation committed (PR #1058) |
| 2026-03-16 20:37 | AI agent marks PR "Ready to merge" |
| 2026-03-17 18:25 | Repo owner Jhon-Crow reports the item doesn't work for 6 weapons, provides logs |
| 2026-03-17 19:05 | Second AI work session: TileMapLayer + SniperRifle hitscan fix |
| 2026-03-17 19:17 | Session 2 marked ready; owner tests the new build |
| 2026-03-17 20:25 | Owner confirms sniper fixed, but PM/Shotgun/UZI/Pistol/Revolver still broken |
| 2026-03-17 20:26 | Third AI work session: GDScript bullet.gd root cause found and fixed |

## Root Cause Analysis

### Bug 1: GDScript `bullet.gd` missing drilling support (Primary — affects PM, UZI, Silenced Pistol, Revolver)

**File**: `scripts/projectiles/bullet.gd`

**Root cause**: Multiple weapons use **GDScript** bullet scenes instead of the C# `Bullet.cs`:
- `MakarovPM` → `Bullet9mm.tscn` → `scripts/projectiles/bullet.gd`
- `SilencedPistol` → `Bullet9mm.tscn` → `scripts/projectiles/bullet.gd`
- `MiniUzi` → `Bullet9mm.tscn` → `scripts/projectiles/bullet.gd`
- `Revolver` → `Bullet12p7mm.tscn` → `scripts/projectiles/bullet.gd`

The GDScript `bullet.gd` had **no `is_drilling_bullet` variable, no setter, and no wall
bypass logic**. When `BaseWeapon.SpawnBullet()` called `bullet.Call("set_is_drilling_bullet", true)`,
the GDScript bullet had no such method — the call silently failed, leaving
`is_drilling_bullet` unchecked and the bullet stopping at walls as normal.

**Evidence**:
- `AssaultRifle` uses `csharp/Bullet.tscn` → `Scripts/Projectiles/Bullet.cs` → **has drilling support → works**
- `MakarovPM` uses `Bullet9mm.tscn` → `scripts/projectiles/bullet.gd` → **no drilling support → fails**
- Log `game_log_20260317_232211.txt` shows PM and UZI both activated drilling but bullets
  stopped at walls; Sniper (hitscan) worked after the hitscan fix.

**Fix**:
1. Added `var is_drilling_bullet: bool = false` variable to `bullet.gd`
2. Added `func set_is_drilling_bullet(drilling: bool) -> void` setter to `bullet.gd`
3. Added drilling bypass check in `_on_body_entered()` before the wall hit logic:
   ```gdscript
   if is_drilling_bullet and (body is StaticBody2D or body is TileMap or body is TileMapLayer):
       return  # Wall ignored — bullet continues with full damage
   ```

### Bug 2: `TileMap` vs `TileMapLayer` in C# bullet/pellet (Affects C# bullets in tile-based levels)

**Files**: `Scripts/Projectiles/Bullet.cs`, `Scripts/Projectiles/ShotgunPellet.cs`

**Root cause**: In Godot 4.3+, `TileMap` was deprecated and replaced with `TileMapLayer`.
The original drilling bypass check used `body is TileMap` which evaluates to `false` for
`TileMapLayer` nodes. Levels using tile-map walls would not be penetrated even for C# bullets.

Note: `LabyrinthLevel.tscn` (where testing was done) uses hand-crafted `StaticBody2D` walls,
so `StaticBody2D` check was sufficient there. The `TileMapLayer` fix matters for other levels.

**Fix**: Added `|| body is TileMapLayer` to drilling bypass in `Bullet.cs` and `ShotgunPellet.cs`.

### Bug 3: SniperRifle hitscan bypass (Affects Sniper Rifle)

**File**: `Scripts/Weapons/SniperRifle.cs`

**Root cause**: The ASVK sniper rifle uses hitscan (instant raycast) instead of spawning
actual bullet projectiles. `SpawnBullet()` is skipped entirely, so:
1. `DrillingBulletsRemaining` was never decremented
2. Hitscan code never checked drilling state

**Fix**:
- `PerformHitscan()`: Skip walls when `DrillingBulletsRemaining > 0`
- `ComputeHitscanEndpoint()`: Same for dry-run
- `Fire()`: Explicit `DrillingBulletsRemaining--` for hitscan path

## Weapon Code Path Summary

| Weapon | Bullet Scene | Bullet Script | Fix Session |
|--------|-------------|---------------|-------------|
| AssaultRifle (M16) | `csharp/Bullet.tscn` | C# `Bullet.cs` | None (worked from start) |
| AKGL | `csharp/Bullet.tscn` | C# `Bullet.cs` | Bug 2 only (tile levels) |
| MakarovPM | `Bullet9mm.tscn` | GDScript `bullet.gd` | **Bug 1** (session 3) |
| SilencedPistol | `Bullet9mm.tscn` | GDScript `bullet.gd` | **Bug 1** (session 3) |
| MiniUzi | `Bullet9mm.tscn` | GDScript `bullet.gd` | **Bug 1** (session 3) |
| Revolver (RSh-12) | `Bullet12p7mm.tscn` | GDScript `bullet.gd` | **Bug 1** (session 3) |
| Shotgun | `ShotgunPellet.tscn` | C# `ShotgunPellet.cs` | Bug 2 only |
| SniperRifle (ASVK) | N/A (hitscan) | N/A | **Bug 3** (session 2) |

## Changes Made

### Session 2 (2026-03-17 19:05)
1. `Scripts/Projectiles/Bullet.cs` — Added `|| body is TileMapLayer` to drilling bypass check
2. `Scripts/Projectiles/ShotgunPellet.cs` — Added `|| body is TileMapLayer` to drilling bypass check
3. `Scripts/Weapons/SniperRifle.cs` — Hitscan drilling support + DrillingBulletsRemaining decrement
4. `assets/sprites/weapons/drilling_bullets_icon.png` — Unique 64×64 icon (drill-tip bullet)

### Session 3 (2026-03-17 20:26)
5. `scripts/projectiles/bullet.gd` — Added `is_drilling_bullet` variable, setter, and wall bypass

## Attached Evidence

- `game_log_20260317_212405.txt` — Session 1 log: AssaultRifle + various weapons (all failing)
- `game_log_20260317_212630.txt` — Session 2 pre-fix: PM/Shotgun/UZI/Pistol/Revolver failing
- `game_log_20260317_232211.txt` — Session 3 evidence: Sniper works; PM/UZI/Pistol/Revolver still fail
  (confirms bullet.gd root cause; weapons that use GDScript bullets were not yet fixed)
