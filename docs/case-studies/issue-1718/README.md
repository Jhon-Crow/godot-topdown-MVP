# Case Study: Issue #1718 — Internationalization (Russian/English)

## Overview

**Issue**: Add Russian and English translations with a language switcher in settings.

**Reported Bugs (PR #1721 feedback, 2026-03-29)**:
1. Translation text not showing — UI shows raw keys (`RESUME`, `ARMORY`) instead of translated text
2. ESC key does not close the Language selection screen (but works in pause menu)
3. Default language should be English

---

## Timeline / Sequence of Events

| Time       | Event |
|------------|-------|
| 2026-03-28 | PR #1721 opened: adds `LocalizationSettings` autoload, `translations.csv`, `LanguageMenu` scene/script, language button in settings |
| 2026-03-28 | CI passes; build exported via `firebelley/godot-export@v7.0.0` |
| 2026-03-29 16:46 | Owner (Jhon-Crow) tests the exported `.exe` — game log saved as `game_log_20260329_164616.txt` |
| 2026-03-29 16:46:16 | `LocalizationSettings` initialises with `locale: en` (correct) |
| 2026-03-29 16:46:34 | Owner switches to Russian — `Locale changed to: ru` logged |
| 2026-03-29 16:46:46 | Owner switches back to English |
| 2026-03-29 16:46:48 | Owner switches to Russian again |
| 2026-03-29 | Owner reports: switcher toggles work but UI text stays as raw keys; ESC doesn't close Language screen |

---

## Root Cause Analysis

### Bug 1: Translations not applied — raw keys displayed

**Symptom**: Menu buttons show `RESUME`, `ARMORY`, `SETTINGS` instead of `Resume`, `Armory`, `Settings` in English; switching to Russian has no visible effect.

**Root Cause**: Godot 4's `locale/translations` project setting expects **compiled `.translation` binary files**, not raw `.csv` source files. The `project.godot` entry was:

```ini
locale/translations=PackedStringArray("res://resources/translations/translations.csv")
```

The `.csv` is a source file; Godot's editor imports it and writes compiled `.translation` files to `.godot/imported/`. The project settings are then updated to reference those compiled files. Because:
- `.gitignore` excludes `*.translation` and `.godot/`
- The compiled files were never committed or generated in the CI export in a way that `project.godot` pointed to them

…the exported binary had no translation resources loaded, so `tr("RESUME")` returned the raw key `"RESUME"`.

**Evidence**: Game log shows locale changes recorded (`Locale changed to: ru`) but no visual change in UI text. The locale function itself works; only the translation tables are missing.

**Fix**: Load translations programmatically at runtime by parsing the CSV directly in `LocalizationSettings._ready()` using `FileAccess`, building `Translation` objects, and registering them with `TranslationServer.add_translation()`. This bypasses the import/compilation step entirely and works correctly in exported builds.

### Bug 2: ESC does not close the Language screen

**Symptom**: Pressing ESC while the Language menu is open closes the Pause menu entirely instead of going back to the Settings menu (or does nothing).

**Root Cause**: `language_menu.gd` is missing the `_unhandled_input` handler that all other sub-menus (e.g. `gameplay_menu.gd`) implement to intercept the `pause` action and call `back_pressed.emit()`.

**Evidence**: Comparing `gameplay_menu.gd` (has `_unhandled_input`) vs `language_menu.gd` (missing it).

**Fix**: Add `_unhandled_input` to `language_menu.gd` identical to the pattern in other sub-menus.

### Bug 3: Default language should be English

**Root Cause (minor)**: The code already defaults to English (`LOCALE_EN`). However if a user had previously saved `ru` (e.g. during testing of the broken build), the persisted value would load `ru` on next launch. This is expected save/load behaviour but could confuse users who expect English after a fresh install.

**Status**: Not a code bug — the default is correct. No change needed; the persistence is correct by design.

---

## Second Report: Russian language still not working (2026-03-29 17:22)

After the first fix (runtime CSV loading added, ESC fixed), the owner tested again with `game_log_20260329_172217.txt` and reported: **"русского языка нет"** (Russian language is absent).

### Analysis of second game log

The second game log (17:22:17) is from the updated build (post-commit `2c199183`). The log shows:
- `LocalizationSettings initialized — locale: ru` ✓
- `Locale changed to: en`, `Locale changed to: ru`, etc. ✓
- **Missing**: `Loaded X locale(s) from CSV` ← this log line is never printed

This means `_load_csv_translations()` returned early before reaching the final `_log_to_file` call. The early returns happen when:
1. `FileAccess.file_exists(CSV_PATH)` returns `false`, OR
2. `FileAccess.open(CSV_PATH, ...)` returns `null`

Both returned `push_warning()` which goes to Godot's internal console but NOT to the game's `FileLogger` — making the failure invisible in the log.

### Root Cause (Bug 4): CSV not bundled in exported PCK

**Root Cause**: Godot 4's export pipeline treats `.csv` files as **translation source files**, not as packable resources. When `ResourceImporterCSVTranslation` processes a `.csv`, it produces compiled `.translation` binary files (stored in `.godot/imported/`) and marks the raw `.csv` as a non-resource file. As a result, `export_filter="all_resources"` does **not** include `.csv` source files in the PCK.

**Consequence**: In the exported build, `FileAccess.file_exists("res://resources/translations/translations.csv")` returns `false` → `_load_csv_translations()` returns early → no Translation objects are registered → `tr("RESUME")` returns `"RESUME"`.

**Evidence**:
- Confirmed by Godot issue tracker: [godotengine/godot#38957](https://github.com/godotengine/godot/issues/38957) and [godotengine/godot#41042](https://github.com/godotengine/godot/issues/41042)
- The first game log (before fix) and second game log (after first fix) both show no "Loaded X locale(s)" message, confirming the CSV was never accessible in either exported build.

**Fix**: Add `*.csv` to `include_filter` in `export_presets.cfg`:
```ini
include_filter="*.csv"
```
This explicitly tells Godot's exporter to include `.csv` files in the PCK as raw data files, making them accessible via `FileAccess` at `res://` paths in exported builds.

---

## Solution

1. **Programmatic CSV translation loading** in `localization_settings.gd`:
   - Parse `res://resources/translations/translations.csv` at runtime
   - Create one `Translation` object per locale column
   - Register with `TranslationServer.add_translation()`
   - Remove the `locale/translations` project setting (no longer needed; avoids confusion)

2. **ESC support** in `language_menu.gd`:
   - Add `_unhandled_input(event)` matching the pattern in other sub-menu scripts

3. **CSV included in exported PCK** via `export_presets.cfg`:
   - Set `include_filter="*.csv"` so the raw CSV is bundled in the export
   - Without this, `FileAccess` cannot find the file at `res://` in exported builds

4. **Improved error logging** in `localization_settings.gd`:
   - Changed `push_warning()` errors in `_load_csv_translations()` to also call `_log_to_file()` so failures appear in the game log

---

## Attached Artifacts

- `game_log_20260329_164616.txt` — Full game log from the owner's first test session on 2026-03-29
- `game_log_20260329_172217.txt` — Full game log from the owner's second test session on 2026-03-29
