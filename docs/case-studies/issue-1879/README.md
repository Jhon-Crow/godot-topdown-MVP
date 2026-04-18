# Issue 1879 Case Study: Grenade Tutorial Flow

## Summary

Issue 1879 reported that grenade training worked only on the Training map. On
Labyrinth the grenade tutorial could not be completed because hint steps did not
react to the player's actions and kept rolling back. On other maps the shared
weapon hint component still showed an older, incorrect grenade throw tutorial.

The fix aligns Labyrinth and shared weapon hints with the reviewed six-step
grenade sequence already used by Training, while preserving the C# player
grenade state machine as the authoritative source for post-pin-pull states.

## Data Collected

Raw issue and PR data is stored in `data/`:

- `issue-1879.json`: issue title, body, author, timestamps, and comments.
- `issue-1879-comments.json`: issue comments fetched with pagination.
- `pr-1880-comments.json`, `pr-1880-review-comments.json`,
  `pr-1880-reviews.json`: existing PR discussion/review data.
- `pr-1832.json`, `pr-1843.json`, `pr-1849.json`, `pr-1864.json`: related
  merged PR metadata.
- `pr-1843.diff`, `pr-1864.diff`: related diffs used to reconstruct recent
  tutorial rollback work.
- `focused-gutconfig.json`: minimal GUT config used for the focused local runs.
- `pr-comment-4272260526/game_log_20260418_040521.txt`: owner-provided
  exported Windows log from the follow-up PR comment reporting missing `G`
  grenade hints on Building and Training Ground.

Local investigation logs are stored in `logs/`:

- `godot_import_issue_1879.log`: headless Godot import pass.
- `gut_issue_1879_grenade.log`: focused grenade regression run.
- `gut_issue_1879_focused.log`: two-file focused run, including unrelated
  existing non-grenade failures observed during verification.
- `dotnet_build_issue_1879.log`: local C# build output.

## Timeline

- 2026-04-16: PR 1849, "Fix grenade hint activation timing", merged.
- 2026-04-16: PR 1832, "Fix grenade tutorial hint progression", merged.
- 2026-04-16: PR 1843, "Fix labyrinth tutorial rollback states", merged.
- 2026-04-17: PR 1864, "Fix training tutorial hint rollback", merged.
- 2026-04-18 00:17 UTC: Issue 1879 opened, reporting that Training works,
  Labyrinth rolls back, and other maps still show the old grenade tutorial.
- 2026-04-18 00:47 UTC: This branch updated Labyrinth and shared weapon hints to
  use the same effective six-step grenade sequence.
- 2026-04-18 01:12 UTC: Follow-up PR feedback reported that pressing `G` did
  not show grenade training on Building and Training Ground, with
  `game_log_20260418_040521.txt` attached.

## Technical Findings

The C# grenade state machine in `Scripts/Characters/Player.Grenade.cs` remains
`GrenadeState.Idle` during the initial `G+RMB` hold and right-drag. It switches
to a non-idle state only after the player releases RMB and the pin-pull state is
entered.

Labyrinth had been requiring `grenade_state >= 1` before acknowledging the
initial `G+RMB` step. That made the first visible tutorial step impossible to
complete on Labyrinth: the GDScript hint wanted a C# state that the C# code was
not supposed to set yet.

The shared `WeaponHintsComponent` still used an older three-step grenade hint
source (`arm`, `aim`, `throw`) instead of the reviewed six-step Training text:

- hold `G+RMB`
- drag right
- release RMB
- hold RMB again
- release G
- aim and release RMB

The shared component also dismissed the grenade hint when normal-level grenade
count dropped to zero after pin-pull, even though the active grenade sequence was
still in progress.

The follow-up exported log showed two different setup paths:

- Building loaded `res://scenes/levels/BuildingLevel.tscn` at 04:06:25 and
  created a scene-owned `WeaponHintsComponent` from exported NodePaths at
  04:06:26. That confirms Building already had the export-safe component in this
  PR branch, but its level script still needed to reuse that scene-owned node
  instead of creating a second dynamic component when `_ready()` also runs.
- Training Ground loaded `res://scenes/levels/csharp/TestTier.tscn` at 04:05:56
  and accepted player grenade input at 04:05:57 and 04:06:03, but no
  `WeaponHintsComponent` lines appeared for that scene. This C# Training Ground
  scene uses `tutorial_level.gd`, not `test_tier.gd`, so the shared component
  setup in `test_tier.gd` never ran for the exported route.

During test verification, Godot 4.3 also exposed an adjacent UI bug:
`RichTextLabel` does not support the `horizontal_alignment` property. That
invalid assignment aborted hint creation in headless tests before hint labels
were registered. The relevant tutorial hint creators now avoid that unsupported
property.

