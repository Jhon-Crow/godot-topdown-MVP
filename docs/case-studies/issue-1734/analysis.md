# Case Study: Issue #1734 — Difficulty Selection Not Shown After Save Clear

## Overview

**Issue:** When the player uses "clear all saves" and restarts the game, the difficulty selection screen does not appear, even though it should (since the game is back to a "first launch" state).

**Reporter:** Jhon-Crow
**Date observed:** 2026-03-29
**Branch:** `issue-1734-824e6ede1bfc`
**PR:** #1735

---

## Log Files

Actual game logs provided by the reporter after testing a locally-built binary:

| File | Timestamp | Context |
|------|-----------|---------|
| `logs/game_log_20260329_175348.txt` | 17:53:48 | Session **before** clearing saves — player has progress (4 entries), Power Fantasy difficulty |
| `logs/game_log_20260329_175414.txt` | 17:54:14 | Session **after** clearing saves — 0 progress entries, but difficulty still Power Fantasy, no first-launch screen shown |

**Note:** Both logs show `build_info.cfg not found`, meaning the reporter was testing a **locally built binary** that predates the PR fixes. The fix commits (`3698ad1f`, `2c0b14fe`) were pushed to the PR branch after these logs were captured.

---

## Timeline of Events

### Session 1 (17:53:48) — game_log_20260329_175348.txt

```
[17:53:48] [DifficultyManager] Loaded difficulty: Power Fantasy (value: 3)
[17:53:48] [ProgressManager] ProgressManager ready, loaded 4 entries
[17:53:48] [PersistManager] Navigating to last played level: res://scenes/levels/BeachLevel.tscn
...
[17:53:55] [PersistManager] All saves cleared — game reset to first-launch state
[17:53:57] [GameManager] restart_scene() — starting scene reload
[17:53:58] [PersistManager] State saved to user://game_state.cfg        ← auto-save re-creates file!
[17:53:58] [PersistManager] Auto-saved current level on scene change: res://scenes/levels/BeachLevel.tscn
...
[17:54:04] [PersistManager] All saves cleared — game reset to first-launch state  ← second clear attempt
```

- Player has existing progress (4 entries)
- Difficulty is Power Fantasy (value 3) — saved in `difficulty_settings.cfg`
- Player triggered "clear all saves" at 17:53:55 (and again at 17:54:04)
- `game_state.cfg` was deleted, then **immediately re-created** 3 seconds later by the auto-save on scene change
- `difficulty_settings.cfg` was **never deleted** in the old binary (pre-fix)

### Session 2 (17:54:14) — game_log_20260329_175414.txt

```
[17:54:14] [DifficultyManager] Loaded difficulty: Power Fantasy (value: 3)
[17:54:14] [ProgressManager] ProgressManager ready, loaded 0 entries
[17:54:14] [PersistManager] Loading saved state from user://game_state.cfg
[17:54:14] [PersistManager] Already at last played level: res://scenes/levels/LabyrinthLevel.tscn
```

- Progress is 0 entries — cleared ✓
- Difficulty is **still Power Fantasy** — `difficulty_settings.cfg` survived ✗
- `game_state.cfg` exists (re-created by auto-save in session 1)
- No difficulty selection screen appeared — because `is_first_launch()` returned `false`

---

## Root Cause Analysis

### Primary Bug: `clear_all_saves()` does not delete `difficulty_settings.cfg` (pre-fix)

**File:** `scripts/autoload/persist_manager.gd`, function `clear_all_saves()` (line ~495)

The old binary's function correctly deleted `game_state.cfg`:
```gdscript
if FileAccess.file_exists(SAVE_PATH):
    DirAccess.remove_absolute(SAVE_PATH)
```

But never touched `difficulty_settings.cfg` (owned by `DifficultyManager`).

### Secondary Observation: `game_state.cfg` is immediately re-created after clear

