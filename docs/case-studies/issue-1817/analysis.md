# Issue 1817 Case Study

## Scope

Issue [#1817](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1817) started as a tutorial-line reset bug. Follow-up feedback expanded the scope:

- M16 reload tutorial must roll back when the reload combo is aborted by shooting
- grenade tutorial must roll back when preparation/throw does not complete
- silenced pistol training must appear on the training map
- revolver reload tutorial must not complete when the cylinder is opened and closed without inserting a cartridge
- shotgun full-reload tutorial must count the first bolt-open step, but must not complete when the action is opened and closed without loading a shell

## Collected Data

- Owner reproduction log from earlier PR feedback: [game_log_20260416_021623.txt](./game_log_20260416_021623.txt)
- Owner reproduction logs from PR #1864 feedback:
  - [game_log_20260417_025935.txt](./game_log_20260417_025935.txt)
  - [game_log_20260417_030201.txt](./game_log_20260417_030201.txt)
  - [game_log_20260417_033631.txt](./game_log_20260417_033631.txt)
  - [game_log_20260417_210216.txt](./game_log_20260417_210216.txt)
  - [game_log_20260417_214336.txt](./game_log_20260417_214336.txt)
- Filtered timeline extracts:
  - [game_log_20260417_025935.filtered.txt](./game_log_20260417_025935.filtered.txt)
  - [game_log_20260417_030201.filtered.txt](./game_log_20260417_030201.filtered.txt)
  - [game_log_20260417_033631.filtered.txt](./game_log_20260417_033631.filtered.txt)
- Relevant code: `scripts/components/weapon_hints_component.gd`, `Scripts/Characters/Player.cs`, `Scripts/Weapons/Revolver.cs`, `Scripts/Weapons/Shotgun.cs`
- Regression tests: `tests/unit/test_labyrinth_grenade_tutorial.gd`, `tests/unit/test_weapon_hints_component.gd`

## Timeline

1. April 15, 2026: original issue reported for canceled tutorial combinations not resetting.
2. April 15, 2026 22:22:58 UTC: owner reported remaining grenade and shotgun failures on PR #1843.
3. April 15, 2026 23:17:51 UTC: owner attached `game_log_20260416_021623.txt`.
4. April 17, 2026 00:06:57 UTC: owner reported three remaining PR #1864 issues and attached two new logs.
5. April 17, 2026: new logs show revolver open/close sequences at `03:01:16` -> `03:01:19` and `03:01:26` -> `03:01:33`, plus shotgun open/close-without-load sequences at `03:02:30`, `03:02:37`, and nearby repeated attempts.
6. April 17, 2026 00:37:57 UTC: owner attached `game_log_20260417_033631.txt` and reported "nothing changed" in the latest build.
7. April 17, 2026 18:02:49 UTC: owner attached `game_log_20260417_210216.txt` and reported a gray screen after launching the exported exe.
8. April 17, 2026 18:47:33 UTC: owner attached `game_log_20260417_214336.txt` and reported that shotgun was now correct, but silenced pistol reload training still did not appear on the Training map and revolver empty open/close still completed the line.

## Findings

The first attached log is mostly startup telemetry. It confirms the reproduction environment:

- Windows build, Godot 4.3 stable
- tutorial sessions were entered multiple times
- grenade/tutorial systems were active, but that log does not include per-step tutorial state transitions

The April 17 logs add useful weapon-level transitions:

- `WeaponHintsSettings` mode is `ALWAYS`, so hints should be shown even for previously seen weapons.
- `Player.Weapon` selects and equips `revolver` and `shotgun` in the training scene.
- revolver logs show `cylinder opened (R key)` followed by `cylinder closed (R key), reload complete` without any matching cartridge-insert signal in the filtered trace.
- shotgun logs show `Bolt opened for loading`, then `Reload complete - bolt closed` with unchanged shell counts such as `6/8` and `7/8`, which is an aborted reload from the tutorial perspective.
- the latest log confirms the same Training map path: revolver opens and closes at `03:36:40` without a cartridge insert, and shotgun opens at `03:37:23` / `03:37:25` then closes with `shouldLoad=False` and still `6 shells`.
- the exported-exe startup log shows `SceneLoader` reporting `THREAD_LOAD_INVALID_RESOURCE` for `res://scenes/levels/RoguelikeLevel.tscn`, falling back to synchronous loading, and then arriving at `RoguelikeLevel` while dependent systems still report no player. This is consistent with the user-visible gray/blank startup state.
- `game_log_20260417_214336.txt` confirms the later build launched successfully and that `WeaponHintsSettings` was still in `ALWAYS` mode. The remaining owner report is therefore not a settings/first-time-only problem; it is a Training-level signal wiring and rollback-state problem.

## Root Causes

### 1. Grenade tutorial trusted raw input instead of the real grenade state

In `scripts/levels/labyrinth_level.gd`, `_update_tutorial_grenade_hint_step()` had a fallback path that advanced the hint when `grenade_prepare` and `grenade_throw` inputs were held together, even if the player grenade state machine had not entered `WAITING_FOR_G_RELEASE`.

Result:

- repeated `G` presses or partial input sequences could move the tutorial to later steps
- releasing inputs before the grenade actually armed did not always roll the hint back correctly

### 2. Shotgun tutorial completion treated idle as success

`WeaponHintsComponent._on_shotgun_reload_state_changed()` treated `ReloadStateChanged(0)` as successful completion. The shotgun emits state `0` both after a real shell load plus close and after opening/closing the action without loading.

Result:

- opening and closing the shotgun without loading a shell could still complete the tutorial

### 3. Revolver tutorial completion treated idle as success

`WeaponHintsComponent._on_revolver_reload_state_changed()` also treated `ReloadStateChanged(0)` as successful completion. The revolver emits state `0` after closing the cylinder, even if no cartridge was inserted.

Result:

- opening and closing the revolver cylinder could dismiss the reload hint and mark the training line complete

### 4. Silenced pistol mapping needed explicit coverage

The central weapon hint component already maps `silenced_pistol` to the C# `SilencedPistol` node, but there was no focused regression test for the training-map path.

Result:

- future changes could silently break the suppressed pistol hint connection path

### 5. The first PR #1864 follow-up fixed the shared component, not the Training map handler

The owner reproduced the remaining issue on the Training map. That scene uses `scripts/levels/tutorial_level.gd` for its main reload tutorial flow, while the previous patch added rollback state to `scripts/components/weapon_hints_component.gd`.

Result:

- factory/labyrinth-style shared weapon hints had rollback guards, but Training still completed shotgun reload on every `ReloadStateChanged(0)`
- Training revolver still rendered the all-grey final step when the cylinder returned to idle without any inserted cartridge

### 6. Training map never treated SilencedPistol as a pistol reload tutorial weapon

`scripts/levels/tutorial_level.gd` detected `Shotgun`, `MiniUzi`, `AssaultRifle`, `AKGL`, `Revolver`, and `MakarovPM`, but did not have a `SilencedPistol` branch in `_connect_player_signals()`.

Result:

- the silenced pistol could be equipped, but the Training map did not connect its fired/reload/ammo signals for the tutorial flow
- the reload hint did not appear after the two-shot threshold on the Training map
- even if a hint was manually forced, the generic fallback would use the rifle-style `R -> F -> R` sequence instead of the pistol `R -> R` sequence

### 7. Training revolver rollback used stale cartridge state across attempts

`tutorial_level.gd` used `_revolver_last_inserted_count` to decide whether `ReloadStateChanged(0)` was a real completion or an aborted empty close. That value could persist after a previous reload attempt inserted a cartridge.

Result:

- a later sequence of open cylinder -> close cylinder without insertion could still see stale inserted-count state and render the line as completed

### 8. SceneLoader fallback could expose a blank screen after exported startup failure

`SceneLoader._fallback_sync_load()` ignored the return value from `change_scene_to_packed()` and always hid the loading overlay. `_on_load_complete()` had the same overlay-clearing behavior after a scene-change error. If threaded loading reports `THREAD_LOAD_INVALID_RESOURCE` in an exported build and the synchronous scene change also fails, the loader clears its visual guard and exposes the underlying not-yet-ready or failed scene.

Result:

- exported startup can appear as a gray/blank screen instead of staying on the loading overlay with useful log diagnostics

## Solution Direction

- Drive grenade tutorial progression strictly from the player grenade state machine (`WAITING_FOR_G_RELEASE`, `AIMING`, `IDLE`).
- Track whether shotgun reload reached the meaningful loaded-shell state before allowing `ReloadStateChanged(0)` to complete the tutorial.
- Track whether revolver reload inserted a cartridge before allowing `ReloadStateChanged(0)` to complete the tutorial.
- Add a Training-map `SilencedPistol` branch that connects shot/reload/ammo signals and uses the same two-step pistol reload path as Makarov PM.
- Reset Training-map revolver per-attempt loaded-cartridge state on every close, so empty open/close attempts after previous inserts roll back correctly.
- Reset hint label text and strikethrough progress when a reload action closes without the meaningful load step.
- Mirror those guards inside `tutorial_level.gd`, because Training does not rely solely on the shared weapon hint component.
- Keep the loading overlay visible and preserve loader state when SceneLoader cannot complete either threaded or synchronous scene transition.
- Add focused tests for silenced pistol node lookup, aborted revolver reload rollback, successful revolver completion, aborted shotgun reload rollback, and successful shotgun completion.
- Add focused Training-map tests for silenced pistol two-step reload and revolver stale-state rollback after a previous cartridge insert.
- Add a SceneLoader regression test for failed synchronous fallback after invalid threaded resource status.
- Keep regression coverage for both canceled and completed flows.

## Additional Data Needed

For future debugging, add optional tutorial debug logs behind a disabled-by-default flag:

- grenade tutorial step changes with current grenade state
- shotgun reload tutorial transitions with `ReloadStateChanged` values
- explicit reset/completion reasons
