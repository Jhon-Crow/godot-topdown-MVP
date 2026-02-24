# Case Study: Issue #781 — Homing Bullets Don't Work for Pistol Bullets

## Summary

Homing bullets (active item) do not function correctly for pistol-type weapons:
MakarovPM, MiniUzi, SilencedPistol, and Revolver. When the homing effect is
activated and these weapons are fired, bullets either fly in the wrong direction
(rightward by default) or fail to home toward enemies.

---

## Timeline of Events

| Date | Event |
|------|-------|
| Before 2026-02-15 | Issue #677 implemented homing bullets for the M16/AssaultRifle using C# `Bullet.cs`. |
| Before 2026-02-15 | Issue #704 added aim-line targeting (select enemy nearest to crosshair) for shotgun pellets. |
| Before 2026-02-15 | Issue #709 added wall-aware homing (skip enemies behind walls). |
| 2026-02-15 | Issue #781 opened: pistol bullets don't work with homing. |
| 2026-02-15 | PR #783 attempted fix: added setter methods + `enable_homing_with_aim_line` to `bullet.gd`. **CLOSED without merge** due to pistol bullet display/movement breaking. |
| 2026-02-16 | PR #812 attempted fix: only added `enable_homing_with_aim_line` to `bullet.gd`, skipped direction setter fix. **CLOSED without merge**. |
| 2026-02-19 | Issue owner requests new attempt taking past failures into account. |
| 2026-02-19 | PR #867 first commit — adds `Call()` setter methods, fixes direction. Verified homing still not working. |
| 2026-02-20 | Owner tests build from commit `0de505b6`. Reports homing STILL not working. Attaches game logs. Hints "check language conflicts and imports". |
| 2026-02-24 | Deep analysis of game logs reveals two additional bugs: `_is_player_bullet()` case sensitivity and `shooter_id` 64-bit truncation. PR #867 updated with complete fix. |

## Game Logs

Two game logs were attached by the owner after testing the initial fix:

- [`game-logs/game_log_20260220_004007.txt`](game-logs/game_log_20260220_004007.txt) — 14,137 lines, MakarovPM → MiniUzi → SilencedPistol → Revolver test
- [`game-logs/game_log_20260220_004330.txt`](game-logs/game_log_20260220_004330.txt) — 1,791 lines, focused homing bullet test (directory named "Самонаводящиеся пули" = "Homing bullets")

**Key observations from logs:**
- No script errors (zero `[ERROR]` level lines)
- `Player.Homing` lifecycle works correctly (activation/expiry)
- Bullets fired correctly (gunshot sounds logged)
- No `[Bullet]` homing debug output — because `_debug_homing = false` by default AND because `_apply_homing_steering` was returning early due to `_is_player_bullet()` returning false
- `shooter_id` values observed: `268437662` (first log) — within 32-bit range, `118497479586` (second log) — beyond 32-bit range, confirming the truncation bug

---

## Root Cause Analysis

### Architecture Overview

The game has two bullet implementations:
- **`Scripts/Projectiles/Bullet.cs`** — C# bullet used by AssaultRifle, SniperRifle, Shotgun pellets
- **`scripts/projectiles/bullet.gd`** — GDScript bullet used by pistol/SMG weapons via `Bullet9mm.tscn` and `Bullet12p7mm.tscn`

### Root Cause 1: C# to GDScript Property Interop Failure

C# weapons (MakarovPM, SilencedPistol, MiniUzi, Revolver) set bullet properties via `Node.Set()`:

```csharp
bullet.Set("direction", direction);    // SILENTLY FAILS
bullet.Set("shooter_id", id);          // SILENTLY FAILS
bullet.Set("shooter_position", pos);   // SILENTLY FAILS
```

**This is the core bug.** In Godot 4, `Node.Set()` called from C# only works for **`@export` variables** in GDScript. The `direction`, `shooter_id`, `shooter_position`, `stun_duration` variables in `bullet.gd` are NOT exported:

```gdscript
# In bullet.gd — these are NOT @export:
var direction: Vector2 = Vector2.RIGHT    # stays RIGHT (default)
var shooter_id: int = -1                   # stays -1 (no self-hit prevention)
var shooter_position: Vector2 = Vector2.ZERO
var stun_duration: float = 0.0
```

**Effect**: All pistol bullets fly RIGHT regardless of aim direction.

