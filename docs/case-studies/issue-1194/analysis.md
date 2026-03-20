# Case Study: Issue #1194 — Separate Passive Item Collection Logic for Roguelike

## Issue Summary

**Title (RU):** сделай отдельную логику сбора пассивных предметов для Рогалика
**Title (EN):** Create separate passive item collection logic for Roguelike

**Description (RU):** игрок должен иметь возможность взять любое кол-во пассивных предметов одновременно (если они попадаются в сокровищнице) так, чтоб все их эффекты работали.
**Description (EN):** The player must be able to pick up any number of passive items simultaneously (if they appear in the treasure room) so that all their effects work.

---

## Root Cause Analysis

### Current Architecture

`ActiveItemManager` uses a **single integer slot** (`current_active_item: int`) to store the player's equipped item. This means only ONE item (whether active or passive) can be equipped at any time.

**Passive items** (BREAKER_BULLETS, LASER_SIGHT, EXTENDED_MAGAZINE, ARMORED_SKIN, AUTO_RELOAD, COMBAT_DISPOSITION) are:
- Identified via `PASSIVE_ACTIVE_ITEM_TYPES` array in `roguelike_level.gd`
- Checked via `has_X()` methods that compare `current_active_item == <type>`
- Set via `ActiveItemManager.set_active_item(type, false)` which overwrites the single slot

**The Bug:** When a player picks up a second passive item in the treasure room, it calls `set_active_item()` which *overwrites* the first passive item. Only the most recently picked passive item remains active.

### Evidence

From `roguelike_level.gd` line 1386-1398:
```gdscript
if is_passive:
    if item_type == current:
        return  # skip same item
    ActiveItemManager.set_active_item(item_type, false)  # OVERWRITES previous item!
    pedestal.queue_free()
```

From `active_item_manager.gd` line 303-304:
```gdscript
func has_laser_sight() -> bool:
    return current_active_item == ActiveItemType.LASER_SIGHT  # only checks single slot
```

---

## Solution Design

### Approach: Separate Passive Item Collection Array

Add a `collected_passive_items: Array` to `ActiveItemManager` that stores all passive items collected during a roguelike run. This separates passive item state from the active item slot.

**Key Design Decisions:**
1. `current_active_item` remains the single slot for **active** (non-passive) items
2. `collected_passive_items` is a new array holding all collected passive items
3. Passive `has_X()` methods check BOTH the active slot AND the passive array
4. On roguelike run start/end/death: clear `collected_passive_items`
5. Passive items persist across room transitions within a run (like the weapon)

### Files Modified

1. **`scripts/autoload/active_item_manager.gd`**
   - Add `var collected_passive_items: Array = []`
   - Add `func add_passive_item(type: int) -> void`
   - Add `func reset_passive_items() -> void`
   - Add `func has_passive_item(type: int) -> bool`
   - Update `has_breaker_bullets()`, `has_laser_sight()`, `has_extended_magazine()`, `has_armored_skin()`, `has_auto_reload()`, `has_combat_disposition()`, `should_force_laser_sight()`, `get_magazine_size_multiplier()`, `get_total_ammo_multiplier()` to check both slots
   - Signal `passive_item_added` emitted when passive added

2. **`scripts/levels/roguelike_level.gd`**
   - Update `_apply_pedestal_active_item()` to use `add_passive_item()` for passive types
   - Update `_force_roguelike_loadout()` to clear passive items on run start (level 1 room 1)
   - Update `_pick_random_pedestal_item()` to skip already-collected passives
   - Remove duplicate passive items from being offered on pedestal

3. **`scripts/autoload/game_manager.gd`**
   - Call `ActiveItemManager.reset_passive_items()` in `roguelike_reset_session()`

4. **`tests/unit/test_roguelike_level.gd`**
   - Add tests for multiple passive item collection
   - Add tests for passive item persistence across treasure rooms
   - Add tests that already-collected passives are not re-offered on pedestal

---

## Existing Similar Patterns in Codebase

- **Roguelike weapon persistence:** `GameManager.roguelike_run_weapon` persists weapon across rooms. Same pattern used for passive items via `GameManager`.
- **Extended Magazine:** Already a passive item. `has_extended_magazine()` returns true when equipped. After fix, also returns true when in `collected_passive_items`.
- **Combat Disposition:** Another passive. The `_on_combat_disposition_init` logic runs whenever this passive is detected.

---

## Alternative Approaches Considered

1. **Separate PassiveItemManager autoload:** Over-engineered for 6 passive items. Adds complexity.
2. **Bitmask/flags on current_active_item:** Would require breaking change to all item type comparisons. High risk.
3. **Multiple active item slots:** Would require major UI/architecture changes outside the scope.
4. **Array in GameManager:** Less cohesive than keeping it in ActiveItemManager which already owns item state.

**Chosen approach** (Array in ActiveItemManager) is minimal, backward-compatible, and follows existing patterns.
