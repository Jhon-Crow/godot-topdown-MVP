# Issue 1823 case study

## Timeline
- 2026-04-15T23:51:47Z: PR branch `issue-1823-08a665283274` triggered CI runs for commit `44e7e02f84d98243f625bb1d3e1a4ba292a06c88`.
- 2026-04-16T00:04:16Z: PR comment reported three gameplay regressions on maps `Building`, `Labyrinth`, and `Labyrinth Complex`, attached runtime log `game_log_20260416_030116.txt`, and noted unit tests in CI appearing to run forever.
- 2026-04-16: local analysis pulled the attached log and current CI metadata into `docs/case-studies/issue-1823/`.

## Runtime findings
- The previous implementation in `scripts/components/weapon_hints_component.gd` showed the grenade hint only while `grenade_prepare` was held.
- That behavior does not match the existing tutorial implementations in `scripts/levels/tutorial_level.gd` and `scripts/levels/labyrinth_level.gd`, where the grenade hint persists across the full arm -> aim -> throw sequence and is dismissed only on `grenade_thrown`.
- The attached runtime log shows a session transitioning from `LabyrinthLevel` into `BuildingLevel`, confirming the report is about generic level weapon hints rather than only the dedicated tutorial map.

## Root cause
- `WeaponHintsComponent` polled `Input.is_action_pressed("grenade_prepare")` and dismissed the hint immediately on release.
- `WeaponHintsComponent` did not connect to the player's `grenade_thrown` / `GrenadeThrown` signal, so it had no way to dismiss on the actual completed throw.
- The added unit tests covered only show-on-press and dismiss-on-release behavior, so they locked in the wrong behavior instead of the tutorial-consistent flow.
- The grenade hint path was additionally gated on `_current_weapon_id == "m16"`, which made the behavior brittle on regular levels where the active weapon-hint lifecycle was running but the selected-weapon routing did not match that exact ID during the reported map flows.

## Fix direction implemented locally
- Mirror the tutorial grenade hint state machine in `WeaponHintsComponent`.
- Keep the grenade hint visible after `grenade_prepare` is released.
- Advance hint text/strikethrough through the same step progression used by tutorial code.
- Dismiss the hint only when the player emits `grenade_thrown`.
- Remove the hard-coded `"m16"` gate so the generic weapon hints component can show the grenade tutorial sequence on the affected non-tutorial maps.
- Update unit tests to assert persistence-until-throw, clear input state between tests, and cover the non-`m16` regression.

## CI status at investigation time
- Current head SHA: `44e7e02f84d98243f625bb1d3e1a4ba292a06c88`.
- Non-passing run observed: Actions run `24484363556` was still `in_progress` when inspected.
- The only active step was `Run GUT tests`, started at `2026-04-15T23:52:42Z`.
- `gh run view --log` still returned exit code `1` while the job was active, so the exact hang point could not yet be extracted; placeholder output was preserved in `ci-logs/run-gut-24484363556.log`.

## Next CI follow-up
- Re-check run `24484363556` after completion and download the final log into `ci-logs/`.
- If it still hangs, inspect whether the new input-driven tests need explicit signal/timer settlement in headless GUT.
