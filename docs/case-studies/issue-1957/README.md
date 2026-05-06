# Issue 1957 Case Study: Weapon Tutorial Hint Localization And Building Map Wiring

## Source Data

- Issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1957
- Reporter log: `game_log_20260506_142618.txt`
- Extracted key lines: `log-key-lines.txt`
- Local build log: `dotnet-build.log`

## Timeline Reconstructed From Log

- 14:26:18 UTC: Game starts on `LabyrinthLevel`; `LocalizationSettings` loads 2 translations and initializes locale `en`.
- 14:26:59 UTC: Player selects `m16`; Labyrinth reloads and configures `m16`.
- 14:28:28 UTC: Player switches to `BuildingLevel`.
- 14:28:29 UTC: `WeaponHintsComponent` auto-sets up from exported NodePaths but logs `Weapon node not found on player for: m16 - hints not connected to actions` before `Player.Weapon` finishes selecting `m16`.
- 14:28:29-14:29:15 UTC: The same Building pattern repeats across restarts, so weapon-specific hints cannot connect to `Fired`, `ReloadCompleted`, `FireModeChanged`, `ScopeStateChanged`, or `HammerCocked` signals.

## Root Causes

1. Labyrinth tutorial hints still hardcoded Russian RMB/action text in several weapon-specific builders. Even with locale `en`, strings such as `ПКМ`, `R открыть`, and Russian M16 fire-mode text bypassed translation keys.
2. Regular-map `WeaponHintsComponent` looked up weapon nodes only by scene children. On Building, the component auto-setup can run before C# weapon setup finishes, and stale/missing child lookup leaves hints disconnected from the active `Player.CurrentWeapon`.

## Implemented Fix

- Labyrinth weapon tutorial strings now use existing translation keys for shotgun, revolver, M16, scope, hammer-cock, and AK GL launcher hints.
- `WeaponHintsComponent` now prefers the authoritative `Player.CurrentWeapon` when it matches the selected weapon id, then falls back to child-node lookup.
- Regular-map shotgun pump hints now use translation keys instead of hardcoded Russian RMB fragments.
- Regression tests cover English-locale translation key usage and the Building stale-child/current-weapon lookup path.

## Verification

- `dotnet build` succeeded; warnings are existing project warnings and are preserved in `dotnet-build.log`.
- Static search confirms production hint scripts touched by this fix no longer contain hardcoded Russian RMB/action fragments.
- GUT tests could not be run locally because this workspace does not provide a `godot` executable on PATH.
