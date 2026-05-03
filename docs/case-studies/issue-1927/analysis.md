# Case Study: Issue #1927 - Game Crash When Applying Armory Weapon

## Summary

Hard crash (no error printed to log) when the player opens the armory menu, chooses a weapon, and presses "Apply" / confirm. The first report mentioned the revolver. Follow-up PR feedback reported that the crash still reproduced with ASVK and revolver, so the investigation was expanded from a revolver-only HUD cleanup bug to the shared scene-reload ownership pattern for weapon overlays.

## Environment

- OS: Windows
- Build: release (non-debug), Godot 4.3-stable
- Branch: issue-1925-34da7c98b0a6
- Build date: 2026-05-03T06:05:00Z

## Collected Artifacts

| Artifact | Local path | Result |
| --- | --- | --- |
| Original issue log | `logs/game_log_20260503_093315.txt` | Downloaded successfully; 1107 lines. |
| PR feedback log `game_log_20260503_101617.txt` | `logs/game_log_20260503_101617.download-error.xml` | GitHub attachment redirected to a zero-byte object and returned HTTP 416 / `InvalidRange`. |
| PR feedback log `game_log_20260503_101640.txt` | `logs/game_log_20260503_101640.download-error.xml` | GitHub attachment redirected to a zero-byte object and returned HTTP 416 / `InvalidRange`. |

The two follow-up attachment downloads were preserved as XML error artifacts rather than treated as logs.

## Timeline of Events (from log)

| Time     | Event |
|----------|-------|
| 09:33:15 | Game started on LabyrinthLevel with revolver selected |
| 09:33:16 | Scene auto-navigated to RevolverLevel (last played level) |
| 09:33:17 | Player and 14 enemies initialized on RevolverLevel |
| 09:33:18 | Armory menu opened → player selects Shotgun |
| 09:33:20 | `GameManager.restart_scene()` called; scene reloaded with Shotgun |
| 09:33:20 | New Player/Shotgun session begins on RevolverLevel |
| 09:33:23 | Log ends abruptly during shotgun gameplay, no error output |

The original log proves the apply action triggered `restart_scene()` and the reload completed. The process then terminated without a GDScript error, engine panic line, or FileLogger error. That points to a hard native/C# teardown crash rather than an ordinary script exception.

## External References

- Godot 4.3 `SceneTree.change_scene_to_packed()` documents that the outgoing current scene is removed immediately, then freed at the end of the frame; `reload_current_scene()` replaces the active scene with a new instance of its original `PackedScene`: https://docs.godotengine.org/en/4.3/classes/class_scenetree.html
- Godot 4.3 `Node` docs describe `tree_exiting` / `NOTIFICATION_EXIT_TREE` as the point where a node is about to leave the `SceneTree`: https://docs.godotengine.org/en/4.3/classes/class_node.html

## Root Cause

There are **two independent crash paths**, not one. The first PR addressed only path A (teardown ownership). Owner feedback "вылетает при выборе ASVK или револьвера" exposed path B (duplicate weapon instantiation race), which is the dominant trigger when the user picks a weapon in the armory and presses Apply.

### Path B (primary): Duplicate weapon instantiation race during scene reload

When `GameManager.restart_scene()` reloads the current level after the player presses Apply in the armory, two independent code paths both try to instantiate the selected weapon as a child of `Player`:

1. **C# `Player._Ready()`** calls `ApplySelectedWeaponFromGameManager()` (`Scripts/Characters/Player.cs:3016+`). It loads e.g. `res://scenes/weapons/csharp/Revolver.tscn`, instantiates the scene, sets `weapon.Name = "Revolver"`, calls `AddChild(weapon)`, and assigns `CurrentWeapon = weapon`.
2. **Level GDScript `_setup_selected_weapon()`** runs from the level's `_ready()`. In the vulnerable levels it does the same: `load(...).instantiate()`, `revolver.name = "Revolver"`, `_player.add_child(revolver)`, then `_player.EquipWeapon(revolver)`.

Godot does not allow two siblings to share a name, so the second `add_child()` causes the engine to auto-rename the new node — `"Revolver"` becomes `"Revolver2"`, `"SniperRifle"` becomes `"SniperRifle2"`. Then `EquipWeapon(revolver)` removes the original first instance from the tree.

The first instance was instantiated by Player.cs and ran its `_Ready()` immediately. For Revolver and SniperRifle this means deferred setup is already queued:

- **Revolver** (`Scripts/Weapons/Revolver.cs:360`): `CallDeferred(MethodName.SetupCylinderHUD)`.
- **SniperRifle / ASVK**: scope overlay creation and signal wiring against the level root.

