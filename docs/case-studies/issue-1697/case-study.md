# Case Study: Issue #1697 — после удаление прогресса всё равно доступна автоперезарядка / After deleting progress, auto-reload is still available + kill stats not reset

**Date:** 2026-03-28
**Issue:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1697
**PR:** https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1700
**Log files analyzed:**
- [`game_log_20260328_175445.txt`](game_log_20260328_175445.txt) — 464 lines, session showing the reset bug in action

---

## 1. Summary

The game owner reported two problems after deleting all saves (resetting progress to first-launch state):

1. **Auto-reload** remained active after clearing all saves (original issue)
2. **`kills_through_wall`** counter was not reset — persisted value of **6** survived the clear
3. **`levels_completed_with_silenced_pistol`** counter was not reset — persisted value of **2** survived the clear

Both problems share the same root cause: `clear_all_saves()` in `persist_manager.gd` did not reset all the stat fields that it saves.

---

## 2. How the Save/Clear System Works

```
clear_all_saves() called (e.g. from settings menu)
     │
     ├── DirAccess.remove_absolute(SAVE_PATH)    ← deletes game_state.cfg
     │
     ├── GameManager reset:
     │     kills_without_laser_sight = 0         ✓
     │     shots_fired_special_weapons = 0        ✓
     │     total_deaths = 0                       ✓
     │     no_damage_levels_completed = 0         ✓
     │     levels_completed_rank_a_or_higher = 0  ✓
     │     kills_through_wall = ???               ← MISSING
     │     levels_completed_with_silenced_pistol  ← MISSING
     │
     ├── GrenadeManager reset                     ✓
     │
     ├── ActiveItemManager reset:
     │     current_active_item = NONE             ✓ (direct assign)
     │     active_item_changed signal NOT emitted ← BUG (original issue)
     │     → _autoReloadActive remained true
     │
     └── ProgressManager.clear_all_progress()     ✓
```

The stats `kills_through_wall` and `levels_completed_with_silenced_pistol` were **added in Issue #1624** but `clear_all_saves()` was never updated to reset them. The save/load code (lines 317–321, 407–415) correctly handles these fields, but the reset code (lines 506–510) was not kept in sync.

---

## 3. Timeline Reconstruction from Log

### Session start (17:54:45)

```
[17:54:45] [PersistManager] Loading saved state from user://game_state.cfg
[17:54:45] [PersistManager] Restored kills_without_laser_sight: 0
[17:54:45] [PersistManager] Restored shots_fired_special_weapons: 0
[17:54:45] [PersistManager] Restored total_deaths: 0
[17:54:45] [PersistManager] Restored no_damage_levels_completed: 0
[17:54:45] [PersistManager] Restored levels_completed_rank_a_or_higher: 0
[17:54:45] [PersistManager] Restored kills_through_wall: 6           ← non-zero
[17:54:45] [PersistManager] Restored levels_completed_with_silenced_pistol: 2  ← non-zero
[17:54:45] [PersistManager] Restored unlocked active item type: 11   ← auto-reload unlocked
[17:54:45] [PersistManager] Restored selected active item type: 0    ← NONE selected
```

The save file has:
- `kills_through_wall = 6` (from drilling-bullets unlocking progress)
- `levels_completed_with_silenced_pistol = 2` (from recoil-compensator unlocking progress)
- Active item type 11 (auto-reload) unlocked, but type 0 (NONE) selected

### Player interaction — clear saves (17:55:05)

```
[17:55:05] [PersistManager] State saved to user://game_state.cfg
[17:55:05] [Player.ItemPickup] active_item_changed received: type=0
[17:55:05] [Player.ItemPickup] De-equipping all active item subsystems before re-init
[17:55:05] [Player.ItemPickup] All active item subsystems de-equipped
[17:55:05] [Player.ItemPickup] No player-side init required for item type 0
[17:55:05] [ActiveItemManager] Loudspeaker progress reset
[17:55:05] [ProgressManager] All progress cleared
[17:55:05] [PersistManager] All saves cleared — game reset to first-launch state
```

