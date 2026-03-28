# Case Study: Issue #1635 — Experimental Sample Auto-Include Future Active Items

## Overview

**Issue:** [#1635](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1635) — Update Experimental Sample (Экспериментальный образец)

**Request (translated):** Make the Experimental Sample item trigger effects from newly added active items, and ideally make it automatically include any future items that are added.

**Pull Request:** [#1660](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1660)

---

## Event Timeline

| Date/Time | Event |
|-----------|-------|
| Issue #1635 created | Owner requests Experimental Sample to include new active items |
| PR #1660 created | Fix implemented with dynamic pool + FINE_MOTOR_SKILLS + DASH cases |
| 2026-03-27 20:07 | PR logged as complete, no merge conflicts at that point |
| 2026-03-28 07:06 | Owner reports "не добавилось" — uploads `game_log_20260328_100220.txt` |
| 2026-03-28 07:11 | AI work session started; merge conflict with main resolved |
| 2026-03-28 07:12 | PR updated with merge conflict fix + case study added |
| 2026-03-28 07:25 | Owner reports "не добавились" again — uploads `game_log_20260328_102225.txt` |
| 2026-03-28 16:42 | AI work session started; deep root cause analysis + code fixes |

---

## Root Cause Analysis

### Original Bug

The Experimental Sample used a hardcoded `randi_range(1, 17)` to pick a random effect type. The enum `ActiveItemType` had been extended with new items, but the range was never updated:

```gdscript
# OLD buggy code in player.gd (before any fixes)
var random_type: int = randi_range(1, 17)  # Hardcoded — misses types 18, 19, 20...
```

When **FINE_MOTOR_SKILLS** (type 19) and **DASH** (type 20) were added, the `17` was never bumped.

### Log Analysis — First Report (game_log_20260328_100220.txt, 10:02)

- Log format: `Charges remaining: X — triggering random effect for type Y`
- Types triggered: 3, 5, 7, 8, 11, 12, 15, 16 — all in range 1–17
- FINE_MOTOR_SKILLS (19) and DASH (20) **never** triggered
- This log was from a build using `randi_range(1, 17)` — the original code

### Log Analysis — Second Report (game_log_20260328_102225.txt, 10:22)

- Log format: still `Charges remaining: X — triggering random effect for type Y` (old log format)
- This confirms the game is **still running an older binary** despite PR #1660 being prepared
- Types triggered: 1, 2, 3, 4, 5, 7, 8, 11, 12, 15, 16 — still only up to type 16
- Notable: types 15 (DRILLING_BULLETS) and 16 (RECOIL_COMPENSATOR) work in this build with specific effects ("Drilling bullets effect: 30 drilling bullets applied", "Recoil compensator activated for 1,8s")
- FINE_MOTOR_SKILLS (19) and DASH (20) still **never** triggered
- **This is an intermediate build** — it handles types 15 and 16 but still doesn't include types 19 and 20

The second log is NOT from our PR. Our PR's code would log `"[Player.ExperimentalSample] Charges: %d — type %d attempt %d"` (with attempt number). The second log still uses the old format without attempt number.

### Why Type 19 and 20 Are Missing From the Second Build

The intermediate build in the second log uses a list like `[1..17]` or a fixed set that was manually extended to include types 15 and 16. Types 19 and 20 were simply not in that list.

Our PR (#1660) introduces the **dynamic pool** approach which automatically picks up types 19, 20 (and any future items with `activation_hint`).

---

## Issue with Our Initial PR Implementation

After comparing our code with the intermediate build behavior, we identified two additional problems:

### Problem 1: Case 20 (DASH) Required Pre-Equipped Item

Our initial case 20 checked `_dash_effect != null` — but `_dash_effect` is only initialized when Dash is equipped. If the player has Experimental Sample equipped (not Dash), `_dash_effect` would be null and case 20 always returned false.

**Fix:** Case 20 now calls `_experimental_sample_init_temp_dash()` to create a temporary `DashEffect` node if not already present.

### Problem 2: Type 16 (RECOIL_COMPENSATOR) Was Blacklisted

Type 16 was in the re-roll blacklist despite having `activation_hint`. The intermediate build shows Recoil Compensator working ("Recoil compensator activated for 1.8s").

**Fix:** Type 16 removed from blacklist. Added case 16 that activates `_recoil_compensator_active` for 1.8s via async timer.

### Problem 3: Type 7 (FORCE_FIELD) Was Blacklisted

Similarly, FORCE_FIELD (7) was in the original blacklist. The intermediate build shows it working ("Force field activated for 1,8s").

**Fix:** Type 7 removed from blacklist. Added case 7 that calls `_force_field.activate()` for a brief 1.8s window via async timer.

---

## All Active Items — Experimental Sample Classification

| Type | Name | Has activation_hint | Experimental Sample behavior |
|------|------|---------------------|------------------------------|
| 0  | None | No | Excluded explicitly |
| 1  | Flashlight | Yes | Re-roll (hold-type, no instant effect) |
| 2  | Homing Bullets | No | **Triggered** — activates homing for 1.2s |
| 3  | Teleport Bracers | Yes | Re-roll (hold-to-aim, C# boundary check needed) |
| 4  | BFF Pendant | Yes | **Triggered** — summons companion |
| 5  | Invisibility Suit | Yes | **Triggered** — activates if equipped |
| 6  | Breaker Bullets | No | Re-roll (passive) |
| 7  | Force Field | Yes | **Triggered** — brief 1.8s activation |
| 8  | Trajectory Glasses | Yes | **Triggered** — activates if equipped |
| 9  | Laser Sight | No | Re-roll (passive) |
| 10 | Extended Magazine | No | Re-roll (passive) |
| 11 | Loudspeaker | Yes | **Triggered** — applies effect if equipped |
| 12 | Breaching Charges | Yes | **Triggered** — detonates existing charges |
| 13 | Armored Skin | No | Re-roll (passive) |
| 14 | Auto-Reload | No | Re-roll (passive) |
| 15 | Drilling Bullets | Yes | Re-roll (no GDScript implementation yet) |
| 16 | Recoil Compensator | Yes | **Triggered** — brief 1.8s activation (Issue #1635) |
| 17 | Combat Disposition | No | Re-roll (passive) |
| 18 | Experimental Sample | Yes | Excluded explicitly (prevents self-triggering) |
| 19 | Fine Motor Skills | Yes | **Triggered** — instant reload (Issue #1635) |
| 20 | Dash | Yes | **Triggered** — dash toward cursor (Issue #1635) |
| 21 | Grenade Bag | No | Re-roll (passive) |

---

## Solution Design

### Key Insight: `activation_hint` as Eligibility Marker

Items with an `"activation_hint"` key in `ACTIVE_ITEM_DATA` have on-press Space effects. These are the items the Experimental Sample should attempt to trigger. Passive items (no `activation_hint`) cannot be meaningfully triggered on-press.

### Dynamic Pool — Automatic Future-Proofing

`active_item_manager.gd` dynamically builds the eligible pool:

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

**This means:** Adding a new active item to `ACTIVE_ITEM_DATA` with an `"activation_hint"` key will automatically make it eligible for Experimental Sample.

### What Still Requires Manual Work

When a new activatable item is added, a `case` must be added to `_trigger_experimental_sample_effect()` in `player.gd`. If no case exists, the system re-rolls (up to 20 attempts) and falls back to homing bullets — no crash, but the new item won't trigger.

Types 1 (FLASHLIGHT), 3 (TELEPORT_BRACERS), and 15 (DRILLING_BULLETS) are in the pool (have `activation_hint`) but are in the re-roll blacklist because their effect cannot be instantaneously triggered without additional infrastructure. They waste 1 re-roll attempt when picked.

---

## Files Changed

### `scripts/autoload/active_item_manager.gd`
- Added `get_experimental_sample_eligible_types()` — dynamic pool from `ACTIVE_ITEM_DATA`

### `scripts/characters/player.gd`
- Replaced `randi_range(1, 17)` with dynamic eligible types list
- Removed types 7 and 16 from re-roll blacklist
- Added case 7 (FORCE_FIELD): brief 1.8s activation via timer
- Added case 16 (RECOIL_COMPENSATOR): brief 1.8s activation via timer
- Added case 19 (FINE_MOTOR_SKILLS): instant reload via `_fine_motor_skills_activate_async()`
- Added case 20 (DASH): creates temp `DashEffect` node if needed, then dashes
- Added helper functions: `_experimental_sample_activate_recoil_compensator_briefly()`, `_experimental_sample_activate_force_field_briefly()`, `_experimental_sample_init_temp_dash()`

### `tests/unit/test_experimental_sample.gd`
- Updated mock to include all 22 item types
- Added `get_experimental_sample_eligible_types()` to mock
- Added tests for FINE_MOTOR_SKILLS and DASH inclusion
- Added tests for GRENADE_BAG and EXPERIMENTAL_SAMPLE exclusion

---

## Known Patterns / References

1. **Data-driven game design**: Using `ACTIVE_ITEM_DATA` as single source of truth, queried at runtime — avoids fragile hardcoded lists.

2. **Open/Closed Principle**: Pool is open for extension (add item to `ACTIVE_ITEM_DATA` with `activation_hint`), closed for modification (no need to change pool logic).

3. **Godot async timer pattern**: `await get_tree().create_timer(duration).timeout` — standard Godot approach for time-limited effects without dedicated FSM states.

---

## Logs

- [`game_log_20260328_100220.txt`](game_log_20260328_100220.txt) — First owner report (build before fix, types 1–17 only)
- [`game_log_20260328_102225.txt`](game_log_20260328_102225.txt) — Second owner report (intermediate build, types 1–16, types 19–20 still missing)