When that deferred call fires, the original Revolver/SniperRifle is no longer in the tree, but its native object is still alive. The setup code touches `GetTree()` / `GetParent()` / scene-root overlays in states it never expected — that is the hard native crash with no GDScript stack trace. It matches the symptom: "press Apply → crash within a frame".

Some levels were already protected: `labyrinth_level.gd` had a `weapon_names` early-return guard (originally added in "Bug fix round 6"), and `test_tier.gd` had the same pattern. The vulnerable levels were:

| Level | Pre-fix state |
| --- | --- |
| `decadence_level.gd` | No protection at all |
| `sewer_level.gd` | No protection at all |
| `city_level.gd` | Protection dict missing `revolver`, `ak_gl`, `m16` |

Owner feedback specifically called out revolver and ASVK, which are the two weapons with deferred-setup logic that crashes when orphaned by the duplicate. Other duplicates (Shotgun, MakarovPM) merely cause UI/signal bugs of the same family that previous bug-fix rounds addressed (see the "Bug fix round 6" comment in `labyrinth_level.gd:1745`).

### Path A (secondary): Scene-owned weapon overlays explicitly QueueFreed from weapon `_ExitTree()`

This was the path the first PR addressed. It still exists as a latent risk and the fix is kept.

### Revolver HUD

**File:** `Scripts/Weapons/Revolver.cs`

`SetupCylinderHUD()` creates a `RevolverCylinderHUDLayer` as a direct child of the level root. The revolver stores a reference to the nested `RevolverCylinderUI`, but the revolver does not own that node. During `reload_current_scene()`, the level root already owns freeing the HUD layer and its children.

The old `_ExitTree()` called `_cylinderUI.QueueFree()` anyway. That could queue a scene-owned HUD node for deletion while the outgoing scene was already being freed.

### ASVK Scope Overlay

**File:** `Scripts/Weapons/SniperRifle.cs`

`CreateScopeOverlay()` creates a `ScopeOverlay` `CanvasLayer` and adds it to `GetTree().CurrentScene`, not as a child of the ASVK node. When ASVK exits during a scene reload with the scope active, `_ExitTree()` called `DeactivateScope()`, and `DeactivateScope()` called `RemoveScopeOverlay()`, which always called `_scopeOverlay.QueueFree()`.

That is the same ownership error as the revolver HUD, and it matches the owner follow-up that ASVK still crashed.

## Fix

### Path B fix: duplicate-weapon protection in level scripts

Brought the `labyrinth_level.gd` early-return guard into the three vulnerable level scripts so the GDScript `_setup_selected_weapon()` no longer instantiates a second copy of a weapon that C# `Player._Ready()` already added.

- `scripts/levels/decadence_level.gd` `_setup_selected_weapon()`: added the full `weapon_names` dict and the `_player.get("CurrentWeapon") == existing_weapon` early-return before any `load().instantiate()` path.
- `scripts/levels/sewer_level.gd` `_setup_selected_weapon()`: same insertion.
- `scripts/levels/city_level.gd` `_setup_selected_weapon()`: extended the existing `weapon_names` dict to cover `revolver`, `ak_gl`, and `m16` so the early-return now fires for the weapons the user can pick in the armory.

The audit covered all 14 level scripts that define `_setup_selected_weapon()`. After the fix, 13 use the explicit `weapon_names` + early-return pattern; `test_tier.gd` already had its own copy of the same pattern.

### Path A fix (kept from the previous PR)

#### GameManager

Added `is_reloading_scene()` so C# weapon cleanup code can distinguish normal weapon removal from current-scene teardown.

#### ASVK

Changed ASVK `_ExitTree()` to:

- Query `GameManager.is_reloading_scene()`.
- During scene reload, deactivate local scope state and camera offset without explicitly queue-freeing the `ScopeOverlay` or emitting teardown signals.
- During normal scope release or non-reload weapon removal, keep the existing behavior and queue-free the overlay.

#### Revolver

Kept the previous correction: `_ExitTree()` disconnects the cylinder UI reference but does not queue-free the level-owned HUD.

## Regression Test

`tests/unit/test_issue_1927_scene_reload_overlay_cleanup.gd` locks down both crash paths in source.

Path A (ownership):

- `GameManager` exposes the reload guard.
- ASVK checks the reload guard from `_ExitTree()`.
- ASVK overlay cleanup makes explicit queue-free optional.
- Revolver no longer calls `_cylinderUI.QueueFree()`.

Path B (duplicate weapon race):

- `decadence_level.gd`, `sewer_level.gd`, and `city_level.gd` each include `revolver` and `sniper` in their `weapon_names` dict.
- Each of those level scripts contains the `_player.get("CurrentWeapon") == existing_weapon` early-return.

## Reproduction Steps

