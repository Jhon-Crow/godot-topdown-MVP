# Case Study: Issue #1171 — Fix Sniper Enemy (ASVK)

## Issue Summary

**Title:** fix враг снайпер (fix sniper enemy)

**Description:**
1. Трассер начинается не у ствола, а на небольшом расстоянии от ствола
   (The tracer starts not at the barrel, but at some distance from the barrel)
2. Снайпер часто промахивается мимо игрока (даже когда игрок рядом и не движется)
   (The sniper often misses the player even when the player is nearby and stationary)

**Attached Log:** `game_log_20260318_101031.txt` (copied to `docs/game_log_20260318_101031.txt`)

---

## Timeline / Sequence of Events (from log)

| Time | Event |
|------|-------|
| 10:11:05 | Sniper (ASVK) spawned via Experimental Menu at (350, 1000) |
| 10:11:12 | Sniper (ASVK) spawned via F8 at (350, 360) |
| 10:11:17 | Sniper (ASVK) spawned again via F8 at (350, 360) |
| 10:11:21 | Shot fired (sound at 487, 282), **player HIT** at (655, 109) |
| 10:11:24 | Shot fired (sound at 487, 282), **MISS** |
| 10:11:27 | Shot fired (sound at 487, 282), **MISS** |
| 10:11:31 | Shot fired (sound at 487, 282), **player HIT** at (878, 327) |
| 10:11:37 | Shot fired (sound at 487, 282), **player HIT** at (878, 159) — lethal |

**Hit rate:** 3/5 shots = 60%. For a "perfectly accurate" sniper rifle with `initial_spread = 0.0`, this is unacceptably low.

---

## Root Cause Analysis

### Bug 1: Tracer starts away from barrel

**Location:** `Scripts/Projectiles/SniperBullet.cs`

**Root cause:** The `SniperBulletEnemy.tscn` uses a real physics `Area2D` bullet with `SniperBullet.cs` and `TrailLength = 15`. The trail is updated in `_PhysicsProcess` via `UpdateTrail()` which records `GlobalPosition` (the bullet's current position) each frame:

```csharp
public override void _PhysicsProcess(double delta)
{
    var movement = Direction * Speed * (float)delta;
    Position += movement;          // Bullet moves FIRST
    UpdateTrail();                 // Trail records MOVED position (not barrel!)
    ...
}
```

At `Speed = 10000` px/s and 60fps, the bullet moves **~167px per frame**. On the first physics frame, the bullet has already moved 167px from the barrel before `UpdateTrail()` records the position. The trail never captures the spawn position (barrel), so it visually appears to start ~167px away from the barrel.

**In `_Ready()`, the `_positionHistory` is empty**, meaning there is no trail record for the initial spawn position.

### Bug 2: Enemy sniper misses often

**Location:** `scripts/objects/enemy.gd`, `_execute_shoot()` and `_shoot_single_bullet()`

**Root cause:** Physics tunneling. The enemy sniper fires a real physics projectile (`SniperBulletEnemy.tscn`) at `Speed = 10000` px/s. This means the `Area2D` bullet moves **~167px per physics frame** (at 60fps).

The player's HitArea has a radius of approximately 20px. If the bullet's center doesn't pass through the HitArea's collision shape in any single frame, the collision is never detected — this is the classic "fast bullet tunneling" problem. At 10000 px/s, tunneling causes approximately 2/5 misses, which matches the observed ~60% hit rate.

In contrast, the **player's sniper rifle** uses **hitscan** (instant raycast) in `SniperRifle.cs` `Fire()`, which never misses due to tunneling. The enemy was given a physics bullet instead of hitscan, creating an inconsistency.

---

## Additional Contributing Factor: Bullet Spawn Offset Mismatch

**Location:** `scripts/objects/enemy.gd`, `_get_bullet_spawn_position()`

The sniper config sets `bullet_spawn_offset = 60.0`, but `_get_bullet_spawn_position()` uses a hardcoded `muzzle_local_offset = 52.0` for all weapons. This means the muzzle position calculation is slightly off (8px discrepancy) for the sniper rifle. This is a minor visual inaccuracy but does not cause misses.

---

## Solution

### Fix 1: Tracer starts at barrel

**File:** `Scripts/Projectiles/SniperBullet.cs`

Pre-populate `_positionHistory` with the spawn position (`GlobalPosition`) in `_Ready()` **before any movement occurs**. This ensures the trail always starts from the barrel position on the very first frame.

```csharp
public override void _Ready()
{
    ...
    _trail = GetNodeOrNull<Line2D>("Trail");
    if (_trail != null)
    {
        _trail.ClearPoints();
        _trail.TopLevel = true;
        _trail.Position = Vector2.Zero;
        // Pre-populate with spawn (barrel) position so trail starts there
        _positionHistory.Add(GlobalPosition);
    }
    ...
}
```

### Fix 2: Enemy sniper uses hitscan

**File:** `scripts/objects/enemy.gd`

Add a dedicated `_shoot_sniper_hitscan()` method that:
1. Performs an instant raycast from the muzzle in the fire direction
2. Applies damage to any enemy/player hit along the path
3. Spawns a static smoke tracer Line2D from muzzle to hit point (same visual as player)

In `_execute_shoot()`, when `weapon_type == WeaponType.SNIPER_RIFLE`, call `_shoot_sniper_hitscan()` instead of `_shoot_single_bullet()`.

---

## Files Changed

- `Scripts/Projectiles/SniperBullet.cs` — Fix trail pre-population in `_Ready()`
- `scripts/objects/enemy.gd` — Add hitscan shooting for SNIPER_RIFLE enemy type

## Tests

- `tests/unit/test_sniper_enemy_hitscan.gd` — Verify hitscan logic and tracer spawning
