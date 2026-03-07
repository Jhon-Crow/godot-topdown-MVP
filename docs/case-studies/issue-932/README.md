# Case Study: Issue #932 — Fix Force Field (Силовое поле)

## Issue Description

**Report**: "fix силовое поле"

1. Силовое поле должно ловить пули — они должны прилипать на границе поля, как в остановленном времени при особом последнем шансе.
2. Когда силовое поле исчезает — пули должны разлетаться в разные стороны от игрока.

(Translation: 1. The force field should catch bullets — they should stick to the boundary of the field, as in stopped time at a special last chance. 2. When the force field disappears — the bullets should fly off in different directions away from the player.)

---

## Background

This is the fourth consecutive issue on the force field feature:
- **#676**: Force field not activating at all (missing `InitForceField()` in `Player.cs`)
- **#906**: Requested bullet trapping + bubble visual
- **#912**: Force field not trapping bullets (C# `QueueFree()` race condition)
- **#932 (PR #933 v1)**: Added boundary snapping (`_snap_to_boundary()`) — but bullets still weren't trapped
- **#932 (PR #933 v2)**: Root cause found — GDScript/C# `in` operator interop bug (this fix)

---

## Root Cause Analysis

### Part 1: Boundary snapping (PR #933 v1)

The previous `_trap_bullet()` in `force_field_effect.gd` (as of PR #913) correctly:
- Stopped the bullet's physics process
- Stored it in `_trapped_bullets`

But it did NOT reposition the bullet to the boundary of the force field. PR #933 v1 added `_snap_to_boundary()` to fix this. However, after deployment, the owner reported the fix still didn't work.

### Part 2: GDScript/C# `in` operator bug (root cause of "не работает")

**Game log evidence** (`game_log_20260301_030334.txt`):

Every time a C# `Bullet.cs` enters the force field, the log shows:
```
[ForceFieldEffect] Area entered: Bullet (script: res://Scripts/Projectiles/Bullet.cs)
[ForceFieldEffect] Bullet missing properties — has_direction=false has_speed=false class=Area2D — skipping trap
[ForceFieldEffect] DIAGNOSTIC: Bullet survived trap — C# fix is active
[Player] Hit blocked by force field (C#)
```

The force field detects bullets but **never traps them** — the property check always fails, returning `has_direction=false has_speed=false`. On every deactivation: **"Released 0 trapped projectiles"**.

**Why?** The code used:
```gdscript
var has_direction := "direction" in bullet   # ← ALWAYS FALSE for C# nodes!
var has_speed := "speed" in bullet           # ← ALWAYS FALSE for C# nodes!
```

In Godot 4, the GDScript `in` operator checks the node's **GDScript property table**. For C# nodes (`partial class Bullet : Area2D`), this table only contains the base Godot class properties (`Area2D`). C# `[Export]` properties like `Direction` and `Speed` are NOT in this table, so `"direction" in bullet` always returns `false`.

This is confirmed by the log's `class=Area2D` — `get_class()` returns the base Godot type for C# nodes.

**The correct pattern** (already used in level scripts throughout the codebase for other C# properties):
```gdscript
# From building_level.gd, revolver_level.gd, etc.:
weapon.get("CurrentAmmo")    # PascalCase for C# [Export] properties
weapon.get("ReserveAmmo")
```

For bullet properties which use GDScript-friendly snake_case names:
```gdscript
bullet.get("direction") != null   # Works for BOTH C# [Export] and GDScript vars
bullet.get("speed") != null
```

The `Node.get()` method correctly resolves C# exported properties (registered as snake_case), while the `in` operator does not.

---

## Fix Applied

Replaced all `"prop" in node` checks with `node.get("prop") != null` in `force_field_effect.gd`:

```gdscript
# BEFORE (broken for C# Bullet/ShotgunPellet nodes):
var has_direction := "direction" in bullet   # always false
var has_speed := "speed" in bullet           # always false
if not has_direction or not has_speed:
    return  # always skips the trap!

# AFTER (works for both C# and GDScript nodes):
var has_direction := bullet.get("direction") != null
var has_speed := bullet.get("speed") != null
if not has_direction or not has_speed:
    return  # only skips if property truly doesn't exist
```

Also fixed property writes to use `.set()` instead of direct assignment:
```gdscript
# BEFORE:
if "shooter_id" in bullet:
    bullet.shooter_id = -1

# AFTER:
if bullet.get("shooter_id") != null:
    bullet.set("shooter_id", -1)
```

---

### Part 3: Force field trapping player's own bullets (PR #933 v3)

After v2 fix was applied, the owner tested again and reported:
> "сейчас щит останавливает пули игрока, а не врагов"
> (Translation: "now the shield stops the player's bullets, not the enemies'")

**Game log evidence** (`game_log_20260306_001151.txt`):

```
[SoundPropagation] Sound emitted: type=GUNSHOT, pos=(450, 1250), source=PLAYER (MiniUzi), range=1469
[ForceFieldEffect] Area entered: Bullet9mm (script: res://scripts/projectiles/bullet.gd)
[ForceFieldEffect] Bullet trapped at boundary (class=Area2D). Total trapped: 1
```

The player is shooting with MiniUzi (`source=PLAYER (MiniUzi)`) and all those bullets are being trapped. The force field was trapping ALL bullets in range — including those fired by the player.

**Root cause**: `_trap_bullet()` and `_trap_shrapnel()` had no check for who fired the projectile. Any bullet with `direction` and `speed` properties would be trapped, regardless of whether it was fired by an enemy or by the player.

**Why this wasn't caught earlier**: In PR #933 v2, the owner had invincibility mode enabled (`[ExperimentalSettings] Invincibility: true`). The player fired first and those bullets filled the field. The expected behavior (enemy bullets being trapped) was never tested.

**Fix (PR #933 v3)**: Added `_is_player_projectile()` helper that looks up the shooter via `instance_from_id(shooter_id)` and checks `is_in_group("player")`. Both `_trap_bullet()` and `_trap_shrapnel()` call this before trapping and skip player-fired projectiles.

---

## Prior Issues on This Feature

| Issue | Description | Fix |
|-------|-------------|-----|
| #676 | Force field not activating | Added `InitForceField()` in `Player.cs` |
| #912 | C# bullets destroying themselves before force field traps them | `IsForceFieldArea()` check in `Bullet.cs`/`ShotgunPellet.cs` |
| #932 v1 | Bullets not snapping to boundary ring | Added `_snap_to_boundary()` and `_update_trapped_positions()` |
| #932 v2 | Trap never executes — GDScript `in` operator bug | Replace `"prop" in node` with `node.get("prop") != null` |
| #932 v3 | Force field traps player's own bullets | **This fix**: Added `_is_player_projectile()` check using `shooter_id` + `is_in_group("player")` |

---

## Files Modified

1. `scripts/effects/force_field_effect.gd` — Replace `"prop" in node` with `node.get("prop") != null` throughout; add `_is_player_projectile()` to skip player-fired projectiles

## Attached Data

- `game_log_20260301_030334.txt` — Full game session log showing v1 bug (7,015 lines)
- `logs/game_log_20260302_185211.txt` — Game log showing v2 bug (bullets disappear — older build)
- `logs/game_log_20260306_001151.txt` — Game log showing v3 bug (player bullets trapped)

---

## Key Facts

- **FIELD_RADIUS**: 35px — the force field boundary radius
- **Boundary snap**: `global_position + direction_to_bullet.normalized() * FIELD_RADIUS`
- C# `[Export]` properties are accessible via `node.get("snake_case_name")` from GDScript — but NOT via the `in` operator
- C# bullets (Bullet.cs, ShotgunPellet.cs) have `IsForceFieldArea()` checks to prevent `QueueFree()` when entering force field area (from PR #913)
- GDScript bullet (`bullet.gd`) naturally doesn't destroy itself when entering force field area because it only calls `_destroy()` when `area.has_method("on_hit")`, and the force field area does not have that method
- `shooter_id` is set on every bullet by the weapon when spawning; Player is in `"player"` group (in `scenes/characters/Player.tscn`); enemies are in `"enemies"` group (added via `add_to_group("enemies")` in `enemy.gd`)
