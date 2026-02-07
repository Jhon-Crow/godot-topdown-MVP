# Case Study: Issue #561 - Progress Saving

## Problem Statement

PR #558 added a card-based level selection menu that displays difficulty ratings and grades for each level. However, the progress parameters (completion status, scores, ranks) are not actually persisted. When the game restarts, all progress is lost.

**Issue**: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/561

## Current State Analysis

### Existing Persistence
- **DifficultyManager** saves difficulty setting to `user://difficulty_settings.cfg` using `ConfigFile`
- **InputSettings** saves input bindings to `user://input_settings.cfg` using `ConfigFile`
- **GameManager** holds weapon selection in memory only (not persisted)

### What Needs Saving
1. **Level completion status** - whether a level has been completed
2. **Best rank per level per difficulty** - the best rank (F-S) achieved
3. **Best score per level per difficulty** - the highest score achieved

### Score/Rank System (ScoreManager)
- Ranks: F, D, C, B, A, A+, S
- Score based on: kills, combo, time bonus, accuracy, damage taken, special kills
- `complete_level()` returns a `score_data` dictionary with `total_score` and `rank`

## Solution Design

### Approach: ProgressManager Autoload

Create a new autoload singleton `ProgressManager` that:
1. Follows the same `ConfigFile` pattern as `DifficultyManager`
2. Saves to `user://progress.cfg`
3. Stores best rank and score per level per difficulty mode
4. Integrates with `ScoreManager.score_calculated` signal
5. Provides data to `LevelsMenu` for display

### Data Structure

```
[progress]
; Key format: "level_path:difficulty_name"
; Value: {"rank": "A+", "score": 12500}
"res://scenes/levels/BuildingLevel.tscn:Normal" = {"rank": "A+", "score": 12500}
"res://scenes/levels/TestTier.tscn:Hard" = {"rank": "B", "score": 8000}
```

### Integration Points
1. **ScoreManager** → emits `score_calculated` → **ProgressManager** saves if better
2. **LevelsMenu** → reads from **ProgressManager** → displays rank on cards

### UI Display
- Each level card shows progress results (as stars) for **all four** difficulties simultaneously
- Difficulty labels use short names: E (Easy), N (Normal), H (Hard), PF (Power Fantasy)
- Ranks are converted to stars: S/A+=5, A=4, B=3, C=2, D/F=1, not completed=0
- Star colors match rank colors (S=gold, A+=green, etc.)
- A legend at the bottom explains the abbreviations

## References
- Godot ConfigFile docs: https://docs.godotengine.org/en/stable/classes/class_configfile.html
- Similar pattern: `scripts/autoload/difficulty_manager.gd` lines 264-286
