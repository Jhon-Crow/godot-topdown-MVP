# Case Study: Issue #829 — Revolver Bullets Should Pass Through Enemies

## Overview

**Issue:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/829
**PR:** https://github.com/Jhon-Crow/godot-topdown-MVP/pull/834
**Game log:** `game_log_20260219_200947.txt` (in this folder)
**Date of bug report:** 2026-02-19
**Reported by:** Jhon-Crow (project owner)

### Summary

The RSh-12 revolver fires 12.7x55mm armor-piercing rounds. Per the issue, these bullets should pass through enemies rather than stopping on contact. The first implementation attempt (commit `a253ddac`) added a `PenetratesEnemies` flag to `WeaponData`, `Bullet.cs`, and `bullet.gd`, and set `PenetratesEnemies = true` in `RevolverData.tres`. However, the owner confirmed in comment https://github.com/Jhon-Crow/godot-topdown-MVP/pull/834#issuecomment-... that "revolver bullets still don't pass through enemies."

---

## Timeline / Sequence of Events

| Time | Event |
|------|-------|
| 2026-02-19 16:19 | AI solver session 1 starts, implements `PenetratesEnemies` feature |
| 2026-02-19 16:25 | PR #834 created as draft, solution log posted |
| 2026-02-19 16:25 | Auto-restart triggered (uncommitted `build-output.log`) |
| 2026-02-19 16:29 | Session 2 completes, PR marked "Ready to merge" |
| 2026-02-19 17:12 | Owner Jhon-Crow tests the exported game build (`game_log_20260219_200947.txt`) |
| 2026-02-19 17:12 | Owner confirms: "пули револьвера всё ещё не проходят сквозь врагов." (bullets still don't pass through) |
| 2026-02-19 17:12 | Owner requests a case study and deep root cause analysis |
| 2026-02-19 19:00 | AI session 3 (this session) starts, PR reverted to draft |

---

## Architecture: How Bullet Collision Works

The Godot Top-Down Template uses a two-layer collision system for bullets and enemies:

```
Bullet (Area2D)                    Enemy
 ├── collision_layer = 16           ├── CharacterBody2D
 └── collision_mask  = 39               ├── collision_layer = 2
     (layers 1,2,3,6)                   └── HitArea (Area2D)
                                             └── collision_layer = 2
                                                 collision_mask  = 16
```

Because the bullet's `collision_mask = 39` includes layer 2 (bits: `39 = 0b00100111` = layers 1, 2, 3, 6), the bullet detects collisions with **both**:

1. The enemy's `CharacterBody2D` (layer 2) → triggers `_on_body_entered` / `OnBodyEntered`
2. The enemy's `HitArea` (Area2D, layer 2) → triggers `_on_area_entered` / `OnAreaEntered`

---

## Root Cause Analysis

### Primary Root Cause: `PenetratesEnemies` check is absent from `_on_body_entered`

The `penetrates_enemies` / `PenetratesEnemies` flag was **only added to `_on_area_entered`** (the `HitArea` path), but **not to `_on_body_entered`** (the `CharacterBody2D` body path).

In `bullet.gd` (line 324–393) and `Bullet.cs` (line 461–562), the `_on_body_entered` / `OnBodyEntered` handler:

1. Checks if the body is the shooter → return
2. Checks if the body is dead → return
3. Checks if already penetrating the same body → return
4. Checks if inside a penetration hole → return
5. **If the body is a `StaticBody2D` or `TileMap`:** runs wall ricochet/penetration logic
6. **Falls through for any other body type** (including alive `CharacterBody2D` enemy): plays a *wall hit sound* and calls `queue_free()` — destroying the bullet

This means: **when the bullet's collision shape enters the enemy's `CharacterBody2D`, the bullet is immediately destroyed with a wall sound and no damage, bypassing all `PenetratesEnemies` logic.**

Evidence from game log:
```
[20:09:56] [ENEMY] [Enemy2] Enemy died (ricochet: false, penetration: false)
[20:10:22] [ENEMY] [Enemy3] Enemy died (ricochet: false, penetration: false)
... (17/17 enemy deaths show penetration: false)
```

The log line `[Bullet]: Penetrating through enemy, bullet continues flying` (added in `_on_area_entered`) **never appears** in the entire 1.1 MB game log. This confirms the penetration path was never reached.

### Secondary Issue: Re-triggering on same enemy

Even if `_on_body_entered` were fixed, a penetrating bullet would repeatedly trigger `_on_area_entered` each physics frame while overlapping the enemy's HitArea (since Area2D generates `area_entered` once on entry). However, after the bullet exits and re-enters an enemy due to physics frame timing, it could re-apply damage. A `_penetrated_enemies` set is needed to track which enemies have already been hit per-bullet.

### Why the Implementation Appeared Correct

The `PenetratesEnemies` code in `_on_area_entered` is syntactically correct and would work — but it is unreachable in practice because `_on_body_entered` destroys the bullet first. The Godot physics engine processes body collisions before or simultaneously with area collisions. Since both the CharacterBody2D and HitArea are on layer 2, and the bullet mask includes layer 2, both callbacks are queued — but the body collision fires first (or the body collision `queue_free()` cancels the area collision before it can be processed).

---

## The Fix

### 1. `bullet.gd` — add `penetrates_enemies` handling in `_on_body_entered`

In `_on_body_entered`, after the existing shooter/dead-entity checks, add a check for alive CharacterBody2D enemies when `penetrates_enemies` is true:

```gdscript
# After the dead-entity check, before the StaticBody2D block:
# Issue #829: If this is an alive enemy body and bullet penetrates enemies,
# pass through without destroying the bullet.
if penetrates_enemies and body.has_method("is_alive") and body.is_alive():
    if body not in _penetrated_enemy_bodies:
        _penetrated_enemy_bodies.append(body)
        print("[Bullet]: Penetrating through enemy body (CharacterBody2D), bullet continues")
    return  # Don't destroy the bullet
```

Add `var _penetrated_enemy_bodies: Array = []` to track which bodies have been passed through.

### 2. `Bullet.cs` — same fix in `OnBodyEntered`

Add equivalent logic before the `StaticBody2D`/`TileMap` block.

---

## Impact Assessment

- **All 17 enemy deaths in the game session** occurred with `penetration: false`
- **Zero occurrences** of the penetration print statement in 1.1 MB of logs
- The feature was effectively non-functional despite appearing to be implemented
- The fix requires ~10 lines of code in each of `bullet.gd` and `Bullet.cs`

---

## References

- Godot Area2D collision signal docs: https://docs.godotengine.org/en/stable/classes/class_area2d.html
- Godot issue #62506 (deferred collision shape disabling): https://github.com/godotengine/godot/issues/62506
- Game log: `game_log_20260219_200947.txt`
- Implementation commit: `a253ddac feat: revolver bullets pass through enemies (Issue #829)`
