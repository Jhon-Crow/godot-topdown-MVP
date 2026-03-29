# Case Study: Issue #1635 — Experimental Sample missing FINE_MOTOR_SKILLS and DASH effects

## Overview

**Issue:** The Experimental Sample active item does not trigger effects for FINE_MOTOR_SKILLS (type 19) or DASH (type 20), even though those items exist in the game.

**Root cause:** Two compounding bugs — a hard-coded type range that excluded new items, and incorrect equipped-flag checks that prevented execution even after the range was expanded.

---

## Evidence Files

| File | Description |
|------|-------------|
| `game_log_20260329_171906.txt` | Game session log provided by owner on 2026-03-29 (first log). Shows 139 Experimental Sample activations with the pre-fix main-branch binary. Types 19 and 20 never appear. |
| `game_log_20260329_180633.txt` | Game session log provided by owner on 2026-03-29 (second log, ~1 hour later). 134 Experimental Sample activations with an intermediate/alternative binary. Types 7 and 16 work (new helper code present), but types 19 and 20 still never appear. |

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

The user ran the game using a **prebuilt binary from the main branch** (before the PR fix was merged). The game log (`game_log_20260329_171906.txt`) was recorded on 2026-03-29 and shows 139 Experimental Sample activations across approximately 100 seconds of play.

**Evidence that this was the pre-fix binary:**
- Types 1 (FLASHLIGHT), 3 (TELEPORT_BRACERS), and 15 (DRILLING_BULLETS) appear in the log — these are only reachable via the old `randi_range(1, 17)` range; they are intentionally excluded from the fixed `EXPERIMENTAL_SAMPLE_ELIGIBLE_TYPES`.
- No types 19 or 20 appear at all.

**Type frequency distribution:**

| Type | Item | Count | In fixed ELIGIBLE_TYPES? |
|------|------|-------|--------------------------|
| 1 | FLASHLIGHT | 24 | No (passive; excluded) |
| 11 | LOUDSPEAKER | 18 | Yes |
| 5 | INVISIBILITY_SUIT | 15 | Yes |
| 3 | TELEPORT_BRACERS | 14 | No (passive; excluded) |
| 16 | RECOIL_COMPENSATOR | 14 | Yes (re-added in fix) |
| 15 | DRILLING_BULLETS | 14 | No (passive; excluded) |
| 7 | FORCE_FIELD | 11 | Yes (re-added in fix) |
| 8 | TRAJECTORY_GLASSES | 10 | Yes |
| 12 | BREACHING_CHARGES | 10 | Yes |
| 2 | HOMING_BULLETS | 6 | Yes |
| 4 | BFF_PENDANT | 3 | Yes |
| **19** | **FINE_MOTOR_SKILLS** | **0** | **Yes — was missing** |
| **20** | **DASH** | **0** | **Yes — was missing** |

The absence of types 19 and 20 across 139 activations confirms the bug statistically. With `randi_range(1, 17)` the probability of both types being absent from 139 trials is essentially zero — the types were structurally unreachable in the old code.

The user uploaded this log on 2026-03-29 commenting **"не добавилось"** ("didn't get added"), requesting the log be preserved in this case study folder.

### Phase 5 — Second user test (2026-03-29 18:06 – 18:10)

The user ran a second game session (~1 hour after Phase 4) using a **different binary** that has partial experimental sample fixes implemented. The log (`game_log_20260329_180633.txt`) records 134 Experimental Sample activations.

**Key observations about this binary:**
- Types 7 (FORCE_FIELD), 16 (RECOIL_COMPENSATOR) are now handled with "temporary node created" messages — indicates the helper-function approach from the fix is present
- Types 1 (FLASHLIGHT), 3 (TELEPORT_BRACERS), 12 (BREACHING_CHARGES), 15 (DRILLING_BULLETS) also produce "temporary node created" messages — a broader set of items is handled
- Types 19 and 20 still do not appear at all across all 134 activations — confirming the FINE_MOTOR_SKILLS and DASH bugs persist

**Type frequency distribution (second log):**

| Type | Item | Count | Notes |
|------|------|-------|-------|
| 1 | FLASHLIGHT | 18 | "temporary node created" message visible |
| 11 | LOUDSPEAKER | 17 | |
| 15 | DRILLING_BULLETS | 16 | "drilling bullets applied" message |
| 12 | BREACHING_CHARGES | 15 | "temporary node created" message visible |
| 7 | FORCE_FIELD | 14 | "temporary node created" — helper code present |
| 3 | TELEPORT_BRACERS | 13 | "aiming for 1,8s" message |
| 8 | TRAJECTORY_GLASSES | 12 | "temporary effect node created" |
| 5 | INVISIBILITY_SUIT | 12 | |
| 16 | RECOIL_COMPENSATOR | 9 | "activated for 1,8s" |
| 2 | HOMING_BULLETS | 5 | |
| 4 | BFF_PENDANT | 3 | |
| **19** | **FINE_MOTOR_SKILLS** | **0** | **Still absent — bug confirmed again** |
| **20** | **DASH** | **0** | **Still absent — bug confirmed again** |

The second log reinforces the root cause analysis: even with partial fixes that enable types 7 and 16 to fire, the code path for types 19 and 20 still fails. This is consistent with Bug 2 (equipped-flag guards) being the primary remaining blocker.

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
- `docs/case-studies/issue-1635/game_log_20260329_171906.txt` — first game log submitted by owner (pre-fix binary, 139 activations)
- `docs/case-studies/issue-1635/game_log_20260329_180633.txt` — second game log submitted by owner (partial-fix binary, 134 activations)
