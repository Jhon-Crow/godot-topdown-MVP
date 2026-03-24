# Case Study: Issue #1307 — RPG Rocket Does Not Explode When Hit

## Problem Statement

The RPG rocket projectile does not explode when shot by the player's bullets.
(Russian: "ракета РПГ не взрывается от попадания")

## Timeline of Events (from game_log_20260322_060618.txt)

1. **06:12:04** — RpgEnemy1 fires rocket at `(3552, 1334)`, health=1
2. **06:12:04** — RpgEnemy2 fires rocket at `(1928, 2018)`, health=1
3. **06:12:05** — First rocket impacts a RigidBody2D after 1.11s → explodes normally
4. **06:12:06** — Second rocket impacts CoverTall1 (StaticBody2D) after 1.53s → explodes normally
5. **06:12:39** — RpgEnemy1 fires another rocket
6. **06:12:42** — Rocket impacts Player after 2.31s → explodes normally
7. **06:13:13** — RpgEnemy2 fires another rocket
8. **06:13:21** — Rocket impacts WallLeft after 1.96s → explodes normally

**Zero "Hit!" or "Shot down" events in entire log** — despite player firing hundreds of bullets
in the vicinity of rockets. The interception mechanism never triggers.

## Root Cause Analysis

### Architecture

The RPG rocket uses `scenes/projectiles/RpgRocket.tscn` which instantiates `bullet.gd`
with `is_rpg_rocket = true`. The rocket is an **Area2D** on collision layer 5 (bitmask 16).

Player bullets also use `bullet.gd` (without `is_rpg_rocket`) — also Area2D on
collision layer 5 (bitmask 16).

### Collision Layer Configuration

| Entity     | collision_layer | collision_mask | Layers monitored |
|------------|----------------|----------------|------------------|
| Bullet     | 16 (layer 5)   | 39 (1,2,3,6)   | 1,2,3,6          |
| RPG Rocket | 16 (layer 5)   | 55 (1,2,3,5,6) | 1,2,3,5,6        |

### Signal Flow Analysis

For Godot Area2D `area_entered` signal to fire between two Area2Ds, **at least one** of:
- A.collision_mask includes B.collision_layer, OR
- B.collision_mask includes A.collision_layer

**Bullet → Rocket detection**: bullet.mask(39) & rocket.layer(16) = 0 → **NO signal on bullet**
**Rocket → Bullet detection**: rocket.mask(55) & bullet.layer(16) = 16 → **Signal fires on rocket**

So only the **rocket** receives `_on_area_entered` when a bullet overlaps it.

### The Skip Logic (the actual bug)

In `bullet.gd` line 615–631, the rocket's `_on_area_entered` handler has:

```gdscript
# RPG rocket: explode when hitting any hit-area (enemy/player HitArea)
if is_rpg_rocket:
    ...
    # Skip other projectiles on the projectiles collision layer (Issue #1133).
    if area.collision_layer & 16:
        return
```

This skips **all** areas on layer 5 — including player bullets. The comment says
"They interact with the rocket via their own `_on_area_entered` which calls
`rocket.on_hit()` directly." But this is incorrect: bullets have `collision_mask = 39`
which does NOT include layer 5, so bullets never receive `_on_area_entered` for the rocket.

### Secondary Issue: Intercept vs Explode

Even if the collision were detected, `on_hit()` (line 2156) calls `_rpg_intercept()`
which **silently destroys** the rocket (small white flash, no explosion AOE).
The issue requests the rocket to **explode** when hit.

## Root Causes Summary

1. **Primary**: The rocket's `_on_area_entered` skips all layer-5 areas (line 623),
   blocking bullet detection. Bullets cannot detect the rocket either (mask mismatch).
2. **Secondary**: `on_hit()` calls `_rpg_intercept()` (silent destruction) instead of
   `_rpg_explode()` (full explosion with AOE damage, sound, visual effects).

## Fix

1. In the rocket's `_on_area_entered`, when detecting a layer-5 area that is NOT
   another RPG rocket (`is_rpg_rocket` == false), treat it as an incoming bullet hit
   and call `on_hit()`.
2. Change `on_hit()` to call `_rpg_explode()` instead of `_rpg_intercept()` so the
   rocket detonates with full explosion effects when shot.
