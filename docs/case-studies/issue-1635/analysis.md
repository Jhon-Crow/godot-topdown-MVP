# Case Study: Issue #1635 — Experimental Sample missing FINE_MOTOR_SKILLS and DASH effects

## Overview

**Issue:** The Experimental Sample active item does not trigger effects for FINE_MOTOR_SKILLS (type 19) or DASH (type 20), even though those items exist in the game.

**Root cause:** Three compounding bugs — a hard-coded type range that excluded new items, incorrect equipped-flag checks that prevented execution even after the range was expanded, and a later C# runtime implementation that still omitted types 19 and 20 from its weighted pool.

---

## Evidence Files

| File | Description |
|------|-------------|
| `game_log_20260329_171906.txt` | Game session log provided by owner on 2026-03-29 (first log). Shows 139 Experimental Sample activations with the pre-fix main-branch binary. Types 19 and 20 never appear. |
| `game_log_20260329_180633.txt` | Game session log provided by owner on 2026-03-29 (second log, ~1 hour later). 134 Experimental Sample activations with an intermediate/alternative binary. Types 7 and 16 work (new helper code present), but types 19 and 20 still never appear. |
| `game_log_20260410_221212.txt` | Game session log provided by owner on 2026-04-10 after more fixes. Shows 216 Experimental Sample activations from the shipped C# player path. Types 19 and 20 still never appear because the C# weighted pool omits them. |

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

### Phase 6 — Third user test (2026-04-10 22:12 – 22:14)

The user ran another session after the PR changed `scripts/characters/player.gd`. The uploaded log (`game_log_20260410_221212.txt`) records 216 Experimental Sample activations. The active level scenes instantiate `res://scenes/characters/csharp/Player.tscn`, so the runtime implementation is `Scripts/Characters/Player.ActiveItems.cs`, not the GDScript player file that had received most of the previous fix.

**Key observations about this binary:**
- Runtime log messages exactly match the C# implementation, including `Charges remaining: ... — triggering random effect for type ...`.
- `Scripts/Characters/Player.ActiveItems.cs` used `int[] activeTypes = { 1, 2, 3, 4, 5, 7, 8, 11, 12, 15, 16 };`, so types 19 and 20 were structurally impossible to select.
- The C# `TriggerExperimentalSampleEffect` switch also had no `case 19` or `case 20`; even forced values would fall through to the homing fallback.

**Type frequency distribution (third log):**

| Type | Item | Count |
|------|------|-------|
| 7 | FORCE_FIELD | 36 |
| 8 | TRAJECTORY_GLASSES | 24 |
| 15 | DRILLING_BULLETS | 24 |
| 16 | RECOIL_COMPENSATOR | 24 |
| 5 | INVISIBILITY_SUIT | 23 |
| 1 | FLASHLIGHT | 21 |
| 3 | TELEPORT_BRACERS | 21 |
| 12 | BREACHING_CHARGES | 18 |
| 11 | LOUDSPEAKER | 15 |
| 2 | HOMING_BULLETS | 6 |
| 4 | BFF_PENDANT | 4 |
| **19** | **FINE_MOTOR_SKILLS** | **0** |
| **20** | **DASH** | **0** |

This changes the final root cause: previous GDScript fixes were directionally correct, but they did not affect the shipped C# player scene. The fix must update `Scripts/Characters/Player.ActiveItems.cs`.

---

## Root Cause Analysis

Three distinct bugs:

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

### Bug 3: Runtime C# implementation stayed out of sync

All playable level scenes currently instantiate `scenes/characters/csharp/Player.tscn`, which attaches `Scripts/Characters/Player.cs` and its partial `Player.ActiveItems.cs`. The C# Experimental Sample code had an independent weighted pool and switch statement. That pool stopped at type 16:

```csharp
int[] activeTypes = { 1, 2, 3, 4, 5, 7, 8, 11, 12, 15, 16 };
```

As a result, FINE_MOTOR_SKILLS (19) and DASH (20) could never be selected in the actual exported build, even though the GDScript implementation had been updated.

Official Godot documentation reviewed during this investigation:

- [Godot C# basics](https://docs.godotengine.org/en/stable/tutorials/scripting/c_sharp/c_sharp_basics.html) — C# scripts are first-class Godot scripts backed by the .NET runtime, so attached C# scene scripts must be updated directly.
- [Godot Singletons/Autoload](https://docs.godotengine.org/en/stable/tutorials/scripting/singletons_autoload.html) — autoloaded scripts are nodes in the scene tree, matching this project's `/root/ActiveItemManager` access pattern from C#.

---

## Solution

The final fix addresses all issues in the shipped C# path and keeps the GDScript-side correction in place:

### 1. Eligible types updated

Types 19 (FINE_MOTOR_SKILLS) and 20 (DASH) are added to the C# weighted pool:

```csharp
private static readonly int[] ExperimentalSampleActiveTypes =
{
    1, 2, 3, 4, 5, 7, 8, 11, 12, 15, 16, 19, 20
};
```

### 2. Case 19 — works without FMS equipped

```csharp
case 19: // FINE_MOTOR_SKILLS
    _fineMotorSkillsActive = true;
    FineMotorSkillsActivateAsync();
    return 2.0f;
```

The reload logic itself (`FineMotorSkillsActivateAsync`) only references the player's weapon and does not require `_fineMotorSkillsEquipped`.

### 3. Case 20 — creates temporary DashEffect if needed

```csharp
case 20: // DASH
    Node? dashNode = EnsureExperimentalSampleDashEffect();
    dashNode.Call("activate", dir);
    return 1.0f;
```

`EnsureExperimentalSampleDashEffect()` instantiates `DashEffect.tscn`, adds it as a child node, and initializes it without setting Dash as the equipped active item. `IsDashActive()` now checks the dash effect node directly so movement override and damage immunity work during Experimental Sample dashes.

### 4. Cases 7 and 16 added

- Case 7 (FORCE_FIELD): activates force field if equipped and not already active; schedules deactivation after 1.8s.
- Case 16 (RECOIL_COMPENSATOR): activates recoil compensation briefly (1.8s) via async timer.

---

## Files Changed

- `Scripts/Characters/Player.ActiveItems.cs` — added C# runtime pool entries and handlers for FINE_MOTOR_SKILLS (19) and DASH (20), plus temporary DashEffect creation for Experimental Sample
- `scripts/characters/player.gd` — previous GDScript-side correction kept in place
- `tests/unit/test_experimental_sample.gd` — restored broken test header and added C# runtime regression checks for types 19 and 20
- `docs/case-studies/issue-1635/game_log_20260329_171906.txt` — first game log submitted by owner (pre-fix binary, 139 activations)
- `docs/case-studies/issue-1635/game_log_20260329_180633.txt` — second game log submitted by owner (partial-fix binary, 134 activations)
- `docs/case-studies/issue-1635/game_log_20260410_221212.txt` — third game log submitted by owner (C# runtime pool omission, 216 activations)
