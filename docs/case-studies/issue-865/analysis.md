# Case Study: Issue #865 — Ammo Counter Not Working (AK, PM, Revolver)

## Summary

The ammo counter (HUD display) fails to update when the player uses AK (AKGL), Makarov PM, or Revolver weapons on specific maps.

**Reported issues:**
1. AK ammo counter not working on: Training (Обучение), City (Город), Laboratory (Лаборатория)
2. PM ammo counter not working on: City (Город)
3. Revolver counter only works on: Laboratory (Лаборатория)

---

## Attached Data

- `game_log_20260219_233205.txt` — Game log from 2026-02-19 (user-provided). Note: The log does not contain ammo-related errors because no AmmoChanged signal is connected — the counter simply doesn't update silently.

---

## Root Cause Analysis

### Timeline of Events

1. Weapon ammo counter implementation was added per-level, with each level script maintaining its own `_setup_ammo_tracking()` / weapon lookup logic.
2. New weapons (AKGL, MakarovPM, Revolver) were added to the game over time.
3. Some levels (Beach, Castle, Docks, Building) were correctly updated to include the new weapons in their lookup chains.
4. Three levels (City, Laboratory, Tutorial) were **missed** in the update.

### Root Cause: Missing Weapon Lookup Entries

Each level script contains a sequential `if weapon == null` chain to find the player's equipped weapon:

```gdscript
var weapon = _player.get_node_or_null("Shotgun")
if weapon == null:
    weapon = _player.get_node_or_null("MiniUzi")
if weapon == null:
    weapon = _player.get_node_or_null("SilencedPistol")
if weapon == null:
    weapon = _player.get_node_or_null("SniperRifle")
if weapon == null:
    weapon = _player.get_node_or_null("AssaultRifle")
# BUG: AKGL, Revolver, MakarovPM not checked in some levels
```

If the player's weapon is not found in this chain, `weapon` remains `null` and the code falls to the `else` branch which tries to connect to GDScript player signals (which C# players don't have). This results in **no AmmoChanged signal connection**, so the HUD counter never updates.

### Affected Files and Locations

| File | Missing Weapons | Lines |
|------|----------------|-------|
| `scripts/levels/city_level.gd` | AKGL, Revolver, MakarovPM | ~265-273 |
| `scripts/levels/labyrinth_level.gd` | AKGL | ~503-516 |
| `scripts/levels/tutorial_level.gd` (`_setup_ammo_tracking`) | AKGL | ~508-514 |
| `scripts/levels/tutorial_level.gd` (`_setup_weapon_connections`) | AKGL | ~384 |

### Why Revolver works ONLY on Laboratory

The `labyrinth_level.gd` weapon lookup chain (lines 503-516) explicitly includes Revolver and MakarovPM but **not AKGL**. So revolver counter works on Laboratory.

The `city_level.gd` weapon lookup chain (lines 265-273) doesn't include Revolver, MakarovPM, or AKGL — so none of them work on City.

### Working vs. Broken Levels

| Level | Includes AKGL | Includes Revolver | Includes MakarovPM |
|-------|--------------|-------------------|-------------------|
| Beach (`beach_level.gd`) | ✅ Line 179 | N/A (uses single lookup) | ✅ Line 181 |
| Castle (`castle_level.gd`) | ✅ Line 346 | N/A | ✅ Line 348 |
| Docks (`docks_level.gd`) | ✅ Line 202 | N/A | ✅ Line 204 |
| Building (`building_level.gd`) | ✅ Line 556 | N/A | ✅ Line 558 |
| **City (`city_level.gd`)** | ❌ Missing | ❌ Missing | ❌ Missing |
| **Laboratory (`labyrinth_level.gd`)** | ❌ Missing | ✅ Line 514 | ✅ Line 516 |
| **Tutorial (`tutorial_level.gd`)** | ❌ Missing (in `_setup_ammo_tracking`) | ✅ Line 514 | ✅ Line 513 |

---

## Fix

### city_level.gd

Add AKGL, Revolver, and MakarovPM to the weapon lookup chain after AssaultRifle (lines ~273):

```gdscript
if weapon == null:
    weapon = _player.get_node_or_null("AKGL")
if weapon == null:
    weapon = _player.get_node_or_null("Revolver")
if weapon == null:
    weapon = _player.get_node_or_null("MakarovPM")
```

Also in the secondary lookup within `_on_weapon_swap` or similar functions (line ~563).

### labyrinth_level.gd

Add AKGL to the weapon lookup chain after AssaultRifle (lines ~512):

```gdscript
if weapon == null:
    weapon = _player.get_node_or_null("AKGL")
```

Also in `_update_magazines_label` secondary lookup (line ~938).

### tutorial_level.gd

In `_setup_ammo_tracking` (lines ~512), add AKGL lookup after AssaultRifle.

In `_setup_weapon_connections` (lines ~384), add AKGL handling in the elif chain to connect `AmmoChanged` signal and set fire mode tutorial flag.

---

## Prevention (README Documentation)

When adding new weapon types in the future, the following level scripts must be updated with the new weapon's node name in the weapon lookup chain:

- `scripts/levels/city_level.gd`
- `scripts/levels/labyrinth_level.gd`
- `scripts/levels/tutorial_level.gd`
- `scripts/levels/beach_level.gd`
- `scripts/levels/castle_level.gd`
- `scripts/levels/docks_level.gd`
- `scripts/levels/building_level.gd`

**Reference pattern** (from `beach_level.gd`, lines 168-181):
```gdscript
var weapon = _player.get_node_or_null("Shotgun")
if weapon == null:
    weapon = _player.get_node_or_null("MiniUzi")
if weapon == null:
    weapon = _player.get_node_or_null("SilencedPistol")
if weapon == null:
    weapon = _player.get_node_or_null("SniperRifle")
if weapon == null:
    weapon = _player.get_node_or_null("AssaultRifle")
if weapon == null:
    weapon = _player.get_node_or_null("AKGL")
if weapon == null:
    weapon = _player.get_node_or_null("MakarovPM")
```
