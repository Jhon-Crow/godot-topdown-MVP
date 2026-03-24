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

---

## Deep Case Study — Game Log Evidence (2026-03-21)

The owner provided `game_log_20260321_004046.txt` (run at 00:40:46 Moscow time, posted
as bug report at 2026-03-20 21:45 UTC = 00:45 Moscow time). This log was captured from a
**pre-fix build** (without PR #1195) and directly confirms both reported bugs.

### Timeline Reconstructed from Log

| Log Line | Time | Event |
|---|---|---|
| 1 | 00:40:46 | Game starts on LabyrinthLevel |
| 251 | 00:40:50 | Player enters RoguelikeLevel |
| 741 | 00:40:57 | Combat room 1 cleared |
| 2121 | 00:41:09 | Combat room 2 cleared |
| 2560 | 00:41:25 | Combat room 3 cleared |
| **2565** | **00:41:27** | **Level 1 Treasure Room** — pedestal: "АК-74 + ГП" (weapon) |
| 2643 | 00:41:35 | Player exits treasure room — **no weapon pickup** |
| 4472 | 00:41:48 | Combat room cleared |
| 5166 | 00:42:03 | Combat room cleared |
| 5849 | 00:42:17 | Combat room cleared |
| **6193** | **00:42:27** | **Level 2 Treasure Room** — pedestal: "Auto-Reload" (passive) |
| **6259** | 00:42:30 | `Active item changed from None to Auto-Reload` ← OLD `set_active_item()` |
| 6263 | 00:42:32 | Player exits treasure room (but auto-reload NOT yet active in player!) |
| **9007** | **00:43:20** | **Level 3 Treasure Room** — Player._ready() runs → `Auto-reload active` (line 9047) |
| 9054 | 00:43:20 | Pedestal: "Breaker Bullets" (passive) |
| 9145 | 00:43:39 | Player exits Level 3 treasure room |
| 10043 | 00:43:51 | Next combat room → **if Breaker Bullets picked up, `set_active_item(BREAKER_BULLETS)` would have replaced Auto-Reload** |

### Key Observations from Log

1. **Bug 1 confirmed** (line 6259): `ActiveItemManager.set_active_item()` is used for
   passive items. The log says "Active item **changed from None** to Auto-Reload" — this is
   the `set_active_item()` code path, which writes to `current_active_item`. Picking a second
   passive would have overwritten this.

2. **Bug 2 confirmed** (lines 6233 vs 9047): Auto-Reload was "not selected" at Level 2's
   `_ready()` (line 6233), then picked up at 00:42:30 (line 6259). But the player's internal
   flag `_autoReloadActive` only became `true` at Level 3's `_ready()` (line 9047 — full 1
   minute later). Effect was **delayed by one full room transition**.

3. **Pedestal returns** (not directly visible in this log for passives, but confirmed by
   the code path): When a passive displaced an existing item via `set_active_item()`, the
   old item would go back to the pedestal (the active-item swap logic). This is the
   "passive items return to pedestal" bug reported by the owner.

### Why the Bugs Occur

The entire roguelike item system was originally designed around **active items** that the
player deliberately chooses between. The "passive items don't displace" feature was added
later (PR #1166) by reusing `set_active_item(type, false)` — a shortcut that avoided the
level restart but didn't properly separate passive accumulation from active swapping.

The single-slot `current_active_item` integer was never designed to hold multiple items.

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

---

## Bug 3: Crash when entering treasure room (2026-03-24)

### Symptom

Game crashes "sometimes" when transitioning between roguelike rooms, often when entering
the treasure room. The crash is non-deterministic and depends on timing.

### Evidence from game logs

Two crash logs provided: `game_log_20260324_061109.txt` and `game_log_20260324_061451.txt`.

Both logs end abruptly after `[RoguelikeLevel] Player reached exit — advancing (treasure_room=false)`.
After this line, the normal "Scene changed" and room initialization messages never appear —
the game process terminates (segfault).

### Root Cause: Unguarded coroutine after await in `_setup_navigation()`

`_setup_navigation()` contains `await get_tree().physics_frame` (line 936). After the await,
the coroutine accesses `self`, `nav_region`, and `nav_poly` — all of which are bound to the
current RoguelikeLevel scene node.

When a room transition occurs (`change_scene_to_file()`), the old scene tree is freed. However,
Godot 4.x does NOT cancel pending coroutines when nodes are freed. The coroutine resumes on
the next `physics_frame`, but `self` is now a freed reference. The call to
`NavigationServer2D.parse_source_geometry_data(nav_poly, source_geometry, self)` passes this
freed reference to the C++ engine, causing a segfault.

**Why "sometimes"**: The crash only occurs when the room transition happens before the
navigation bake completes (within 1 physics frame of room load). This timing window is
narrow but consistently hit in fast-paced play — e.g., the player clearing the last enemy
while standing near the exit zone.

### Additional risk: Double scene transitions

`_on_player_reached_exit()` → `call_deferred("_advance_to_next_room")` had no guard against
being called multiple times. Although `body_entered` normally fires once, deferred calls
during rapid scene changes could queue multiple transitions.

### Fix

1. **Guard coroutine after await** (`_setup_navigation()`):
   ```gdscript
   await get_tree().physics_frame
   if not is_instance_valid(self) or not is_inside_tree():
       return
   ```

2. **Transition guard flag** (`_transitioning: bool`):
   - Set `true` at the start of `_advance_to_next_room()`
   - Checked in `_on_player_reached_exit()` and `_advance_to_next_room()` to prevent double calls

This follows the existing pattern in `_on_player_died()` (line 1350) which already uses
`is_instance_valid(self)` after an `await`.
