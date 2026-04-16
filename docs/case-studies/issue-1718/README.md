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

---

## Third Report: Russian language still not working + font broken (2026-03-29 17:51)

After the second fix (include_filter added to export_presets.cfg), the owner tested again with `game_log_20260329_175132.txt` and reported:
1. **"кстати, сейчас похоже испортился шрифт (должен быть как в main)"** — "font appears broken (should be like main)"
2. **"всё ещё не меняется язык"** — "language still doesn't change"
3. **"переведи всё на 2 языка!"** — "translate everything to 2 languages!"

### Analysis of third game log

The third log (17:51:32) shows:
```
[LocalizationSettings] ERROR: CSV not found at res://resources/translations/translations.csv — translations will not work.
[LocalizationSettings] LocalizationSettings initialized — locale: en
[LocalizationSettings] Locale changed to: ru
[LocalizationSettings] Locale changed to: en
```

The CSV is **still** not found in the PCK despite `include_filter="*.csv"` being present.

### Root Cause (Bug 5): include_filter has no effect — CSV is excluded by Godot's importer

**Root Cause**: Godot's CSV importer (`ResourceImporterCSVTranslation`) processes the CSV during the editor/build phase and produces compiled `.translation` binary files stored **alongside the CSV** at:
- `res://resources/translations/translations.en.translation`
- `res://resources/translations/translations.ru.translation`

The CI build log (run `23711389121`) confirms these compiled files ARE in the PCK:
```
savepack: Storing File: res://resources/translations/translations.csv.import
savepack: Storing File: res://resources/translations/translations.en.translation
savepack: Storing File: res://resources/translations/translations.ru.translation
```

But the raw `translations.csv` is NOT stored. The `include_filter="*.csv"` adds `.csv` to the explicit include list, but Godot's importer-resource relationship **overrides** this: imported resources are stored under their compiled form, not their source form. The `.csv` path is remapped to the compiled `.translation` resources.

**Consequence**: `FileAccess.file_exists("res://resources/translations/translations.csv")` returns `false` in the exported build because only the compiled `.translation` files are in the PCK, not the raw CSV.

**The "font broken" symptom**: Since translations fail entirely, all UI buttons show raw UPPERCASE keys (`RESUME`, `ARMORY`, `SETTINGS`, etc.) instead of proper translated text. The uppercase keys are longer and cause buttons to reflow/resize, which *looks* like a font change but is actually just the missing translation text.

### Final Fix

**Replace the CSV-loading approach with loading the compiled `.translation` binary files**:

The compiled files ARE in the PCK at `res://resources/translations/translations.en.translation` and `res://resources/translations/translations.ru.translation`. Use `load()` to load them instead of `FileAccess` on the raw CSV:

```gdscript
func _load_translations() -> void:
    for path in TRANSLATION_PATHS:
        var translation: Translation = load(path) as Translation
        if translation == null:
            _log_to_file("ERROR: Failed to load translation from %s" % path)
            continue
        TranslationServer.add_translation(translation)
```

**Also add `locale/translations` to `project.godot`** so Godot's editor knows to import the CSV and produce the compiled `.translation` files during build:

```ini
[internationalization]
locale/translations=PackedStringArray("res://resources/translations/translations.csv")
```

This ensures:
1. The editor imports the CSV → creates `translations.en.translation` + `translations.ru.translation` next to the CSV
2. The export bundles these compiled files in the PCK
3. `LocalizationSettings._load_translations()` loads them at runtime via `load()`
4. `TranslationServer.set_locale("ru")` triggers Godot's auto-translate on all Control nodes

---

## Solution

1. **Load compiled `.translation` binary files** in `localization_settings.gd`:
   - Use `load("res://resources/translations/translations.en.translation")` and `.ru.translation`
   - Register with `TranslationServer.add_translation()`
   - Remove the raw CSV `FileAccess` approach (CSV is not in the exported PCK)

2. **Add `locale/translations`** to `project.godot`:
   - `locale/translations=PackedStringArray("res://resources/translations/translations.csv")`
   - Tells Godot to import the CSV and produce compiled `.translation` files during build/export

