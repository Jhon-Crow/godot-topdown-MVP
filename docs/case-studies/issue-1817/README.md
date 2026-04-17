# Issue 1817 Case Study

## Summary

Issue: tutorial hint lines in the labyrinth level stayed partially completed after the player canceled an in-progress input sequence.

Observed variants from the issue and PR discussion:
- Grenade tutorial: releasing `G` before the grenade activation/throw sequence completed left the first steps crossed out.
- Shotgun full-reload tutorial: opening and then closing the bolt without loading shells incorrectly completed the tutorial instead of resetting it.

## Collected Data

- `issue.json`: issue title/body and available comments captured via GitHub CLI.
- `pr.json`: PR 1843 metadata and discussion snapshot.
- `game_log_20260416_012023.txt`: owner-provided runtime log attached in the PR conversation.

## Reconstructed Sequence

### Grenade tutorial

1. Tutorial enters the grenade step and shows the 3-part combo hint.
2. Holding `grenade_prepare` advances the hint to step 1 and extends the strikethrough.
3. Releasing `grenade_prepare` before the throw previously only changed internal state partially, leaving the label in a visually completed state.
4. Expected behavior: both the logical step and the visual strike progress return to the initial prompt.

### Shotgun full reload tutorial

1. Tutorial shows `open -> load shells -> close`.
2. The reload state machine can return to idle (`state == 0`) both after a real reload and after a canceled attempt.
3. Previous logic treated every transition back to idle as reload completion.
4. Expected behavior: idle should only complete the tutorial after the loading phase actually started; otherwise the hint must reset.

## Root Cause

The tutorial handlers were using coarse state transitions:
- Grenade rollback reset the step flags, but the label/strikethrough state was not consistently rebuilt through a dedicated reset path.
- Shotgun reload completion inferred success from `new_state == 0` alone, which conflated cancellation with a real reload completion.

## Proposed Fix

- Add a dedicated grenade hint reset helper that restores both tutorial state variables and the rendered label.
- Reuse that helper when grenade preparation is aborted and before dismissing the hint after a successful throw.
- Gate shotgun reload completion on observed progress (`strike_progress >= 0.25`), which indicates the player reached the loading phase.
- Otherwise rebuild the shotgun hint in its initial state.

## Verification

Regression coverage added in `tests/unit/test_labyrinth_grenade_tutorial.gd`:
- grenade prepare canceled before completion resets the hint
- shotgun bolt close without shell loading resets instead of completing
- shotgun reload still completes after the loading phase has begun

Local execution of GUT was not possible in this environment because no `godot` executable is installed.