**Reference**: [Godot docs — C# to GDScript interop](https://docs.godotengine.org/en/stable/tutorials/scripting/cross_language_scripting.html)

### Root Cause 2: Missing `enable_homing_with_aim_line` in `bullet.gd`

The C# `BaseWeapon.SpawnBullet()` checks for `enable_homing_with_aim_line` first, then falls back to `enable_homing`. Since `bullet.gd` only had `enable_homing()`, the fallback worked. However, without the direction being set correctly (Root Cause 1), homing had no effect since the bullet was flying RIGHT already.

### Root Cause 3: `_is_player_bullet()` case sensitivity (NEWLY DISCOVERED)

Even after the `Call()` setter fix (Root Causes 1 & 2), homing still didn't work because `_apply_homing_steering()` has this guard:

```gdscript
func _apply_homing_steering(delta: float) -> void:
    if not _is_player_bullet():
        return  # Always returned here for C# pistol bullets!
```

The OLD `_is_player_bullet()` implementation used a **case-sensitive** script path check:

```gdscript
# BROKEN: case-sensitive check
var script: Script = shooter.get_script()
if script and script.resource_path.contains("player"):  # LOWERCASE
    return true
```

The C# Player's script path is `res://Scripts/Characters/Player.cs` — which contains `"Player"` (capital P) but NOT `"player"` (lowercase p). Therefore `_is_player_bullet()` **always returned false** for C# pistols, and homing steering never ran.

**Fix**: Use `is_in_group("player")` instead — same pattern used everywhere else in the codebase (grenades, enemies, ricochet code):

```gdscript
# FIXED: group membership
if shooter is Node and (shooter as Node).is_in_group("player"):
    return true
```

The C# Player node has `groups=["player"]` in `scenes/characters/csharp/Player.tscn`, so this check always succeeds.

### Root Cause 4: `shooter_id` 64-bit truncation

`GetInstanceId()` returns a `ulong` (64-bit unsigned), but C# code cast it to `(int)` (32-bit signed):

```csharp
bullet.Call("set_shooter_id", (int)owner.GetInstanceId());  // Truncates high bits!
```

The second game log shows `shooter_id=118497479586` — a value that exceeds `int.MaxValue` (2,147,483,647). When cast to `int`, this becomes a different (negative) number. Then `instance_from_id(shooter_id)` returns null (no node with that truncated ID), and `_is_player_bullet()` returns false even before the group check.

**Fix**: Cast to `(long)` to preserve all 64 bits:

```csharp
bullet.Call("set_shooter_id", (long)owner.GetInstanceId());  // Preserves full ID
```

### Why Previous Attempts Failed

**PR #783** (correct diagnosis, wrong timing):
- Added setter methods to `bullet.gd` ✅
- Added `enable_homing_with_aim_line` to `bullet.gd` ✅
- Called `AddChild()` BEFORE calling setter methods ❌

The mistake: when `AddChild()` is called, Godot runs `_ready()`. At that point `direction = Vector2.RIGHT` (default). Then setter methods were called AFTER `_ready()` — which works for movement, but initial rotation was set incorrectly in `_ready()`, and `is_breaker_bullet` check in `_ready()` fired before `set_is_breaker_bullet()` was called.

**PR #812** (incomplete fix):
- Added `enable_homing_with_aim_line` to `bullet.gd` ✅
- Did NOT add setter methods ❌
- Bullets still flew RIGHT because `Set("direction", ...)` still failed silently

**PR #867 first commit (0de505b6)** (good fix, but incomplete):
- Added setter methods BEFORE `AddChild()` ✅
- Added `enable_homing_with_aim_line()` to `bullet.gd` ✅
- Fixed `Node.Set()` → `Call()` for GDScript bullets ✅
- `_is_player_bullet()` case sensitivity bug remained ❌ (homing steering still always skipped)
- `shooter_id` cast used `(int)` truncation ❌ (ID lookup failed for large IDs)

---

## The Correct Fix (PR #867)

### Fix 1: Add setter methods to `bullet.gd`

Methods callable from C# via `Call()` that work BEFORE `AddChild()`:

```gdscript
func set_direction(dir: Vector2) -> void:
    direction = dir.normalized()
    _update_rotation()

func set_speed(spd: float) -> void:
    speed = spd

func set_damage(dmg: float) -> void:
    damage = dmg

func set_shooter_id(id: int) -> void:
    shooter_id = id

func set_shooter_position(pos: Vector2) -> void:
    shooter_position = pos

func set_stun_duration(duration: float) -> void:
    stun_duration = duration

func set_is_breaker_bullet(is_breaker: bool) -> void:
    is_breaker_bullet = is_breaker

func set_penetrates_enemies(penetrate: bool) -> void:
    penetrates_enemies = penetrate
```

### Fix 2: Add `enable_homing_with_aim_line` to `bullet.gd`

Matches C# `Bullet.cs.EnableHomingWithAimLine()` behavior with aim-line targeting
and wall-awareness (Issue #709):

```gdscript
func enable_homing_with_aim_line(shooter_pos: Vector2, aim_dir: Vector2) -> void:
    homing_enabled = true
    _homing_original_direction = direction.normalized()
    _use_aim_line_targeting = true
    _homing_shooter_origin = shooter_pos
    _homing_aim_direction = aim_dir.normalized()
```

### Fix 3: Update C# weapons to call setters BEFORE `AddChild()`

In `BaseWeapon.cs`, `MakarovPM.cs`, and `SilencedPistol.cs`, replace `Set()` calls with `Call()` setter methods, ensuring they are called BEFORE `AddChild()`. Also cast `GetInstanceId()` to `(long)` not `(int)`:

```csharp
// BEFORE AddChild() — so _ready() sees correct values
bulletNode.Call("set_direction", direction);
bulletNode.Call("set_speed", WeaponData.BulletSpeed);
bulletNode.Call("set_damage", WeaponData.Damage);
bulletNode.Call("set_shooter_id", (long)owner.GetInstanceId());  // (long) not (int)!
bulletNode.Call("set_shooter_position", GlobalPosition);
bulletNode.Call("set_stun_duration", StunDurationOnHit);

GetTree().CurrentScene.AddChild(bulletNode);  // _ready() runs here with correct values

// AFTER AddChild() — homing needs scene tree for physics raycasts
bulletNode.Call("enable_homing_with_aim_line", player.GlobalPosition, aimDir);
```

### Key Insight: Why BEFORE AddChild()

`Call()` works on any GDScript node regardless of scene tree membership. Calling setter methods before `AddChild()` ensures:
1. `_ready()` runs with correct `direction` → initial rotation is correct
2. `is_breaker_bullet` is set → `_ready()` loads the shrapnel scene correctly
3. Homing is called AFTER `AddChild()` because `_has_line_of_sight_to_target()` needs `get_world_2d()` which requires scene tree membership

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/projectiles/bullet.gd` | **Fix `_is_player_bullet()`** to use `is_in_group("player")` instead of broken case-sensitive script path check; added C# interop setter methods, `enable_homing_with_aim_line()`, `_find_enemy_nearest_to_aim_line()`, `_has_line_of_sight_to_target()`, wall-awareness in `_find_nearest_enemy_position()` |
| `Scripts/AbstractClasses/BaseWeapon.cs` | Cast `GetInstanceId()` to `(long)` not `(int)`; updated `SpawnBullet()` to use `Call()` setters before `AddChild()` for GDScript bullets |
| `Scripts/Weapons/MakarovPM.cs` | Cast `GetInstanceId()` to `(long)`; updated `SpawnBullet()` to use `Call()` setters before `AddChild()` |
| `Scripts/Weapons/SilencedPistol.cs` | Cast `GetInstanceId()` to `(long)`; updated `SpawnBullet()` to use `Call()` setters before `AddChild()` |
| `tests/unit/test_homing_bullets.gd` | Added tests for aim-line homing behavior (Issue #781) |
| `docs/case-studies/issue-781/game-logs/` | Added owner-attached game logs from test sessions on 2026-02-20 |

---

## Affected Weapons

| Weapon | Bullet Scene | Fix Applied |
|--------|-------------|-------------|
| MakarovPM | `Bullet9mm.tscn` (bullet.gd) | SpawnBullet in `MakarovPM.cs` |
| SilencedPistol | `Bullet9mm.tscn` (bullet.gd) | SpawnBullet in `SilencedPistol.cs` |
| MiniUzi | `Bullet9mm.tscn` (bullet.gd) | SpawnBullet via `BaseWeapon.cs` |
| Revolver (RSh-12) | `Bullet12p7mm.tscn` (bullet.gd) | SpawnBullet via `BaseWeapon.cs` |

---

## References

- [Godot 4 C# interop docs](https://docs.godotengine.org/en/stable/tutorials/scripting/cross_language_scripting.html)
- [Node.Set() behavior for non-export properties](https://github.com/godotengine/godot/issues/62506)
- Issue #677: Initial homing bullets implementation
- Issue #704: Aim-line targeting for shotgun pellets
- Issue #709: Wall-aware homing
- PR #783: Previous attempt (wrong AddChild timing)
- PR #812: Previous attempt (missing direction fix)
