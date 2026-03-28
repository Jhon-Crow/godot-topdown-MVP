# Case Study: Issue #1635 — Experimental Sample Auto-Include Future Active Items

## Overview

**Issue:** [#1635](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1635) — Update Experimental Sample (Экспериментальный образец)

**Request (translated):** Make the Experimental Sample item trigger effects from newly added active items, and ideally make it automatically include any future items that are added.

**Pull Request:** [#1660](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1660)

---

## Root Cause Analysis

### The Bug

The Experimental Sample used a hardcoded `randi_range(1, 17)` to pick a random effect type. The enum `ActiveItemType` was defined at compile time, but the range was never updated when new items were added:

```gdscript
# OLD buggy code in player.gd
var random_type: int = randi_range(1, 17)  # Hardcoded — misses types 18, 19, 20...
```

When **FINE_MOTOR_SKILLS** (type 19) and **DASH** (type 20) were added, the hardcoded `17` was never updated, so those items could never be triggered by Experimental Sample.

### Evidence from Game Log

The game log (`game_log_20260328_100220.txt`, provided by owner) shows:
- Only types 3, 5, 7, 8, 11, 12, 15, 16 were triggered — all in range 1–17
- FINE_MOTOR_SKILLS (19) and DASH (20) were never triggered
- Format: `Charges remaining: X — triggering random effect for type Y` (old code format)
- This log was from a build **before** the fix in PR #1660 was merged

### Why the Fix Wasn't Visible to the Owner

At the time the owner tested (2026-03-28), PR #1660 had not been merged into main yet (it had a merge conflict). The owner was running a build from before the fix.

---

## All Active Items — Classification

| Type | Name | Has activation_hint | Eligible for Experimental Sample |
|------|------|---------------------|----------------------------------|
| 0  | None | No | No (excluded explicitly) |
| 1  | Flashlight | Yes | Yes |
| 2  | Homing Bullets | No | No (passive trigger on equip) |
| 3  | Teleport Bracers | Yes | Yes |
| 4  | BFF Pendant | Yes | Yes |
| 5  | Invisibility Suit | Yes | Yes |
| 6  | Breaker Bullets | No | No (passive) |
| 7  | Force Field | Yes | Yes |
| 8  | Trajectory Glasses | Yes | Yes |
| 9  | Laser Sight | No | No (passive) |
| 10 | Extended Magazine | No | No (passive) |
| 11 | Loudspeaker | Yes | Yes |
| 12 | Breaching Charges | Yes | Yes |
| 13 | Armored Skin | No | No (passive) |
| 14 | Auto-Reload | No | No (passive) |
| 15 | Drilling Bullets | Yes | Yes |
| 16 | Recoil Compensator | Yes | Yes |
| 17 | Combat Disposition | No | No (passive) |
| 18 | Experimental Sample | Yes | No (excluded explicitly — would trigger itself) |
| 19 | Fine Motor Skills | Yes | **Yes** (was missing before fix) |
| 20 | Dash | Yes | **Yes** (was missing before fix) |
| 21 | Grenade Bag | No | No (passive) |

---

## Solution Design

### Key Insight: Use `activation_hint` as the eligibility marker

Items with an `"activation_hint"` key in `ACTIVE_ITEM_DATA` require the player to press Space. These are the items the Experimental Sample should trigger. Passive items (no `activation_hint`) cannot be meaningfully triggered on-press.

### Dynamic Pool — Automatic Future-Proofing

The solution in `active_item_manager.gd` dynamically builds the eligible pool:

```gdscript
## Returns all item types eligible for Experimental Sample triggering.
## Any future item with "activation_hint" is automatically included.
func get_experimental_sample_eligible_types() -> Array[int]:
    var result: Array[int] = []
    for item_type: int in ACTIVE_ITEM_DATA.keys():
        if item_type == ActiveItemType.NONE:
            continue
        if item_type == ActiveItemType.EXPERIMENTAL_SAMPLE:
            continue
        var data: Dictionary = ACTIVE_ITEM_DATA[item_type]
        if data.has("activation_hint"):
            result.append(item_type)
    return result
```

**This means:** Adding a new active item to `ACTIVE_ITEM_DATA` with an `"activation_hint"` key will automatically make it eligible for Experimental Sample. No manual updates needed to the pool.

### What Still Needs Manual Updates

When a new activatable item is added, a `case` must be added to `_trigger_experimental_sample_effect()` in `player.gd` to define how the effect fires. If no case is added, `_trigger_experimental_sample_effect()` returns `false`, the system re-rolls (up to 20 attempts), and falls back to homing bullets — so the game never crashes, but the new item won't trigger.

This is an acceptable trade-off: the pool is automatic, but the effect implementation is explicit per-item.

---

## Files Changed

### `scripts/autoload/active_item_manager.gd`
- Added `get_experimental_sample_eligible_types()` function (line ~445)
- Dynamically builds pool from `ACTIVE_ITEM_DATA` by checking for `"activation_hint"`

### `scripts/characters/player.gd`
- Updated `_handle_experimental_sample_input()` to use the dynamic eligible types list
- Added `case 19` (FINE_MOTOR_SKILLS): triggers instant reload
- Added `case 20` (DASH): triggers dash toward aim direction
- Removed hardcoded `randi_range(1, 17)` — now uses `eligible_types[randi() % eligible_types.size()]`

### `tests/unit/test_experimental_sample.gd`
- Updated mock to include all 22 item types with correct `activation_hint` flags
- Added `get_experimental_sample_eligible_types()` to the mock
- Added tests for FINE_MOTOR_SKILLS and DASH inclusion
- Added tests for GRENADE_BAG and EXPERIMENTAL_SAMPLE exclusion

---

## Known Patterns / References

Similar "auto-discover" patterns for extensible effect systems:

1. **Godot Engine — Signal/Connection pattern**: Using a marker property in data dictionaries is a well-established Godot pattern for avoiding hardcoded switch/match statements. See: [Godot docs — Dictionary](https://docs.godotengine.org/en/stable/classes/class_dictionary.html)

2. **Data-driven game design**: The approach of using `ACTIVE_ITEM_DATA` as a single source of truth, then querying it at runtime, is a standard data-driven pattern that avoids fragile parallel arrays or hardcoded lists.

3. **Open/Closed Principle**: The implementation is "open for extension, closed for modification" — adding a new item only requires adding to `ACTIVE_ITEM_DATA` and `_trigger_experimental_sample_effect()`, not touching the pool logic.

---

## Timeline

| Date | Event |
|------|-------|
| Issue #1635 created | Owner requests Experimental Sample to include new active items |
| PR #1660 created | Fix implemented with dynamic pool + FINE_MOTOR_SKILLS + DASH cases |
| 2026-03-27 | PR marked ready, no conflicts at that time |
| 2026-03-28 | Main branch merged new changes (issue-1624 unlock conditions, drone grenade) → merge conflict in test file |
| 2026-03-28 10:02 | Owner tests old build (before fix), confirms items not added |
| 2026-03-28 | Merge conflict resolved, PR updated |
