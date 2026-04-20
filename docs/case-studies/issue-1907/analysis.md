# Issue #1907: Fix Unlock Toast Shown on Every Game Restart

## Problem Statement

When the armory has items available to unlock (conditions met, but not yet permanently unlocked by the player), toast notifications appear during combat on **every game restart**, not just once when the item first becomes available.

## Log Evidence

From `game_log_20260420_114551.txt`:

```
[11:45:52] [UnlockNotificationManager] Suppressed 5 already-available startup unlock notification(s)
...
[11:46:09] [UnlockNotificationManager] Announcing previously startup-available unlock after live condition signal: weapon:mini_uzi
[11:46:09] [UnlockNotificationManager] Announcing previously startup-available unlock after live condition signal: grenade:4
[11:46:09] [UnlockNotificationManager] Announcing previously startup-available unlock after live condition signal: active_item:12
[11:46:09] [UnlockNotificationManager] Announcing previously startup-available unlock after live condition signal: active_item:16
[11:46:09] [UnlockNotificationManager] Announcing previously startup-available unlock after live condition signal: active_item:17
[11:46:09] [UnlockManager] Kill condition met — items now available to unlock in armory
```

At 11:45:52, 5 already-available items were correctly suppressed. But at 11:46:09 (when a kill triggered `kills_without_laser_sight_updated`), all 5 suppressed items fired their toast notifications anyway.

## Timeline of Events

1. **Startup** (`_ready` → `_seed_announced_available_unlocks`): 5 items that already have conditions met are detected and added to `_startup_suppressed_available_keys`. This is correct — they should not show a toast since they were available before this session.

2. **First kill** → `items_unlocked_by_kill_condition` signal fires → `_queue_new_available_unlocks` runs.

3. **Bug**: In `_queue_new_available_unlocks`, for each entry collected:
   - The check `if _announced_available_keys.get(key, false)` passes (they were never announced).
   - `_announced_available_keys[key] = true` is set.
   - `_startup_suppressed_available_keys.erase(key)` removes the suppression.
   - `show_unlock_notification(...)` fires the toast.

4. On the **next game restart**: `_announced_available_keys` is reset to `{}` (in-memory only). `_startup_suppressed_available_keys` is also reset. The same 5 items are suppressed at startup again, then re-announced on the first kill again.

## Root Cause

`_announced_available_keys` is not persisted across sessions. On every new session:
- Startup suppression correctly captures already-available items.
- But the first live signal removes the suppression and shows the toast, defeating the purpose.

The design intent of `_startup_suppressed_available_keys` was to suppress items at startup (correct), but allow them to be shown "once" when a live signal triggers (wrong: this re-shows on every session since memory is wiped on restart).

## Fix

In `_queue_new_available_unlocks`, items in `_startup_suppressed_available_keys` should be **permanently skipped for the current session** — not erased and re-announced. The suppression at startup means "this was already available before the player started playing today, don't bother them again this session."

```gdscript
# Before (buggy):
_announced_available_keys[key] = true
if _startup_suppressed_available_keys.erase(key):
    _log("Announcing previously startup-available unlock after live condition signal: %s" % key)
show_unlock_notification(entry["name"], entry["kind"])

# After (fixed):
if _startup_suppressed_available_keys.has(key):
    continue
_announced_available_keys[key] = true
show_unlock_notification(entry["name"], entry["kind"])
```

## Correct Behavior After Fix

- Items available at startup: never shown in current session (startup suppression is permanent).
- Items whose condition becomes newly met during a session (new kill or level completion): shown once via toast.
- On next restart: items already available are again suppressed and not shown.

## Files Changed

- `scripts/autoload/unlock_notification_manager.gd`: fixed `_queue_new_available_unlocks`
- `tests/unit/test_unlock_notification_manager.gd`: replaced test validating old behavior with test validating correct behavior
