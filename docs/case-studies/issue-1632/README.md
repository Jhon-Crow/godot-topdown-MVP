# Issue 1632 Case Study: Chemical Cloud Illusions

## Source Data

- `logs/game_log_20260425_223524.txt`
- `logs/game_log_20260425_223813.txt`
- `logs/game_log_20260425_232347.txt`
- `github/issue-1632.txt`
- `github/issue-1632-comments.json`
- `github/pr-1914.json`
- `github/pr-1914-comments.json`

The first two gameplay logs were attached to PR #1914 on 2026-04-25 after the owner reported that the gas cloud was visible but illusion copies did not seem to appear. A third gameplay log was attached later the same day after the owner reported that the effect could trigger when the player did not touch the smoke and that too few copies appeared. The owner then clarified that the first touch of gas should immediately create 3-4 illusion copies per affected enemy, with only later copies added progressively over time.

## Timeline

- 2026-04-20: PR #1914 added wall-safe validation before moving the original enemy during illusion cluster creation.
- 2026-04-20: CI passed and the PR was marked ready.
- 2026-04-25: The owner reported that illusion copies appeared absent while gas was visible and attached two Windows gameplay logs.
- 2026-04-25: PR #1914 sorted alive enemies by distance to the chemical cloud before spending the per-cloud cap.
- 2026-04-25: The owner reported two follow-up regressions: the effect can trigger before the player touches visible smoke, and some clouds create too few copies.
- 2026-04-25: The owner clarified that first gas contact should immediately create 3-4 copies per enemy, before progressive spawning adds later copies.
- 2026-04-25: This case study preserved the logs and PR/issue metadata in this directory.

## Log Reconstruction

In `game_log_20260425_223524.txt`, the first chemical cloud at `(1444.875, 3078.863)` logs `Player not in range (719px), no illusions spawned`. A later cloud at `(2644.862, 3099.771)` logs `Spawned 10 illusion copies for 22 enemies`.

In `game_log_20260425_223813.txt`, several chemical clouds log successful illusion creation, including `Spawned 10 illusion copies for 22 enemies` and `Spawned 10 illusion copies for 23 enemies`. The illusion spawn lines are mostly for enemies around coordinates such as `(300, 2670)`, `(3700, 2670)`, `(300, 1890)`, and `(3700, 1890)`.

The important pattern is that the logs do not show a hard spawn failure. They show that the per-cloud cap was spent on the first alive enemies returned by the scene tree, which can be far from the active gas/player encounter. From the player's viewpoint near the visible gas cloud, that looks like copies did not appear.

In `game_log_20260425_232347.txt`, the later review build shows two additional patterns:

- The first pair of chemical clouds at `(74.44795, 1335.873)` and `(73.59083, 1258.724)` are created with `grow_in=5.62s`. The first cloud immediately spawns 10 illusions, then the second cloud logs `Global illusion cap reached (12), stopping` after only 2 copies. This matches the owner report that there are too few copies: a nearby cloud can inherit only the last global slots after another cloud consumes 10/12.
- Clouds are spawned with a visual grow-in, but the player range check used the final `cloud_radius` immediately. That lets the gameplay effect trigger while the visible gas is still scaled smaller than the final radius, matching the report that the effect can trigger before the player touches the smoke.

## Root Cause

`ChemicalCloud._spawn_illusions_for_nearby_enemies()` used `get_nodes_in_group("enemies")` in scene-tree order and stopped after `max_illusions_per_cloud` copies. The code and comments described nearby illusion copies, but the implementation did not prioritize enemies near the cloud.

On maps with many enemies, especially Railway Station, the first enemies in group order can be distant map fixtures. The cloud still reaches the illusion cap, but those copies can be off screen or far away from the gas, creating a user-visible false negative.

The follow-up regressions had separate causes:

- The grow-in visual scaled the cloud from zero to full size, but `_is_player_in_range()` still checked against the full final radius.
- The local-priority fix preserved the old per-cloud cap of 10 while the global cap is 12. When gas-mask enemies throw several chemical grenades close together, one cloud can consume most of the global illusion budget and leave the next visible cloud with only 1-2 copies.
- The initial cluster size was still using the historical 2-6 random range. That allowed first-contact clusters smaller than the owner-specified 3-4 copies per enemy.

## Fix Direction

Prioritize alive enemies by distance to the chemical cloud before spending the per-cloud illusion cap. Keep the existing Issue #1632 wall checks in place so the original enemy still cannot be teleported into or through obstacle geometry.

For the follow-up reports:

- Use the effective grown cloud radius for player-trigger checks while the gas visual is still growing.
- Use a dedicated 3-4 copy range for first-contact clusters, then leave progressive spawning to add later copies over time.
- Avoid spending the last few initial-spawn slots on partial clusters that visibly look too small compared with the intended 3-4 first-contact copies per enemy.

## Verification Targets

- Unit coverage should assert that alive enemies are sorted nearest to the cloud first and dead enemies are excluded.
- Existing wall validation tests should continue to reject destinations inside walls and paths crossing walls.
- Unit coverage should assert that grow-in range checks use the effective visible cloud radius.
- Unit coverage should assert that first-contact clusters use the owner-specified 3-4 copy range.
- Unit coverage should assert that an initial cluster is skipped when remaining budget cannot create the randomized cluster size.
- Manual verification should reproduce the Railway Station chemical grenade flow and confirm that illusion copies appear around enemies local to the visible gas encounter.
