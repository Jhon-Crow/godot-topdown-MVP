# Case Study: Missing City Map (Город)

## Bug Report

**Date**: 2026-02-10
**Reporter**: Jhon-Crow
**Comment**: "исчезла карта Город" (the City map disappeared)
**Attachment**: `game_log_20260210_221910.txt`

## Timeline Reconstruction

### 1. Original Sniper Implementation (PR #582)
- Sniper enemies were added but incomplete
- Issue #665 reported three problems: no cover, no smoke trail, no damage

### 2. First Fix Attempt (PR #666 - CLOSED)
- Branch: `issue-665-4f2447514623`
- Added CityLevel scene with sniper enemies
- **19 failed test rounds** trying to fix sniper mechanics
- PR was closed (not merged) due to complexity and test failures

### 3. Current Branch (PR #707)
- Branch: `issue-665-2fbfc3d8f9fb`
- Focused on fixing sniper functionality via `SniperComponent`
- **Did NOT include CityLevel scene** - it only existed on the closed PR #666 branch

### 4. Previous "City" Menu Fix (Commit ce3eed64)
- Commit: `fix: rename City→Building Level in levels menu`
- The levels menu had "City/Город" label but pointed to `BuildingLevel.tscn`
- Fixed by renaming the label to "Building Level/Здание"
- **Root cause**: CityLevel.tscn was never merged to main

### 5. User Confusion
- User expected a "City" (Город) map with outdoor urban environment
- The "City" menu item was renamed to "Building Level" (indoor building)
- **No actual outdoor CityLevel exists in the current build**

## Root Cause Analysis

### Primary Cause
The CityLevel scene was created in PR #666 but that PR was closed without merging. The current PR #707 started from a fresh branch and only focused on sniper mechanics (SniperComponent), not the level itself.

### Contributing Factors
1. **Branch isolation**: CityLevel.tscn only exists on `origin/issue-665-4f2447514623` branch
2. **Incomplete merge**: PR #707 did not cherry-pick the CityLevel scene from PR #666
3. **Menu mismatch**: The levels menu was corrected to remove the "City" reference, but the underlying issue (missing level) was not addressed

## Evidence from Game Log

The `game_log_20260210_221910.txt` shows these levels loaded:
```
[22:19:10] Scene changed to: LabyrinthLevel
[22:19:17] Scene changed to: BuildingLevel
[22:19:19] Scene changed to: TestTier
[22:19:21] Scene changed to: CastleLevel
[22:19:23] Scene changed to: Tutorial
[22:19:25] Scene changed to: BeachLevel
```

**CityLevel is NOT in the list** - confirming the scene is missing from the build.

## Solution

### Immediate Fix
1. Copy `CityLevel.tscn` and `city_level.gd` from branch `issue-665-4f2447514623` to current branch
2. Add "City/Город" entry to levels menu in `levels_menu.gd`
3. Verify sniper enemies work with the new SniperComponent

### Files to Add
- `scenes/levels/CityLevel.tscn` - Urban outdoor map (~6000x5000 pixels)
- `scripts/levels/city_level.gd` - Level script

### Level Menu Entry
```gdscript
{
    "name": "City",
    "name_ru": "Город",
    "path": "res://scenes/levels/CityLevel.tscn",
    "description": "Urban warfare with buildings and long sight lines. Features sniper enemies.",
    "preview_color": Color(0.25, 0.25, 0.30, 1.0),
    "preview_accent": Color(0.5, 0.5, 0.55, 1.0),
    "enemy_count": 10,
    "map_size": "6000x5000"
}
```

## Prevention

1. When closing a PR, document what work was done and whether any assets need to be carried forward
2. When creating a new branch for the same issue, check if previous branches had work that needs to be preserved
3. Add integration tests that verify all levels in the menu actually exist
