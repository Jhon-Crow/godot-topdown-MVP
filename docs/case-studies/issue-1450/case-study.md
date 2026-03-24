# Case Study: Issue #1450 — Treasure Room State Not Persisted

## Summary

After exiting the treasure room (сокровищница) and re-entering it within the same roguelike run,
the room generates a new item pedestal instead of showing the already-visited (empty) state.
This allows players to repeatedly collect items from the same treasure room.

## Data

- **Issue:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1450
- **Log file:** `game_log_20260324_180116.txt`
- **Reported by:** Jhon-Crow
- **Severity:** High — allows unintended infinite item farming

## Timeline / Sequence of Events (from log)

```
[18:01:16] Game started
[18:01:21] Roguelike run started (Level 1)
[18:02:05] TREASURE ROOM — Level 1 — pedestal: Тихий пистолет (Silenced Pistol)
[18:02:13] TREASURE ROOM — Level 1 — pedestal: АК-74+ГП  ← SAME LEVEL, NEW ITEM
[18:02:23] TREASURE ROOM — Level 1 — pedestal: Flashlight ← 3rd re-entry, new item again
...
[18:06:28] TREASURE ROOM — Level 4 — pedestal: Dash
[18:06:37] TREASURE ROOM — Level 4 — pedestal: Снайперская винтовка ← re-entered Level 4's treasure room
[18:06:41] TREASURE ROOM — Level 4 — pedestal: Револьвер
[18:06:47] TREASURE ROOM — Level 4 — pedestal: Force Field
... (continues for 20+ re-entries at Level 4)
```

At Level 4, the player enters/exits the treasure room ~20 times in ~2 minutes (18:06:28–18:08:19),
each time receiving a brand-new item pedestal.

## Root Cause Analysis

### Architecture

The roguelike level uses an Isaac-style branching room map (`GameManager.roguelike_room_map`).
Each room entry in the map has a `"cleared": bool` field. When a room is cleared:
- Combat rooms: enemies all killed → `cleared = true` (line 1748)
- Start rooms and cleared revisits: `cleared` is read in `_ready()` → `_room_cleared = true` → doors open
- Treasure rooms: **`cleared` is NEVER set to true** in the map entry

### Bug 1 — Treasure room map entry never marked `cleared`

In `_navigate_to_map_room()` (line 2383), when the player navigates to a treasure room:

```gdscript
match target_room["map_room_type"]:
    "treasure":
        GameManager.roguelike_in_treasure_room = true
        _show_map_room_transition(...)  # Changes scene
```

The **current room** (source) gets `cleared = true` at line 2397-2398, but the **target treasure
room** is never marked `cleared`. So when the player exits and re-enters the treasure room from
any connected room, `map_room["cleared"]` is still `false`.

### Bug 2 — No re-entry guard in `_ready()` / `is_treasure_map_room` path

In `_ready()` (line 273), when `is_treasure_map_room == true`:
```gdscript
if is_treasure_map_room:
    ...
    _spawn_treasure_pedestal()   # Always spawns a new pedestal
```

There is no check for `map_room["cleared"]` before spawning a pedestal. Similarly, the legacy
path at line 208 (`GameManager.roguelike_in_treasure_room == true`) always spawns a pedestal.

### Combined Effect

Because Bug 1 means `cleared` is always `false` for the treasure room, and Bug 2 always spawns
a new pedestal without checking `cleared`, every time the player enters the treasure room (from
any connected room on the branching map), they get a fresh pedestal with a new random item.

## Fix

### Fix 1 — Mark treasure room as `cleared` when the player enters it

In `_navigate_to_map_room()`, after setting `roguelike_in_treasure_room = true`, also mark the
target room's map entry as `cleared = true`. This persists through scene reloads via GameManager.

```gdscript
"treasure":
    GameManager.roguelike_in_treasure_room = true
    # Issue #1450: mark the treasure room as cleared so re-entry is detected
    rooms[target_room_idx]["cleared"] = true
    if not (target_room_idx in GameManager.roguelike_visited_rooms):
        GameManager.roguelike_visited_rooms.append(target_room_idx)
    rooms[target_room_idx]["visited"] = true
    _show_map_room_transition(target_room_idx, "Сокровищница!", Color(1.0, 0.85, 0.3, 1.0))
```

### Fix 2 — Skip pedestal on re-entry of cleared treasure room

In the `is_treasure_map_room` branch of `_ready()`, check if the room is already cleared before
spawning a pedestal:

```gdscript
if is_treasure_map_room:
    ...
    var treasure_already_cleared: bool = GameManager.roguelike_room_map[map_room_idx]["cleared"] \
        and GameManager.roguelike_room_map[map_room_idx]["visited"]
    if not treasure_already_cleared:
        _spawn_treasure_pedestal()
```

Wait — but if we apply Fix 1 we mark `cleared = true` on first entry, so on re-entry the
pedestal won't spawn. This is the correct behaviour.

The same check should also be applied to the legacy `roguelike_in_treasure_room` path.

## Additional References

- Issue #1166 — introduced treasure rooms
- Issue #1399 — introduced the branching room map
- Issue #1313 — added `roguelike_offered_items` to prevent duplicate item offers (partially
  addresses the symptom but not the root cause)
