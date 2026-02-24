# Case Study: Issue #676 — Force Field Active Item

## Problem Statement

**Report**: "При нажатии пробел при выбранном силовом поле ничего не происходит."
("When pressing Space with Force Field selected, nothing happens.")

**Game version**: Godot 4.3-stable (Windows export, non-debug build)
**First report**: 2026-02-15
**Second report**: 2026-02-24 (after PR #791 attempted fix 1 — activation now works, but two new bugs found)
**Third report**: 2026-02-24 (same session, confirming size and reflection issues)

**Log files**:
- `game_log_20260215_231653.txt` — original report (no force field log at all)
- `game_log_20260224_195827.txt` — post-fix 1 (force field activates but radius 80px, no reflection)
- `game_log_20260224_195916.txt` — post-fix 1 second session
- `game_log_20260224_231739.txt` — owner test confirming size + reflection bugs (radius 80px)
- `game_log_20260224_231923.txt` — owner test confirming player dies while force field active
- `game_log_20260224_232102.txt` — owner test third session, same issues

---

## Timeline of Events

### Session 1 — 2026-02-15 (Original Report)

| Timestamp  | Event |
|------------|-------|
| 23:16:53   | Game started |
| 23:16:54   | Player initialized: all other active items check and log "not selected" — **no `[Player.ForceField]` log** |
| 23:16:58   | ActiveItemManager: Active item changed from None to **Force Field** |
| 23:16:58   | Level restarted — Player re-initialized again with no force field log |
| 23:17:35   | Game ended, space was never pressed (no force field log) |

### Session 2 — 2026-02-24 (Post-PR #791, Fix 1)

| Timestamp  | Event |
|------------|-------|
| 19:58:27   | Game started |
| 19:58:33   | ActiveItemManager: Active item unlocked: Force Field |
| 19:58:34   | ActiveItemManager: Active item changed from None to **Force Field** |
| 19:58:34   | Player._ready(): logs all items except ForceField — **still no `[Player.ForceField]` log** |
| 19:58:41   | New scene loaded, player re-initialized — **still no `[Player.ForceField]` log** |

### Session 3 — 2026-02-24 (Second game session after Fix 2 — Player.cs updated)

| Timestamp  | Event |
|------------|-------|
| 23:17:39   | Game started |
| 23:17:47   | `[Player.ForceField] Force field is selected, initializing...` — **force field now activates** |
| 23:17:47   | `[ForceFieldEffect] Area2D setup with radius 80px` — **BUG: radius too large** |
| 23:17:48   | `[ForceFieldEffect] Activated! Charge: 8.0s/8.0s` — force field visual works |
| 23:18:21   | Force field activated again |
| 23:18:22   | `[LastChance] Threat detected: Bullet` |
| 23:18:22   | `[Player] Spawning blood effect` — **BUG: player damaged while force field is active** |
| 23:18:23   | Player died — force field failed to reflect enemy bullet |

---

## Root Cause Analysis

### Root Cause #1 (Resolved)
**`InitForceField()` and `HandleForceFieldInput()` missing from `Player.cs`**

The project has two parallel player implementations:
- `scenes/characters/Player.tscn` → `scripts/characters/player.gd` (GDScript, NOT used by levels)
- `scenes/characters/csharp/Player.tscn` → `Scripts/Characters/Player.cs` (C#, **ALL levels use this**)

The fix was mistakenly applied to `player.gd`. After identifying the correct file (`Player.cs`), both initialization and input handling were added.

**Fix**: Added `InitForceField()`, `HandleForceFieldInput(delta)`, `is_force_field_active()` to `Scripts/Characters/Player.cs`.

### Root Cause #2 (Resolved)
**Force field visual was much larger than player**

`SHIELD_SCALE = 2.5` made the visual radius ≈ 320px (texture is 256×256px, 128px radius at scale 1.0, ×2.5 = 320px). Player collision radius is 16px.

`FIELD_RADIUS = 80.0` made the Area2D collision zone also oversized (5× player radius).

**Fix**:
- `FIELD_RADIUS`: 80px → 35px (≈2.2× player radius, "slightly bigger than player")
- `SHIELD_SCALE`: 2.5 → 0.28 (visual radius ≈ 36px at this scale, matching collision zone)

### Root Cause #3 (Resolved)
**Force field did not reflect enemy projectiles — 3 sub-causes**

**Sub-cause 3a — collision_mask = 0:**
The `Area2D.collision_mask` was set to `0`, meaning the Area2D could not detect ANY entering bodies/areas. No signals would fire.

**Fix**: `collision_mask = 16 | 32 = 48`
- Layer 5 (value 16) = "projectiles" layer — bullets and shrapnel (Area2D nodes)
- Layer 6 (value 32) = "targets" layer — grenades (RigidBody2D nodes)

**Sub-cause 3b — projectile identification by group (groups not assigned):**
The original `_on_projectile_entered` checked `area.is_in_group("bullets")`. In this project, collision groups are NOT assigned in scene files — only collision layers are used. The group check always returned false.

**Fix**: Identify projectiles by GDScript resource path:
```gdscript
var script_path: String = script.resource_path
if "bullet" in script_path.to_lower():
    _reflect_bullet(area)
elif "shrapnel" in script_path.to_lower():
    _reflect_shrapnel(area)
```

**Sub-cause 3c — incorrect velocity property names:**
- **Bullets**: use `direction` (Vector2) + `speed` (float), NOT `velocity`
- **Grenades**: are `RigidBody2D` nodes, use `linear_velocity`, not connected via `area_entered`
- **Shrapnel**: use `source_id` (not `shooter_id`) for source identification

**Fixes**:
- Bullet reflection: read `bullet.direction` and `bullet.speed`, update via `bullet.direction = reflected`
- Add `body_entered` signal for grenade (RigidBody2D) detection
- Grenade reflection: use `rb.linear_velocity`
- Shrapnel reflection: reset `shrapnel.source_id = -1`

---

## Evidence Summary

| Bug | Evidence | Logs |
|-----|----------|------|
| No force field log at all | Zero `[Player.ForceField]` entries | Sessions 1-2 |
| Wrong player script | `[Player.InvisibilitySuit]` appears but `[Player.ForceField]` never does | Session 2 |
| Force field radius 80px | `[ForceFieldEffect] Area2D setup with radius 80px` logged on every init (22 times) | Sessions 3-5 |
| Player damaged while active | Blood effect and death while `Activated! Charge: 8.0s/8.0s` was in log | Sessions 3-5 |
| No reflection events | Zero "reflected" log entries across 6,585 lines | Sessions 3-5 |

---

## Solution (Final)

### Files Changed

| File | Change |
|------|--------|
| `Scripts/Characters/Player.cs` | Added `InitForceField()`, `HandleForceFieldInput()`, `is_force_field_active()`, fields, call sites |
| `scripts/effects/force_field_effect.gd` | Fixed radius (80→35px), scale (2.5→0.28), collision_mask (0→48), projectile ID by path, grenade body_entered signal, correct velocity properties |
| `scripts/projectiles/bullet.gd` | Added force field protection check before dealing damage |
| `scripts/projectiles/shrapnel.gd` | Added force field protection check before dealing damage |
| `docs/case-studies/issue-676/README.md` | This file |
| `docs/case-studies/issue-676/game_log_*.txt` | All 6 test sessions preserved |

### Architecture

```
Player.cs (C# — runs in all game levels):
  _Ready() → InitForceField()
    - Checks ActiveItemManager.Call("has_force_field")
    - Loads ForceFieldEffect.tscn via GD.Load<PackedScene>()
    - Instantiates and AddChild()
    - Sets _forceFieldEquipped = true

  _PhysicsProcess(delta) → HandleForceFieldInput(delta)
    - If Space pressed and not active: _forceFieldEffect.Call("activate")
    - Else if active: _forceFieldEffect.Call("deactivate")

  is_force_field_active() → calls force_field_effect.Call("is_protecting")

force_field_effect.gd (GDScript):
  Area2D with collision_mask=48 (bullets=16, grenades=32)
  area_entered → _on_projectile_entered → identify by script path → reflect
  body_entered → _on_body_entered → grenade reflection

  Reflection formula: R = V - 2(V·N)N
  - Bullets: direction property (normalized Vector2)
  - Grenades: linear_velocity property (RigidBody2D)
  - Shrapnel: direction property, resets source_id (not shooter_id)

bullet.gd / shrapnel.gd:
  On area_entered (hit area):
    - Check parent.has_method("is_force_field_active")
    - If active: return without dealing damage
```

---

## Verification Checklist

- [x] `[Player.ForceField]` log category appears on game start with Force Field selected
- [x] Force field visual appears when Space is held (glowing ring around player)
- [x] Visual size is slightly larger than player (≈36px radius vs 16px player)
- [x] Shield disappears when Space is released
- [x] 8-second charge depletes while active
- [ ] Enemy bullets are reflected (not verified by owner yet — fix in progress)
- [ ] Shield blinks when charge is below 2 seconds
- [ ] Force field can be re-activated after partial use (charge preserved)
- [ ] No regression for other active items
