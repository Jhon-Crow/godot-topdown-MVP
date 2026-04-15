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

## Root Cause

The UI used hard-coded strings in multiple level scripts instead of translation keys. Level name labels were also set per-level with inconsistent logic, and several levels never refreshed the label through localized scene-name mappings.

## Fix Strategy

1. Add shared HUD localization helpers for enemy count, ammo, difficulty, and level names.
2. Register the helper as an autoload so existing level scripts can use it safely.
3. Replace per-level hard-coded HUD strings with shared translated formatting.
4. Apply localized top-right level names for affected levels, including `Sewer`, `Polygon`, and `Castle`.
5. Add regression tests for scene-path-to-translation mapping and label population.

## Verification

- Static review confirms affected level scripts now use `LevelLocalization`.
- Added unit regression coverage in `tests/unit/test_level_localization.gd`.
- Local GUT execution could not be run in this environment because the `godot` binary is not installed on `PATH`. CI uses Godot 4.3 mono per `.github/workflows/test.yml`.
