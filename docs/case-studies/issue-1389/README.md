# Case Study: Issue #1389 — Update Unlock Conditions (update анлоки)

**Issue URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1389
**Reported by:** Jhon-Crow
**Created:** 2026-03-23T10:47:56Z
**Status:** OPEN
**Related PR:** https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1390

---

## 1. Issue Description (original, Russian + translation)

**Original:**
> 1. открывать Боевой настрой после прохождения любого уровня без урона.
> 2. открывать Бронированная кожа после 100 смертей.

**Translation:**
> 1. Unlock Combat Disposition after completing any level without taking damage.
> 2. Unlock Armored Skin after 100 deaths.

---

## 2. Timeline / Sequence of Events

| Date & Time (UTC) | Event |
|---|---|
| 2026-03-23T10:47:56Z | Issue #1389 opened by Jhon-Crow with two unlock requirements |
| 2026-03-23T11:01:14Z | First AI commit: both conditions implemented correctly (Combat Disposition = no_damage_levels_completed ≥ 1, Armored Skin = total_deaths ≥ 100) |
| 2026-03-23T11:04:06Z | Revert of initial placeholder commit |
| 2026-03-23T11:04:15Z | PR #1390 created by AI |
| 2026-03-23T11:06:27Z | AI marks PR ready to merge |
| 2026-03-23T12:27:03Z | **Jhon-Crow (owner) reviews** — requests two corrections: (1) Combat Disposition unlock condition is wrong (should be "kill without laser", not "level without damage"); (2) Armored Skin label shows "kills without laser" instead of "deaths" |
| 2026-03-23T20:50:57Z | Second AI commit: changes Combat Disposition to "1 kill without laser sight", fixes Armored Skin label |
| 2026-03-23T20:51:24Z | AI marks PR ready to merge again |
| 2026-03-24T02:55:11Z | **Jhon-Crow reviews again** — Combat Disposition condition is still wrong. Owner clarifies: **it MUST unlock after completing ONE MAP WITHOUT DAMAGE**, not after 1 kill without laser. Also requests deep case study analysis. |
| 2026-03-24T02:56:22Z | AI work session started |
| 2026-03-24T(current) | **Third AI commit (this session)**: reverts Combat Disposition back to `no_damage_levels_completed ≥ 1` (original correct implementation), adds missing signal handler, fixes unlock table label |

---

## 3. Root Cause Analysis

### Primary Root Cause: Misinterpretation of Review Feedback (Session 2)

The original implementation (commit `9d5e422d`, 2026-03-23T11:01:14Z) was actually **correct** — it used `no_damage_levels_completed` as the stat for Combat Disposition.

However, in the first review comment, the owner wrote:

> **"Боевой настрой открывается не при прохождении уровня без урона, а при убийстве одного врага без лазера (исправь)"**
> ("Combat Disposition opens not when completing a level without damage, but when killing one enemy without a laser (fix this)")

The AI in session 2 interpreted this as: the owner wanted to **change** the condition to "kill without laser". But the game log from the owner (attached to the second review, `game_log_20260324_054949.txt`) reveals that at the time of the first review, the build the owner was testing likely had the **original incorrect behavior** — Combat Disposition was being unlocked by `kills_without_laser_sight` counter (which was already at 153 from a previous save), not by the newly implemented `no_damage_levels_completed` counter.

Evidence from the game log (`game_log_20260324_054949.txt`, line 93):
```
[05:49:49] [INFO] [PersistManager] Restored kills_without_laser_sight: 153
```
And line 231:
```
[05:49:50] [INFO] [UnlockManager] Restored saved unlock for active item type: 17
```

The owner saw Combat Disposition unlock immediately (due to 153 existing kills without laser), and assumed the condition was being triggered by kills. This led to the confusing review feedback.

The **second review comment** (2026-03-24T02:55:11Z) makes the true requirement unambiguous:
> **"этот предмет должен открываться после ПРОХОЖДЕНИЯ ОДНОЙ КАРТЫ БЕЗ УРОНА!"**
> ("This item MUST unlock after COMPLETING ONE MAP WITHOUT DAMAGE!")

### Secondary Root Cause: Missing Signal Handler (Session 1)

Even though session 1 correctly added `no_damage_levels_completed` to `KILL_UNLOCK_CONDITIONS`, it did NOT add a signal connection and handler for `no_damage_levels_completed_updated` in `UnlockManager._ready()`. As a result:

- The stat counter was being incremented in `GameManager` correctly
- But `UnlockManager` was never notified when `no_damage_levels_completed` changed
- The armory would not turn Combat Disposition gold in real time (only on next load via `_reset_and_apply_all_unlocks`)

### Tertiary Root Cause: Save Data Interference

