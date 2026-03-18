# Game Log Analysis: game_log_20260317_040003.txt

## Reported Issue
RPG enemy still doesn't fire the rocket projectile — the projectile never appears visually (the shot doesn't fly).

## What the Log Shows
- `RpgEnemy1` and `RpgEnemy2` spawn on TestTier (Полигон) ✅
- `RpgEnemy2` enters COMBAT, sound is emitted: `type=GUNSHOT, pos=RpgEnemy2, range=2500` ✅ (RPG sound range)
- But no visible rocket appears in the game

## Root Cause: ProjectilePoolManager Hijacks the Rocket

When `_shoot()` calls `_shoot_single_bullet()` → `_spawn_projectile()`, the spawn function first asks `ProjectilePoolManager.get_bullet()`. The pool manager returns a **pooled regular bullet** (pre-instantiated `Bullet.tscn` or `csharp/Bullet.tscn`), completely ignoring `bullet_scene` which points to `RpgRocket.tscn`.

The pooled bullet has `pool_activate(pos, dir, sid, null)` called on it, which fires a regular bullet that flies off invisibly (tiny, fast, disappears immediately). The RPG rocket scene is **never instantiated**.

This explains:
- Sound is emitted (sound logic runs before/after projectile spawning — correct range=2500 RPG loudness)
- Weapon switches to PM after firing (switch logic also runs after spawning — works fine)
- No visible rocket (wrong projectile was spawned from pool)

## Fix Applied
Added `_fire_rpg_rocket()` function that **bypasses the ProjectilePoolManager** and directly instantiates the RPG rocket from `bullet_scene`, analogous to how `AKGL.cs`'s `FireGrenadeLauncher()` directly instantiates the `VOGGrenade` scene without using any bullet pool.

In `_execute_shoot()`, the RPG path now calls `_fire_rpg_rocket()` instead of falling through to `_shoot_single_bullet()` → `_spawn_projectile()` (which would hit the pool).

## Timeline Reconstruction
1. Session 1 (2026-02-08): RPG enemies added to CastleLevel ❌ (wrong level)
2. Session 2 (2026-02-08): Moved RPG enemies to TestTier ✅ — but enemies not visible due to RPG sprite missing
3. Session 3 (2026-03-16): Merged main, fixed sprite — weapon sprite now visible ✅
4. Session 4 (2026-03-16): Fixed weapon switch sprite — PM sprite shown after switch ✅
5. Session 5 (2026-03-17 00:34): Fixed timer-reset bug — timer no longer resets every frame ✅
6. Session 6 (2026-03-17 00:46): Pre-initialized shoot timer on COMBAT entry ✅
7. **Session 7 (2026-03-17 01:04)**: Found pool manager hijack root cause → fixed with `_fire_rpg_rocket()` ✅
