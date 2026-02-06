# Case Study: Issue #501 — Power Fantasy Mode Fixes

## Overview

Issue #501 reported three bugs in the Power Fantasy difficulty mode:
1. Ricochets should not damage the player but should damage enemies
2. M16 should have 3x more magazines in Power Fantasy mode
3. Grenade explosions should trigger the "special last chance" time-stop effect for 400ms

## Timeline

| Timestamp | Event |
|-----------|-------|
| 2026-02-06 09:30 | Initial fix commit `cf0055e` merged (PR #502) — addressed ricochet logic, ammo multiplier in BaseWeapon, and grenade effect duration |
| 2026-02-06 12:54 | User tested (game_log_20260206_125451.txt) — Normal mode, Ammo: 30/30, Health: 4/4 |
| 2026-02-06 12:58 | User tested (game_log_20260206_125832.txt) — Power Fantasy mode, Ammo: 30/30, Health: 10/10, enemies HP halved |
| 2026-02-06 09:59 | User reported: M16 still has 2 magazines; grenade effect not the "real" last chance |

## Root Cause Analysis

### Bug 1: M16 Still Has 2 Magazines (Not 3x)

**Symptoms:** In Power Fantasy mode, the M16 assault rifle only had 2 magazines (60 bullets total) instead of the expected 6 magazines (180 bullets = 2 base × 3 multiplier).

**Evidence from logs:**
- `game_log_20260206_125832.txt` line 121: `[Player] Ready! Ammo: 30/30` — only showing current magazine
- Line 619 (12:58:39): `Player ammo empty: false -> true` — first magazine emptied after ~7s
- Line 770 (12:58:41): `Player ammo empty: true -> false` — reloaded successfully (spare available)
- Line 1155 (12:58:44): `Player ammo empty: false -> true` — second magazine emptied, no more reloads possible
- No `[BaseWeapon]` log messages in file (GD.Print goes to stdout, not FileLogger)

**Root Cause:** The `building_level.gd` script (line 989) calls:
```gdscript
assault_rifle.ReinitializeMagazines(2, true)
```

This **overrides** the magazine count to exactly 2, regardless of difficulty. The `BaseWeapon._Ready()` → `InitializeMagazinesWithDifficulty()` correctly applied the 3x multiplier, but the level script then wiped it out by forcing 2 magazines.

The `ReinitializeMagazines()` method (BaseWeapon.cs:737) does a raw initialization without consulting the DifficultyManager:
```csharp
public virtual void ReinitializeMagazines(int magazineCount, bool fillAllMagazines = true)
{
    MagazineInventory.Initialize(magazineCount, WeaponData.MagazineSize, fillAllMagazines);
}
```

**Fix:** Modified `building_level.gd` to apply the DifficultyManager's ammo multiplier when reinitializing magazines:
```gdscript
var base_magazines: int = 2
var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
if difficulty_manager:
    var ammo_multiplier: int = difficulty_manager.get_ammo_multiplier()
    if ammo_multiplier > 1:
        base_magazines *= ammo_multiplier
assault_rifle.ReinitializeMagazines(base_magazines, true)
```

### Bug 2: Grenade Explosion Not Triggering "Real" Last Chance Effect

**Symptoms:** When a grenade exploded in Power Fantasy mode, the screen showed a brief saturation/slowdown effect, but NOT the full "last chance" time-freeze effect (sepia overlay, time stop, player can move freely) that occurs in Hard mode.

**Evidence from logs:**
- Line 1695: `[PowerFantasy] Grenade exploded - triggering 400ms special last chance effect`
- Line 1696-1698: `Starting power fantasy effect: Time scale: 0.10, Duration: 400ms` — simple Engine.time_scale slowdown
- Line 1138-1140: `[LastChance] Threat detected: Bullet` → `Not in hard mode - effect disabled` — LastChance system rejected the trigger
- Line 1789: `Effect duration expired after 315.00 ms` — effect was cut short by a kill resetting the timer

**Root Cause:** The `PowerFantasyEffectsManager.on_grenade_exploded()` implemented its own simple time-slowdown effect (`Engine.time_scale = 0.1` + saturation shader) instead of using the `LastChanceEffectsManager`'s full time-freeze effect. The `LastChanceEffectsManager._can_trigger_effect()` was gated on `is_hard_mode()`, refusing to activate in Power Fantasy mode.

**Fix:**
1. Added `trigger_grenade_last_chance(duration_seconds)` public method to `LastChanceEffectsManager` that triggers the full time-freeze effect with a configurable duration
2. Modified `PowerFantasyEffectsManager.on_grenade_exploded()` to call `LastChanceEffectsManager.trigger_grenade_last_chance(0.4)` instead of its own simple effect
3. Made `_start_last_chance_effect()` accept parameters for duration and trigger type (grenade vs threat)
4. Grenade-triggered effects don't consume the one-time "used" flag, allowing multiple grenade triggers per life

## Files Changed

| File | Change |
|------|--------|
| `scripts/levels/building_level.gd` | Apply ammo multiplier from DifficultyManager when reinitializing M16 magazines |
| `scripts/autoload/last_chance_effects_manager.gd` | Add `trigger_grenade_last_chance()` method, parameterize duration in `_start_last_chance_effect()` |
| `scripts/autoload/power_fantasy_effects_manager.gd` | Delegate grenade explosion to LastChanceEffectsManager for full time-freeze effect |

## Game Logs

- [game_log_20260206_125451.txt](./game_log_20260206_125451.txt) — Normal difficulty test
- [game_log_20260206_125832.txt](./game_log_20260206_125832.txt) — Power Fantasy mode test (shows both bugs)

## Lessons Learned

1. **Level scripts can override weapon initialization**: When a weapon's `_Ready()` initializes ammo correctly, level scripts that call `ReinitializeMagazines()` afterwards can silently undo the difficulty multiplier. The fix should be at the calling site (level script) to ensure the multiplier is always applied.

2. **Different effect systems should be composable**: Instead of duplicating time-manipulation logic across managers, the grenade explosion effect should reuse the existing LastChanceEffectsManager's time-freeze system with configurable parameters.

3. **GD.Print vs FileLogger**: `GD.Print()` output goes to stdout (Godot console), not to the file logger. When debugging issues from user-provided file logs, the absence of GD.Print messages doesn't mean the code didn't run — it means the output wasn't captured.
