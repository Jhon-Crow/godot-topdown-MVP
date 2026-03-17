# Case Study: Issue #1073 — Recoil Compensator Active Item

## Issue Summary

**Title:** добавить активный предмет компенсатор отдачи
**Reporter:** Jhon-Crow (owner)
**URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1073

### Requirements
- 15-second charge, depletes at 1 s/s while Space is held
- Unlimited activations while charge lasts
- When active: eliminates weapon spread (random) and screen-shake recoil completely
- Fire rate +10% boost while active
- Progress bar shows remaining charge above player when active

---

## Timeline / Sequence of Events

### 2026-03-16 — Initial Implementation (PR #1074)

The Recoil Compensator was implemented as `ActiveItemType` enum index **10** (directly after `LASER_SIGHT`). At this point the main branch had 10 items (indices 0–9).

**Files changed:**
- `scripts/autoload/active_item_manager.gd` — added enum value, data, `has_recoil_compensator()`
- `scripts/characters/player.gd` — `_init_recoil_compensator()`, `_handle_recoil_compensator_input()`, spread/shake suppression, fire rate boost
- `tests/unit/test_recoil_compensator.gd` — 60 unit tests
- `tests/unit/test_active_item_manager.gd` — updated mock

CI passed. PR marked "Ready to merge."

### 2026-03-16 to 2026-03-17 — Main branch diverges

Between the PR branch creation and the owner's test, **4 new active items** were merged into main:

| Type Index | Item | Issue |
|---|---|---|
| 10 | LOUDSPEAKER | #959 |
| 11 | BREACHING_CHARGES | #1043 |
| 12 | ARMORED_SKIN | #1045 |
| 13 | AUTO_RELOAD | #1067 |

The branch was **not rebased or merged** with these additions.

### 2026-03-17 21:42 — Owner tests the PR build

The owner ran a game export that included the `active_item_manager.gd` changes (RECOIL_COMPENSATOR as type 10) but also had saved state from a newer build.

**Evidence from `game_log_20260317_214250.txt`:**

```
[21:42:50] [INFO] [PersistManager] Restored unlocked active item type: 10
[21:42:50] [INFO] [ActiveItemManager] Invalid active item type: 14
[21:42:50] [INFO] [PersistManager] Restored selected active item type: 14
```

The user's saved game had selected active item **type 14** (which would be RECOIL_COMPENSATOR in the fully-merged state), but the build only knew types 0–10, making type 14 invalid. The game loaded with `None` selected instead.

### Root Cause #1: Enum Index Conflict

The PR added RECOIL_COMPENSATOR at index 10, but main added 4 other items first. The correct index should be **14** (after AUTO_RELOAD). The branch was never rebased onto main.

### 2026-03-17 — Player init missing RecoilCompensator log

After the user selected Recoil Compensator from the Armory and the level restarted:

```
[21:43:02] [INFO] [Player.Flashlight] No flashlight selected in ActiveItemManager
[21:43:02] [INFO] [Player.TeleportBracers] No teleport bracers selected in ActiveItemManager
...
[21:43:02] [INFO] [Player.TrajectoryGlasses] No trajectory glasses selected in ActiveItemManager
[21:43:02] [INFO] [Player] Ready! ...
```

**No `[Player.RecoilCompensator]` log appeared.** This means the `player.gd` changes were not present in the exported build, OR the restarted level picked up a stale active item state. Since the `active_item_manager.gd` changes ARE present (the item appears in the Armory), the likely cause is an **outdated game export** that includes only partial changes.

### Root Cause #2: Missing Icon

Screenshot `screenshot_armory_missing_icon.png` shows the Recoil Compensator with a **question mark** instead of an icon. The referenced asset `res://assets/sprites/weapons/recoil_compensator_icon.png` does not exist in the repository.

---

## Root Causes

1. **Wrong enum index**: RECOIL_COMPENSATOR was added as index 10 on a branch that diverged from main before 4 other items (LOUDSPEAKER=10, BREACHING_CHARGES=11, ARMORED_SKIN=12, AUTO_RELOAD=13) were merged. The correct index is **14**.

2. **Missing icon asset**: `recoil_compensator_icon.png` was never created, causing a question mark in the Armory UI.

3. **Branch not merged with main**: The PR branch was behind `origin/main` by many commits, causing merge conflicts and enum misalignment. The `player.gd` changes may not be present in the version the user tested.

---

## Proposed Solution

1. Merge `origin/main` into the branch and resolve all conflicts.
2. Move `RECOIL_COMPENSATOR` to after `AUTO_RELOAD` (index 14) in the enum.
3. Create `recoil_compensator_icon.png` programmatically.
4. Update all tests to use the new index.
5. Verify all init/handle/suppress calls are in `player.gd` after merge.

---

## Artifacts

- `game_log_20260317_214250.txt` — owner's game session log showing the bugs
- `screenshot_armory_missing_icon.png` — screenshot showing missing icon in Armory
