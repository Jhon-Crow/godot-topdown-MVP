# Issue 1817 Case Study

## Scope

Issue [#1817](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1817) started as a tutorial-line reset bug. Follow-up feedback on PR [#1843](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1843) expanded the scope:

- shotgun full-reload tutorial was completing when the player only opened and closed the action
- grenade tutorial was advancing after repeated `G` presses instead of only after the real grenade state machine progressed

## Collected Data

- Owner reproduction log: [game_log_20260416_021623.txt](./game_log_20260416_021623.txt)
- Relevant code: `scripts/levels/labyrinth_level.gd`
- Regression tests: `tests/unit/test_labyrinth_grenade_tutorial.gd`

## Timeline

1. April 15, 2026: original issue reported for canceled tutorial combinations not resetting.
2. April 15, 2026 22:22:58 UTC: owner reported two remaining failures on PR #1843.
3. April 15, 2026 23:17:51 UTC: owner confirmed the PR still did not work and attached `game_log_20260416_021623.txt`.

## Findings

The attached log is mostly startup telemetry. It confirms the reproduction environment:

- Windows build, Godot 4.3 stable
- tutorial sessions were entered multiple times
- grenade/tutorial systems were active, but the log does not include per-step tutorial state transitions

Because the log lacks tutorial-specific state tracing, the root cause had to be confirmed from code paths and regression tests rather than from the attachment alone.

## Root Causes

### 1. Grenade tutorial trusted raw input instead of the real grenade state

In `scripts/levels/labyrinth_level.gd`, `_update_tutorial_grenade_hint_step()` had a fallback path that advanced the hint when `grenade_prepare` and `grenade_throw` inputs were held together, even if the player grenade state machine had not entered `WAITING_FOR_G_RELEASE`.

Result:

- repeated `G` presses or partial input sequences could move the tutorial to later steps
- releasing inputs before the grenade actually armed did not always roll the hint back correctly

### 2. Shotgun tutorial completion inferred progress from strikethrough state

`_on_tutorial_shotgun_reload_state_changed()` treated `ReloadStateChanged(0)` as a successful completion when the hint strikethrough had advanced far enough. That is an indirect signal and can be wrong for canceled reload flows.

Result:

- opening and closing the shotgun without entering the shell-loading phase could still complete the tutorial

## Solution Direction

- Drive grenade tutorial progression strictly from the player grenade state machine (`WAITING_FOR_G_RELEASE`, `AIMING`, `IDLE`).
- Track whether shotgun reload actually entered the loading phase before allowing `ReloadStateChanged(0)` to complete the tutorial.
- Keep regression coverage for both canceled and completed flows.

## Additional Data Needed

For future debugging, add optional tutorial debug logs behind a disabled-by-default flag:

- grenade tutorial step changes with current grenade state
- shotgun reload tutorial transitions with `ReloadStateChanged` values
- explicit reset/completion reasons
