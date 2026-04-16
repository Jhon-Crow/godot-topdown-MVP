# Issue 1831 Case Study

## Summary

Issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1831

Request: when an item becomes available during play, show a top-screen Armory notification for 4 seconds with text `Открыто ... !`, slide-in/slide-out animation, a golden frame, and a shine animation similar to a Steam achievement notification.

## Collected Data

- `data/issue.json`: issue title, body, metadata, and empty comment list from GitHub.
- `data/issue-comments.json`: current issue comments from the GitHub API.
- `data/pr-1859.json`: prepared PR metadata and status before implementation.
- `data/related-prs-armory-unlock.json`: recent merged PRs involving Armory/unlock behavior.
- `data/related-prs-gold-shine.json`: recent merged PRs involving the gold shine visual language.
- `online-research.md`: external references used for the implementation approach.

## Timeline

- 2026-04-13 19:18:30 UTC: issue #1831 opened with the unlock notification requirement.
- 2026-04-16: prepared branch `issue-1831-8dd128f0f3cf` and draft PR #1859 existed with only the placeholder `.gitkeep` commit.
- 2026-04-16: local investigation found that `UnlockManager` emits availability signals and Armory slots/score buttons already use gold highlighting, but no global toast UI listened to those signals.

## Existing System

- `UnlockManager` owns the unlock condition tables and emits:
  - `items_unlocked_by_condition(level_path)` when level-progress conditions become satisfied.
  - `items_unlocked_by_kill_condition` when stat-driven conditions become satisfied.
- `ArmoryMenu` checks `UnlockManager.is_*_condition_met(...)` and highlights locked, available slots in gold.
- Several level score screens call `UnlockManager.has_any_available_unlock()` to highlight the Armory button.
- The repo already has a reusable `scripts/shaders/gold_shine.gdshader` used by Armory slots, accordion buttons, and the Apply button.

## Root Cause

The unlock system had condition detection and gold visual affordances, but no top-level UI component that converted unlock availability signals into an immediate player-facing notification.

Because availability is not the same as permanent equipment unlock in this project, the notification must listen to the availability signals and announce locked items whose conditions just became satisfied. The Armory still remains responsible for the permanent unlock action by LMB hold.

## Solution Direction

Add a global `UnlockNotificationManager` autoload:

- Extends `CanvasLayer` so the toast is drawn above gameplay and menus.
- Uses the existing Armory icon asset.
- Reuses `gold_shine.gdshader` for the requested shine animation.
- Queues notifications so several items becoming available from one condition are shown one after another.
- Seeds already-available locked items on startup so old save progress does not replay stale notifications.
- Shows only newly available locked items, avoiding notifications for already-open items.
- Keeps each toast visible for exactly `4.0` seconds between slide-in and slide-out.

## Alternatives Considered

1. Add the notification only inside `ArmoryMenu`.
   - Rejected because the issue asks for notification when the item becomes available during play, and Armory may not be open.

2. Trigger from `GameManager.unlock_weapon`, `GrenadeManager.unlock_grenade`, and `ActiveItemManager.unlock_active_item`.
   - Rejected as the primary trigger because those methods run after the player manually opens the case in Armory. The issue wording follows the existing system language: items "become available" when conditions are met.

3. Use a third-party toast/notification plugin.
   - Rejected because the repo already has the necessary UI, shader, translation, and signal infrastructure, and a small native autoload keeps the dependency surface lower.

## Validation Plan

- Add regression tests for:
  - manager script existence,
  - requested `Открыто ... !` text,
  - 4-second display duration,
  - only locked items with met conditions being collected.
- Run targeted GUT test when a Godot binary is available:
  - `godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_unlock_notification_manager -gexit`
- Run broader checks:
  - GUT unit/integration suite,
  - `dotnet build`,
  - repository CI after push.

## Local Validation

- `git diff --check`: passed.
- `dotnet build`: passed.
- `Godot_v4.3-stable_mono_linux.x86_64 --headless -s addons/gut/gut_cmdln.gd -gselect=test_unlock_notification_manager -gexit`: passed 4 tests / 12 assertions.
