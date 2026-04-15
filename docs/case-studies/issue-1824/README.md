# Issue 1824 Case Study

## Summary

Issue: [#1824](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1824)

Reported problems:
- HUD labels for enemies, shops, difficulty, and ammo were not consistently translated.
- Most level names in the top-right corner were not translated to Russian.
- `Polygon` and `Castle` did not switch back to English when English locale was active.
- `Sewer` had no top-right level name at all.

## Collected Artifacts

- `issue.json`: GitHub issue snapshot.
- `game_log_20260413_203716.txt`: attached runtime log from the issue report.
- `game_log_20260415_223201.txt`: follow-up runtime log attached in PR comment after the first fix attempt.
- `pr-comment-4254897754-difficulty.png`: screenshot from the PR showing the incorrect difficulty label rendering.

## Root Cause

The UI used hard-coded strings in multiple level scripts instead of translation keys. A second regression remained after the first fix attempt: several levels applied the localized top-right level name only during setup or end-state flows, so the HUD could keep the stale scene text or remain blank during normal gameplay. `SewerLevel.tscn` also had no `LevelLabel` node in `CanvasLayer/UI`, so the shared localization helper had nothing to update and the top-right map name stayed missing. `Building` and `Sewer` additionally needed to refresh their HUD labels after locale changes instead of relying on the original scene text. The special difficulty names `Power Fantasy` and `Black Metal` also needed to stay in their canonical English form in the HUD instead of being translated.

## Fix Strategy

1. Add shared HUD localization helpers for enemy count, ammo, difficulty, and level names.
2. Register the helper as an autoload so existing level scripts can use it safely.
3. Replace per-level hard-coded HUD strings with shared translated formatting.
4. Refresh top-right level labels from the shared helper during runtime HUD updates for affected levels, including `Building`, `Beach`, `Docks`, `Factory`, `Labyrinth Complex`, `Winter Forest`, `Railway Station`, and `Sewer`.
5. Create a top-right `LevelLabel` dynamically when a level scene is missing that node, which fixes `Sewer` without duplicating scene-specific fallback code.
6. Keep `Power Fantasy` and `Black Metal` unchanged in the gameplay HUD while preserving translated names for the standard difficulties.
7. Add regression tests for scene-path-to-translation mapping, HUD difficulty rendering, and label population, including the missing-label case.

## Verification

- Static review confirms affected level scripts now use `LevelLocalization`.
- Follow-up artifact review confirms the April 15 report targeted runtime label refresh and special-difficulty naming, both now covered by the shared helper.
- Added unit regression coverage in `tests/unit/test_level_localization.gd`.
- Local GUT execution could not be run in this environment because the `godot` binary is not installed on `PATH`. CI uses Godot 4.3 mono per `.github/workflows/test.yml`.
