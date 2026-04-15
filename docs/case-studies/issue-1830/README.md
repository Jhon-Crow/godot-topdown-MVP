# Issue #1830 Case Study

## Summary

Revolver reload training on the tutorial map had two sequential regressions:

1. The `scroll` step was crossed out too early immediately after `RMB up`.
2. After the first fix split `scroll` into its own step, the tutorial no longer marked `scroll` as completed after the player actually scrolled.

This folder stores the issue evidence and a compact reconstruction of the failure.

## Collected Evidence

- `issue-1830-image.png`: original screenshot from issue #1830.
- `game_log_20260413_220706.txt`: April 13, 2026 log attached to the issue.
- `game_log_20260415_210923.txt`: April 15, 2026 log attached to the PR comment reporting the regression.

## Timeline

- 2026-04-13: issue #1830 reported that after `RMB up`, both `RMB up` and `scroll` were struck through.
- 2026-04-15: PR #1834 introduced a fix to make `scroll` a separate tutorial step.
- 2026-04-15: follow-up PR comment reported the new regression: `scroll` no longer completed after wheel input.

## Root Cause

The tutorial logic inferred revolver progress from `ReloadStateChanged` and the weapon properties.

The buggy mapping treated `CanInsertCartridge == true` as proof that the player had already finished the `scroll` step and should now see `R close`. That assumption is unreliable:

- immediately after insertion, the player still has not scrolled, but the state is `Loading`
- after scrolling to another empty chamber, `CanInsertCartridge` is also `true`

So `CanInsertCartridge` cannot distinguish:

- "cartridge inserted, still on the same chamber, waiting for scroll"
- "scroll completed, now on a different chamber"

## Fix Strategy

Track the chamber index at the moment of cartridge insertion and compare it with the current chamber index when `ReloadStateChanged(Loading)` arrives.

- same chamber index: highlight `scroll`
- different chamber index: highlight `R close`

This disambiguates the two states without changing revolver weapon behavior.

## Validation

Regression coverage was added in `tests/unit/test_tutorial_level.gd` for:

- insert without scroll: `scroll` remains highlighted
- scroll after insert: `R close` becomes highlighted
- scroll to another empty chamber: `R close` still remains highlighted