The `active_item_changed` signal IS now emitted (fix from first iteration of PR #1700), correctly
de-equipping items. The scene then reloads to Tutorial.

### After reload (17:55:06) — the bug evidence

```
[17:55:06] [PersistManager] State saved to user://game_state.cfg
[17:55:06] [PersistManager] Auto-saved current level on scene change: res://scenes/levels/csharp/TestTier.tscn
[17:55:06] [Player.AutoReload] Auto-reload not selected in ActiveItemManager   ✓  (auto-reload fixed)
```

Auto-reload is now correctly NOT active after the clear. However, since `kills_through_wall`
and `levels_completed_with_silenced_pistol` were not zeroed in GameManager memory before the
auto-save on scene change fires, the **new save file** would re-persist the stale values 6 and 2.

---

## 4. Root Cause Analysis

### Root Cause 1 (ORIGINAL): `active_item_changed` signal not emitted on clear

**Location:** `scripts/autoload/persist_manager.gd`, `clear_all_saves()`, line 524

```gdscript
# BEFORE FIX — signal never emitted:
active_item_manager.current_active_item = active_item_manager.ActiveItemType.NONE
```

The Player's C# handler `OnActiveItemPickedUp` was connected to `active_item_changed`. Because
the signal was bypassed, `DeequipAllActiveItems()` was never called, `_autoReloadActive` stayed
`true`, and auto-reload kept working after a full save reset.

**Fix (commit 7b77a73e):** Emit the signal explicitly after resetting `current_active_item`.

### Root Cause 2 (THIS ISSUE): New kill-stat fields not added to reset block

**Location:** `scripts/autoload/persist_manager.gd`, `clear_all_saves()`, lines 506–510

```gdscript
# BEFORE FIX — missing two fields introduced in Issue #1624:
game_manager.kills_without_laser_sight = 0        # Issue #1196
game_manager.shots_fired_special_weapons = 0       # Issue #1346
game_manager.total_deaths = 0                      # Issue #1389
game_manager.no_damage_levels_completed = 0        # Issue #1389
game_manager.levels_completed_rank_a_or_higher = 0 # Issue #1589
# ← kills_through_wall missing
# ← levels_completed_with_silenced_pistol missing
```

When Issue #1624 added `kills_through_wall` and `levels_completed_with_silenced_pistol`, the
corresponding entries were correctly added to `_save_state_with_level()` (lines 317–321) and
`_load_state()` (lines 407–415), but `clear_all_saves()` was not updated.

As a result, the in-memory counters in `GameManager` kept their loaded values (6 and 2), and
the next `_save_state()` call (triggered by the scene-change auto-save during tutorial reload)
would write them back to disk, making the reset appear incomplete even across restarts.

**Fix:** Add the two missing reset lines in `clear_all_saves()`:

```gdscript
game_manager.kills_through_wall = 0               # Issue #1624
game_manager.levels_completed_with_silenced_pistol = 0  # Issue #1624
```

---

## 5. Evidence Summary

| Stat | Loaded at startup | Reset by clear_all_saves? | Expected after reset |
|---|---|---|---|
| `kills_without_laser_sight` | 0 | ✅ yes | 0 |
| `shots_fired_special_weapons` | 0 | ✅ yes | 0 |
| `total_deaths` | 0 | ✅ yes | 0 |
| `no_damage_levels_completed` | 0 | ✅ yes | 0 |
| `levels_completed_rank_a_or_higher` | 0 | ✅ yes | 0 |
| `kills_through_wall` | **6** | ❌ **NO (bug)** | 0 |
| `levels_completed_with_silenced_pistol` | **2** | ❌ **NO (bug)** | 0 |
| `active_item_changed` signal emitted | — | ✅ yes (PR fix) | de-equip all items |

---

## 6. Why the Bug Was Introduced

The pattern used in `persist_manager.gd` requires any new persisted stat to be added in
**three places** simultaneously:
1. `_save_state_with_level()` — write to config file
2. `_load_state()` — read from config file
3. `clear_all_saves()` — reset in-memory value on wipe

Issue #1624 correctly added the fields to places 1 and 2, but missed place 3. This is a
structural fragility: there is no single source of truth or automated check that enforces
all three must stay in sync.

**Proposed systemic improvement:** Extract the list of resettable stats into a dictionary or
helper method so that saving, loading, and resetting all operate on the same canonical list.
This would prevent future regressions of this type.

---

## 7. Fix Applied

**File:** `scripts/autoload/persist_manager.gd`

```gdscript
# clear_all_saves() — GameManager kill-stat reset block (after fix):
game_manager.kills_without_laser_sight = 0        # Issue #1196
game_manager.shots_fired_special_weapons = 0       # Issue #1346
game_manager.total_deaths = 0                      # Issue #1389
game_manager.no_damage_levels_completed = 0        # Issue #1389
game_manager.levels_completed_rank_a_or_higher = 0 # Issue #1589
game_manager.kills_through_wall = 0               # Issue #1624
game_manager.levels_completed_with_silenced_pistol = 0  # Issue #1624
```

Combined with the previously committed fix (emit `active_item_changed` on clear), all stat
resets and active item de-equipping now work correctly after a save wipe.
