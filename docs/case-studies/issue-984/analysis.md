# Issue #984: Sequential Level Unlocking

## Problem Statement

The next map should only become available after the player has completed the previous one.
At the start of the game, only the first level (Лабиринт / Labyrinth) should be accessible.

All other levels were previously shown as fully clickable cards regardless of whether the
player had completed the required prerequisite levels.

## Root Cause Analysis

`scripts/ui/levels_menu.gd` — the `_populate_level_cards()` function — iterated over all
levels in the `LEVELS` array and created clickable cards for each without any check against
player progress. There was no concept of "level locked/unlocked" in the UI at all.

`scripts/autoload/progress_manager.gd` had `is_level_completed(path, difficulty)` to check
a specific difficulty, and `get_progress_for_all_difficulties(path)` which returns a
dictionary of completed difficulties — but no method that answered the single question:
"has this level been beaten on *any* difficulty?"

## Solution

### 1. `ProgressManager`: added `is_level_completed_any_difficulty(level_path)`

A new helper method that returns `true` if the given level has been completed on at least
one difficulty mode. This is the criterion used to unlock the next level in the sequence.

### 2. `LevelsMenu`: added `is_level_unlocked(level_index, progress_manager)`

A new method on the menu that encapsulates the unlock rule:
- Index 0 (Labyrinth) is always unlocked.
- Every other level requires `is_level_completed_any_difficulty()` to return `true` for the
  immediately preceding level.

### 3. `LevelsMenu`: visual treatment for locked cards

`_create_level_card()` now accepts an `unlocked` parameter:
- **Locked card background**: darkened, low-contrast border.
- **Preview area**: dimmed colors, lock emoji (🔒) replaces map stats.
- **Level name**: greyed out.
- **Description**: replaced by "Complete the previous level to unlock".
- **Progress grades**: shown as dimmed dashes; no grade lookup is performed.
- **Mouse interaction**: no click handler, no pointer cursor; tooltip explains the lock.

### 4. Tests

New tests added in:
- `tests/unit/test_ui_menus.gd` — 13 new tests under "Level Locking / Progression Tests":
  covering that Labyrinth is always open, that subsequent levels are locked by default,
  that completing any difficulty of the prior level unlocks the next one, and that the
  unlock chain is sequential (completing level 0 does not skip level 1 to unlock level 2).
- `tests/unit/test_progress_manager.gd` — 6 new tests for
  `is_level_completed_any_difficulty()`: false with no progress, true after each of the four
  difficulty modes, does not bleed across levels, and F-rank still counts as a completion.

Pre-existing test issues fixed:
- `test_level_display_name_russian` referenced "Tutorial" / "Обучение" which was never in
  the mock; updated to test "Labyrinth" / "Лабиринт" which is the actual first level.
- `test_level_enemy_count` referenced "Tutorial" (4 enemies); updated to test "Labyrinth"
  (5 enemies) and removed the non-existent Tutorial assertion.

## Sequence

The canonical level order (from `LEVELS` in `levels_menu.gd`) is:

```
0  Labyrinth       (always unlocked)
1  Building Level  (requires Labyrinth beaten)
2  Polygon         (requires Building Level beaten)
3  Castle          (requires Polygon beaten)
4  City            (requires Castle beaten)
5  Beach           (requires City beaten)
6  Docks           (requires Beach beaten)
7  Double Corridor (requires Docks beaten)
```

## Design Decisions

- **Any difficulty counts**: completing a level on Easy is sufficient to unlock the next one.
  This keeps the progression accessible while still enforcing a linear order.
- **F rank counts**: the unlock criterion is "level completed at all", not "level completed
  well". Even an F rank means the player finished the level.
- **All 8 levels still shown**: locked levels remain visible as greyed-out cards so players
  can see what's ahead and plan their progression.
