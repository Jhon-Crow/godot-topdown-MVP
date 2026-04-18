# Issue 1817 Case Study

## Summary

Issue: tutorial hint lines in the labyrinth level stayed partially completed after the player canceled an in-progress input sequence.

Observed variants from the issue and PR discussion:
- Grenade tutorial: releasing `G` before the grenade activation/throw sequence completed left the first steps crossed out.
- Shotgun full-reload tutorial: opening and then closing the bolt without loading shells incorrectly completed the tutorial instead of resetting it.
- M16 reload tutorial: pressing `R` and then shooting should cancel the partial reload hint.
- Revolver reload tutorial: opening and closing the cylinder without inserting a cartridge should reset the reload hint.
- Silenced pistol training must be connected on the training map.

## Collected Data

- `issue.json`: issue title/body and available comments captured via GitHub CLI.
- `pr.json`: PR 1843 metadata and discussion snapshot.
- `game_log_20260416_021623.txt`: owner-provided runtime log attached in the PR conversation.
- `game_log_20260417_025935.txt`: owner-provided runtime log for revolver reload training feedback.
- `game_log_20260417_030201.txt`: owner-provided runtime log for shotgun reload training feedback.
- `game_log_20260417_033631.txt`: owner-provided runtime log after the first PR #1864 fix, reporting no behavior change.
- `game_log_20260417_210216.txt`: owner-provided exported-exe startup log after the latest PR #1864 fix, reporting a gray screen.
- `game_log_20260417_214336.txt`: owner-provided runtime log after the gray-screen fix, reporting two remaining Training-map issues: missing silenced pistol reload training and revolver empty open/close completion.
- `game_log_20260417_230427.txt`: owner-provided runtime log after the next follow-up, reporting that silenced pistol training used the wrong Makarov-style reload hint and revolver reload training still disappeared after two `R` presses.
- `game_log_20260417_235155.txt`: owner-provided runtime log after the latest follow-up, reporting that revolver reload training still reacts to cylinder close even though close is not the active step after empty open/close.
- `game_log_20260418_014100.txt`: owner-provided runtime log after commit `e088219c`, reporting that revolver reload training is still skipped by pressing `R R`.
- `game_log_20260417_025935.filtered.txt`: filtered weapon/tutorial timeline from the first April 17 log.
- `game_log_20260417_030201.filtered.txt`: filtered weapon/tutorial timeline from the second April 17 log.
- `game_log_20260417_033631.filtered.txt`: filtered weapon/tutorial timeline from the latest April 17 log.
- `dotnet-build.log`: local build verification log.
- `dotnet-build-latest.log`: local build verification log for the final follow-up patch.

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

### Revolver reload tutorial

1. Tutorial shows `open cylinder -> insert cartridge -> rotate/continue -> close`.
2. The reload state machine can return to idle (`state == 0`) after closing the cylinder with or without inserting a cartridge.
3. Previous logic treated every close as reload completion.
4. Expected behavior: closing without inserting a cartridge resets the hint; closing after insertion completes it.

## Root Cause

The tutorial handlers were using coarse state transitions:
- Grenade rollback reset the step flags, but the label/strikethrough state was not consistently rebuilt through a dedicated reset path.
- Shotgun and revolver reload completion inferred success from `new_state == 0` alone, which conflated cancellation with real reload completion.

## Proposed Fix

- Add a dedicated grenade hint reset helper that restores both tutorial state variables and the rendered label.
- Reuse that helper when grenade preparation is aborted and before dismissing the hint after a successful throw.
- Gate shotgun reload completion on observing the close-ready state after a shell load.
- Gate revolver reload completion on observing the loading state after a cartridge insert.
- Otherwise rebuild the corresponding hint in its initial state and clear strikethrough progress.
- Add a regression test that `silenced_pistol` resolves to the `SilencedPistol` weapon node.
- Apply the rollback gates in both the shared `WeaponHintsComponent` and the Training map's own
  `tutorial_level.gd` handlers. The latest log showed Training map behavior was unchanged because
  the previous patch fixed only the shared component path.
- Add explicit Training-map handling for `SilencedPistol` so it connects shot, reload, and ammo
  signals while still using the rifle-style `[R] [F] [R]` reload hint used by Uzi/M16.
- Reset the Training-map revolver per-attempt cartridge tracker when a reload closes, so a previous
  successful insert or single partial insert cannot make a later incomplete close look completed.
- Treat the Training-map revolver `ClosingCylinder` transition as rollback unless the current attempt
  already inserted the tutorial quota or filled the cylinder.
- Ignore the generic player `ReloadCompleted` signal for revolver training unless the same
  revolver-specific completion gate is satisfied; `Player.cs` emits this signal on every cylinder
  close, including empty `R R` cancellation.

## Verification

Regression coverage added in `tests/unit/test_labyrinth_grenade_tutorial.gd`:
- grenade prepare canceled before completion resets the hint
- shotgun bolt close without shell loading resets instead of completing
- shotgun reload still completes after the loading phase has begun
- Training map shotgun and revolver handlers contain rollback guards for canceled reloads

Regression coverage added in `tests/unit/test_weapon_hints_component.gd`:
- silenced pistol node lookup
- revolver open/close without cartridge insertion rolls back
- revolver close after cartridge insertion dismisses
- shotgun open/close without shell loading rolls back
- shotgun close after shell loading dismisses

Regression coverage added in `tests/unit/test_tutorial_level.gd`:
- silenced pistol uses the rifle-style reload hint on the Training map
- revolver incomplete open/insert/close rolls back instead of dismissing the line
- revolver `ClosingCylinder` without cartridge insertion does not render the completed all-grey line
- generic `ReloadCompleted` after an empty revolver `R R` sequence does not dismiss the reload line

Regression coverage added in `tests/unit/test_scene_loader.gd`:
- invalid threaded resource fallback keeps the loading overlay visible if the sync scene change fails, preventing a blank/gray screen from being exposed without diagnostics

Local execution of GUT was not possible in this environment because no `godot` executable is installed.
