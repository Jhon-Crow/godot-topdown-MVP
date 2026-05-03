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

The crash pattern is scene-owned weapon overlays being explicitly `QueueFree()`-ed from weapon `_ExitTree()` while `GameManager.restart_scene()` is already tearing down the current scene.

### Revolver HUD

**File:** `Scripts/Weapons/Revolver.cs`

`SetupCylinderHUD()` creates a `RevolverCylinderHUDLayer` as a direct child of the level root. The revolver stores a reference to the nested `RevolverCylinderUI`, but the revolver does not own that node. During `reload_current_scene()`, the level root already owns freeing the HUD layer and its children.

The old `_ExitTree()` called `_cylinderUI.QueueFree()` anyway. That could queue a scene-owned HUD node for deletion while the outgoing scene was already being freed.

### ASVK Scope Overlay

**File:** `Scripts/Weapons/SniperRifle.cs`

`CreateScopeOverlay()` creates a `ScopeOverlay` `CanvasLayer` and adds it to `GetTree().CurrentScene`, not as a child of the ASVK node. When ASVK exits during a scene reload with the scope active, `_ExitTree()` called `DeactivateScope()`, and `DeactivateScope()` called `RemoveScopeOverlay()`, which always called `_scopeOverlay.QueueFree()`.

That is the same ownership error as the revolver HUD, and it matches the owner follow-up that ASVK still crashed.

## Fix

### GameManager

Added `is_reloading_scene()` so C# weapon cleanup code can distinguish normal weapon removal from current-scene teardown.

### ASVK

Changed ASVK `_ExitTree()` to:

- Query `GameManager.is_reloading_scene()`.
- During scene reload, deactivate local scope state and camera offset without explicitly queue-freeing the `ScopeOverlay` or emitting teardown signals.
- During normal scope release or non-reload weapon removal, keep the existing behavior and queue-free the overlay.

### Revolver

Kept the previous correction: `_ExitTree()` disconnects the cylinder UI reference but does not queue-free the level-owned HUD.

## Regression Test

Added `tests/unit/test_issue_1927_scene_reload_overlay_cleanup.gd`.

The test locks down the ownership contract:

- `GameManager` exposes the reload guard.
- ASVK checks the reload guard from `_ExitTree()`.
- ASVK overlay cleanup makes explicit queue-free optional.
- Revolver no longer calls `_cylinderUI.QueueFree()`.

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
- The first PR fixed the revolver-specific instance, but ASVK had the same ownership pattern

## Verification

- `dotnet build`
- Godot CLI is not installed in this workspace, so GUT tests must run in CI or a Godot-enabled environment.
