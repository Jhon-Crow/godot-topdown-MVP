# Case Study: Issue #1808 - Shotgun Counter Starts At Zero

## Summary

**Issue:** [#1808](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1808) - `fix счётчик дробовика`

**Affected maps:** Building, Labyrinth Complex, Labyrinth2, and any persisted startup path that lands on `TestTier`

**Reported behavior:** when the player starts with the shotgun, the HUD shows `0` loaded shells before the first shot, even though the shotgun is actually loaded with `8`. After the first shot, the counter becomes correct and continues updating normally.

## Collected Artifacts

- `issue.txt` - saved issue body
- `issue-1808-screenshot.png` - screenshot from the issue
- `game_log_20260411_015626.txt` - original runtime log from the report
- `game_log_20260416_023550.txt` - latest owner repro log showing persisted startup navigation and remaining `Labyrinth2` startup failures
- `issue-1808-comment-4256398298.png` - latest owner screenshot showing `0/8` on startup

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

In each affected level script:

1. the level connects to the shotgun's `ShellCountChanged` signal
2. the initial HUD value is still read from `CurrentAmmo`
3. `CurrentAmmo` is `0` at startup for the shotgun
4. only after the first shot does `ShellCountChanged` fire and correct the HUD

So the bug is not in the ongoing counter update logic. It is an initialization bug in the first HUD push.

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

This keeps the patch minimal and aligned with the existing shotgun runtime update path.

## Test Coverage

Added unit coverage in:

- `tests/unit/test_level_scripts.gd`

The new tests demonstrate both states:

1. old startup behavior shows `AMMO: 0/8` when using `CurrentAmmo`
2. fixed startup behavior shows `AMMO: 8/8` when using `ShellsInTube`

Coverage was added for Building, Labyrinth, Labyrinth2, and TestTier.

## Online / External Facts

No external web facts were needed to identify the fault. The issue was fully explained by:

- the owner report
- the attached screenshot
- the attached runtime log
- the local level-script code

## Outcome

The HUD now receives the correct initial shotgun ammo state before the first shot on the affected maps, on `Labyrinth2`, and on the persisted startup path that reaches `TestTier`, while the existing `ShellCountChanged` path continues handling subsequent updates.