3. **ESC support** in `language_menu.gd` (already fixed in previous session):
   - `_unhandled_input(event)` matching the pattern in other sub-menu scripts

---

## Attached Artifacts

- `game_log_20260329_164616.txt` — Full game log from the owner's first test session on 2026-03-29
- `game_log_20260329_172217.txt` — Full game log from the owner's second test session on 2026-03-29
- `game_log_20260329_175132.txt` — Full game log from the owner's third test session on 2026-03-29
- `game_log_20260329_181610.txt` — Full game log from the owner's fourth test session on 2026-03-29

---

## Fourth Report: Armory untranslated, level descriptions untranslated, Black Metal name issue, difficulty not refreshing (2026-03-29 18:16)

After the third fix (compiled `.translation` files loaded), translation now works. The owner tested with `game_log_20260329_181610.txt` and reported:

1. **"перевод включается, но не переведено ничего в armory"** — "translation works, but nothing in armory is translated (should be translated including tooltips)"
2. **"не переведено описание уровней"** — "level descriptions are not translated"
3. **"не надо переводить сложность black metal"** — "do not translate 'Black Metal' difficulty (keep it as English)"
4. **"сразу после переключения языка сложности не переводятся"** — "difficulty labels don't update immediately after switching language"

### Analysis of fourth game log (18:16:10)

The fourth log confirms translations ARE working now:
```
[LocalizationSettings] Loaded 2 translation(s)
[LocalizationSettings] LocalizationSettings initialized — locale: ru
[LocalizationSettings] Locale changed to: en
[LocalizationSettings] Locale changed to: ru
```

This is the first time `Loaded 2 translation(s)` appears — translations load correctly. However only the pause/settings menus had translation keys; armory and levels menu were not translated.

### Root Causes (Session 4)

**Bug 6: Armory not translated**

The armory menu builds its UI programmatically from `FIREARMS`, `GRENADE_DATA`, and `ACTIVE_ITEM_DATA` dictionaries. These dictionaries contained hardcoded English `name` and `description` strings. The `_create_item_slot()` and `_create_active_item_slot()` functions read these strings directly without calling `tr()`.

The level descriptions in `levels_menu.gd` similarly used a hardcoded `"description"` field and always displayed the Russian name via `name_ru` regardless of current locale.

**Bug 7: Black Metal stays "Black Metal" in Russian**

"Black Metal" is a proper music genre/band name (like "Heavy Metal") — an English loanword that is not transliterated in Russian music culture. The CSV had `BLACK_METAL,Black Metal,Блэк Метал` which wrongly transliterated it to Cyrillic.

**Bug 8: Difficulty menu doesn't refresh on locale change**

`difficulty_menu.gd` calls `_update_button_states()` which uses `tr()` correctly, but it was only connected to `difficulty_changed` and `settings_changed` signals — not to `locale_changed`. Switching language while the difficulty menu was open didn't trigger a refresh.

### Fixes (Session 4)

1. **Translation keys for armory**: Added `name_key`/`desc_key` fields to all `FIREARMS` entries in `armory_menu.gd`, all `GRENADE_DATA` entries in `grenade_manager.gd`, and all `ACTIVE_ITEM_DATA` entries in `active_item_manager.gd`. Updated all slot-building code to use `tr(name_key)` when available.

2. **Translation keys for levels**: Added `name_key`/`desc_key` fields to all LEVELS entries in `levels_menu.gd`. Updated display logic to use `tr(name_key)` for level names (replacing the `name_ru` hack) and `tr(desc_key)` for descriptions. Also removed hardcoded `"PLAYING"` / locked/tooltip texts.

3. **Black Metal as proper noun**: Updated `translations.csv` — `BLACK_METAL,Black Metal,Black Metal` and `DIFFICULTY_STATUS_BLACK_METAL` Russian value now reads `"Black Metal: ..."` instead of `"Блэк Метал: ..."`.

4. **Difficulty menu locale refresh**: Added `locale_changed` signal connection in `difficulty_menu._ready()` that calls `_update_button_states()`, so button labels immediately update when language switches.

5. **Full translation CSV**: Added ~150 new translation keys covering all armory items (8 weapons, 5 grenades, 21 active items), all 14 levels, and UI strings for the armory and levels menus.
