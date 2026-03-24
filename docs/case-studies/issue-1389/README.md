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
| 2026-03-24T03:01:49Z | Third AI commit: reverts Combat Disposition back to `no_damage_levels_completed ≥ 1`, adds missing signal handler, fixes unlock table label |
| 2026-03-24T03:52:05Z | **Jhon-Crow reviews again** — Combat Disposition still unlocks even when player takes damage. Owner says to use a damage-taken flag, not HP-based logic. Provides `game_log_20260324_064838.txt` |
| 2026-03-24T03:52:57Z | AI work session started (session 4) |
| 2026-03-24T(current) | **Fourth AI commit (this session)**: fixes root cause — C# Player.TakeDamage() was not calling ScoreManager.register_damage_taken(), so `_damage_taken` was always 0 at level completion |

---

## 3. Root Cause Analysis

### Primary Root Cause (Session 4): C# Player never registers damage with ScoreManager

The **actual** root cause of the persistent "unlocks even with damage" bug is in `Scripts/Characters/Player.cs`. The C# `TakeDamage()` method handles damage correctly (health reduction, effects, sounds), but **never calls `ScoreManager.register_damage_taken()`**.

The GDScript version of the player (`scripts/characters/player.gd`, lines 1107-1109) correctly calls:
```gdscript
var score_manager: Node = get_node_or_null("/root/ScoreManager")
if score_manager and score_manager.has_method("register_damage_taken"):
    score_manager.register_damage_taken(1)
```

But the C# version — which is the **active player in the running game** (evidenced by "C# Damaged" signals in game logs) — has no equivalent call.

**Consequence**: `ScoreManager._damage_taken` stays at 0 for the entire level. When `complete_level()` is called, the score data always contains `"damage_taken": 0`. `GameManager._on_score_calculated()` then always increments `no_damage_levels_completed`, even if the player took multiple hits.

**Evidence from `game_log_20260324_064838.txt`**:
- Lines 678-687: Player takes 3 hits (health drops 9→8→7) — `PenultimateHit` and `LastChance` both log the C# `Damaged` signal
- **No `[ScoreManager] Damage taken:` log entries appear** — confirming `register_damage_taken()` was never called
- Line 1794: `"No-damage level condition met"` — incorrectly triggered despite player taking damage
- Line 1797: `"Level completed! Final score: 10374, Rank: B"` — damage penalty is 0 (despite 3 hits)

### Secondary Root Cause (Session 2): Misinterpretation of Review Feedback

The original implementation (commit `9d5e422d`) was correct in using `no_damage_levels_completed` as the stat. Session 2 misread the owner's feedback (which was describing observed broken behavior, not desired behavior) and changed it to `kills_without_laser_sight`.

### Tertiary Root Cause (Session 1): Missing Signal Handler

Session 1 omitted the `no_damage_levels_completed_updated` signal connection in UnlockManager, preventing real-time armory updates.

### Quaternary Root Cause: Save Data Interference

The owner's save file contained `kills_without_laser_sight: 153`, which masked bugs in early sessions.

---

## 4. Bug Summary Table

| # | Description | Root Cause | Session Fixed |
|---|---|---|---|
| Bug 1 | C# Player.TakeDamage() never calls ScoreManager.register_damage_taken() — damage_taken always 0 | Missing cross-language bridge between C# damage system and GDScript ScoreManager | Session 4 (this) |
| Bug 2 | Combat Disposition condition used wrong stat (`kills_without_laser_sight` instead of `no_damage_levels_completed`) | Session 2 misread review feedback | Session 3 |
| Bug 3 | No signal handler for `no_damage_levels_completed_updated` in UnlockManager | Omission in session 1 implementation | Session 3 |
| Bug 4 | Armored Skin label showed "kills (no Laser Sight)" instead of "deaths" | Display label not updated for new stat type | Session 2 |

---

## 5. Files Changed

### `Scripts/Characters/Player.cs` (Session 4 — key fix)
- `TakeDamage()` — added call to `ScoreManager.register_damage_taken(1)` after all early-return guards (invincibility, force field, armored skin immunity), right before `base.TakeDamage(amount)`. This ensures the GDScript ScoreManager tracks actual damage taken during a level, enabling correct no-damage level detection.

### `scripts/autoload/active_item_manager.gd` (Session 4)
- Resolved merge conflict with main (added `DASH` entry)
- Fixed Combat Disposition comment to say "complete 1 level without taking damage"

### `scripts/autoload/unlock_manager.gd` (Session 3)
- `KILL_UNLOCK_CONDITIONS` — Combat Disposition entry: stat changed back to `no_damage_levels_completed` (min: 1)
- `_ready()` — added signal connection: `no_damage_levels_completed_updated` → `_on_no_damage_levels_completed_updated`
- Added `_on_no_damage_levels_completed_updated` handler function

### `scripts/ui/unlock_table_menu.gd` (Session 3)
- Kill-based progress label: added `elif stat == "no_damage_levels_completed"` → shows `"X / N levels without damage"`

### `tests/unit/test_combat_disposition_unlock.gd` (Session 3)
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

- [`game_log_20260324_054949.txt`](./game_log_20260324_054949.txt) — Game log from the owner's test session on 2026-03-24 05:49 (Windows build, Godot 4.3-stable)
- [`game_log_20260324_064838.txt`](./game_log_20260324_064838.txt) — Game log from the owner's test session on 2026-03-24 06:48 — proves damage is detected by C# Damaged signal but never reaches ScoreManager
- [`issue.json`](./issue.json) — GitHub issue metadata

---

## 9. Additional Context (Online Research)

Key learnings from this multi-session debugging process:

1. **Cross-language bridges**: In mixed GDScript/C# Godot projects, when one language system (C# Player) performs an action (taking damage), it must explicitly notify systems in the other language (GDScript ScoreManager). The GDScript Player had this bridge; the C# Player did not. Always check both language implementations.
2. **Read the game logs carefully**: The absence of expected log lines (`[ScoreManager] Damage taken:`) was the key evidence. The bug was not in the condition logic or signal handling — it was in the damage registration path.
3. **Ambiguous feedback**: When an owner says "X opens not when Y, but when Z", they may be describing observed broken behavior, not desired behavior. Cross-reference the original requirements.
4. **Save data pollution**: Pre-existing save data can mask bugs by satisfying conditions that should not yet be met.
5. **Signal-driven unlock systems**: Adding a stat to a condition array is not sufficient — the system must also subscribe to the stat's update signal.
