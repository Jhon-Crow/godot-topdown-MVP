# Issue 1945 Case Study: Ammo HUD Stuck On Makarov PM

## Summary

The issue report said the ammo counter showed the same value for every selected weapon, changed only for Makarov PM, and reproduced on Decadence, Double Corridor, and Sewer. The attached screenshot shows the HUD stuck at `Ammo: 9 / 81` with `Mag: -`, which matches a configured Makarov PM rather than the selected weapon.

All issue attachments were downloaded into `docs/case-studies/issue-1945/artifacts/`:

- `ammo-counter-screenshot.png`
- `game_log_20260503_224814.txt`
- `game_log_20260503_225402.txt`
- `game_log_20260503_225541.txt`
- `raw/game_log_20260503_233150.txt`

## Evidence From Logs

All three logs were produced by build branch `issue-1943-fdf0cabf3a9c`, commit `1c60c46fcbb1e6628bbb51b28104257df49c8508`, build date `2026-05-03T16:35:12Z`.

Decadence (`game_log_20260503_224814.txt`) repeatedly configures the Makarov PM before the selected weapon is applied. For example:

- Line 414: `DecadenceLevel` configures Makarov PM ammo to 10 magazines.
- Lines 512 and 520: `Player.Weapon` then applies `m16` and equips `AssaultRifle`.
- Lines 6802, 6900, and 6908 show the same ordering for `mini_uzi`.
- Lines 2735, 2761, and 2833 show the Makarov PM path, which explains why PM appeared to be the only weapon with correct HUD behavior.

Double Corridor (`game_log_20260503_225402.txt`) shows:

- Line 200: Labyrinth startup HUD refreshes Makarov PM as `9/351`.
- Line 463: weapon hints connect to `makarov_pm`.
- Lines 935 and 943: the selected weapon later becomes `mini_uzi` and equips as `MiniUzi`.

Sewer (`game_log_20260503_225541.txt`) shows:

- Lines 433 and 434: `SewerLevel` configures Makarov PM ammo.
- Lines 531 and 539: the selected `mini_uzi` is applied and equipped afterward.

Follow-up City report (`raw/game_log_20260503_233150.txt`) shows the same race on a map that was not included in the first patch:

- Line 98: `GameManager` selects `ak_gl`.
- Lines 872 and 880: the City player and `CityLevel` initialize.
- Lines 950-959: the deferred player weapon application removes `MakarovPM`, instantiates `AKGL`, and equips it as `30/30`.
- There is no `CityLevel` HUD refresh for `AKGL` in that log, which matches the owner's report that the counter failed on City after the first fix.

## Root Cause

The affected GDScript level scripts connected the HUD to child weapon nodes during the parent level `_ready()` path. At that moment the player still had the startup Makarov PM child available. The C# `Player` then applied the selected weapon through `CallDeferred(MethodName.ApplySelectedWeaponFromGameManager)`, removed the startup weapon, and equipped the selected weapon.

Official Godot lifecycle docs explain the ordering that makes this possible:

- Godot calls child `_ready()` callbacks before parent `_ready()` callbacks, so `Player._Ready()` can queue its deferred selected-weapon application before the level script runs.
- `Object.call_deferred()` runs the method during idle time, mainly after process and physics frames.
- `Object.get()` returns `null` for a missing property, which makes checking `CurrentWeapon` safe on compatible and fallback player nodes.
- Godot signal connection docs warn that connecting the same signal/callable twice is invalid unless guarded, so the fix checks `is_connected()` before connecting.

Sources:

- https://docs.godotengine.org/en/stable/classes/class_node.html
- https://docs.godotengine.org/en/stable/classes/class_object.html#class-object-method-call-deferred

## Fix

The affected levels now use the same ammo HUD selection model:

1. Prefer `Player.CurrentWeapon` as the authoritative equipped weapon.
2. If `CurrentWeapon` is not ready, fall back to the selected weapon ID from `GameManager`.
3. Only then probe child weapon nodes as a compatibility fallback.
4. Connect ammo, magazine, fired, and shell signals only when not already connected.
5. Schedule a deferred refresh so the HUD rebinds after the C# selected-weapon application runs.
6. Refresh the HUD from the selected weapon, including the shotgun `ShellsInTube` special case.

Touched levels:

- `scripts/levels/decadence_level.gd`
- `scripts/levels/city_level.gd`
- `scripts/levels/revolver_level.gd`
- `scripts/levels/sewer_level.gd`

## Regression Coverage

Added unit coverage for the three reported maps:

- `tests/unit/test_city_level.gd`
- `tests/unit/test_decadence_level.gd`
- `tests/unit/test_revolver_level.gd`
- `tests/unit/test_sewer_level.gd`

Each test models the reported failure mode: an initial stale Makarov PM HUD update followed by a deferred refresh from the final selected weapon. Source-level assertions also verify that each affected script now reads `Player.CurrentWeapon` and schedules the deferred HUD refresh.

## CI Follow-Up

The first CI pass after the City follow-up reached head `b5dd750943aa517c8bff8b1be8829e34072c283a`. GUT, C# validation, GDScript compilation, lint, architecture, interoperability, and gameplay validation passed. Windows Export failed before project export because the workflow's download step returned `ERROR 502: Bad Gateway or Proxy Error`; the downloaded log is preserved as `raw/windows-export-25290161684.log`.
