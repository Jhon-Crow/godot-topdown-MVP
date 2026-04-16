# Case Study: Issue #1734 — Difficulty Selection Not Shown After Save Clear

## Overview

**Issue:** When the player uses "clear all saves" and restarts the game, the difficulty selection screen does not appear, even though it should (since the game is back to a "first launch" state).

**Reporter:** Jhon-Crow
**Date observed:** 2026-03-29, 2026-03-30
**Branch:** `issue-1734-824e6ede1bfc`
**PR:** #1735

---

## Log Files

| File | Timestamp | Context |
|------|-----------|---------|
| `logs/game_log_20260329_175348.txt` | 17:53:48 | Session **before** clearing saves — 4 progress entries, Power Fantasy |
| `logs/game_log_20260329_175414.txt` | 17:54:14 | Session **after** clear (pre-fix binary) — difficulty still Power Fantasy, no picker shown |
| `logs/game_log_20260330_111405.txt` | 11:14:05 | Session **before** clearing saves — 1 entry, Gunslinger difficulty |
| `logs/game_log_20260330_111500.txt` | 11:15:00 | Session **after** clear (post-fix binary) — difficulty now Normal ✓, but picker **still not shown** ✗ |

**Note:** All logs show `build_info.cfg not found`, meaning the reporter was testing locally-built binaries. The March 30 logs are from the reporter's own build of the PR branch.

---

## Timeline of Events

### March 29 — Session 1 (17:53:48) — Pre-fix binary

```
[17:53:48] [DifficultyManager] Loaded difficulty: Power Fantasy (value: 3)
[17:53:48] [ProgressManager] ProgressManager ready, loaded 4 entries
[17:53:55] [PersistManager] All saves cleared — game reset to first-launch state
[17:53:58] [PersistManager] State saved to user://game_state.cfg   ← auto-save re-creates file!
```

### March 29 — Session 2 (17:54:14) — Pre-fix binary

```
[17:54:14] [DifficultyManager] Loaded difficulty: Power Fantasy (value: 3)   ← still Power Fantasy!
[17:54:14] [ProgressManager] ProgressManager ready, loaded 0 entries          ← progress cleared ✓
```

**Bug #1 found:** `difficulty_settings.cfg` was not deleted by `clear_all_saves()`.

---

### March 30 — Session 1 (11:14:05) — PR binary (with Bug #1 fix)

```
[11:14:05] [DifficultyManager] Loaded difficulty: Gunslinger (value: 5)
[11:14:06] [ProgressManager] ProgressManager ready, loaded 1 entries
[11:14:34] [PersistManager] All saves cleared — game reset to first-launch state
[11:14:35] [PersistManager] ...  (scene auto-save fires shortly after)
[11:14:49] [PersistManager] All saves cleared — game reset to first-launch state  ← second clear
```

### March 30 — Session 2 (11:15:00) — PR binary (with Bug #1 fix)

```
[11:15:00] [DifficultyManager] Loaded difficulty: Normal (value: 1)   ← reset to Normal ✓
[11:15:00] [ProgressManager] ProgressManager ready, loaded 0 entries   ← cleared ✓
[11:15:00] [PersistManager] Already at last played level: LabyrinthLevel.tscn
```
→ **No difficulty selection screen appeared.**

**Bug #2 found:** Even though `difficulty_settings.cfg` was deleted correctly (difficulty reset to Normal), the first-launch screen still did not appear.

---

## Root Cause Analysis

### Bug #1 (Fixed in commit `2c0b14fe`): `clear_all_saves()` left `difficulty_settings.cfg` intact

`clear_all_saves()` deleted `game_state.cfg` but never touched `difficulty_settings.cfg`. Since `is_first_launch()` checks for that file, it returned `false` and the picker was skipped.

**Fix:** `clear_all_saves()` now calls `DifficultyManager.reset_to_default()` which deletes `difficulty_settings.cfg`.

---

### Bug #2 (Root cause of March 30 report): `main.gd` is NEVER the startup scene

This is the **actual root cause** that caused the issue to persist after Bug #1 was fixed.

**File:** `project.godot`
```ini
run/main_scene="res://scenes/levels/LabyrinthLevel.tscn"
```

