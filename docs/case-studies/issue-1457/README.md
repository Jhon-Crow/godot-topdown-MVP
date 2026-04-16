# Case Study: Issue #1457 - Enemy Catches on Walls While Pursuing

## Summary

Issue #1457 reports that an enemy "bugs against the wall", visually catches on a wall or passage corner, and cannot immediately continue along the path. The provided screenshots show a valid yellow navigation path while the enemy body is physically pinned at a wall edge or narrow doorway.

This case study starts from current `main` after two failed solution attempts:

- PR #1477 tried broad stuck detection, cover/position blacklists, escape impulses, `MOTION_MODE_FLOATING`, and nav resets. It grew into a large behavior change and later sessions mixed real wall-stuck reports with unrelated wrong-binary / script-load symptoms.
- PR #1557 tried changing the wall avoidance raycast logic and `path_max_distance`. It fixed one class of corner rubbing but made narrow passage traversal worse, because suppressing or normalizing lateral wall forces is very sensitive inside corridors.

The new fix avoids another wall-avoidance rewrite. It changes two lower-level assumptions that match Godot's navigation and physics documentation:

1. Enemies are top-down `CharacterBody2D` actors, so wall contacts should be handled in `MOTION_MODE_FLOATING` with `wall_min_slide_angle = 0.0`.
2. `NavigationAgent2D.target_position` should not be assigned every physics frame for the same cover target, because that requests a new path and can make agents dance or look backward near navmesh edges.

## Collected Data

Raw data is stored under `docs/case-studies/issue-1457/`:

- `data/issue-1457.json` and `data/issue-1457-comments.json`: issue body and owner comments.
- `failed-prs/pr-1477.json`, `failed-prs/pr-1477.diff.gz`: first failed attempt metadata and compressed diff.
- `failed-prs/pr-1557.json`, `failed-prs/pr-1557.diff.gz`: second failed attempt metadata and compressed diff.
- `failed-prs/pr-1560-related-ai-regression-tests.json`: related regression-test PR for "AI completely broken" failure classes.
- `logs/`: 19 downloaded game logs from the issue and failed PR comments.
- `screenshots/`: 7 downloaded PNG screenshots from the issue and failed PR comments.
- `data/attachment-urls.txt`: source URL list for downloaded attachments.

PNG headers were verified with `head -c 8 | od` because the `file` utility is not installed in this environment. All screenshot files begin with the PNG signature.

## Timeline

| Date | Source | Event |
| --- | --- | --- |
| 2026-03-24 | Issue #1457 | Initial report with screenshot and three logs. Enemy path line is valid, but the body is caught at a wall/passage edge. |
| 2026-03-24 to 2026-03-26 | PR #1477 | Multiple fixes attempted: reduced nav wall avoidance, stuck reroutes, cover and position blacklists, escape impulses, `MOTION_MODE_FLOATING`. Logs still showed repeated stuck positions and later wrong-binary/script-load failures. |
| 2026-03-26 | Issue comment | Owner says the previous attempt failed and requests a new approach. |
| 2026-03-26 to 2026-04-11 | PR #1557 | Wall-avoidance rewrite attempted. Owner reports "gets stuck in lower part of passage", then "not fixed", then "now worse, cannot pass the passage at all". |
| 2026-04-11 | Issue comment | Owner asks to start from current `main`, collect failed-attempt data, reconstruct events, and find a new approach. |
| 2026-04-16 | PR #1856 | New branch starts from current `main` with only generated placeholder commit on top. |

## Log Findings

The logs show three distinct symptom families:

1. Real navigation/physics sticking:
   - Original logs from `20260324_200456`, `200849`, and `201259` show repeated `PURSUING corner check` lines, often flipping to near `-180 deg`. This matches a path waypoint temporarily behind the actor or a body sliding at a wall while the visual facing system follows unstable path positions.
   - PR #1477 logs add explicit `[#1457] PURSUING stuck` messages around positions such as `(492, 663)` and `(1760, 824)`, confirming that earlier fixes detected the stuck but often rerouted into the same geometry.
   - PR #1557 logs show the later wall-avoidance approach regressed narrow passages: repeated low-angle checks around `7 deg` in `game_log_20260327_100332.txt`, then the owner reports the passage is worse in `game_log_20260327_110427.txt`.

2. Wrong-binary or script-load symptoms:
   - Several logs from March 25-26 show `Enemy tracking complete: 0 enemies registered` and `has_died_signal=False` for all enemies. These do not match wall navigation; they indicate the exported binary did not load the expected GDScript enemy script/signals. Those sessions should not drive the wall-navigation fix.

3. Configuration amplifying visibility of the bug:
   - Many sessions have `Global stuck max time: 20.0s`, so the global fallback was intentionally delayed. The wall catch therefore remains visible for much longer than the default global stuck timer.

## Root Causes

### Root Cause 1: Grounded CharacterBody2D Semantics in a Top-Down Game

Current `main` leaves enemies in the default `CharacterBody2D` motion mode. Godot 4.3 documents `MOTION_MODE_GROUNDED` as suitable when walls, floors, ceilings, and slopes matter. For this game, all collisions should be wall-style top-down contacts. Godot also documents `MOTION_MODE_FLOATING` as the mode to use when all collisions should be reported as walls.

