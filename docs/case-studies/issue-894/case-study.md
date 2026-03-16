# Case Study: Issue #894 — Add Unlock System

## Issue Summary

**Title:** добавь систему анлоков (Add an unlock system)

**Reporter:** Jhon-Crow
**PR:** #924
**Status:** Bug reported in PR after initial implementation

---

## Requirements (from issue)

1. PM pistol and flashbang grenade open from the start (unchanged)
2. Other items can be opened when conditions are met (completing a level a certain way)
3. Items whose condition is met are highlighted gold in the armory
4. Unlock conditions:
   - Labyrinth at grade D or higher → Mini Uzi
   - Building at grade D or higher → Shotgun
   - Polygon at grade D or higher → Sniper Rifle + Flashlight
   - Castle at grade F or higher (any completion) → Revolver + Teleport Bracers
5. **All unspecified items can be opened from the start** ("все не указанные предметы можно открыть с самого начала")

---

## Timeline of Events

### Initial Implementation (commit `3609d017`)
- Created `scripts/autoload/unlock_manager.gd` — new autoload tracking level-based conditions
- Modified `scripts/ui/armory_menu.gd` — added gold highlighting for condition-met locked items
- Registered UnlockManager as autoload in `project.godot`
- Created unit tests in `tests/unit/test_unlock_manager.gd`

**Bug introduced:** In `armory_menu.gd`, the LMB hold unlock was triggered for ANY locked item, regardless of whether the condition was met:
```gdscript
else:  # Locked item
    # Start tracking LMB hold for unlocking — NO CONDITION CHECK!
    _lmb_hold_tracking[slot] = {...}
```

### Fix Commit (commit `0c5bf2bb`)
Changed `else` to `elif condition_met` in both `_on_slot_gui_input` and `_on_active_item_slot_gui_input`. This gates the LMB unlock flow behind the condition check.

### User Report (2026-03-02)
Owner reports: "не работает - всё оружие сейчас открывается даже если ничего не пройдено"
(= "doesn't work - all weapons are now opening even without completing anything")

---

## Root Cause Analysis

### Root Cause 1: Default unlock states are incorrect

The issue requirement states: "all unspecified items can be opened from the start". However, the current implementation locks ALL items by default except PM pistol and flashbang grenade.

**Items that SHOULD be unlocked by default (no conditions defined):**

Weapons (in `game_manager.gd`):
- `m16` — currently `false`, should be `true`
- `silenced_pistol` — currently `false`, should be `true`
- `ak_gl` — currently `false`, should be `true`

Grenades (in `grenade_manager.gd`):
- `FRAG (1)` — currently `false`, should be `true`
- `DEFENSIVE (2)` — currently `false`, should be `true`
- `AGGRESSION_GAS (3)` — currently `false`, should be `true`

Active Items (in `active_item_manager.gd`):
- `HOMING_BULLETS (2)` — currently `false`, should be `true`
- `INVISIBILITY_SUIT (4)` — currently `false`, should be `true`
- `BREAKER_BULLETS (5)` — currently `false`, should be `true`
- `FORCE_FIELD (6)` — currently `false`, should be `true`
- `TRAJECTORY_GLASSES (7)` — currently `false`, should be `true`

### Root Cause 2: Save state restoration bypasses condition validation

`PersistManager._load_state()` restores all saved weapon unlock states from `game_state.cfg` without checking whether those states are still valid given the current unlock conditions.

If a user had previously unlocked condition-gated weapons via the old buggy LMB mechanism (before the condition_met fix), those states are saved in `game_state.cfg`. On next startup, PersistManager restores those states, making all weapons appear unlocked even without completing the required levels.

**Affected code in `persist_manager.gd`:**
```gdscript
# Restores unlocked state unconditionally
for weapon_id in config.get_section_keys(SECTION_UNLOCKED_WEAPONS):
    var is_unlocked: bool = config.get_value(SECTION_UNLOCKED_WEAPONS, weapon_id, false)
    if is_unlocked and weapon_id in game_manager.unlocked_weapons:
        game_manager.unlocked_weapons[weapon_id] = true  # No condition check!
```

---

## Fix Plan

### Fix 1: Update default unlock states

In `game_manager.gd`:
- Set `m16`, `silenced_pistol`, `ak_gl` to `true` by default

In `grenade_manager.gd`:
- Set `FRAG`, `DEFENSIVE`, `AGGRESSION_GAS` to `true` by default

In `active_item_manager.gd`:
- Set `HOMING_BULLETS`, `INVISIBILITY_SUIT`, `BREAKER_BULLETS`, `FORCE_FIELD`, `TRAJECTORY_GLASSES` to `true` by default

### Fix 2: Validate save state restoration against unlock conditions

In `persist_manager.gd`, when restoring locked weapons from save file, check if:
1. The weapon has no conditions (freely available) → restore as unlocked
2. The weapon has a condition → only restore as unlocked if UnlockManager confirms condition is met

This prevents corrupted/outdated save files from bypassing the unlock system.

---

## Verification

After fixes:
- Fresh start: PM + flashbang + all "free" items available; condition-gated items locked
- After completing Labyrinth D+: Mini Uzi shows gold border, can be opened by LMB hold
- LMB hold on non-condition-met items: nothing happens
- After completing all levels: all condition items unlock properly
- Save/load: unlock state persists correctly

---

## References

- Issue #894: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/894
- PR #924: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/924
- Related: `scripts/autoload/unlock_manager.gd`
- Related: `scripts/ui/armory_menu.gd`
- Related: `scripts/autoload/persist_manager.gd`
- Related: `scripts/autoload/game_manager.gd`
- Related: `scripts/autoload/grenade_manager.gd`
- Related: `scripts/autoload/active_item_manager.gd`
