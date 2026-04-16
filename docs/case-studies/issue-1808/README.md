# Case Study: Issue #1808 - Shotgun Counter Starts At Zero

## Summary

**Issue:** [#1808](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1808) - `fix счётчик дробовика`

**Affected maps:** Building, Labyrinth Complex, Labyrinth2, and any persisted startup path that lands on `TestTier`

**Reported behavior:** when the player starts with the shotgun, the HUD shows `0` loaded shells before the first shot, even though the shotgun is actually loaded with `8`. After the first shot, the counter becomes correct and continues updating normally.

## Collected Artifacts

- `issue.txt` - saved issue body
- `issue-1808-screenshot.png` - screenshot from the issue
- `game_log_20260411_015626.txt` - original runtime log from the report
- `issue-1808-comment-4256398298.png` - latest owner screenshot showing `0/8` on startup
- `issue-1808-comment-20260416-023550.png` - owner screenshot showing `AMMO: 0/84`
- `logs/game_log_20260416_000103.txt` - owner follow-up showing Building and Labyrinth Complex still at `0`
- `logs/game_log_20260416_012901.txt` - owner follow-up from the next build with the same symptom
- `logs/game_log_20260416_023550.txt` - owner repro log showing persisted startup navigation and remaining `Labyrinth2` startup failures
- `logs/game_log_20260416_095403.txt` - owner follow-up showing Building still at `0` for shotgun and Labyrinth Complex HUD counters broken
- `logs/game_log_20260416_101928.txt` - owner follow-up showing the C# player equips shotgun as `0/8`, then level scripts take the already-equipped early-return path
- `logs/game_log_20260416_192552.txt` - latest owner follow-up showing `LabyrinthLevel` refreshes shotgun HUD correctly, while `BuildingLevel` and `Labyrinth2Level` do not reach their level HUD setup before the user leaves the map

## Timeline

### 2026-04-11 01:56:26 UTC

The attached game log starts in `LabyrinthLevel` with shotgun selected.

### 2026-04-11 01:56:27 UTC

The player equips the shotgun and the log records:

- `Equipped Shotgun (ammo: 0/8)`
- `Player] Ready! Ammo: 0/8`

This confirms the startup state is wrong before any shot is fired.

### After first shot

The issue report states the HUD becomes correct after the first shot, which matches the code path where `ShellCountChanged` starts driving the display.

## Root Cause

The shotgun does not use `CurrentAmmo` as its authoritative loaded-ammo value for the HUD startup path. It uses `ShellsInTube`.

The latest owner repro also showed that the game can start in `LabyrinthLevel` and then immediately auto-navigate to the saved last-played level through `PersistManager`. In the attached `2026-04-16 02:35:50 UTC` log, startup enters `LabyrinthLevel`, then redirects to `res://scenes/levels/csharp/TestTier.tscn`, and the user later selects the shotgun there.

That means the bug was broader than the first patch assumed: it was not enough to fix only Building/Labyrinth if the persisted startup flow could land on another level script that still initialized shotgun HUD ammo from `CurrentAmmo`.

The same log later shows `Player.Weapon] Equipped Shotgun (ammo: 0/8)` immediately after entering `Labyrinth2Level`, which exposed another unfixed level-specific startup path.

### 2026-04-16 09:54:03 UTC

The latest owner log confirms a broader HUD binding problem. The level scripts were still finding the weapon by probing player child nodes in a fixed order. That is fragile because the C# `Player` exposes the authoritative equipped weapon as `CurrentWeapon`; stale or transitional child nodes can remain visible during setup and cause the HUD to connect to or initialize from the wrong node.

This explains both remaining symptoms:

- Building can still show `0` for shotgun if the startup HUD path binds to a stale or incompletely initialized child instead of the equipped shotgun's `ShellsInTube`.
- Labyrinth Complex can have enemy/ammo HUD counters appear broken when level setup follows the wrong weapon node path and skips the actual current weapon state.

In each affected level script:

1. the level connects to the shotgun's `ShellCountChanged` signal
2. the initial HUD value is still read from `CurrentAmmo`
3. `CurrentAmmo` is `0` at startup for the shotgun
4. only after the first shot does `ShellCountChanged` fire and correct the HUD
5. the script can choose the wrong weapon node before it even reaches the shotgun-specific display helper

So the bug is not in the ongoing counter update logic. It is an initialization/binding bug in the first HUD push.

### 2026-04-16 10:19:28 UTC

The newest owner log narrowed the remaining failure further. It shows this order on startup:

1. `Player.Weapon] Equipped Shotgun (ammo: 0/8)`
2. `Player] Ready! Ammo: 0/8`
3. `LabyrinthLevel] Shotgun already equipped by C# Player - applying labyrinth ammo config`

The same sequence repeats after persisted navigation to `BuildingLevel` and after manual navigation to `Labyrinth2Level`.

The previous fix made startup display helpers read `ShellsInTube`, but the level ammo config functions only refreshed the HUD inside selected weapon branches. For `shotgun`, those functions intentionally do not reinitialize magazines, so the "already equipped by C# Player" early-return path could apply no branch-specific refresh and leave the HUD at the C# player's initial `CurrentAmmo`-based `0/8` display.

### 2026-04-16 19:25:52 UTC

The latest owner log changes the diagnosis. `LabyrinthLevel` now reaches the expected post-config refresh:

- `HUD ammo refreshed (post level ammo config): Shotgun 8/28`

The same log then enters `BuildingLevel` and `Labyrinth2Level`, and both scenes show the C# player ready with:

- `Player.Weapon] Equipped Shotgun (ammo: 0/8)`
- `Player] Ready! Ammo: 0/8`

However, neither scene emits the expected level-script setup logs before the owner navigates away. `BuildingLevel` has no `Found Environment/Enemies`, `Setting up weapon`, or `HUD ammo refreshed` lines. `Labyrinth2Level` similarly has no level counter/HUD setup lines. Both scripts were running `_setup_navigation()` before enemy tracking and player/HUD tracking. On the larger maps, the navigation parse/bake can delay the rest of `_ready()`, leaving visible HUD counters at their default C# startup state during the first seconds of the level.

## Code Evidence

Affected files:

- `scripts/levels/building_level.gd`
- `scripts/levels/labyrinth_level.gd`
- `scripts/levels/labyrinth2_level.gd`
- `scripts/levels/test_tier.gd`

All four scripts had the same startup pattern:

- connect `ShellCountChanged`
- call `_update_ammo_label_magazine(weapon.CurrentAmmo, weapon.ReserveAmmo)`

That is valid for magazine-fed weapons, but wrong for the shotgun.

## Fix

For shotgun startup only, initialize the HUD from:

- `ShellsInTube`
- `ReserveAmmo`

All other weapons keep using:

- `CurrentAmmo`
- `ReserveAmmo`

The level scripts now also use `Player.CurrentWeapon` first when binding HUD signals and pushing the initial HUD state. Child-node probing remains only as a fallback by selected weapon id. This prevents stale child nodes from overriding the actual equipped weapon.

The affected level ammo config functions now also perform an unconditional post-config HUD refresh through a shared helper. This matters for the C# pre-equipped shotgun path because shotgun does not enter the magazine-reinitialization branches, but it still must push `ShellsInTube/ReserveAmmo` to the HUD after the early-return config path.

Labyrinth and Labyrinth2 now find `CanvasLayer/UI/AmmoLabel` before selected weapon setup, matching Building's ordering, so config-time HUD refreshes cannot silently no-op because the label reference has not been initialized yet.

The final fix also moves navigation baking behind the critical startup work on Building, Labyrinth, Labyrinth2, and TestTier. Enemy tracking, enemy labels, player tracking, weapon setup, and the first shotgun HUD refresh now complete before `_setup_navigation` is deferred. This preserves the Issue #1289 navmesh bake, but prevents expensive navigation work from blocking first-frame counters on large maps.

## Test Coverage

Added unit coverage in:

- `tests/unit/test_level_scripts.gd`

The new tests demonstrate both states:

1. old startup behavior shows `AMMO: 0/8` when using `CurrentAmmo`
2. fixed startup behavior shows `AMMO: 8/8` when using `ShellsInTube`

Coverage was added for Building, Labyrinth, Labyrinth2, and TestTier.

Additional regression tests cover stale child-node selection:

1. Building uses the equipped shotgun from `CurrentWeapon` even if another weapon child exists.
2. Labyrinth2 uses the equipped non-shotgun weapon from `CurrentWeapon` even if a stale shotgun child exists.

Additional regression tests now cover the C# pre-equipped shotgun path on Building, Labyrinth, and Labyrinth2. These tests model the newest log sequence where `CurrentAmmo` is `0`, `ShellsInTube` is `8`, and the level must still push `AMMO: 8/8` during setup.

Additional regression tests read the real level scripts and assert that Building, Labyrinth, Labyrinth2, and TestTier initialize enemy/player HUD counters before scheduling navigation setup. This protects the specific 2026-04-16 19:25 failure mode where the level scene loaded but the level script had not reached HUD setup before the visible `0/8` state was observed.

## Online / External Facts

No external web facts were needed to identify the fault. The issue was fully explained by:

- the owner report
- the attached screenshot
- the attached runtime log
- the local level-script code

## Outcome

The HUD now receives the correct initial shotgun ammo state before the first shot on the affected maps, on `Labyrinth2`, and on the persisted startup path that reaches `TestTier`, while the existing `ShellCountChanged` path continues handling subsequent updates. HUD setup is also bound to the actual equipped C# weapon, and critical HUD/enemy counters are initialized before deferred navmesh baking can consume startup time on larger maps.
