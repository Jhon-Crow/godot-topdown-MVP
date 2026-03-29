# Case Study: Issue #1734 — Difficulty Selection Not Shown After Save Clear

## Overview

**Issue:** When the player uses "clear all saves" and restarts the game, the difficulty selection screen does not appear, even though it should (since the game is back to a "first launch" state).

**Reporter:** Jhon-Crow
**Date observed:** 2026-03-29
**Branch:** `issue-1734-824e6ede1bfc`
**PR:** #1735

---

## Log Files

| File | Timestamp | Context |
|------|-----------|---------|
| `game_log_20260329_175348.txt` | 17:53:48 | Session **before** clearing saves — player has progress (4 entries), Power Fantasy difficulty |
| `game_log_20260329_175414.txt` | 17:54:14 | Session **after** clearing saves — 0 progress entries, but difficulty still Power Fantasy, no first-launch screen shown |

---

## Timeline of Events

### Session 1 (17:53:48) — game_log_20260329_175348.txt

```
[DifficultyManager] Loaded difficulty: Power Fantasy (value: 3)
[ProgressManager] ProgressManager ready, loaded 4 entries
[PersistManager] Navigating to last played level: res://scenes/levels/BeachLevel.tscn
```

- Player has existing progress (4 entries)
- Difficulty is Power Fantasy (value 3) — saved in `difficulty_settings.cfg`
- Player presumably triggers "clear all saves" at some point during or after this session

### Session 2 (17:54:14) — game_log_20260329_175414.txt

```
[DifficultyManager] Loaded difficulty: Power Fantasy (value: 3)
[ProgressManager] ProgressManager ready, loaded 0 entries
[PersistManager] Already at last played level: res://scenes/levels/LabyrinthLevel.tscn
```

- Progress is now 0 entries — `game_state.cfg` was deleted ✓
- Difficulty is **still Power Fantasy** — `difficulty_settings.cfg` was NOT deleted ✗
- No difficulty selection screen appeared — because `is_first_launch()` returned `false`

---

## Root Cause Analysis

### Primary Bug: `clear_all_saves()` does not delete `difficulty_settings.cfg`

**File:** `scripts/autoload/persist_manager.gd`, function `clear_all_saves()` (line ~495)

The function correctly deletes `game_state.cfg`:
```gdscript
if FileAccess.file_exists(SAVE_PATH):
    DirAccess.remove_absolute(SAVE_PATH)
```

But it never touches `difficulty_settings.cfg` (owned by `DifficultyManager`).

### Secondary Effect: `is_first_launch()` returns `false` after save clear

**File:** `scripts/autoload/difficulty_manager.gd`, function `is_first_launch()` (line ~336)

```gdscript
func is_first_launch() -> bool:
    return not FileAccess.file_exists(SETTINGS_PATH)
    # SETTINGS_PATH = "user://difficulty_settings.cfg"
```

Since `difficulty_settings.cfg` was not removed, `is_first_launch()` returns `false`, and `main.gd` never calls `_show_first_launch_difficulty_menu()`.

### Sequence of Events

```
User: "Clear All Saves"
  → persist_manager.clear_all_saves()
      → deletes user://game_state.cfg ✓
      → does NOT delete user://difficulty_settings.cfg ✗

Game restart:
  → DifficultyManager._ready() loads difficulty_settings.cfg → Power Fantasy
  → main.gd _ready():
      → DifficultyManager.is_first_launch()
          → FileAccess.file_exists("user://difficulty_settings.cfg") → TRUE
          → is_first_launch() returns FALSE
      → difficulty selection screen is NOT shown ✗
```

---

## Additional Context

The original Issue #1734 implementation (commit `3698ad1f`) correctly added the first-launch detection mechanism in `difficulty_manager.gd` and the display logic in `main.gd`. However, the save-clearing path (`clear_all_saves()`) was not updated to also reset the difficulty state, creating this regression.

This is a classic "partial reset" bug: two separate files store game state (`game_state.cfg` for progress, `difficulty_settings.cfg` for difficulty), but only one is cleared when "reset to defaults" is triggered.

---

## Proposed Fix

In `persist_manager.gd`, `clear_all_saves()` should:

1. Delete `difficulty_settings.cfg` via `DifficultyManager`'s settings path
2. Reset `DifficultyManager.current_difficulty` to default (NORMAL)

This ensures `is_first_launch()` returns `true` after a save clear, causing the difficulty selection to appear on the next startup — matching the user's expectation of a true "reset to first launch state."

```gdscript
# Also reset difficulty settings so first-launch screen appears on next start
var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
if difficulty_manager:
    difficulty_manager.reset_to_default()
```

And add `reset_to_default()` to `difficulty_manager.gd`:

```gdscript
## Reset difficulty to default and delete the settings file,
## so the next launch is treated as a first launch (Issue #1734).
func reset_to_default() -> void:
    current_difficulty = Difficulty.NORMAL
    if FileAccess.file_exists(SETTINGS_PATH):
        DirAccess.remove_absolute(SETTINGS_PATH)
```

---

## Impact

- **Severity:** Medium — the game works, but the player's explicit choice to "reset all saves" does not fully restore the first-launch experience
- **Affected scenarios:** Any player who uses "clear all saves" and expects to re-select difficulty on the next launch
- **No data loss risk:** The fix is purely additive (also deletes a settings file that was previously missed)
