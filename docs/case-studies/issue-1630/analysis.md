# Case Study: Issue #1630 — Score screen shows before player reaches exit (Labyrinth2Level)

## Summary

**Issue**: The score screen appeared immediately after all enemies were killed in Labyrinth2Level, instead of waiting for the player to reach the exit zone.

**Root cause**: The W key shortcut in `_input()` called `_complete_level_with_score()` directly when `_level_cleared` was true, bypassing the exit zone requirement.

**Fix**: Removed the incorrect W key binding from `_input()` and replaced it with the standard `_unhandled_input()` pattern used by all other levels (W key triggers Watch Replay only when `_score_shown` is true).

---

## Timeline / Sequence of Events

### Session 1 (08:12:23 – 08:13:29)
- Level loaded: 17 enemies
- Kills 1–17 registered (combo up to 17)
- At 08:13:23: `Player controls disabled (level completed)` fires
- No "Exit zone activated" or "Player reached exit" in log
- Score screen shown immediately → S rank, 486,217 points
- Player restarts at 08:13:29

### Session 2 (08:13:29 – 08:14:26)
- Level reloaded: 17 enemies again
- Last kill at 08:14:18 (combo ended at 1)
- At 08:14:24 (6 seconds after last kill): `Player controls disabled (level completed)` fires
- No "Exit zone activated" or "Player reached exit" in log
- Score screen shown → S rank, 141,166 points

---

## Root Cause Analysis

### The Bug

In `scripts/levels/labyrinth2_level.gd`, the `_input()` function contained:

```gdscript
elif event.keycode == KEY_W and _level_cleared:
    _complete_level_with_score()
```

This allowed pressing **W** after killing all enemies to immediately show the score screen — bypassing the exit zone completely.

### Evidence from the Log

- The log contains zero occurrences of `"Exit zone activated"` or `"Player reached exit"`
- Level completion fires after a short pause following the last kill (consistent with the player pressing W)
- The `ReplayManager` kept recording with `enemies=17` (tracked list size, not alive count) right up to the completion moment

### Why This Shortcut Existed

In all other levels (building, labyrinth, sewer, factory, etc.), the W key is used to trigger **Watch Replay** (only after `_score_shown` is true). The W key shortcut in `labyrinth2_level.gd` was a **mis-implementation** — it was wired to trigger level completion instead of watch replay.

### Comparison with Correct Levels

All other levels follow this pattern:

```gdscript
## Handle W key shortcut for Watch Replay when score is shown.
func _unhandled_input(event: InputEvent) -> void:
    if not _score_shown:
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_W:
            # Only trigger replay if enabled in experimental settings
            var experimental_settings = get_node_or_null("/root/ExperimentalSettings")
            if experimental_settings and experimental_settings.has_method("is_replay_enabled") and experimental_settings.is_replay_enabled():
                _on_watch_replay_pressed()
```

The `_score_shown` flag is only set to `true` inside `_add_score_screen_buttons()`, which is called after the full score animation completes — well after the player has already reached the exit.

---

## Fix Applied

Removed:
```gdscript
elif event.keycode == KEY_W and _level_cleared:
    _complete_level_with_score()
```

Added standard `_unhandled_input()` for Watch Replay (same as all other levels).

**File changed**: `scripts/levels/labyrinth2_level.gd`

---

## Data Files

- `game_log_20260328_081217.txt` — Full game session log (6671 lines) provided by the issue author
- `file_list.txt` — Repository file listing at time of investigation