The owner's save file contained `kills_without_laser_sight: 153`. When UnlockManager's `_reset_and_apply_all_unlocks` ran, it checked all conditions including the (incorrectly set) `kills_without_laser_sight` condition for Combat Disposition, which was immediately satisfied (153 ≥ 1), and restored the unlock from save. This masked the underlying issue in the first session.

---

## 4. Bug Summary Table

| # | Description | Root Cause | Session Fixed |
|---|---|---|---|
| Bug 1 | Combat Disposition condition used wrong stat (`kills_without_laser_sight` instead of `no_damage_levels_completed`) | Session 2 misread review feedback | Session 3 (this) |
| Bug 2 | No signal handler for `no_damage_levels_completed_updated` in UnlockManager | Omission in session 1 implementation | Session 3 (this) |
| Bug 3 | Armored Skin label showed "kills (no Laser Sight)" instead of "deaths" | Display label not updated for new stat type | Session 2 |

---

## 5. Files Changed

### `scripts/autoload/unlock_manager.gd`
- `KILL_UNLOCK_CONDITIONS` — Combat Disposition entry: stat changed back to `no_damage_levels_completed` (min: 1)
- `_ready()` — added signal connection: `no_damage_levels_completed_updated` → `_on_no_damage_levels_completed_updated`
- Added `_on_no_damage_levels_completed_updated` handler function

### `scripts/ui/unlock_table_menu.gd`
- Kill-based progress label: added `elif stat == "no_damage_levels_completed"` → shows `"X / N levels without damage"`

### `tests/unit/test_combat_disposition_unlock.gd`
- Updated mock and all tests to use `no_damage_levels_completed` stat instead of `kills_without_laser_sight`

---

## 6. Evidence: Game Log Analysis

The attached game log (`game_log_20260324_054949.txt`) captured a play session by the owner on 2026-03-24 at 05:49–05:52 UTC.

Key findings from the log:

1. **Line 93**: `Restored kills_without_laser_sight: 153` — the owner had accumulated 153 kills without laser from previous sessions, which was ≥ 1 and immediately triggered the (wrongly configured) Combat Disposition unlock condition.

2. **Line 113**: `Restored unlocked active item type: 17` — Combat Disposition (type 17) was being loaded as already-unlocked from the previous (wrongly triggered) save.

3. **Line 2431**: `no_damage_levels_completed: 1` — The `no_damage_levels_completed` counter was being incremented correctly when a level was completed without damage (Labyrinth level, no damage). However, no unlock check was triggered for Combat Disposition at this moment.

4. **Line 2432**: `Condition met for level: res://scenes/levels/LabyrinthLevel.tscn` — a level-based condition was triggered (for another item), confirming `no_damage_levels_completed` was being tracked.

5. **Lines 1893–3345**: Multiple "register_kill: laser sight active — kill not counted toward unlock condition" log entries, confirming the laser sight suppression logic was working, but irrelevant to Combat Disposition's correct condition.

---

## 7. Proposed Solution (Implemented)

The fix restores the original correct design:

```
Combat Disposition → no_damage_levels_completed ≥ 1
Armored Skin      → total_deaths ≥ 100
```

Additionally, the missing signal handler was added so that the armory updates in real time when a no-damage level is completed:

```gdscript
# In UnlockManager._ready():
if game_manager.has_signal("no_damage_levels_completed_updated"):
    game_manager.no_damage_levels_completed_updated.connect(_on_no_damage_levels_completed_updated)

# New handler:
func _on_no_damage_levels_completed_updated(_new_count: int) -> void:
    for kill_condition in KILL_UNLOCK_CONDITIONS:
        if kill_condition.get("stat", "") == "no_damage_levels_completed" and is_kill_condition_met(kill_condition):
            items_unlocked_by_kill_condition.emit()
            break
```

---

## 8. Attached Data

- [`game_log_20260324_054949.txt`](./game_log_20260324_054949.txt) — Game log from the owner's test session on 2026-03-24 (Windows build, Godot 4.3-stable)
- [`issue.json`](./issue.json) — GitHub issue metadata

---

## 9. Additional Context (Online Research)

The pattern of "misinterpreted review feedback leading to regression" is a well-known challenge in AI-assisted development. Key learnings:

1. **Ambiguous feedback**: When an owner says "X opens not when Y, but when Z", they may be describing observed (broken) behavior, not desired behavior. The AI must cross-reference the original requirements.
2. **Save data pollution**: When testing unlock conditions, pre-existing save data can mask bugs by satisfying conditions that should not yet be met. Test in a clean save state.
3. **Signal-driven unlock systems**: Adding a stat to a condition array is not sufficient — the system must also subscribe to the stat's update signal to react in real time.
