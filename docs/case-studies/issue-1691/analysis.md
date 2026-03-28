# Case Study: Issue #1691 — Loudspeaker Not Unlocked From Start

## Summary

**Issue**: The loudspeaker (громкоговоритель) should be fully unlocked from game start (not behind any condition), but should not be auto-selected.

**Reported by**: Jhon-Crow on 2026-03-28
**Status**: Bug confirmed via game log analysis. Root cause found.
**Log file**: `game_log_20260328_175144.txt`

---

## Timeline / Sequence of Events

| Time | Event |
|------|-------|
| 17:51:44 | Game launched (Windows, non-debug build, Godot 4.3-stable) |
| 17:51:46 | PersistManager loaded — restored unlocked active item type 11 (LOUDSPEAKER) ✅ |
| 17:51:46 | PersistManager restored selected active item type 0 (NONE) ✅ |
| 17:51:48 | UnlockManager ran deferred reset+restore — LOUDSPEAKER not touched (correct, no condition) ✅ |
| 17:51:55 | User opened Armory via pause menu |
| 17:52:04 | **User triggered "Clear All Saves"** — `clear_all_saves()` called |
| 17:52:04 | `[ActiveItemManager] Loudspeaker progress reset` |
| 17:52:04 | `[ProgressManager] All progress cleared` |
| 17:52:04 | `[PersistManager] All saves cleared — game reset to first-launch state` |
| 17:52:05 | Level reloaded — game continues running with in-memory state |
| After 17:52:05 | LOUDSPEAKER is `false` in memory — shows as LOCKED in armory ❌ |

---

## Root Cause Analysis

### Primary Bug: `persist_manager.gd` — `clear_all_saves()` resets LOUDSPEAKER to locked

**Location**: `scripts/autoload/persist_manager.gd`, lines 519–527

```gdscript
# Reset ActiveItemManager to defaults
var active_item_manager: Node = get_node_or_null("/root/ActiveItemManager")
if active_item_manager:
    for item_type in active_item_manager.unlocked_active_items.keys():
        # BUG: sets ALL items to false except NONE
        # LOUDSPEAKER should also be true (it's freely available from start)
        active_item_manager.unlocked_active_items[item_type] = item_type == active_item_manager.ActiveItemType.NONE
```

This loop sets **every item** to `false` except `NONE`. But `LOUDSPEAKER` has `true` as its default value in `active_item_manager.gd` because it has no unlock condition. After `clear_all_saves()` runs, LOUDSPEAKER becomes `false` **in memory** for the rest of the current session.

### Why Prior Fix Was Insufficient

The previous PR (`fix(#1691)` commit `3cf8c14d`) only updated:
1. A comment in `active_item_manager.gd`
2. Unit tests (mock classes were missing methods/entries)

It did **not** fix the actual runtime bug in `clear_all_saves()`.

### Why It Works On First Launch (But Breaks After Clearing Saves)

On fresh start or normal load:
- `active_item_manager.gd` initializes `unlocked_active_items` with `LOUDSPEAKER: true`
- PersistManager's `_load_state()` only sets items to `true` if saved as `true` — never sets to `false`
- Result: LOUDSPEAKER is `true` ✅

After `clear_all_saves()`:
- The loop in `clear_all_saves()` iterates all items and sets each to `item_type == NONE`
- `LOUDSPEAKER (11) == NONE (0)` → `false`
- In-memory state: LOUDSPEAKER is `false` ❌
- Armory shows LOUDSPEAKER as locked for the rest of the session

---

## Fix

In `persist_manager.gd`, the `clear_all_saves()` reset loop must preserve the default unlock state for items that are freely available from the start (i.e., `LOUDSPEAKER`).

**Approach**: Instead of hardcoding only `NONE` as unlocked, use `UnlockManager.get_active_items_with_conditions()` to identify condition-gated items and reset only those. Items not in any condition table retain their defaults.

**Alternative simpler approach**: Check the item's default value from the original dictionary definition. Since we can't easily query the original default at runtime, the cleanest fix is:

```gdscript
# In clear_all_saves(), replace:
active_item_manager.unlocked_active_items[item_type] = item_type == active_item_manager.ActiveItemType.NONE

# With: only reset condition-gated items (items not in any unlock condition keep their defaults)
var unlock_manager: Node = get_node_or_null("/root/UnlockManager")
var condition_gated_items: Array[int] = []
if unlock_manager and unlock_manager.has_method("get_active_items_with_conditions"):
    condition_gated_items = unlock_manager.get_active_items_with_conditions()
for item_type in active_item_manager.unlocked_active_items.keys():
    if item_type in condition_gated_items:
        active_item_manager.unlocked_active_items[item_type] = false
    # else: keep the default value (e.g. LOUDSPEAKER stays true, NONE stays true)
```

---

## Additional Context

- The game binary used for testing was: `I:/Загрузки/godot exe/UNLOCKES/Godot-Top-Down-Template.exe`
- Build: Godot 4.3-stable, Windows, non-debug
- The save file already had LOUDSPEAKER (type 11) listed as unlocked, confirming it was correctly persisted before the clear

---

## Files Involved

| File | Role |
|------|------|
| `scripts/autoload/active_item_manager.gd` | Defines default unlock state: `LOUDSPEAKER: true` |
| `scripts/autoload/persist_manager.gd` | **BUG HERE** — `clear_all_saves()` resets LOUDSPEAKER to `false` |
| `scripts/autoload/unlock_manager.gd` | Correctly ignores LOUDSPEAKER (no condition) |
| `scripts/ui/armory_menu.gd` | Reads unlock state to show locked/unlocked slots |
