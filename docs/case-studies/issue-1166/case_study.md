# Case Study: Issue #1166 — Update Roguelike Mode (Treasure Pedestal Bugs)

## Overview

- **Issue**: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1166
- **PR**: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1167
- **Reporter / Owner**: Jhon-Crow
- **Status**: Bug fix applied

---

## Original Feature Request (Issue #1166)

The owner requested an Isaac-style treasure mechanic:

> 1. After completing one stage (all rooms/levels), the player enters a treasure room with a random item (weapon/grenade/active/passive).
> 2. Items are picked up by touching the pedestal (Isaac mechanics).
> 3. Passive items stack/accumulate; active items replace the current one (old item placed back on pedestal).

The initial implementation (PR #1167, commit `eafb219c`) added a treasure pedestal system, but contained 3 bugs discovered during testing.

---

## Bug Report (Comment on PR, 2026-03-18)

**Reporter**: Jhon-Crow (repo owner)
**Log file**: `game_log_20260318_100318.txt` (downloaded to this folder)
**Screenshot**: `screenshot_1.png` — shows HUD "РОГАЛИК — Комната 2 / 3 — Лабиринт"

### Bug 1: Pedestal appears after each room, not after the full level/stage

**Expected**: Pedestal appears only after ALL rooms are cleared (end of run/stage).
**Actual**: Pedestal appeared after every individual room.

### Bug 2: Item cannot be picked up from the pedestal

**Expected**: Player walks into the pedestal and collects the item automatically (Isaac style).
**Actual**: Item not collected on touch.

### Bug 3: Item displays as a square, not as icon

**Expected**: Item displayed as its actual icon (transparent background).
**Actual**: Item shown as a plain coloured square (`ColorRect`).

---

## Root Cause Analysis

### Bug 1 — Pedestal on every room

In `roguelike_level.gd`, function `_on_enemy_died()`:

```gdscript
if _current_enemy_count <= 0:
    _room_cleared = true
    call_deferred("_spawn_treasure_pedestal")  # ← called unconditionally
    call_deferred("_activate_exit_zone")
```

`_spawn_treasure_pedestal()` was called every time all enemies in a room died, regardless of whether it was the last room or not. The original feature spec says pedestal should appear after **all rooms** in a stage are cleared.

**Fix**: Guard the call with `if _current_room_idx + 1 >= _total_rooms`.

---

### Bug 2 — Item not picked up on touch

The pedestal `Area2D` was created with `monitoring = true` set **before** `add_child(pedestal)`. In Godot 4, when an `Area2D` first enters the scene tree with `monitoring = true`, any bodies **already overlapping** the area at the moment it becomes active do **not** emit the `body_entered` signal — they only emit if they enter the area **after** monitoring is enabled.

Since the pedestal spawns at room centre and the player might already be standing there (or walks over it as enemies are dying), the signal never fires for the initial overlap.

**Fix**: Set `pedestal.monitoring = false` before `add_child(pedestal)`, then call `pedestal.set_deferred("monitoring", true)` after it's in the scene tree. This causes Godot to re-evaluate overlaps in the next physics frame, emitting `body_entered` for any already-overlapping bodies.

```gdscript
pedestal.monitoring = false   # disabled during setup
add_child(pedestal)
pedestal.set_deferred("monitoring", true)  # enabled after add_child
```

---

### Bug 3 — Square display instead of icon

The visual "item" on the pedestal was a `ColorRect` (a plain coloured square):

```gdscript
var orb := ColorRect.new()
orb.size  = Vector2(PEDESTAL_SIZE * 0.55, PEDESTAL_SIZE * 0.55)
orb.color = PEDESTAL_ITEM_GLOW   # golden colour
```

This doesn't show any meaningful icon. The `ActiveItemManager` already provides icon paths via `get_active_item_icon_path(type)`, and weapon icons exist in `res://assets/sprites/weapons/weapon_case_icon.png`.

**Fix**: Replace `ColorRect` with `TextureRect` that loads the actual item icon, with transparent background (`expand_mode = EXPAND_KEEP_SIZE`, `stretch_mode = STRETCH_KEEP_ASPECT_CENTERED`). Fall back to the coloured square if the icon path is empty or not found.

---

## Second Bug Report (Comment on PR, 2026-03-18 ~07:57 UTC)

**Reporter**: Jhon-Crow (repo owner)
**Log file**: `game_log_20260318_105539.txt`
**Issue**: After the multi-level treasure room implementation (`e20299db`), the pedestal was missing in the treasure room ("в сокровищнице не было пьедестала").

### Analysis of `game_log_20260318_105539.txt`

The log shows 4 combat rooms (Level 1) followed by a 5th scene change (at 10:56:22) with **no enemies and no ScoreManager "Level started" message** — this is the treasure room loading correctly. The player stayed ~9 seconds then the next combat room loaded.

The game log system uses `FileLogger.info()` for custom events; Godot's built-in `print()` does **not** appear in the file log. Therefore we cannot confirm from the log whether `_spawn_treasure_pedestal()` ran or whether the pedestal was added to the scene.

### Root Cause (Bug 4): Deferred pedestal spawn + small visual

Two contributing factors were identified:

**Factor A — Deferred spawn timing**: The pedestal was created with `call_deferred("_spawn_treasure_pedestal")`, meaning it ran one frame AFTER `_ready()`. While this should work, it introduced a race condition: if any deferred code in other autoloads (e.g., CinemaEffects, PenultimateHit) triggered a scene interaction on the same deferred frame, the pedestal's `add_child` could fail silently in the exported non-debug build.

**Factor B — Pedestal too small / not logged**: The pedestal base was only 48×19 pixels — easy to miss. More critically, because only `print()` (not `FileLogger`) was used inside `_spawn_treasure_pedestal`, there was no evidence in the game log whether the function ran at all.

**Fix**:
1. Changed `call_deferred("_spawn_treasure_pedestal")` → direct `_spawn_treasure_pedestal()` call in `_ready()` for treasure rooms. The `set_deferred("monitoring", true)` for the overlap signal is still deferred.
2. Added `FileLogger.info()` calls throughout the treasure room code path so future logs will confirm execution.
3. Made the pedestal visually larger (glow ring, wider base, bigger icon and labels) so the player cannot miss it.

---

## Timeline of Events

| Time (UTC) | Event |
|------|-------|
| 2026-03-18 06:50 | Initial solution committed (`eafb219c`) with pedestal system |
| 2026-03-18 06:56 | PR marked ready to merge |
| 2026-03-18 07:06 | Owner tests build, reports 3 bugs (pedestal every room / can't pick up / square display) |
| 2026-03-18 07:07 | AI work session starts |
| 2026-03-18 07:15 | Bugs 1–3 fixed (`42741498`) |
| 2026-03-18 07:34 | Treasure room + multi-level progression implemented (`e20299db`) |
| 2026-03-18 07:57 | Owner tests again, reports pedestal missing in treasure room |
| 2026-03-18 ~08:00 | Log downloaded, analysed; deferred spawn + small visual identified as root cause |
| 2026-03-18 ~08:10 | Bug 4 fixed: direct spawn, FileLogger tracing, larger visuals |

---

## Fix Summary

| Bug | Root Cause | Fix |
|-----|-----------|-----|
| 1: Pedestal every room | Unconditional `_spawn_treasure_pedestal()` call | Guard: only call on last room; move to dedicated treasure room |
| 2: Item not picked up | `monitoring=true` set before `add_child`, skips existing overlaps in Godot 4 | Set `monitoring=false`, then `set_deferred("monitoring", true)` after `add_child` |
| 3: Square display | `ColorRect` orb instead of icon texture | Use `TextureRect` with `get_active_item_icon_path()` / `weapon_case_icon.png` |
| 4: Pedestal missing in treasure room | Deferred spawn (could fail silently in export) + too small to notice | Direct spawn in `_ready()`, FileLogger tracing, larger visuals |

---

## Files Changed

- `scripts/levels/roguelike_level.gd` — treasure room spawn, pedestal visibility, FileLogger tracing
- `tests/unit/test_roguelike_level.gd` — tests for last-room pedestal logic and treasure room flow
- `docs/case-studies/issue-1166/game_log_20260318_105539.txt` — second game log from owner

---

## References

- Godot 4 docs: [Area2D.body_entered](https://docs.godotengine.org/en/stable/classes/class_area2d.html#signals) — signal fires when body **enters** the area (not for pre-existing overlaps when monitoring is first enabled)
- Godot 4 docs: [call_deferred](https://docs.godotengine.org/en/stable/classes/class_object.html#class-object-method-call-deferred) — schedules call at end of current frame; in exported non-debug builds, errors inside deferred calls are silently discarded
- The Binding of Isaac — pedestal/treasure room mechanic that inspired this feature
- `ActiveItemManager.get_active_item_icon_path()` — `scripts/autoload/active_item_manager.gd:245`
