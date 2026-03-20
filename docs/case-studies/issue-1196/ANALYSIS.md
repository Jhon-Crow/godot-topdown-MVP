# Case Study: Issue #1196 — Laser Sight Unlock Condition

## Overview

**Issue**: Add unlock condition for the Laser Sight active item.
**Requirement**: Unlocks after 1,000 kills made **without** the Laser Sight equipped. Add to the unlock table in Experimental Settings.

**Initial PR**: #1197 — Implemented the basic unlock condition.

**Owner feedback (2026-03-20)**: Two additional requirements identified during testing:
1. Only count kills from the **player's weapons** (not enemy-vs-enemy or ally-vs-enemy kills).
2. Do **not** count kills made with **any** laser sight active — including:
   - The Laser Sight active item (purple)
   - Power Fantasy difficulty blue laser sight
   - Weapon-level built-in laser sight (e.g., AssaultRifle's red laser)

---

## Timeline / Sequence of Events

### Session 1 (`game_log_20260320_074304.txt`)
- **07:43:05** — Game started, no laser sight equipped (no ActiveItem selected).
- **07:43:57** — First kill registered: `kills_without_laser_sight: 1`
- **07:44:57** — Kills 10–12 in rapid succession (multiple enemies killed in quick burst).
- **07:45:22** — Counter reaches 24. Steady increment, consistent with player kills.
- Session ended after 30 qualifying kills logged.
- **Total `kills_without_laser_sight` in log**: 30

### Session 2 (`game_log_20260320_074740.txt`)
- **07:47:42** — Game resumed, `PersistManager` restored `kills_without_laser_sight: 48` (persistence working correctly).
- **07:48:09** — Kill #49 registered.
- **07:48:10** — Kill #50 registered.
- **07:48:19** — Owner opened Unlock Table menu to verify progress display.
- Session ended at 50 qualifying kills (50/1000 shown in table).

---

## Root Cause Analysis

### Problem 1: Non-Player Kills Being Counted

**Root cause**: The `register_kill()` call in `_on_enemy_died()` was triggered by the `died` signal on ALL enemy deaths, regardless of who caused the death. The `died` signal carries no information about the killer.

In the game:
- Enemies can potentially be killed by grenade splash damage from other enemies
- Allies (BFF companion from the pendant) can kill enemies
- These non-player kills incorrectly incremented `kills_without_laser_sight`

**Fix**:
- Added `_killed_by_player: bool` field to `enemy.gd`, tracked when `on_hit_with_bullet_info()` is called.
- Extended `died_with_info` signal to carry `is_player_kill: bool`.
- Passed `_is_player_bullet()` from `bullet.gd` through the hit call chain.
- Updated all level scripts to call `GameManager.register_kill(is_player_kill)` from `_on_enemy_died_with_info()` instead of `_on_enemy_died()`.

### Problem 2: Wrong Laser Sight Detection

**Root cause**: The initial implementation only checked `ActiveItemManager.has_laser_sight()`, which returns `true` only when the **Laser Sight active item** (purple) is the selected active item. Two other laser sight sources were missed:

1. **Power Fantasy blue laser**: Enabled by `DifficultyManager` when difficulty is `POWER_FANTASY`. Detected via `DifficultyManager.should_force_blue_laser_sight()`.
2. **Weapon-level built-in laser**: The AssaultRifle (`AssaultRifle.tscn`, `AssaultRifle.cs`) has `LaserSightEnabled = true` by default and renders a red `Line2D` node named `"LaserSight"` as a child.

**Fix**:
- Added `has_any_laser_sight_active()` method to `ActiveItemManager`.
- Checks all three sources:
  1. Active item: `has_laser_sight()`
  2. Power Fantasy difficulty: `DifficultyManager.should_force_blue_laser_sight()`
  3. Weapon-level: Inspects player's weapon children for `LaserSightEnabled` property or a visible `"LaserSight"` Line2D node.
- `GameManager.register_kill()` now calls `active_item_manager.has_any_laser_sight_active()`.

### Problem 3: C# Projectiles Not Passing `is_from_player` (Bug introduced in fix for Problem 1)

**Reported in**: Owner comment 2026-03-20T06:09:14Z — "судя по таблице теперь вообще не защитываются убийства (даже из дробовика без прицела)" (kills from shotgun without laser sight not being counted at all)

**Root cause**: The fix for Problem 1 added `is_from_player` parameter to the GDScript hit chain (`bullet.gd` → `hit_area.gd` → `enemy.gd`). However, C# projectiles (`ShotgunPellet.cs`, `Bullet.cs`, `SniperBullet.cs`, `BreakerDetonation.cs`) were calling `on_hit`, `TakeDamage`, or `on_hit_with_bullet_info_and_damage` **without** the `is_from_player` parameter.

Evidence from `game_log_20260320_090631.txt`:
```
[ENEMY] [Enemy2] Enemy died (ricochet: false, penetration: false, player_kill: false)
[GameManager] register_kill: skipping non-player kill (enemy-vs-enemy or ally-vs-enemy)
```
Even when using a **shotgun** (C# weapon), kills showed `player_kill: false` — because `ShotgunPellet.OnAreaEntered()` called `area.Call("on_hit")` (no player info) or `damageable.TakeDamage()` (no player info).

The call stack for a shotgun hit was:
1. `ShotgunPellet.OnAreaEntered()` → `area.Call("on_hit")` ← **no is_from_player!**
2. `hit_area.on_hit()` → `parent.on_hit()` (no player param)
3. `enemy.on_hit()` → `on_hit_with_bullet_info(..., is_from_player=false)`
4. `_killed_by_player = false`
5. `died_with_info.emit(is_player_kill=false)`
6. `register_kill(false)` → kill skipped

**Fix**: Updated all four C# projectile files to prefer calling `on_hit_with_bullet_info_and_damage` with `is_from_player` set correctly before falling back to `IDamageable`/`on_hit`:
- `ShotgunPellet.cs`: Added `on_hit_with_bullet_info_and_damage` as highest-priority hit method, passing `IsPlayerPellet()`.
- `Bullet.cs`: Added `on_hit_with_bullet_info_and_damage` as highest-priority hit method, passing `IsPlayerBullet()`.
- `SniperBullet.cs`: Already called `on_hit_with_bullet_info_and_damage` but was missing the 6th `is_from_player` argument.
- `BreakerDetonation.cs`: Added `isFromPlayer` param to `ApplyDamage()`; added `IsShooterPlayer()` helper.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/objects/enemy.gd` | Added `_killed_by_player: bool` field; added `is_from_player` param to `on_hit_with_bullet_info()`; updated `died_with_info` signal to carry `is_player_kill`; reset in `respawn()` |
| `scripts/objects/hit_area.gd` | Added `is_from_player` param to `on_hit_with_bullet_info()` and `on_hit_with_bullet_info_and_damage()` |
| `scripts/projectiles/bullet.gd` | Pass `_is_player_bullet()` as `from_player` in all `on_hit_*` calls |
| `Scripts/Projectiles/ShotgunPellet.cs` | Prefer `on_hit_with_bullet_info_and_damage` over `on_hit`/`IDamageable`, passing `IsPlayerPellet()` |
| `Scripts/Projectiles/Bullet.cs` | Prefer `on_hit_with_bullet_info_and_damage` over `IDamageable`/`on_hit`, passing `IsPlayerBullet()` |
| `Scripts/Projectiles/SniperBullet.cs` | Pass `IsPlayerBullet()` as 6th arg to `on_hit_with_bullet_info_and_damage` |
| `Scripts/Projectiles/BreakerDetonation.cs` | Add `isFromPlayer` param to `ApplyDamage()`; add `IsShooterPlayer()` helper |
| `scripts/autoload/game_manager.gd` | `register_kill(is_player_kill: bool = true)` — skip non-player kills; use `has_any_laser_sight_active()` |
| `scripts/autoload/active_item_manager.gd` | Added `has_any_laser_sight_active()` — checks all three laser sight sources |
| `scripts/levels/*.gd` (12 files) | Moved `GameManager.register_kill()` from `_on_enemy_died()` to `_on_enemy_died_with_info(is_player_kill)` |
| `tests/unit/test_laser_sight_unlock.gd` | Updated mock `register_kill()` signature; added 4 new tests for player-kill-only behavior |

---

## External Research

### Godot Signal Patterns for Kill Attribution
- Godot's signal system does not automatically carry contextual data about who triggered a death.
- Industry-standard pattern: tag the entity being killed with the killer's identity at damage time, then emit it on death.
- Reference: Godot docs on [signals with parameters](https://docs.godotengine.org/en/stable/getting_started/step_by_step/signals.html).

### Laser Sight Detection Completeness
- Three independent systems can produce a laser sight in this game:
  1. Player selects Laser Sight as active item (purple, `ActiveItemManager`)
  2. Power Fantasy difficulty mode (blue, `DifficultyManager`)
  3. Weapon default (red, weapon scene/C# script export property)
- Any system that produces a visible laser on the weapon must disqualify that kill for the unlock counter.

---

## Test Results

All 24 unit tests pass (20 original + 4 new):
- `test_non_player_kill_does_not_increment_counter` ✅
- `test_non_player_kill_still_increments_total_kills` ✅
- `test_player_kill_increments_counter` ✅
- `test_mixed_player_and_non_player_kills` ✅

---

## Proposed Solutions Considered

| Solution | Pros | Cons | Chosen? |
|----------|------|------|---------|
| Check laser sight only in `GameManager.register_kill()` | Simple | Can't detect weapon-level laser without inspecting player's children | Partial |
| Pass `is_player_kill` through `died_with_info` signal | Clean data flow, works for all scenarios | Requires changes in 15+ files | ✅ Yes |
| Add global `_player_caused_last_kill: bool` flag | Simple | Race conditions possible in fast kills | No |
| Weapon group membership for laser sight | Scalable | Requires adding all weapon nodes to a group | No |

The chosen approach (passing `is_player_kill` through the signal chain) is the most architecturally sound because it keeps kill attribution with the kill event itself, making it easy to reason about and test.
