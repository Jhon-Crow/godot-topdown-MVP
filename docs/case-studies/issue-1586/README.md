# Issue 1586 Case Study: ASVK Maximum Aiming Range

## Request

Issue #1586 asks to make the ASVK maximum aiming distance larger by 30000 px.
Repeated owner comments reported that previous attempts did not work and suspected a C# / GDScript conflict.

## Data Collected

- `data/issue-1586.json` - issue title, body, comments, timestamps, and state.
- `data/issue-1586-comments.json` - paginated issue comments.
- `data/pr-1865.json` - current PR metadata.
- `data/pr-1865-review-comments.json` - inline PR review comments.
- `data/pr-1865-conversation-comments.json` - PR discussion comments.
- `data/pr-1865-reviews.json` - PR reviews.
- `data/recent-ci-runs.json` - latest CI runs for `issue-1586-5ab025c700ad`.
- `game_log_20260417_033846.txt` - owner-provided exported-game log from the failed PR verification.
- `pr-comments/` - refreshed PR comments, inline comments, and reviews after the failed verification.
- `ci-logs/recent-runs-after-feedback.json` - refreshed CI run list after the failed verification.

## Timeline

- 2026-03-26: Issue opened with the ASVK range request.
- 2026-03-28 to 2026-04-11: Owner reported several previous attempts did not work.
- 2026-04-11: Owner specifically suspected a C# and GDScript conflict.
- 2026-04-16: Owner asked to try again; PR #1865 was created for this branch.
- 2026-04-17 00:40 UTC: Owner reported in PR #1865 that the aim sight distance still did not change and attached `game_log_20260417_033846.txt`.
- 2026-04-17: The attached log shows the exported build equipped `SniperRifle` successfully, so the remaining failure was in visual scope/crosshair travel rather than weapon selection.

## Root Cause

The ASVK range existed in more than one effective location:

- `resources/weapons/SniperRifleData.tres` configured `Range = 5000.0`.
- `Scripts/Weapons/SniperRifle.cs` also hardcoded `float maxRange = 5000.0f` in all ASVK hitscan endpoint paths.
- `Scripts/Weapons/SniperRifle.cs` capped scope/crosshair travel with `MaxScopeZoomDistance = 4.0f`, which on normal viewports is only a few thousand pixels and does not reach the new 30000 px ASVK range.

Changing only a resource or only a C# hitscan constant could leave the exported game visibly aiming at the old practical distance because the scope camera/crosshair system still had an independent viewport-based cap. This matches the owner's C# / GDScript conflict suspicion and the later report that the "дальность прицела" (aim sight distance) did not change.

## Fix

- Set `SniperRifleData.tres` ASVK `Range` to `30000.0`.
- Added `SniperRifle.GetMaxAimRange()` so C# hitscan and time-stop dry-run paths read `WeaponData.Range`.
- Replaced the old `5000.0f` hardcoded max range in normal, breaker, and deferred endpoint calculations.
- Updated scope/crosshair maximum travel to derive its viewport multiplier from `WeaponData.Range`, so RMB aiming can reach 30000 px instead of stopping at the old `4.0x` viewport cap.
- Updated the sniper laser visual path to use the same `GetMaxAimRange()` helper as hitscan and scope.
- Added regression tests that verify the resource range, C# hitscan range, visual scope range, and laser visual range all use the same ASVK range source.

## Verification

Local verification commands and CI status are recorded in the PR and shell logs for this branch.
