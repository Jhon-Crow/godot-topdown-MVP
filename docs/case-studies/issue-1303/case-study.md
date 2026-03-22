# Case Study: Issue #1303 — Pedestal Bugs in Roguelike Mode

## Summary

When returning an active item to a pedestal in roguelike mode, two bugs occurred:
1. The pedestal icon did not update to show the returned item.
2. The pedestal sometimes disappeared entirely instead of offering a swap.

## Timeline (from game_log_20260322_054251.txt)

| Time     | Event                                                        |
|----------|--------------------------------------------------------------|
| 05:42:52 | Player starts with Breaching Charges (active item type 12)   |
| 05:44:05 | Treasure pedestal spawns: Silenced Pistol (weapon)           |
| 05:45:26 | Treasure pedestal spawns: Teleport Bracers (type 3)          |
| 05:45:28 | Active item changed: None → Teleport Bracers                |
| 05:46:42 | Treasure pedestal spawns: Auto-Reload (type 14)              |
| 05:46:44 | Active item changed: Teleport Bracers → Auto-Reload         |
| 05:46:46 | Active item changed: Auto-Reload → Teleport Bracers (swap)  |
| 05:46:56 | Active item changed: Teleport Bracers → Auto-Reload (swap)  |
| 05:49:25 | Treasure pedestal spawns: Trajectory Glasses (type 8)        |
| 05:49:38 | Active item changed: Auto-Reload → Trajectory Glasses       |

The swap at 05:46:44 / 05:46:46 confirms pedestal swapping did work for some items.
However at 05:49:38, taking Trajectory Glasses while holding Auto-Reload caused the
pedestal to disappear (no swap back).

## Root Cause Analysis

### Bug 1: Pedestal disappears instead of offering swap

`PASSIVE_ACTIVE_ITEM_TYPES` in `roguelike_level.gd` used incorrect enum values:

```gdscript
# WRONG (before fix):
const PASSIVE_ACTIVE_ITEM_TYPES: Array = [2, 8, 9, 12, 13, 16]

# CORRECT (after fix):
const PASSIVE_ACTIVE_ITEM_TYPES: Array = [6, 9, 10, 13, 14, 17]
```

The values were shifted — comments named the correct items but the numbers didn't
match `ActiveItemManager.ActiveItemType` enum order. For example:
- Trajectory Glasses = enum 8, was wrongly listed as passive
- Breaker Bullets = enum 6, was listed as 2 (actually HOMING_BULLETS)

This caused Trajectory Glasses (type 8) to be treated as a passive item. When
collecting a passive item, the code always calls `pedestal.queue_free()` — no swap
is offered. The player's old active item (Auto-Reload) was silently discarded from
the pedestal.

### Bug 2: Pedestal icon not updating after active item swap

In `_apply_pedestal_active_item()`, when a non-passive item was swapped and the old
item was placed back on the pedestal, only the label text was updated. The `ItemIcon`
TextureRect was never changed to show the displaced item's icon.

Compare with `_apply_pedestal_weapon()` which correctly updates the icon via
`pedestal.get_node_or_null("ItemIcon")`.

### Bug 3: Multiple passive items cannot coexist (reported 2026-03-22)

From `game_log_20260322_065104.txt`, the player experienced this sequence:

| Time     | Event                                                        |
|----------|--------------------------------------------------------------|
| 06:51:05 | Player starts with Laser Sight as active item                |
| 06:52:22 | Treasure pedestal spawns: Breaker Bullets                    |
| 06:52:24 | Active item changed: None → Breaker Bullets                  |
| 06:52:57 | Breaker bullets active — working correctly                   |
| 06:54:12 | Treasure pedestal spawns: Auto-Reload                        |
| 06:54:14 | Active item changed: Breaker Bullets → Auto-Reload           |
| 06:54:18 | Breaker bullets NOT selected — stopped working               |

**Root cause**: `ActiveItemManager.current_active_item` is a single integer — it can
only hold ONE item at a time. All `has_*()` methods (e.g., `has_breaker_bullets()`)
check `current_active_item == ActiveItemType.X`. When a passive item is collected via
`set_active_item()`, it **replaces** the previous item entirely.

The roguelike level comment said "Passive: just set it without restart (it coexists
with any active item)" — but the underlying `set_active_item()` call overwrites
`current_active_item`, so coexistence never actually worked.

## Fixes Applied

### Phase 1 (initial commit)
1. **Corrected `PASSIVE_ACTIVE_ITEM_TYPES`** enum values to `[6, 9, 10, 13, 14, 17]`.
2. **Added icon update logic** to `_apply_pedestal_active_item()` — mirrors the
   existing pattern from `_apply_pedestal_weapon()`.

### Phase 2 (multiple passive items fix)
3. **Added `collected_passive_items: Array`** to `ActiveItemManager` — accumulates
   passive item IDs as the player picks them up during a roguelike run.
4. **Added `add_passive_item()`, `has_passive_item()`, `clear_passive_items()`** methods.
5. **Updated all passive `has_*()` methods** (`has_breaker_bullets`, `has_laser_sight`,
   `has_extended_magazine`, `has_armored_skin`, `has_auto_reload`, `has_combat_disposition`)
   to check both `current_active_item` and `collected_passive_items`.
6. **Updated derived methods** (`get_magazine_size_multiplier`, `get_total_ammo_multiplier`,
   `should_force_laser_sight`) to use the updated `has_*()` methods.
7. **Updated `_apply_pedestal_active_item()`** in roguelike_level.gd to call
   `add_passive_item()` instead of `set_active_item()` for passive items.
8. **Added `clear_passive_items()`** call at roguelike run start (room 1, level 1).
9. **Updated unit tests** with new mock methods and regression tests.

## Files Changed

- `scripts/autoload/active_item_manager.gd` — added passive item tracking + updated has_*() methods
- `scripts/levels/roguelike_level.gd` — fixed passive type IDs, icon update, passive accumulation
- `tests/unit/test_roguelike_level.gd` — corrected mock data + added regression tests
- `docs/case-studies/issue-1303/` — case study + game logs

## Affected Items (enum mapping)

| Enum Value | Item Name            | Passive? |
|------------|----------------------|----------|
| 0          | None                 | -        |
| 1          | Flashlight           | No       |
| 2          | Homing Bullets       | No       |
| 3          | Teleport Bracers     | No       |
| 4          | BFF Pendant          | No       |
| 5          | Invisibility Suit    | No       |
| 6          | Breaker Bullets      | Yes      |
| 7          | Force Field          | No       |
| 8          | Trajectory Glasses   | No       |
| 9          | Laser Sight          | Yes      |
| 10         | Extended Magazine    | Yes      |
| 11         | Loudspeaker          | No       |
| 12         | Breaching Charges    | No       |
| 13         | Armored Skin         | Yes      |
| 14         | Auto-Reload          | Yes      |
| 15         | Drilling Bullets     | No       |
| 16         | Recoil Compensator   | No       |
| 17         | Combat Disposition   | Yes      |
| 18         | Experimental Sample  | No       |
