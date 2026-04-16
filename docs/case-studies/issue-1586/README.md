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

## Timeline

- 2026-03-26: Issue opened with the ASVK range request.
- 2026-03-28 to 2026-04-11: Owner reported several previous attempts did not work.
- 2026-04-11: Owner specifically suspected a C# and GDScript conflict.
- 2026-04-16: Owner asked to try again; PR #1865 was created for this branch.

## Root Cause

The ASVK range existed in more than one effective location:

- `resources/weapons/SniperRifleData.tres` configured `Range = 5000.0`.
- `Scripts/Weapons/SniperRifle.cs` also hardcoded `float maxRange = 5000.0f` in all ASVK hitscan endpoint paths.

Changing only a resource or only a C# constant could leave the exported game using the old 5000 px range in another path. This matches the owner's C# / GDScript conflict suspicion.

## Fix

- Set `SniperRifleData.tres` ASVK `Range` to `30000.0`.
- Added `SniperRifle.GetMaxAimRange()` so C# hitscan and time-stop dry-run paths read `WeaponData.Range`.
- Replaced the old `5000.0f` hardcoded max range in normal, breaker, and deferred endpoint calculations.
- Added regression tests that verify the resource range and that C# no longer hardcodes `float maxRange = 5000.0f`.

## Verification

Local verification commands and CI status are recorded in the PR and shell logs for this branch.