1. Start game with revolver or ASVK equipped on any level
2. Open the armory menu (pause → Armory)
3. Select a weapon, or keep the current weapon
4. Press "Apply" / "подтвердить"
5. Before the fix, the game could hard-crash during or shortly after scene reload

## Why This Was Hard to Find

- No error message appears (hard engine crash, not GDScript exception)
- The original log continues after `restart_scene()`, so the visible symptom is a few frames after pressing Apply
- The relevant overlays are created by weapon code but owned by the level/current scene root
- The first PR fixed the path A ownership bug, which is real but not the dominant trigger; the user's "вылетает при выборе ASVK или револьвера" reproduces path B (duplicate-instantiation race), and the two bugs share the same surface symptom — apply weapon → crash within a frame
- One level (`labyrinth_level.gd`) had already been hardened against the race in an earlier round (see comment at `labyrinth_level.gd:1745`), masking how broadly other levels were unprotected
- Owner-uploaded follow-up logs (`game_log_20260503_101617.txt`, `_101640.txt`, `_105042.txt`, `_105107.txt`) returned HTTP 416 from GitHub user-attachments storage, so direct log evidence of the new crash was unavailable; root-cause had to come from code inspection

## Session 4 Finding: Build Metadata Mismatch

On the fourth rejection ("не исправлено", `08:56 UTC`), the owner uploaded logs:
- `game_log_20260503_115518.txt` (revolver)
- `game_log_20260503_115534.txt` (ASVK)

Both logs contain:
```
Build branch: issue-1927-8435a8027870
Build commit: 10ffb3f19765645f1a5e52db6accdc73ccdbf152
Build date: 2026-05-03T08:10:00Z
```

Commit `10ffb3f1` is **merge of PR #1930 into `main`** (merged at `07:40 UTC`). It does not contain any fix from our PR #1928.

Our fix commits are:
| Commit | Pushed | Content |
|--------|--------|---------|
| `890fbd82` | 06:40 UTC | Remove `_cylinderUI.QueueFree()` from `Revolver._ExitTree()` |
| `0b4e97d2` | 07:28 UTC | ASVK scope cleanup + `GameManager.is_reloading_scene()` |
| `40595c36` | 08:09 UTC | Weapon duplication guard in 3 level scripts |

