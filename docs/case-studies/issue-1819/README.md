# Case Study: Issue #1819

**Issue URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1819  
**PR URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1842  
**Status:** Re-opened during PR review after owner reproduction on the latest build

## Requirement

Original issue text requires two behaviors:

1. If the player presses RMB for the handoff step but keeps holding `G`, aiming must not appear and throwing must remain impossible until `G` is released.
2. If the player releases `G` before the right hand completes the transfer, the grenade must be dropped at the player's feet, whether activated or not.

## Evidence Collected

- `issue-view.json`: current issue title/body snapshot
- `pr-view.json`: current PR metadata and description
- `pr-comments.json`: PR conversation history including owner feedback
- `game_log_20260416_000608.txt`: owner-provided reproduction log from the latest build
- `game_log_20260416_014229.txt`: owner-provided follow-up log for the revised regression
- `log-key-lines.txt`: extracted grenade-related lines from the reproduction log
- `pr-files.json`: current PR file list and commit history

## Timeline

| Time | Event |
|---|---|
| 2026-04-15 20:25 UTC | Initial PR commit landed with complex grenade handoff changes. |
| 2026-04-15 20:44 UTC | Follow-up PR commit tightened the complex aiming state machine. |
| 2026-04-15 21:08 UTC | Owner reported the grenade still throws while `G` remains held in the latest build and attached `game_log_20260416_000608.txt`. |
| 2026-04-15 22:xx UTC | Evidence review showed the reproduction log was from a build running with `Complex grenades: false`, so the tested code path was the simple grenade path, not the complex one. |
| 2026-04-15 22:48 UTC | Owner reported a second simple-path regression: after activation, pressing RMB and only then releasing `G` still showed the aim reticle even when the handoff event ordering was wrong, and attached `game_log_20260416_014229.txt`. |

## Findings

### 1. The owner reproduced on the simple grenade path

The attached log explicitly shows:

- `ExperimentalSettings initialized ... Complex grenades: false`
- repeated `Mode check: complex=False, settings_node=True`

This means the original PR changes to the complex state machine did not affect the owner's tested path.

### 2. The simple path still allowed throw preparation while `G` was held

In both implementations:

- C#: `HandleSimpleGrenadeAimingState()`
- GDScript: `_handle_simple_grenade_aiming_state()`

the code allowed the grenade to proceed to aiming and throw on RMB release without first requiring `G` to be released.

That behavior matched the old simple-mode comment, but it did not match the issue wording or the owner's review feedback.

### 3. The root cause was scope mismatch, not only state-machine logic

The previous fix correctly hardened the complex path, but the reported gameplay problem existed in a broader rule:

> the grenade must not be throwable while `G` is still held during the handoff.

The implementation enforced that only for complex mode, while the tested build was running simple mode.

### 4. The first simple-path fix still used a level-trigger instead of an edge-trigger

The follow-up owner log showed repeated

- `RMB pressed after pin pull - starting trajectory aiming`
- `G still held during right-hand aiming - waiting for release before aim/throw`

That proved the simple state machine entered its aiming sub-state as soon as RMB was pressed and merely suppressed the throw while `G` stayed down.

The missing rule was stricter:

> the reticle should become active only on the exact frame where `G` is released while RMB is already held for the handoff.

Without that edge-trigger requirement, the code still accepted a stale `SimpleAiming` state and enabled aiming after a later `G` release even though the intended handoff sequence had already been broken.

## Solution Direction

The fix was expanded so both grenade paths obey the same handoff rule:

- complex mode still blocks aiming/throw until `G` is released
- simple trajectory mode now also requires the actual `G` release event while RMB is held; if that event is missed, the state machine falls back to waiting for RMB again instead of showing the reticle

Regression coverage was extended to include the simple aiming path and the exact release-order edge case from the latest owner feedback.