The project's startup scene is `LabyrinthLevel.tscn`, **not** `Main.tscn`. The first implementation (commit `3698ad1f`) placed the `is_first_launch()` check in `main.gd`'s `_ready()`:

```gdscript
# scripts/main.gd
func _ready() -> void:
    var difficulty_manager = get_node_or_null("/root/DifficultyManager")
    if difficulty_manager and difficulty_manager.is_first_launch():
        _show_first_launch_difficulty_menu()
```

But since `Main.tscn` is never loaded at startup, this `_ready()` **never runs**. The difficulty picker never appeared regardless of whether `difficulty_settings.cfg` existed or not.

The March 30 log confirmed this: `DifficultyManager` shows `Normal (value: 1)` — the file was deleted — but no first-launch screen appeared because `main.gd` was never executed.

### Why there are NO `[Main]` log entries in the session 2 log

The log file `game_log_20260330_111500.txt` contains no `[Main]` log entries at all. This is direct evidence that `main.gd._ready()` was never called during startup.

### Sequence of Events (post-Bug-#1-fix, pre-Bug-#2-fix)

```
Game startup:
  → Autoloads initialize: DifficultyManager, PersistManager, ...
  → DifficultyManager._ready():
      → difficulty_settings.cfg NOT found → current_difficulty = NORMAL ✓
      → is_first_launch() would return TRUE ✓ (file missing)
  → PersistManager._ready():
      → _load_state() → reads game_state.cfg
      → call_deferred("_navigate_to_last_level")
  → Scene tree loads: LabyrinthLevel.tscn (the main_scene)
  → PersistManager._navigate_to_last_level() fires:
      → No check for is_first_launch() ✗
      → game_state.cfg exists → navigates to last level directly
  → main.gd._ready() is NEVER called (Main.tscn is not loaded)
  → Difficulty picker never appears ✗
```

---

## Final Fix (commit `fix(#1734): check is_first_launch in PersistManager not main.gd`)

The first-launch check has been moved from `main.gd` to `PersistManager._navigate_to_last_level()`, which runs as an **autoload** on every startup:

```gdscript
# scripts/autoload/persist_manager.gd
func _navigate_to_last_level() -> void:
    # Issue #1734: Show difficulty picker on first launch before any level navigation.
    # The check must live here (an autoload) because the project's run/main_scene is
    # LabyrinthLevel.tscn — Main.tscn and main.gd are never the startup scene.
    var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
    if difficulty_manager and difficulty_manager.is_first_launch():
        _log_to_file("First launch detected — showing difficulty selection before level load")
        _show_first_launch_difficulty_menu()
        return  # Navigation resumes in _on_first_launch_difficulty_selected()

    _do_navigate_to_last_level()
```

### Corrected Sequence of Events (post-final-fix)

```
Game startup:
  → DifficultyManager._ready():
      → difficulty_settings.cfg NOT found → NORMAL, is_first_launch() = TRUE
  → PersistManager._ready():
      → call_deferred("_navigate_to_last_level")
  → LabyrinthLevel.tscn loads (the main_scene)
  → PersistManager._navigate_to_last_level() fires:
      → is_first_launch() == TRUE → show difficulty menu ✓
      → navigation deferred ✓
  → Player picks difficulty
      → difficulty_settings.cfg created ✓
      → _do_navigate_to_last_level() called ✓
      → game proceeds normally ✓
```

---

## Impact

- **Severity:** Medium — the game works, but the player's explicit choice to "reset all saves" did not restore the first-launch difficulty selection experience
- **Root cause chain:** Two bugs in sequence — `clear_all_saves()` missed a file (Bug #1), and even after that fix, the is_first_launch check was in unreachable code (Bug #2)
- **No data loss risk:** Both fixes are purely additive

---

## References

- [Issue #1734](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1734)
- [PR #1735](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1735)
- `scripts/autoload/difficulty_manager.gd` — `is_first_launch()`, `reset_to_default()`
- `scripts/autoload/persist_manager.gd` — `clear_all_saves()`, `_navigate_to_last_level()`
- `scripts/main.gd` — simplified (no longer handles first-launch)