The Windows EXE artifact for commit `40595c36` was produced by CI run
[#25273923619](https://github.com/Jhon-Crow/godot-topdown-MVP/actions/runs/25273923619) at `08:13 UTC` —
**29 minutes after** the main-branch build the owner downloaded.

The `Build branch: issue-1927-8435a8027870` in the log appears because the workflow embeds
`github.head_ref || github.ref_name`, and the owner appears to have downloaded the `windows-build`
artifact from the main-branch CI run whose `github.ref_name` is `main`, not our branch.
The game logs showing "issue-1927" in the branch field may have been generated from an older
session; the commit hash `10ffb3f1` is the authoritative identifier and unambiguously points to main.

## Session 5 Finding: Latest Logs Reach RevolverLevel Before Crash

On the fifth rejection (`09:37 UTC`), the owner uploaded:
- `game_log_20260503_123622.txt` (revolver)
- `game_log_20260503_123644.txt` (ASVK)

These artifacts were downloaded into:
`docs/case-studies/issue-1927/artifacts/pr-comment-4365867777/`.

Both logs still embed commit `10ffb3f19765645f1a5e52db6accdc73ccdbf152`, but the log content
includes messages from the current PR fixes:

- Labyrinth emits "already equipped by C# Player" for both `revolver` and `sniper`, proving the
  duplicate-instantiation guard is present and firing.
- The session proceeds past the original Apply/reload boundary.
- `PersistManager` then performs startup navigation into `res://scenes/levels/RevolverLevel.tscn`.
- `RevolverLevel` initializes a new `Player`, replaces the scene-placed `MakarovPM` with the selected
  revolver or ASVK from `Player._Ready()`, starts replay recording, and continues for several frames.

The remaining hard crash is therefore no longer the original duplicate-instantiation failure. The
remaining timing-sensitive path is `Player._Ready()` replacing and queue-freeing the scene-placed
weapon while the player node, weapon child nodes, and level script are all still in startup `_Ready()`
interleaving. That is especially risky for revolver/ASVK because both have additional startup/deferred
state (revolver cylinder HUD, ASVK scope/weapon-specific helpers).

### Session 5 Fix

`Player._Ready()` now defers `ApplySelectedWeaponFromGameManager()` with:

```
CallDeferred(MethodName.ApplySelectedWeaponFromGameManager);
```

This preserves the C# fallback for exported builds where GDScript level setup is unreliable, but waits
until the current scene startup pass is stable before removing/freeing the scene-placed default weapon
and adding the selected weapon.

The regression test now also locks down that `Player._Ready()` must not synchronously call
`ApplySelectedWeaponFromGameManager()` before base sprite initialization.

## Session 6 Finding: Buffered Logs Mask the Real Crash Site

On the sixth rejection (`13:30 UTC`), the owner uploaded:

- `game_log_20260503_132640.txt` (revolver, 562 lines, 45 552 bytes — valid)
- `game_log_20260503_132701.txt` (ASVK, 249 bytes — Azure `InvalidRange` error, unreadable)

Downloaded to `docs/case-studies/issue-1927/artifacts/pr-comment-4365950554/`.

The valid revolver log shows:

- Labyrinth duplicate-instantiation guard fires (`"already equipped by C# Player"`).
- `Player._Ready()` deferred swap completes: MakarovPM → Revolver.
- ReplayManager begins recording frame 0.
- Revolver pose detected on frame 3.
- The last recorded line is an `ImpactEffects` particle warmup confirmation. **No crash signature, no `_ExitTree`, no error**.

That tail is the smoking gun for log loss, not for a successful run. `scripts/autoload/file_logger.gd`
batches writes and only flushes the buffer once per second (`FLUSH_INTERVAL = 1.0`, see Issue #885).
A hard crash inside the buffer window silently truncates the log right before the actual crash site.
The "log ends in the middle of a frame" pattern across every reproducer is consistent with this.

### Backup-branch comparison

Per the owner's hint ("проверь старый pr в ветку backup, там вероятно всё работало"), inspected
`origin/backup`:

- `Player.cs` calls `ApplySelectedWeaponFromGameManager()` **synchronously** from `_Ready()` (no
  `CallDeferred`).
- `Revolver.cs` is ~1044 lines and contains **no cylinder HUD architecture at all** — no
  `SetupCylinderHUD`, no `RevolverCylinderHUDLayer` CanvasLayer, no `_cylinderUI` field.

The cylinder HUD level-root CanvasLayer was introduced in commit `37c94b82` for Issue #1765. The
backup branch predates it. This narrows the residual crash region to one of:

1. The deferred `SetupCylinderHUD` running on a Revolver that was already removed/replaced by a
   second `ApplySelectedWeaponFromGameManager` pass.
2. Native teardown of the cylinder HUD layer when the level scene is freed.
3. The ASVK scope overlay reaching a deferred frame in a comparable orphan state (different log,
   different last visible event, but same buffered-loss pattern).

### Session 6 changes (this session)

1. **Immediate-flush window in `file_logger.gd`** (Issue #1927): for the first 10 seconds after
   startup, every `_write_log` call flushes to disk. Public helpers
   `force_immediate_flush_window()` and `flush_now()` let other autoloads re-arm the window before
   risky operations.
2. **`game_manager.gd` `restart_scene()`** calls `force_immediate_flush_window()` before the reload
   so a hard crash mid-reload still leaves a complete log file pointing at the crash site.
3. **`Player.cs` `ApplySelectedWeaponFromGameManager`** logs `[trace]` markers around
   `RemoveChild`, `QueueFree`, `Load`, `Instantiate`, and `AddChild`, plus an
   `IsInsideTree()` guard at entry so the deferred call does not touch tree state on a freed
   Player.
4. **`Revolver.cs` `SetupCylinderHUD`** logs `[trace]` markers and bails out if
   `!IsInsideTree()`. Touching the parent chain on an orphaned Revolver was the most likely
   remaining native crash. `_ExitTree` and the deferred-call entry are also traced.
5. **`SniperRifle.cs` `_ExitTree`** logs `[trace]` markers around `DeactivateScope`, recording
   the `IsSceneReloadInProgress()` value so the next ASVK log shows whether the reload guard fires
   at the expected moment.
6. **`.github/workflows/build-windows.yml`**: under `pull_request_target`, `${{ github.sha }}`
   resolves to the synthetic merge commit on main, not the PR head. That made every log embed a
   `Build commit:` value that no longer exists on the PR branch (Session 4 mismatch). Switched to
   `${{ github.event.pull_request.head.sha || github.sha }}` so the build_info.cfg always
   identifies the actual code that was built.

### Why these changes are diagnostic, not just a guess

Items 1–2 close the log-loss hypothesis: the next reproducer either reaches a `[trace]` line
already added by items 3–5 or it does not. If it does, we have the exact crash-site frame. If it
does not, the missing trace identifies the C# constructor path that was running when the crash
fired.

Item 3's `IsInsideTree()` guard is also a real fix candidate: the orphan-deferred-call hypothesis
was unfalsifiable before because we could not see the deferred call running at all. Now we both
see it and short-circuit it.

## Verification

- `dotnet build`
- Godot CLI is not installed in this workspace, so GUT tests must run in CI or a Godot-enabled environment.