## Online Research

Godot 4.3 `Input` documentation confirms that `Input.action_press()` is intended
for tests and code paths using `is_action_pressed()` and
`is_action_just_pressed()`, which is why the regression tests use action state
simulation instead of assigning an unsupported `action` property to
`InputEventKey`.

Source: https://docs.godotengine.org/en/4.3/classes/class_input.html

Godot 4.3 `RichTextLabel` documentation lists paragraph/alignment APIs such as
`push_paragraph(...)` for rich text layout. It does not provide Label's
`horizontal_alignment` property, matching the engine errors observed in the
focused test logs.

Source: https://docs.godotengine.org/en/4.3/classes/class_richtextlabel.html

## Root Causes

1. Labyrinth coupled the first grenade hint step to `GetGrenadeState() >= 1`,
   but the C# state should still be idle during the initial hold and drag.
2. Shared weapon hints had not been updated to the reviewed six-step grenade
   tutorial sequence used by Training and Labyrinth.
3. Shared weapon hints treated zero remaining grenades as "no active grenade
   tutorial", even when `GetGrenadeState()` showed that a grenade throw sequence
   was already active.
4. `RichTextLabel.horizontal_alignment` was used in tutorial hint creation even
   though Godot 4.3 does not support that property on `RichTextLabel`.
5. The exported C# Training Ground scene did not own a shared
   `WeaponHintsComponent`, and its script path was `tutorial_level.gd`; therefore
   `test_tier.gd`'s dynamic weapon-hint setup was bypassed.
6. Scene-owned and script-created hint components could coexist on regular
   scenes unless level scripts reused an existing `WeaponHintsComponent`.

## Fix Strategy

- Let raw input (`grenade_prepare` plus `grenade_throw`) advance the initial
  hold and drag steps on Labyrinth and shared weapon hints.
- Continue to require C# grenade state for the post-pin-pull handoff steps.
- Reset visible hint text and strikethrough together when a partial attempt
  rolls back.
- Keep shared grenade hints visible while `GetGrenadeState() > 0`, even if the
  grenade inventory count has already dropped.
- Connect player-level grenade throw signals independently from weapon-node
  lookup, so hint dismissal depends on the player signal.
- Replace the shared component's old three-step grenade text with the reviewed
  six-step translation keys.
- Remove unsupported `RichTextLabel.horizontal_alignment` assignments from the
  tutorial hint creators touched by this issue.
- Add scene-owned `WeaponHintsComponent` nodes with exported player/canvas paths
  to both Training Ground scene variants, including the exported C# scene.
- Make Building and TestTier level scripts reuse a scene-owned component when
  present to avoid duplicate hint systems.

## Verification

Focused grenade regression command:

```bash
/tmp/godot-4.3-mono/godot/Godot_v4.3-stable_mono_linux.x86_64 --headless -s addons/gut/gut_cmdln.gd -gconfig=res://docs/case-studies/issue-1879/data/focused-gutconfig.json -gunit_test_name=grenade -gexit -glog=2
```

Result: 12 tests, 12 passing. See `logs/gut_issue_1879_grenade.log`.

C# build command:

```bash
dotnet build GodotTopDownTemplate.sln
```

Result: succeeded with existing warnings and no errors. See
`logs/dotnet_build_issue_1879.log`.

Follow-up C# build after the Training Ground export-safe hint fix:

```bash
dotnet build GodotTopDownTemplate.sln
```

Result: succeeded with existing warnings and no errors. See
`logs/dotnet_build_issue_1879_followup.log`.

Follow-up targeted GUT attempt:

```bash
/tmp/godot-4.3-mono/godot/Godot_v4.3-stable_mono_linux.x86_64 --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_test_tier_level.gd -gtest=res://tests/unit/test_building_level.gd -gtest=res://tests/unit/test_weapon_hints_component.gd -gunit_test_name='weapon|test_tier|building' -gexit -glog=2
```

Result: failed before test execution because the local Godot/GUT runner could
not parse `addons/gut/gut_cmdln.gd` (`GutUtils` not declared) after reporting a
missing translation loader. See
`logs/gut_issue_1879_export_safe_hints.log`.

The broader two-file focused run reached 39 passing and 2 failing tests. The
remaining failures are existing non-grenade shotgun/revolver source-test issues
captured in `logs/gut_issue_1879_focused.log`; they are not part of the grenade
regression fixed here.

The local Godot/GUT runs also emit existing project startup/shutdown autoload and
import errors in this workspace. They are preserved in the logs for review.
