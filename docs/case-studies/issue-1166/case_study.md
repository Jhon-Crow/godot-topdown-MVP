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

## Timeline of Events

| Time | Event |
|------|-------|
| 2026-03-18 06:54 | Initial solution committed (`eafb219c`) with pedestal system |
| 2026-03-18 06:56 | PR marked ready to merge |
| 2026-03-18 07:06 | Owner tests the build, reports 3 bugs |
| 2026-03-18 07:07 | New AI work session starts |
| 2026-03-18 ~07:15 | Root causes identified, fixes implemented |

---

## Fix Summary

| Bug | Root Cause | Fix |
|-----|-----------|-----|
| 1: Pedestal every room | Unconditional `_spawn_treasure_pedestal()` call | Guard: only call on last room (`_current_room_idx + 1 >= _total_rooms`) |
| 2: Item not picked up | `monitoring=true` set before `add_child`, skips existing overlaps in Godot 4 | Set `monitoring=false`, then `set_deferred("monitoring", true)` after `add_child` |
| 3: Square display | `ColorRect` orb instead of icon texture | Use `TextureRect` with `get_active_item_icon_path()` / `weapon_case_icon.png` |

---

## Files Changed

- `scripts/levels/roguelike_level.gd` — 3 bug fixes in pedestal system
- `tests/unit/test_roguelike_level.gd` — new tests for last-room pedestal logic

---

## References

- Godot 4 docs: [Area2D.body_entered](https://docs.godotengine.org/en/stable/classes/class_area2d.html#signals) — signal fires when body **enters** the area (not for pre-existing overlaps when monitoring is first enabled)
- The Binding of Isaac — pedestal/treasure room mechanic that inspired this feature
- `ActiveItemManager.get_active_item_icon_path()` — `scripts/autoload/active_item_manager.gd:245`
