# Case Study: Issue #1635 — Experimental Sample missing FINE_MOTOR_SKILLS and DASH effects

## Overview

**Issue:** The Experimental Sample active item does not trigger effects for FINE_MOTOR_SKILLS (type 19) or DASH (type 20), even though those items exist in the game.

**Root cause:** Two compounding bugs — a hard-coded type range that excluded new items, and incorrect equipped-flag checks that prevented execution even after the range was expanded.

---

## Evidence Files

| File | Description |
|------|-------------|
| `game_log_20260329_171906.txt` | Game session log provided by owner on 2026-03-29. Shows 139 Experimental Sample activations, none of which produced type 19 or 20. |

---

## Timeline Reconstruction

### Phase 1 — Original implementation (before fix)

The Experimental Sample was implemented using `randi_range(1, 17)` to pick a random active item type. This hard-coded range covered item types 1–17 only. At the time of implementation, FINE_MOTOR_SKILLS (19) and DASH (20) did not exist yet.

### Phase 2 — New items added (Issues #1315, #1071)

FINE_MOTOR_SKILLS (type 19) and DASH (type 20) were added as new active items. However, the `randi_range(1, 17)` in the Experimental Sample was never updated to include them. Types 18 (EXPERIMENTAL_SAMPLE itself) and 19–20 are all unreachable via the old range.

### Phase 3 — First fix attempt (PR #1729, commit 1a4eb950)

The PR replaced `randi_range(1, 17)` with a pick from `EXPERIMENTAL_SAMPLE_ELIGIBLE_TYPES`, a new constant listing all triggerable item IDs. Cases 19 and 20 were added to the match statement. However, both cases contained an incorrect conditional check:

- **Case 19** checked `if not _fine_motor_skills_equipped` — this flag is only `true` when the player has FINE_MOTOR_SKILLS as their equipped active item. When the player has EXPERIMENTAL_SAMPLE equipped, `_fine_motor_skills_equipped` is always `false`, so case 19 always returned `false` and re-rolled.
- **Case 20** checked `if not _dash_equipped` — same problem. `_dash_equipped` is only `true` if DASH is the player's actual item. When using EXPERIMENTAL_SAMPLE, the dash effect node was never created and `_dash_equipped` was never set.

This means types 19 and 20 were in the eligible list but **always re-rolled on every attempt**, never firing.

Additionally, the first fix attempt removed types 7 (FORCE_FIELD) and 16 (RECOIL_COMPENSATOR) from the eligible pool without providing working alternatives.

### Phase 4 — User tests (2026-03-29 17:19 – 17:20)

The user ran the game using a **prebuilt binary** based on the original code (before the PR was merged). The game log confirms this — the log format `"Charges remaining: X — triggering random effect for type Y"` matches code that predates our PR changes. The log shows 139 Experimental Sample activations across ~100 seconds of play, with the following type distribution:

| Type | Item | Count | Expected? |
|------|------|-------|-----------|
| 1 | FLASHLIGHT | 24 | Old code only |
| 11 | LOUDSPEAKER | 18 | Yes |
| 5 | INVISIBILITY_SUIT | 15 | Yes |
| 3 | TELEPORT_BRACERS | 14 | Old code only |
| 16 | RECOIL_COMPENSATOR | 14 | Old code only |
| 15 | DRILLING_BULLETS | 14 | Old code only |
| 7 | FORCE_FIELD | 11 | Old code only |
| 8 | TRAJECTORY_GLASSES | 10 | Yes |
| 12 | BREACHING_CHARGES | 10 | Yes |
| 2 | HOMING_BULLETS | 6 | Yes |
| 4 | BFF_PENDANT | 3 | Yes |
| **19** | **FINE_MOTOR_SKILLS** | **0** | **MISSING** |
| **20** | **DASH** | **0** | **MISSING** |

The absence of types 19 and 20 across 139 activations confirms the bug statistically (probability of missing a type with ~1/17 chance for 139 trials is astronomically small).

The user reported: **"не добавилось"** ("didn't get added").

---

## Root Cause Analysis

Two distinct bugs:

### Bug 1: Hard-coded range excluded new items

```gdscript
# OLD CODE (main branch)
var random_type: int = randi_range(1, 17)
```

Types 19 and 20 are numerically above 17 and thus unreachable.

### Bug 2: Equipped-flag guards prevent Experimental Sample triggers

```gdscript
# FIRST FIX ATTEMPT — still broken
19: # FINE_MOTOR_SKILLS
    if not _fine_motor_skills_equipped or _fine_motor_skills_active:  # <-- always fails!
        return false
    ...

20: # DASH
    if not _dash_equipped or _dash_effect == null ...:  # <-- always fails!
        return false
    ...
```

`_fine_motor_skills_equipped` is set by `_init_fine_motor_skills()`, which only runs when `ActiveItemManager.has_fine_motor_skills()` returns true — i.e., when FINE_MOTOR_SKILLS is the player's equipped item. When EXPERIMENTAL_SAMPLE is equipped instead, this flag is always `false`.

Similarly, `_dash_equipped` and `_dash_effect` are only set when DASH is the player's equipped item.

---

## Solution

The fix in the second iteration addresses all issues:

### 1. Eligible types updated

Types 7 (FORCE_FIELD) and 16 (RECOIL_COMPENSATOR) re-added to the pool (they have valid on-press effects). Types 19 (FINE_MOTOR_SKILLS) and 20 (DASH) remain in the pool.

### 2. Case 19 — works without FMS equipped

```gdscript
19: # FINE_MOTOR_SKILLS — instant reload regardless of whether FMS is equipped
    if _fine_motor_skills_active:
        return false  # already reloading, re-roll
    _fine_motor_skills_active = true
    _fine_motor_skills_activate_async()
    return true
```

The reload logic itself (`_fine_motor_skills_activate_async`) only references the player's weapon node and does not require `_fine_motor_skills_equipped`.

### 3. Case 20 — creates temporary DashEffect if needed

```gdscript
20: # DASH — create temporary dash effect if needed, then dash
    if _dash_effect == null or not is_instance_valid(_dash_effect):
        _experimental_sample_init_temp_dash()  # create temp node
    if _dash_effect != null and is_instance_valid(_dash_effect) and not _dash_effect.is_dashing():
        var dir := (get_global_mouse_position() - global_position).normalized()
        _dash_effect.activate(dir)
        return true
    return false
```

`_experimental_sample_init_temp_dash()` instantiates the `DashEffect.tscn` scene, adds it as a child node, and initializes it — the same way `_init_dash()` would, but on demand rather than at equip time.

### 4. Cases 7 and 16 added

- Case 7 (FORCE_FIELD): activates force field if equipped and not already active; schedules deactivation after 1.8s.
- Case 16 (RECOIL_COMPENSATOR): activates recoil compensation briefly (1.8s) via async timer.

---

## Files Changed

- `scripts/characters/player.gd` — updated `EXPERIMENTAL_SAMPLE_ELIGIBLE_TYPES`, fixed cases 19 and 20, added cases 7 and 16, added three helper functions
- `tests/unit/test_experimental_sample.gd` — mirrored updated `ELIGIBLE_TYPES` in mock
- `docs/case-studies/issue-1635/game_log_20260329_171906.txt` — game log submitted by owner
