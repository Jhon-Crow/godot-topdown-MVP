# Case Study: Enemy Force Field Does Not Trap Player Bullets (Issue #1034)

## Overview

**Date**: 2026-03-16
**Reported by**: Jhon-Crow (repository owner)
**PR**: #1042
**Log file**: `game_log_20260316_232833.txt`

**Bug summary**: The Force Field Enemy spawns correctly and its force field visually activates, but player bullets pass through the field and damage the enemy normally. The force field only traps *enemy* bullets (from other enemies), which is the opposite of the intended behavior.

---

## Timeline / Sequence of Events

| Time | Event |
|------|-------|
| 23:28:33 | Game starts in LabyrinthLevel |
| 23:28:37 | ForceFieldEnemy spawns at (1600, 850), hp=2 |
| 23:28:37 | `ForceFieldEffect` initializes with 8.0s charge |
| 23:28:37 | `EnemyForceFieldComponent` setup complete (duration=4.0s, recharge=20.0s) |
| 23:28:42 | ForceFieldEnemy spots player → State: IDLE → PURSUING |
| 23:28:42 | ForceFieldEnemy takes hit (hp: 2→1), triggering COMBAT |
| 23:28:42 | **Force field activates** (`[EnemyForceField] Activated`) |
| 23:28:44 | Player fires → bullet enters force field area |
| 23:28:44 | **`[ForceFieldEffect] Skipping player bullet — force field only traps enemy bullets`** |
| 23:28:44 | ForceFieldEnemy takes hit (hp: 1→0) → dies |
| 23:28:46 | ForceFieldEnemy respawns (hp=3), force field reinitializes |
| 23:28:49 | Force field activates again |
| 23:28:50 | Player fires 3 shots → all 3 bullets **skip trap** → enemy dies (hp: 3→0) |
| 23:28:51 | After enemy death: enemy bullets from `Bullet.cs` **ARE trapped** correctly |

**Key log evidence** (lines 687–690 and 1119–1123):
```
[ForceFieldEffect] Area entered: Bullet9mm (script: res://scripts/projectiles/bullet.gd)
[ForceFieldEffect] Skipping player bullet — force field only traps enemy bullets (class=Area2D)
[ForceFieldEffect] DIAGNOSTIC: Bullet survived trap — C# fix is active
[ForceFieldEnemy] Hit: dmg=1, hp=2/2->1/2
```

And after the enemy dies — enemy C# bullets ARE trapped:
```
[ForceFieldEffect] Area entered: @Area2D@1332 (script: res://Scripts/Projectiles/Bullet.cs)
[ForceFieldEffect] Bullet trapped at boundary (class=Area2D). Total trapped: 1
```

---

## Root Cause Analysis

### Architecture Background

The `ForceFieldEffect.tscn` / `force_field_effect.gd` was originally built for the **player's** force field (Issues #676, #906, #912, #930, #932). It contains the method `_is_player_projectile()` which checks whether a bullet was fired by the player, and **skips trapping it** — so the player doesn't accidentally trap their own bullets.

```gdscript
# In force_field_effect.gd, _trap_bullet():
if _is_player_projectile(bullet):
    FileLogger.info("[ForceFieldEffect] Skipping player bullet — force field only traps enemy bullets")
    return
```

### What Went Wrong

When Issue #1034 added the ForceField Enemy, the implementation reused the same `ForceFieldEffect.tscn` scene via `EnemyForceFieldComponent`. However, the `force_field_effect.gd` has **no concept of who owns the force field** — it assumes the owner is always the player and therefore always skips player bullets.

When an **enemy** uses this force field:
- The field is meant to **protect the enemy from player bullets**
- But the hardcoded `_is_player_projectile()` check skips player bullets
- So player bullets **pass through** the enemy's force field
- Enemy bullets (from `Bullet.cs` with enemy `ShooterId`) ARE trapped (by accident — because they're not player bullets)

### Why Enemy Bullets Were Being Trapped

The log shows enemy `Bullet.cs` bullets **were** being trapped after the ForceFieldEnemy died (lines 1164-1175). This is because those C# bullets have `ShooterId` pointing to the enemy node, so `_is_player_projectile()` returns `false`, and they are trapped. This is the **opposite** of the intended behavior for an enemy force field.

### Summary of Root Cause

| Aspect | Player Force Field (correct) | Enemy Force Field (broken) |
|--------|------------------------------|---------------------------|
| Intended behavior | Trap enemy bullets | Trap player bullets |
| Actual behavior | ✅ Traps enemy bullets | ❌ Traps enemy bullets (wrong) |
| What passes through | ✅ Player bullets (correct) | ❌ Player bullets (bug) |

**Root cause**: `ForceFieldEffect` hardcodes "skip player bullets" with no way to invert this for enemy-owned force fields.

---

## Online Research Findings

This class of bug is well-known in game development:

1. **"Component reuse inversion problem"** — When a component is designed for one actor type and reused by the opposing type, behavior predicates need to be inverted. Common in enemy/player symmetrical mechanics (shields, walls, buffs).

2. **Godot collision/group pattern** — The standard Godot approach to distinguish "friendly" vs "hostile" projectiles is via collision layers (e.g., layer 5 = player bullets, layer 6 = enemy bullets) or node groups (`"player_projectile"` vs `"enemy_projectile"`). The existing code uses shooter node group membership (`is_in_group("player")`), which is correct but needs to be aware of the field owner.

3. **"Friendly fire" / "owner awareness"** — The fix pattern is an `owner_is_player: bool` flag on the component, defaulting to `true`, which the enemy component sets to `false`. This inverts the predicate: instead of "skip if player bullet", it becomes "skip if not player bullet" (i.e., skip enemy bullets).

---

## Proposed Solution

Add an `owner_is_player: bool` variable to `force_field_effect.gd` (default `true` for backward compatibility with player force field). The `EnemyForceFieldComponent` sets `owner_is_player = false` after instantiating the scene.

**In `force_field_effect.gd`**:
```gdscript
## Whether this force field is owned by the player (true) or an enemy (false).
## When false, the field traps player projectiles and ignores enemy projectiles.
var owner_is_player: bool = true

# In _trap_bullet():
var is_player_proj := _is_player_projectile(bullet)
var should_skip := (owner_is_player and is_player_proj) or (not owner_is_player and not is_player_proj)
if should_skip:
    FileLogger.info("[ForceFieldEffect] Skipping %s bullet (owner_is_player=%s)" % [
        "player" if is_player_proj else "enemy", owner_is_player])
    return
```

**In `enemy_force_field_component.gd`** `setup()`:
```gdscript
_force_field_effect.set("owner_is_player", false)
```

This change is minimal, backward-compatible (player force field unaffected), and directly inverts the predicate for the enemy case.
