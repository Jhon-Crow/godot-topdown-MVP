# Analysis

## Timeline

- 2026-04-11 11:31:27 UTC: owner comment on the issue asked to retry.
- 2026-04-11 13:25:50 local log timestamp: owner-provided gameplay log starts.
- 2026-04-11 13:25:52 local log timestamp: localization settings initialize with locale `ru`.
- 2026-04-11 13:25:53 local log timestamp: `LabyrinthLevel` loads with selected weapon `ak_gl`.
- 2026-04-16 00:45:10 UTC: owner reports that everything is fixed except Building still has no tutorial hints.
- 2026-04-16 00:49:16 UTC: PR branch commit `9c005143` adds `LevelInitFallback` weapon-hints setup for Building.
- 2026-04-16 07:05:14 UTC: owner reports the latest tested build still has no Building tutorial hints and attaches `game_log_20260416_100413.txt`.
- 2026-04-16 10:04:33 local log timestamp: the attached build loads `BuildingLevel`, runs `LevelInitFallback`, logs replay setup, then immediately logs `GDScript properties synced` without any weapon-hints setup log line.

## Root Cause Notes

### 1. Labyrinth tutorial text localization drift

`labyrinth_level.gd` mirrors tutorial hint behavior locally, but several user-visible strings are still embedded directly in Russian:

- hammer-cock hint
- scope hint
- grenade launcher hint path
- grenade throw hint builder
- reload helper builders

Because those strings bypass `tr(...)`, switching to English cannot affect them.

### 2. Factory missing shared weapon-hints hookup

`building_level.gd` already wires in the shared `weapon_hints_component`, which is the mechanism used on non-tutorial combat maps to show weapon onboarding text.

`factory_level.gd` did not instantiate or set up that component, so Factory never created the expected tutorial lines. The issue report grouped Building and Factory together, but the current branch state shows Building already had the hookup and Factory was the missing piece.

### 3. Building exported-build fallback path

The April 16 runtime log confirms that `BuildingLevel` uses `LevelInitFallback` in the tested export because the GDScript `_ready()` method does not execute. That fallback path must create the shared `WeaponHintsComponent`; otherwise the GDScript-level `_setup_weapon_hints()` method is bypassed.

Current branch code now calls `SetupWeaponHints(levelRoot)` before `SyncGDScriptProperties(levelRoot)`. The April 16 log does not include the expected `Weapon hints component added and setup` message before `GDScript properties synced`, which means the attached test build did not contain the current fallback fix or was built from a commit before `9c005143`.

## Proposed Fix Shape

1. Replace remaining hardcoded tutorial strings with translation-backed builders.
2. Ensure Factory initializes the same shared weapon hints component already used on Building and other combat maps.
3. Add tests that lock:
   - English locale must not show Russian tutorial text on Labyrinth.
   - Building and Factory level scripts must keep the shared weapon hints wiring in place.
   - `LevelInitFallback.cs` must initialize `WeaponHintsComponent` before syncing Building GDScript properties.
