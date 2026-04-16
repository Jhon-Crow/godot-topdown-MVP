# Issue #1821: Building Map Out-of-Ammo Message Missing

## Summary
The out-of-ammo message does not appear on `BuildingLevel` when the player has no bullets left and enemies are still alive.

## Evidence Collected
- User report in issue #1821 and PR #1848 comment on 2026-04-16.
- Runtime log downloaded to `docs/case-studies/issue-1821/game_log_20260416_025902.txt`.
- Existing branch fix in `scripts/levels/building_level.gd`.
- Fallback initialization path in `Scripts/Components/LevelInitFallback.cs`.

## Timeline Reconstruction
All timestamps below come from `game_log_20260416_025902.txt`.

1. `02:59:03`:
   `PersistManager` navigates to `res://scenes/levels/BuildingLevel.tscn`.
2. `02:59:03`:
   `SceneLoader` reports `Invalid resource (falling back to sync)` for `BuildingLevel`.
3. `02:59:03`:
   `LevelInitFallback` configures Building-level camera limits, confirming the C# fallback path is active.
4. `02:59:20`:
   The player equips `m16`, and `LevelInitFallback` applies Building ammo config:
   `BuildingLevel: AssaultRifle magazines reinitialized to 2`.
5. `02:59:31`:
   Enemies receive `Player ammo empty: false -> true` for all remaining enemies.
6. `02:59:31` to `02:59:33`:
   Repeated enemy logs show the player is marked vulnerable because ammo is empty.
7. Missing event:
   There is no log or UI event corresponding to the Building-level game-over/out-of-ammo message, even though enemies remain alive.

## Root Cause
There are two relevant Building-level implementations:

1. `scripts/levels/building_level.gd`
   This path was already fixed to show the game-over message on `AmmoDepleted` by reading `CurrentWeapon.CurrentAmmo` and `CurrentWeapon.ReserveAmmo` directly.

2. `Scripts/Components/LevelInitFallback.cs`
   This fallback path still handled `OnPlayerAmmoDepleted()` by only:
   - broadcasting `set_player_ammo_empty(true)` to enemies
   - emitting the empty-click sound

When the game initializes Building through `LevelInitFallback` instead of the GDScript level logic, the fallback never checks whether the equipped weapon is actually at `0/0`. As a result:

- enemies correctly switch into `ammo_empty` behavior
- the player is effectively out of ammo
- the out-of-ammo message is never shown

The user log matches exactly this failure mode.

## Fix Implemented
Updated `Scripts/Components/LevelInitFallback.cs` so `OnPlayerAmmoDepleted()` now mirrors the fixed GDScript behavior:

- if enemies remain and game-over was not already shown
- read `_player.CurrentWeapon`
- read weapon `CurrentAmmo` and `ReserveAmmo`
- call `ShowGameOverMessage()` when both are `<= 0`

## Test Coverage
Added focused unit coverage in `tests/unit/test_level_scripts.gd` for the fallback-specific behavior:

- show game-over when fallback sees `0/0` ammo
- do not show game-over when reserve ammo remains

## Additional Notes
- Local execution of the focused GUT suite was attempted with the bundled Godot binary, but the engine aborted before producing test output in this environment.
- The change is still low-risk because it only adds the same ammo-depletion guard already used in `building_level.gd`, scoped to the fallback path that the user log proves is active.

## Possible Follow-Ups
1. Add a dedicated `LevelInitFallback` unit test file instead of mirroring the behavior in the broader level test suite.
2. Add an explicit fallback log line when `ShowGameOverMessage()` is triggered from `OnPlayerAmmoDepleted()` to make future field logs easier to diagnose.
