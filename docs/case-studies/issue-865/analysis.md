# Case Study: Issue #865 — Ammo Counter Not Working (AK, PM, Revolver)

## Summary

The ammo counter (HUD display) fails to update when the player uses AK (AKGL), Makarov PM, or Revolver weapons on specific maps.

**Reported issues (initial, 2026-02-19):**
1. AK ammo counter not working on: Training (Обучение), City (Город), Laboratory (Лаборатория)
2. PM ammo counter not working on: City (Город)
3. Revolver counter only works on: Laboratory (Лаборатория)

**Additional finding (2026-02-24, PR comment by Jhon-Crow):**
4. Revolver counter shows 30/30 and does not update on: Building (Здание), Beach (Пляж), Docks (Доки), Castle (Замок), Polygon (Полигон)

---

## Attached Data

- `game_log_20260219_233205.txt` — Game log from 2026-02-19 (user-provided). Note: The log does not contain ammo-related errors because no AmmoChanged signal is connected — the counter simply doesn't update silently.
- `game_log_20260224_190842.txt` — Game log from 2026-02-24 (user-provided). Confirms Revolver is equipped and fired (`RSh-12 Revolver`) on BuildingLevel and BeachLevel and DocksLevel, but the counter shows the previous weapon's value (30/30 from AKGL).

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

### Working vs. Broken Levels (After First Fix — Before Second Fix)

| Level | Includes AKGL | Includes Revolver | Includes MakarovPM |
|-------|--------------|-------------------|-------------------|
| Beach (`beach_level.gd`) | ✅ | ❌ Missing | ✅ |
| Castle (`castle_level.gd`) | ✅ | ❌ Missing | ✅ |
| Docks (`docks_level.gd`) | ✅ | ❌ Missing | ✅ |
| Building (`building_level.gd`) | ✅ | ❌ Missing | ✅ |
| Polygon/TestTier (`test_tier.gd`) | ✅ | ❌ Missing | ✅ |
| City (`city_level.gd`) | ✅ (fixed) | ✅ (fixed) | ✅ (fixed) |
| Laboratory (`labyrinth_level.gd`) | ✅ (fixed) | ✅ | ✅ |
| Tutorial (`tutorial_level.gd`) | ✅ (fixed) | ✅ | ✅ |

**Root cause of 30/30 display:** When Revolver is selected but not found in the weapon lookup chain, no `AmmoChanged` signal is connected. The HUD retains whatever value it showed previously (e.g., 30/30 from a previously used AKGL). The Revolver itself has 5 rounds per cylinder, but the HUD never receives the initial display update either.

---

## Fix

### Second Fix: beach_level.gd, castle_level.gd, docks_level.gd, building_level.gd, test_tier.gd

All five level scripts were missing `Revolver` from:
1. The weapon lookup chain in `_setup_player_tracking()` / `_setup_ammo_tracking()`
2. The `weapon_names` dictionary in `_setup_selected_weapon()`
3. The `elif selected_weapon_id == "revolver":` block in `_setup_selected_weapon()`

**Fix**: Add `Revolver` to all three locations in each affected level script, following the same pattern used in `tutorial_level.gd`.

### First Fix: city_level.gd

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