Godot 4.3 also documents `wall_min_slide_angle` defaulting to `0.261799` radians (15 degrees), and says it only affects movement in floating mode. That default is a friction-like dead zone for shallow wall contacts. The owner explicitly suspected wall "friction"; setting it to `0.0` removes that minimum slide threshold for top-down enemies.

External engine issue godotengine/godot#109926 documents a `CharacterBody2D.move_and_slide()` corner case where wall-corner contact can be classified like floor behavior in grounded motion. The project logs and screenshots match the shape of that failure: path is valid, body is caught at an edge.

### Root Cause 2: Per-Frame Navigation Target Repathing

Current `main` assigns `_nav_agent.target_position = target_pos` every time `_get_nav_direction_to()` is called. Godot 4.3 documents that setting `target_position` requests a new navigation path. The navigation-agent guide calls out two relevant symptoms from very frequent path updates: an agent can dance between positions, and it can look backward for a frame near navmesh edges or edge connections.

The original logs repeatedly show near-backward `PURSUING corner check` angles around `-170 deg` to `-180 deg`, especially while the enemy is at narrow wall geometry. That makes per-frame path churn a plausible contributor even when the navmesh itself has a valid path.

### Root Cause 3: Wall Avoidance Is a Bad Place to Patch This Bug

The failed PR #1557 analysis is useful because it demonstrates why side-ray wall avoidance is too brittle here:

- weakening side avoidance helps wall corners but removes corridor-centering;
- strengthening side avoidance helps corridors but can push enemies into corner edges;
- bilateral side-wall cancellation can be amplified if the tiny residual vector is normalized.

The new fix deliberately leaves `_check_wall_ahead()` and `_apply_wall_avoidance()` unchanged.

## Online Research

Primary sources used:

- Godot 4.3 `CharacterBody2D` docs: `MOTION_MODE_FLOATING` is recommended when all collisions should be walls; `wall_min_slide_angle` defaults to 15 degrees and affects floating movement.
  - https://docs.godotengine.org/en/4.3/classes/class_characterbody2d.html
- Godot 4.3 `NavigationAgent2D` docs: setting `target_position` requests a new path; `get_next_path_position()` advances internal path logic once per physics frame.
  - https://docs.godotengine.org/en/4.3/classes/class_navigationagent2d.html
- Godot 4.3 NavigationAgent guide: very frequent path updates can make agents dance between positions or briefly look backward near navmesh edges.
  - https://docs.godotengine.org/en/4.3/tutorials/navigation/navigation_using_navigationagents.html
- Godot 4.3 NavigationAgent avoidance guide: avoidance has no information from navigation meshes or physics collisions and does not affect pathfinding.
  - https://docs.godotengine.org/en/4.3/tutorials/navigation/navigation_using_navigationagents.html#navigationagent-avoidance
- Godot engine issue #109926: `CharacterBody2D.move_and_slide()` can treat a wall corner like floor behavior in grounded-style motion.
  - https://github.com/godotengine/godot/issues/109926

## Implemented Fix

### `scripts/objects/enemy.gd`

- In `_ready()`, set:
  - `motion_mode = CharacterBody2D.MOTION_MODE_FLOATING`
  - `wall_min_slide_angle = 0.0`
- Add a small navigation-target cache:
  - `_nav_target_cache`
  - `_nav_has_target`
  - `NAV_TARGET_REPATH_DISTANCE = 24.0`
- Update `_get_nav_direction_to()` so a new path is requested only when:
  - there is no cached target yet;
  - the requested target moved more than one enemy radius (`24px`);
  - the agent reports navigation finished but the enemy is still outside the target reach distance.
- Reset cached navigation target and ORCA avoidance velocity during `_reset()`, including `set_velocity_forced(Vector2.ZERO)` for the avoidance simulation after respawn/teleport-style position reset.

## Regression Tests

Added `tests/unit/test_enemy_navigation_issue_1457.gd`:

- instantiates `Enemy.tscn` and verifies `_ready()` applies `MOTION_MODE_FLOATING` plus `wall_min_slide_angle = 0.0`;
- verifies those motion-mode assignments remain present in `enemy.gd`;
- verifies the navigation target cache markers exist;
- simulates the target-cache threshold so small jitter does not repath and meaningful movement still does;
- verifies the fixed wall slide angle is less restrictive than Godot's 15-degree default.

## Proposed Alternatives Considered

- Reapply PR #1477 stuck blacklists/impulses: rejected because it recovers after the symptom instead of preventing the body/path instability and adds large state-specific complexity.
- Reapply PR #1557 wall-avoidance rewrite: rejected because owner feedback showed this made narrow passage traversal worse.
- Increase `path_max_distance`: rejected for this fix because frequent repath triggers were already implicated in the NavigationAgent docs and in the failed attempts.
- Add external navigation libraries: not needed; Godot's built-in `NavigationAgent2D` and `CharacterBody2D` already cover the required behavior when configured for top-down movement.
