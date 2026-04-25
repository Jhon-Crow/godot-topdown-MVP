# Issue 1632 Case Study: Chemical Cloud Illusions

## Source Data

- `logs/game_log_20260425_223524.txt`
- `logs/game_log_20260425_223813.txt`
- `github/issue-1632.txt`
- `github/issue-1632-comments.json`
- `github/pr-1914.json`
- `github/pr-1914-comments.json`

The two gameplay logs were attached to PR #1914 on 2026-04-25 after the owner reported that the gas cloud was visible but illusion copies did not seem to appear.

## Timeline

- 2026-04-20: PR #1914 added wall-safe validation before moving the original enemy during illusion cluster creation.
- 2026-04-20: CI passed and the PR was marked ready.
- 2026-04-25: The owner reported that illusion copies appeared absent while gas was visible and attached two Windows gameplay logs.
- 2026-04-25: This case study preserved the logs and PR/issue metadata in this directory.

## Log Reconstruction

In `game_log_20260425_223524.txt`, the first chemical cloud at `(1444.875, 3078.863)` logs `Player not in range (719px), no illusions spawned`. A later cloud at `(2644.862, 3099.771)` logs `Spawned 10 illusion copies for 22 enemies`.

In `game_log_20260425_223813.txt`, several chemical clouds log successful illusion creation, including `Spawned 10 illusion copies for 22 enemies` and `Spawned 10 illusion copies for 23 enemies`. The illusion spawn lines are mostly for enemies around coordinates such as `(300, 2670)`, `(3700, 2670)`, `(300, 1890)`, and `(3700, 1890)`.

The important pattern is that the logs do not show a hard spawn failure. They show that the per-cloud cap was spent on the first alive enemies returned by the scene tree, which can be far from the active gas/player encounter. From the player's viewpoint near the visible gas cloud, that looks like copies did not appear.

## Root Cause

`ChemicalCloud._spawn_illusions_for_nearby_enemies()` used `get_nodes_in_group("enemies")` in scene-tree order and stopped after `max_illusions_per_cloud` copies. The code and comments described nearby illusion copies, but the implementation did not prioritize enemies near the cloud.

On maps with many enemies, especially Railway Station, the first enemies in group order can be distant map fixtures. The cloud still reaches the illusion cap, but those copies can be off screen or far away from the gas, creating a user-visible false negative.

## Fix Direction

Prioritize alive enemies by distance to the chemical cloud before spending the per-cloud illusion cap. Keep the existing Issue #1632 wall checks in place so the original enemy still cannot be teleported into or through obstacle geometry.

## Verification Targets

- Unit coverage should assert that alive enemies are sorted nearest to the cloud first and dead enemies are excluded.
- Existing wall validation tests should continue to reject destinations inside walls and paths crossing walls.
- Manual verification should reproduce the Railway Station chemical grenade flow and confirm that illusion copies appear around enemies local to the visible gas encounter.
