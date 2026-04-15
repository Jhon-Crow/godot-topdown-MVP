# Issue #1830 Case Study

## Summary

Revolver reload training on the tutorial map had two sequential regressions:

1. The `scroll` step was crossed out too early immediately after `RMB up`.
2. After the first fix split `scroll` into its own step, the tutorial no longer marked `scroll` as completed after the player actually scrolled.
3. The April 15 owner follow-up clarified the intended sequence: because the reload hint appears after two shots, the revolver tutorial should guide two inserted rounds before only `R close` remains, unless the cylinder already reaches `5/5`.

This folder stores the issue evidence and a compact reconstruction of the failure.

## Collected Evidence

- `issue-1830-image.png`: original screenshot from issue #1830.
- `game_log_20260413_220706.txt`: April 13, 2026 log attached to the issue.
- `game_log_20260415_210923.txt`: April 15, 2026 log attached to the PR comment reporting the regression.
- `comment-4256146439-image.png`: April 15, 2026 owner screenshot showing `scroll` not crossing out and the expected repeat of the insert step.
- `game_log_20260416_013739.txt`: April 16, 2026 log attached to the latest owner comment.

## Timeline

- 2026-04-13: issue #1830 reported that after `RMB up`, both `RMB up` and `scroll` were struck through.
- 2026-04-15: PR #1834 introduced a fix to make `scroll` a separate tutorial step.
- 2026-04-15: follow-up PR comment reported the new regression: `scroll` no longer completed after wheel input.
- 2026-04-15 22:41 UTC: owner clarified the desired behavior: after the first scroll, repeat the insert/scroll pair until at least two cartridges were inserted during the shown tutorial, or the cylinder is back to `5/5`, and only then leave `R close`.

## Root Cause

The tutorial logic inferred revolver progress from `ReloadStateChanged` and the weapon properties.

The buggy mapping treated `CanInsertCartridge == true` as proof that the player had already finished the `scroll` step and should now see `R close`. That assumption is unreliable:

- immediately after insertion, the player still has not scrolled, but the state is `Loading`
- after scrolling to another empty chamber, `CanInsertCartridge` is also `true`

So `CanInsertCartridge` cannot distinguish:

- "cartridge inserted, still on the same chamber, waiting for scroll"
- "scroll completed, now on a different chamber"

The first repair fixed that ambiguity by tracking the chamber index, but it still assumed one insert was enough to finish the instructional loop. That mismatched the tutorial trigger condition: the prompt only appears after two shots, so players often still need to load at least two chambers before closing the cylinder.

## Fix Strategy

Track the chamber index at the moment of cartridge insertion and compare it with the current chamber index when `ReloadStateChanged(Loading)` arrives. Combine that with the number of cartridges inserted during the current reload prompt and the current ammo count.

- same chamber index after an insert: highlight `scroll`
- different chamber index before the player has inserted two rounds: highlight `RMB up` again
- once at least two rounds were inserted, or the cylinder reaches `5/5`: highlight `R close`

This disambiguates the two states without changing revolver weapon behavior.

## Validation

Regression coverage was added in `tests/unit/test_tutorial_level.gd` for:

- insert without scroll: `scroll` remains highlighted
- first scroll after first insert: highlight returns to `RMB up`
- scroll to another empty chamber before the second insert: still highlight `RMB up`
- second insert: `R close` becomes highlighted
- cylinder reaches `5/5`: `R close` becomes highlighted immediately