After `clear_all_saves()` triggers `restart_scene()`, the scene changes and `_on_scene_tree_changed()` fires in `PersistManager`, which auto-saves the current (reset) state. This creates a new `game_state.cfg` with clean default values. This is **intentional behavior** — `is_first_launch()` does not check `game_state.cfg`, only `difficulty_settings.cfg`.

### Effect: `is_first_launch()` returns `false` after save clear

**File:** `scripts/autoload/difficulty_manager.gd`, function `is_first_launch()` (line ~336)

```gdscript
func is_first_launch() -> bool:
    return not FileAccess.file_exists(SETTINGS_PATH)
    # SETTINGS_PATH = "user://difficulty_settings.cfg"
```

Since `difficulty_settings.cfg` was not removed, `is_first_launch()` returned `false`, and `main.gd` never called `_show_first_launch_difficulty_menu()`.

### Sequence of Events (pre-fix)

```
User: "Clear All Saves"
  → persist_manager.clear_all_saves()
      → deletes user://game_state.cfg ✓
      → does NOT delete user://difficulty_settings.cfg ✗
  → restart_scene()
  → scene change fires auto-save
      → game_state.cfg re-created with clean state

Game restart:
  → DifficultyManager._ready() loads difficulty_settings.cfg → Power Fantasy
  → main.gd _ready():
      → DifficultyManager.is_first_launch()
          → FileAccess.file_exists("user://difficulty_settings.cfg") → TRUE
          → is_first_launch() returns FALSE
      → difficulty selection screen is NOT shown ✗
```

---

## Fix Applied (commit `2c0b14fe`)

`clear_all_saves()` in `persist_manager.gd` now calls `DifficultyManager.reset_to_default()`:

```gdscript
# Reset difficulty settings so the first-launch difficulty screen appears on next startup.
var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
if difficulty_manager and difficulty_manager.has_method("reset_to_default"):
    difficulty_manager.reset_to_default()
```

And `DifficultyManager.reset_to_default()` (added in `3698ad1f`):

```gdscript
func reset_to_default() -> void:
    current_difficulty = Difficulty.NORMAL
    if FileAccess.file_exists(SETTINGS_PATH):
        DirAccess.remove_absolute(SETTINGS_PATH)
```

### Fixed Sequence of Events

```
User: "Clear All Saves"
  → persist_manager.clear_all_saves()
      → deletes user://game_state.cfg ✓
      → calls difficulty_manager.reset_to_default() ✓
          → resets current_difficulty = NORMAL ✓
          → deletes user://difficulty_settings.cfg ✓

Game restart:
  → DifficultyManager._ready(): difficulty_settings.cfg not found → NORMAL
  → main.gd _ready():
      → DifficultyManager.is_first_launch()
          → FileAccess.file_exists("user://difficulty_settings.cfg") → FALSE
          → is_first_launch() returns TRUE ✓
      → _show_first_launch_difficulty_menu() called ✓
      → difficulty selection screen appears ✓
```

---

## Reporter Testing Note

The logs provided show behavior from a locally-built binary that predates the PR fix. The CI-built binary with our fix is available as the `windows-build` artifact from the GitHub Actions run on the PR branch:
- [Fork Actions](https://github.com/konard/Jhon-Crow-godot-topdown-MVP/actions?query=branch%3Aissue-1734-824e6ede1bfc)
- Latest run: `Build Windows Portable EXE` (run ID 23711856807, completed 2026-03-29T15:02:07Z)

---

## Impact

- **Severity:** Medium — the game works, but the player's explicit choice to "reset all saves" does not fully restore the first-launch experience
- **Affected scenarios:** Any player who uses "clear all saves" and expects to re-select difficulty on the next launch
- **No data loss risk:** The fix is purely additive (also deletes a settings file that was previously missed)

---

## References

- [Issue #1734](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1734)
- [PR #1735](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1735)
- `scripts/autoload/difficulty_manager.gd` — `is_first_launch()`, `reset_to_default()`
- `scripts/autoload/persist_manager.gd` — `clear_all_saves()`
- `scripts/main.gd` — first-launch detection in `_ready()`
