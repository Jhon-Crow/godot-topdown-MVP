# Case Study: Issue #1450 — Treasure Room State Not Persisted

## Summary

After exiting the treasure room (сокровищница) and re-entering it within the same roguelike run,
the room generates a new item pedestal instead of showing the already-visited (empty) state.
This allows players to repeatedly collect items from the same treasure room.

A first fix was attempted (PR #1474, commit `dca7ca8c`) that used a `cleared` flag to skip pedestal
re-spawning. The owner confirmed this fix was **insufficient**: the room was just being cleared on
entry rather than having its state properly saved and restored.

---

## Data

- **Issue:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1450
- **PR:** https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1474
- **Log file (original):** `game_log_20260324_180116.txt`
- **Log file (post-fix repro):** `game_log_20260325_171535.txt`
- **Reported by:** Jhon-Crow
- **Severity:** High — allows unintended infinite item farming

---

## Timeline / Sequence of Events

### Original log (`game_log_20260324_180116.txt`)

```
[18:01:16] Game started
[18:01:21] Roguelike run started (Level 1)
[18:02:05] TREASURE ROOM — Level 1 — pedestal: Тихий пистолет
[18:02:13] TREASURE ROOM — Level 1 — pedestal: АК-74+ГП   ← SAME LEVEL, NEW ITEM
[18:02:23] TREASURE ROOM — Level 1 — pedestal: Flashlight  ← 3rd re-entry, new item
[18:06:28] TREASURE ROOM — Level 4 — pedestal: Dash
...
[18:08:19] TREASURE ROOM — Level 4 — (20+ re-entries, new item each time)
```

### Post-fix log (`game_log_20260325_171535.txt`) — partial fix applied

```
[17:15:49] TREASURE ROOM — Level 1 → pedestal spawned: Dash       ← 1st entry ✓
[17:15:52] Player picked up: Dash
[17:15:56] TREASURE ROOM — Level 1 → already cleared — skipping   ← 2nd entry ✓
[17:16:03] TREASURE ROOM — Level 1 → already cleared — skipping   ← 3rd entry ✓
[17:16:07] TREASURE ROOM — Level 1 → already cleared — skipping   ← 4th entry ✓
[17:16:10] TREASURE ROOM — Level 1 → pedestal spawned: Flashlight ← 5th entry ✗ BUG!
[17:16:13] TREASURE ROOM — Level 1 → already cleared — skipping   ← 6th entry ✓
[17:16:15] TREASURE ROOM — Level 1 → already cleared — skipping   ← 7th entry ✓
```

The partial fix reduced the frequency of the exploit but did not eliminate it.

---

## Root Cause Analysis (Deep — Updated)

### Architecture overview

The roguelike level uses an Isaac-style branching room map (`GameManager.roguelike_room_map`), an
array of room dictionaries. Each room has a `"cleared": bool` field. When a room is cleared:

- Combat rooms: enemies all killed → `cleared = true` (line 1775)
- Treasure rooms: **never properly tracked** — the original bug

Critically, every time a room is visited by `_navigate_to_map_room()`, the *source* room is marked
`cleared = true` at line 2425 (`rooms[current_idx]["cleared"] = true`). The scene is then reloaded
via `change_scene_to_file("RoguelikeLevel.tscn")`, and `_ready()` runs from scratch.

### Two entry paths in `_ready()`

The roguelike level has **two** separate code paths that activate when entering a treasure room:

**Path 1 (line 208):** `if GameManager.roguelike_in_treasure_room:` — used when
`roguelike_in_treasure_room` is already `true` when the scene loads. This fires for the legacy
(pre-map) flow and for any room loaded while `roguelike_in_treasure_room` is set.

**Path 2 (line 287):** `if is_treasure_map_room:` — checks the map entry's `map_room_type ==
"treasure"`. Sets `roguelike_in_treasure_room = true`.

### Bug 1 — `roguelike_in_treasure_room` never reset on exit

In `_navigate_to_map_room()`, the "treasure" branch sets `roguelike_in_treasure_room = true`.
The `_:` (catch-all) branch — used when navigating FROM the treasure room to a combat room — did
**not** reset it to `false`. The only resets were in `_start_new_run()` and `_start_next_level()`.

**Consequence:** After visiting the treasure room, `roguelike_in_treasure_room` stayed `true` for
all subsequent room loads. Every time the player navigated FROM the treasure room to a combat room,
`current_map_room` was set to the combat room index. The next scene loaded with
`roguelike_in_treasure_room = true`, so Path 1 fired — but `roguelike_current_map_room` now pointed
to a **combat room entry**, not the treasure room.

If that combat room's `cleared` was `false` (not yet visited), Path 1 read `false` and spawned a
pedestal! This is confirmed by the 5th visit in the post-fix log: the player navigated to a
**new, uncleared combat room** just before entry 5, so `roguelike_current_map_room` pointed to that
room with `cleared = false`.

Sequence for the 5th-visit bug:
```
(in treasure room)
Player exits → _navigate_to_map_room(combat_new)
  → rooms[treasure_idx]["cleared"] = true   ← marks treasure as cleared (OK)
  → roguelike_current_map_room = combat_new ← points to new combat room
  → roguelike_in_treasure_room NOT reset    ← BUG: stays true
  → scene reloads
_ready():
  roguelike_in_treasure_room == true → Path 1 fires!
  _tr_map_idx = roguelike_current_map_room = combat_new
  rooms[combat_new]["cleared"] == false → spawns pedestal! ✗
```

### Bug 2 — State approach was wrong

The first fix used `cleared` as the "skip pedestal" signal. This was semantically wrong:
- `cleared` is also set for combat rooms when enemies are killed
- `cleared` was set on the **first entry** to the treasure room — but this meant a player who
  entered a treasure room and left WITHOUT picking up the item would see an **empty room** on
  re-entry, which is not the intended game design

The correct design is:
- If the player has **not yet collected the item**: show the same item on re-entry
- If the player **has collected the item**: show empty room

### Bug 3 — Offered item not persisted

The first fix never saved which item was shown on the pedestal. `_pick_random_pedestal_item()` was
called on every spawn (subject only to the `cleared` flag). Even if the `cleared` flag had worked
correctly, re-entering before collection would show a different random item.

---

## Root Causes (Summary)

| # | Root Cause | Effect |
|---|---|---|
| 1 | `roguelike_in_treasure_room` not reset when leaving treasure room | Combat rooms misidentified as treasure rooms in `_ready()` Path 1 |
| 2 | `cleared` flag used as proxy for "pedestal already spawned" | Any uncleared room triggers a pedestal spawn; item not shown on re-entry before collection |
| 3 | Offered item not persisted in room map | Re-entry shows different random item even when item was not collected |

---

## Fix (Issue #1450 — v2)

### Fix 1 — Reset `roguelike_in_treasure_room` on exit

In `_navigate_to_map_room()` `_:` branch (navigating to non-treasure room):

```gdscript
_:
    # Issue #1450: reset flag so the next room is not misidentified as treasure.
    GameManager.roguelike_in_treasure_room = false
    ...
```

### Fix 2 — Add `treasure_item` and `treasure_collected` fields to room map

In `_generate_room_map()`, when tagging a room as treasure:

```gdscript
rooms[treasure_idx]["map_room_type"] = "treasure"
rooms[treasure_idx]["treasure_item"] = null       # persisted item on pedestal
rooms[treasure_idx]["treasure_collected"] = false  # set true when player collects
```

### Fix 3 — Persist offered item; restore on re-entry

In `_spawn_treasure_pedestal()`:

```gdscript
var saved_item = GameManager.roguelike_room_map[map_idx].get("treasure_item", null)
if saved_item != null:
    item = saved_item  # Restore same item (re-entry before collection)
else:
    item = _pick_random_pedestal_item()
    GameManager.roguelike_room_map[map_idx]["treasure_item"] = item  # Persist it
```

### Fix 4 — Skip pedestal on `treasure_collected`, not `cleared`

In `_ready()` both paths:

```gdscript
var already_collected := GameManager.roguelike_room_map[map_idx].get("treasure_collected", false)
if not already_collected:
    _spawn_treasure_pedestal()  # restores same item or picks new one
else:
    # item gone for good — empty room
```

### Fix 5 — Mark collected when pedestal is consumed

New helper called wherever `pedestal.queue_free()` removes the item permanently:

```gdscript
func _mark_treasure_collected() -> void:
    var map_idx := GameManager.roguelike_current_map_room
    GameManager.roguelike_room_map[map_idx]["treasure_collected"] = true
```

Called in `_apply_pedestal_weapon()` and `_apply_pedestal_active_item()` when the pedestal is
removed (not when item is merely swapped back onto it). When a swap occurs (player takes item A,
old item B placed back on pedestal), `treasure_item` is updated to B so re-entry restores B.

---

## Expected Behaviour After Fix

| Scenario | Before fix | After v1 fix | After v2 fix (this PR) |
|---|---|---|---|
| Enter treasure room 1st time | New item spawned | New item spawned ✓ | New item spawned ✓ |
| Exit without picking up, re-enter | New item each time ✗ | Empty room ✗ (item lost) | Same item restored ✓ |
| Pick up item, re-enter | New item spawned ✗ | Empty room ✓ | Empty room ✓ |
| Cycle 5+ times without collecting | New item on ~every 3rd visit ✗ | Empty on 2nd visit ✓ | Same item on each re-visit ✓ |

---

## Additional References

- Issue #1166 — introduced treasure rooms (original feature)
- Issue #1399 — introduced the branching room map (`roguelike_room_map`)
- Issue #1313 — added `roguelike_offered_items` to prevent duplicate item offers
  (partially addresses the symptom but not the root cause)
- Godot 4 docs: Arrays and Dictionaries are reference types — `var rooms = GameManager.roguelike_room_map`
  is a reference, so mutations through `rooms[i]["key"] = val` are visible globally
- Isaac-style roguelikes (Binding of Isaac, Enter the Gungeon) persist room state across visits:
  cleared rooms stay cleared, uncollected pedestals remain with the same item

## Log Files

- `game_log_20260324_180116.txt` — original repro (infinite item farming, 20+ re-entries)
- `game_log_20260325_171535.txt` — post-v1-fix repro (7 re-entries, 5th visit spawns new item)
- `game_log_20260326_170436.txt` — post-v2-fix repro (combat room enemies respawn on revisit)

---

## Bug 4 — Combat Room Enemies Respawn on Revisit (discovered 2026-03-26)

### Owner feedback

> "состояние сокровищницы сохранается, но состояние обычных комнат - нет"
> (treasure room state is saved, but regular room state is not)

### Log evidence (`game_log_20260326_170436.txt`)

Enemy spawn positions exactly repeat across multiple visits to the same combat room:

```
[17:05:15] Enemy_0 Spawned at (1440, 324) — 1st visit
[17:05:31] Enemy_0 Spawned at (1440, 324) — 2nd visit ← enemies respawn!
[17:05:41] Enemy_0 Spawned at (1440, 324) — 3rd visit ← enemies respawn!
[17:06:02] Enemy_0 Spawned at (1440, 324) — 4th visit ← enemies respawn!
[17:06:36] Enemy_0 Spawned at (1440, 324) — 5th visit ← enemies respawn!
```

The room was visited 5 times with enemies re-appearing each time.

### Root Cause — Bug 4

In `_ready()`, the order of operations was:

```gdscript
_build_room_scene()          # ← spawns enemies via _spawn_enemies_in_room()
_spawn_player()
_setup_navigation()
_setup_player_tracking()

if is_start_room or is_cleared_revisit:  # ← checked AFTER spawn
    _room_cleared = true
    ...
    return
```

`_build_room_scene()` calls `_spawn_enemies_in_room()` unconditionally. The `is_cleared_revisit`
check (which should skip enemy spawning) runs **after** enemies are already added to the scene.
Even though `_setup_enemy_tracking()` is not called for cleared revisits, the enemies still
exist in the scene tree — they are visible, mobile, and fire at the player.

### Fix — Bug 4

Move the `is_cleared_revisit` / `is_start_room` check **before** `_build_room_scene()`. For
cleared rooms, use a new `_build_room_scene_no_enemies()` function that builds walls, floor, and
door zones but **does not call `_spawn_enemies_in_room()`**:

```gdscript
# Issue #1450: Start rooms and cleared-revisit rooms must NOT spawn enemies.
if is_start_room or is_cleared_revisit:
    _build_room_scene_no_enemies()   # walls + floor, no enemies
    _spawn_player()
    ...
    return

_build_room_scene()                  # walls + floor + enemies (uncleared rooms only)
_spawn_player()
...
```

### Behaviour After Fix

| Scenario | Before fix | After v3 fix |
|---|---|---|
| Enter cleared combat room | Enemies respawn ✗ | Empty room, doors open ✓ |
| Enter uncleared combat room | Enemies spawn ✓ | Enemies spawn ✓ |
| Treasure room re-entry | Same item restored ✓ | Same item restored ✓ |
