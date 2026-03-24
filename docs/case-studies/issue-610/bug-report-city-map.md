# Bug Report: City Map Disappeared (PR #656 Comment)

## Report Summary

**Reporter:** Jhon-Crow (repository owner)
**Date:** 2026-02-08T22:02:27Z
**PR Comment:** https://github.com/Jhon-Crow/godot-topdown-MVP/pull/656#issuecomment-3868383079

**Symptom:** "карта Город исчезла, при выборе карты Город - загружается Здание"
(City map disappeared, when selecting City map — Building loads)

## Timeline Reconstruction

### Before PR #656 (main branch state)
1. `levels_menu.gd` had "City" (Город) as the **first** entry, pointing to `BuildingLevel.tscn`
2. `BuildingLevel.tscn` was the **only** level scene file for what was labeled "City"
3. There was no separate `CityLevel.tscn` on main

### PR #582 / PR #666 (parallel work, not merged)
- PR #582 (issue #581) created a **new** `CityLevel.tscn` — an outdoor urban warfare map (6000x5000) with sniper enemies
- PR #666 (issue #665) refined this CityLevel further:
  - Added proper `CityLevel.tscn` and `city_level.gd`
  - Renamed "City"→"Building Level"/"Здание" for `BuildingLevel.tscn`
  - Added "City"→"Город" entry pointing to the new `CityLevel.tscn`
- **Neither PR was merged to main** — they remain OPEN

### PR #656 changes (this PR - issue #610)
- Added "Labyrinth" (Лабиринт) as the first entry in `levels_menu.gd`
- Kept "City" (Город) as the second entry, still pointing to `BuildingLevel.tscn`
- Changed `main_scene` in `project.godot` from `BuildingLevel.tscn` to `LabyrinthLevel.tscn`

### What the user experienced
The user likely tested the build from PR #666 branch (which had the real CityLevel), then tested PR #656's branch and noticed:
1. "City" (Город) menu entry loads `BuildingLevel.tscn` (an indoor building), not the outdoor city map
2. The outdoor City map they saw in PR #666 doesn't exist on this branch

## Root Cause Analysis

The root cause is a **naming inconsistency** on `main`:
- `BuildingLevel.tscn` was labeled "City"/"Город" in the levels menu on main
- The actual City level (`CityLevel.tscn`) only exists on unmerged PR #666 branch
- PR #656 inherited this naming confusion and added Labyrinth as first level

## Fix

Rename "City"/"Город" back to "Building Level"/"Здание" in `levels_menu.gd` on this PR branch to accurately reflect that `BuildingLevel.tscn` is an indoor building level, not a city level. The actual CityLevel will be added when PR #666 merges.

## Log Analysis

### game_log_20260209_005853.txt
- Game starts on LabyrinthLevel (new first level — correct)
- Player plays multiple rounds of LabyrinthLevel (dying and restarting)
- No evidence of level menu navigation in this log

### game_log_20260209_010116.txt
- Game starts on LabyrinthLevel
- At 01:01:20: Scene changes to BuildingLevel (user selected "City" from menu)
- At 01:01:28: Scene changes to TestTier (Polygon)
- At 01:01:30: Scene changes to CastleLevel
- Confirms the user navigated through all levels and found "City" loading BuildingLevel

## Files Referenced

- `scripts/ui/levels_menu.gd` — LEVELS array with incorrect "City" label for BuildingLevel
- `scripts/levels/building_level.gd` — next level path array
- `scripts/levels/labyrinth_level.gd` — next level path array
- `scripts/levels/test_tier.gd` — next level path array
- `scripts/levels/castle_level.gd` — next level path array
- `scripts/levels/beach_level.gd` — next level path array
