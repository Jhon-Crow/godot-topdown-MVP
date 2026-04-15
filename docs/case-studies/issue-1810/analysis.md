# Analysis

## Timeline

- 2026-04-11 11:31:27 UTC: owner comment on the issue asked to retry.
- 2026-04-11 13:25:50 local log timestamp: owner-provided gameplay log starts.
- 2026-04-11 13:25:52 local log timestamp: localization settings initialize with locale `ru`.
- 2026-04-11 13:25:53 local log timestamp: `LabyrinthLevel` loads with selected weapon `ak_gl`.

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

## Proposed Fix Shape

1. Replace remaining hardcoded tutorial strings with translation-backed builders.
2. Ensure Factory initializes the same shared weapon hints component already used on Building and other combat maps.
3. Add tests that lock:
   - English locale must not show Russian tutorial text on Labyrinth.
   - Building and Factory level scripts must keep the shared weapon hints wiring in place.
