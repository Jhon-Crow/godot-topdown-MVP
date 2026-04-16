# Issue 1823 case study

## Timeline
- 2026-04-15T23:51:47Z: PR branch `issue-1823-08a665283274` triggered CI runs for commit `44e7e02f84d98243f625bb1d3e1a4ba292a06c88`.
- 2026-04-16T00:04:16Z: PR comment reported three gameplay regressions on maps `Building`, `Labyrinth`, and `Labyrinth Complex`, attached runtime log `game_log_20260416_030116.txt`, and noted unit tests in CI appearing to run forever.
- 2026-04-16: local analysis pulled the attached log and current CI metadata into `docs/case-studies/issue-1823/`.

## Runtime findings
- The previous implementation in `scripts/components/weapon_hints_component.gd` showed the grenade hint only while `grenade_prepare` was held.
- That behavior does not match the existing tutorial implementations in `scripts/levels/tutorial_level.gd` and `scripts/levels/labyrinth_level.gd`, where the grenade hint persists across the full arm -> aim -> throw sequence and is dismissed only on `grenade_thrown`.
- The attached runtime log shows a session transitioning from `LabyrinthLevel` into `BuildingLevel`, confirming the report is about generic level weapon hints rather than only the dedicated tutorial map.
- Follow-up feedback clarified the final expected behavior: generic weapon hints should not be visible at level start, should appear only after pressing `G`, should then stay until the grenade is thrown, and Labyrinth should keep its normal built-in tutorial behavior unchanged.

## Root cause
- `WeaponHintsComponent` polled `Input.is_action_pressed("grenade_prepare")` and dismissed the hint immediately on release.
- `WeaponHintsComponent` did not connect to the player's `grenade_thrown` / `GrenadeThrown` signal, so it had no way to dismiss on the actual completed throw.
- The added unit tests covered only show-on-press and dismiss-on-release behavior, so they locked in the wrong behavior instead of the tutorial-consistent flow.
- The grenade hint path was additionally gated on `_current_weapon_id == "m16"`, which made the behavior brittle on regular levels where the active weapon-hint lifecycle was running but the selected-weapon routing did not match that exact ID during the reported map flows.
- A later implementation made the generic component add the grenade hint as soon as hints were active and the player had grenades. That fixed visibility on more maps, but caused the newest owner-reported regression: the generic hint was shown initially before `G`.

## Fix direction implemented locally
- Mirror the tutorial grenade hint state machine in `WeaponHintsComponent`.
- Keep the grenade hint visible after `grenade_prepare` is released.
- Advance hint text/strikethrough through the same step progression used by tutorial code.
- Dismiss the hint only when the player emits `grenade_thrown`.
- Remove the hard-coded `"m16"` gate so the generic weapon hints component can show the grenade tutorial sequence on the affected non-tutorial maps.
- Gate the first generic grenade hint display on `Input.is_action_pressed("grenade_prepare")`, so regular maps do not show the hint at spawn.
- Update unit tests to assert no initial generic hint before `G`, persistence-until-throw, clear input state between tests, and cover the non-`m16` regression.

## CI status at investigation time
- Current head SHA before this follow-up: `1de1ac1845199c70a2f0bc9f9bddde9278c0b185`.
- Upstream workflow runs for that SHA were all successful at `2026-04-16T00:31:31Z`.
- Fork workflow runs for that SHA were successful except `Run GUT Tests`, which was `cancelled`.
- The cancelled GUT log is preserved as `ci-run-gut-24485510880.log`.
- The GUT job did not reach the `Run GUT tests` step. It was cancelled during `Import project assets` after project-wide Godot import errors such as `res://scripts/autoload/projectile_pool_manager.gd`, `res://scripts/objects/enemy.gd`, and many pre-existing test/experiment scripts. The log lines around 237-1169 show parse/load errors during import.
- Because the cancellation happened before GUT execution, the available CI log does not show a failure caused by `test_weapon_hints_component.gd`; the immediate CI risk is the existing import phase behavior.

## Verification
- `dotnet restore` completed locally.
- `dotnet build --no-restore --configuration Debug` completed locally with warnings and 0 errors.
- Local GUT execution could not be run in this workspace because no `godot` binary is installed.
