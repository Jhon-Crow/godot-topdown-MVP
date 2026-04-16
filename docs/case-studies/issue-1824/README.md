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
- `game_log_20260416_010941.txt`: follow-up runtime log attached after the owner confirmed the `Building` and `Sewer` regressions still reproduced.
- `game_log_20260416_021320.txt`: runtime log attached after a second follow-up report that `Building` HUD localization still failed.
- `game_log_20260416_025240.txt`: runtime log attached after the owner confirmed the `Building` top-left HUD still did not translate to Russian.
- `game_log_20260416_034120.txt`: latest runtime log attached after the owner again confirmed `Building` still showed English in the HUD under Russian locale.
- `game_log_20260416_101642.txt`: runtime log attached after the owner narrowed the `Building` failure to top-left HUD labels; the top-right level name was already translated.
- `game_log_20260416_194323.txt`: runtime log attached after the owner confirmed the same `Building` top-left HUD regression still reproduced.
- `pr-comment-4254897754-difficulty.png`: screenshot from the PR showing the incorrect difficulty label rendering.

## Timeline

1. `2026-04-13 20:37:16`: initial issue report log captured untranslated HUD labels, missing Russian map names, missing `Sewer` label, and `Polygon` / `Castle` not switching back to English.
2. `2026-04-15 19:34:18`: PR feedback added the `Power Fantasy` / `Black Metal` difficulty-name regression plus untranslated top-right labels on `Beach`, `Docks`, `Factory`, `Labyrinth Complex`, `Winter Forest`, and `Railway Station`.
3. `2026-04-15 22:13:00`: follow-up report narrowed the remaining failures to `Building` and `Sewer`.
4. `2026-04-15 23:14:40`: another report confirmed `Building` HUD localization still failed after the `Sewer` fix path was added.
5. `2026-04-15 23:18:43`: commit `a1939152` added the `Building` initialization refresh by calling `_update_debug_ui()` at the end of `_setup_debug_ui()`.
6. `2026-04-15 23:18:47`: upstream CI runs for commit `a1939152` succeeded.
7. `2026-04-15 23:53:17`: the owner posted one more `Building` runtime log, indicating the validation artifact trail needed to be preserved in this case-study even though the code fix was already present on the branch.
8. `2026-04-16 00:42:29`: the owner reported that `Building` still rendered English in the HUD with Russian enabled and attached `game_log_20260416_034120.txt`.
9. `2026-04-16 10:16:42`: the owner clarified that `Building` now translated only the top-right map name; the rest of the HUD stayed English.
10. `2026-04-16 19:43:23`: the owner confirmed the same `Building` top-left HUD failure still reproduced.

## Root Cause

The UI used hard-coded strings in multiple level scripts instead of translation keys. A second regression remained after the first fix attempt: several levels applied the localized top-right level name only during setup or end-state flows, so the HUD could keep the stale scene text or remain blank during normal gameplay. `SewerLevel.tscn` also had no `LevelLabel` node in `CanvasLayer/UI`, so the shared localization helper had nothing to update and the top-right map name stayed missing. `Building` had two initialization bugs on top of that. First, its scene still shipped with the placeholder `LevelLabel` text `"BUILDING INTERIOR"`, leaving an English fallback whenever startup ordering regressed. Second, `_setup_player_tracking()` updated ammo and magazine data before `_setup_debug_ui()` created `DifficultyLabel` and `MagazinesLabel`; then `_setup_debug_ui()` reset the newly created magazine label to the placeholder and `_update_debug_ui()` only refreshed the level and difficulty labels. That is why the later owner reports showed the top-right map name translated while the top-left HUD stayed English or stale. `Building` and `Sewer` additionally needed to refresh their HUD labels after locale changes instead of relying on the original scene text. The special difficulty names `Power Fantasy` and `Black Metal` also needed to stay in their canonical English form in the HUD instead of being translated.

## Fix Strategy

1. Add shared HUD localization helpers for enemy count, ammo, difficulty, and level names.
2. Register the helper as an autoload so existing level scripts can use it safely.
3. Replace per-level hard-coded HUD strings with shared translated formatting.
4. Refresh top-right level labels from the shared helper during runtime HUD updates for affected levels, including `Building`, `Beach`, `Docks`, `Factory`, `Labyrinth Complex`, `Winter Forest`, `Railway Station`, and `Sewer`.
5. Create a top-right `LevelLabel` dynamically when a level scene is missing that node, which fixes `Sewer` without duplicating scene-specific fallback code.
6. Keep `Power Fantasy` and `Black Metal` unchanged in the gameplay HUD while preserving translated names for the standard difficulties.
7. Force `Building` to run a shared full-HUD refresh at the end of `_setup_debug_ui()` so the stale scene-authored labels and the labels created during debug setup are all translated on first frame.
8. Replace the authored `BuildingLevel.tscn` placeholder text with `LEVEL_BUILDING_NAME` so the scene default is translation-safe even if a later initialization step temporarily misses the refresh.
9. Add regression tests for scene-path-to-translation mapping, HUD difficulty rendering, and label population, including the missing-label case, the `Building` placeholder-text override, and the `Building` debug-UI startup ordering that previously left top-left HUD labels stale.

## Verification

- Static review confirms affected level scripts now use `LevelLocalization`.
- Follow-up artifact review confirms the April 15 and April 16 reports targeted runtime label refresh, the missing `Sewer` label, the stale `Building` initialization path, the authored English `Building` fallback text, the later `Building` top-left HUD startup-order failure, and special-difficulty naming, all now covered by the shared helper plus the `Building` full-HUD startup refresh and translation-safe scene default.
- Added unit regression coverage in `tests/unit/test_level_localization.gd`.
- Local GUT execution could not be run in this environment because the `godot` binary is not installed on `PATH`. CI uses Godot 4.3 mono per `.github/workflows/test.yml`.
