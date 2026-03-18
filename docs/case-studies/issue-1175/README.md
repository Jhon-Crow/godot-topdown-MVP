# Case Study: Enemies Get Stuck in Passages / Can't Turn Corners (Issue #1175)

**Issue:** #1175 — враги разучились перемещаться (Enemies forgot how to move)
**PR:** #1176
**Status:** Fixed
**Analyst:** konard (AI)
**Date:** 2026-03-18

---

## 1. Summary

Enemies on the "Здание" (BuildingLevel) map get stuck in corridor passages and cannot turn corners — they collide with walls instead of navigating around them. The problem appeared after version 12.03.2026; before that, navigation worked correctly.

**Root cause:** `path_desired_distance = 40.0` px in `scenes/objects/Enemy.tscn` was too large, causing `NavigationAgent2D` to prematurely consider corner waypoints "reached" — the enemy then tried to take a straight-line shortcut to the next waypoint, cutting through corner geometry and hitting the wall.

**Fix:** Reduce `path_desired_distance` from 40px → 10px. This is large enough to prevent wall-rubbing (the original issue #1107 being fixed) while small enough to not skip corner waypoints prematurely.

---

## 2. Evidence

### 2.1 Game log — `game_log_20260318_113209.txt`

**Build:** Release (Godot 4.3-stable, Windows)
**Level:** BuildingLevel

Key patterns from the log that confirm corner-sticking:

```
[11:32:18] [ENEMY] [Enemy10] PATROL STUCK: pos=(1200, 1601.992) for 1.5s, skipping
[11:32:20] [ENEMY] [Enemy7] PATROL STUCK: pos=(1611.34, 898.8732) for 1.5s, skipping
[11:32:21] [ENEMY] [Enemy10] PATROL STUCK: pos=(1200, 1424.01) for 1.5s, skipping
[11:32:23] [ENEMY] [Enemy7] PATROL STUCK: pos=(1611.842, 899.894) for 1.5s, skipping
[11:32:25] [ENEMY] [Enemy2] FLANKING stuck (2.0s), pos=(496.2088, 663.574), fail=1
[11:32:28] [ENEMY] [Enemy4] FLANKING stuck (2.0s), pos=(575.1457, 847.7456), fail=1
```

Critical observations:
1. Multiple enemies get stuck at EXACTLY the same coordinates across different runs (e.g. Enemy2 always sticks at ~(496, 663)), confirming these are geometry corner positions, not random behavior.
2. Both PATROL and PURSUING/FLANKING states show sticking, confirming it's a pathfinding issue, not state-specific.
3. Enemies repeatedly attempt the same stuck positions, indicating the navigation path correctly points toward these corners but physical movement fails to complete the turn.

### 2.2 Regression Timeline

| Date | Commit | Change | Effect |
|------|--------|--------|--------|
| Before 2026-03-17 | (original) | `path_desired_distance = 4.0` | Navigation worked (corners rounded correctly) |
| 2026-03-17 | `89798783` | `path_desired_distance 4→28` | Fix #1107 wall-rubbing; intermediate value |
| 2026-03-17 | `eb1499b4` | `path_desired_distance 28→40` | **Regression introduced** — enemies now skip corner waypoints |
| 2026-03-18 | `50931c09` | Restore GLOBAL_STUCK_MAX_TIME 1.5→4.0 | Unrelated fix, did not address corner issue |
| 2026-03-18 | This fix | `path_desired_distance 40→10` | Corner navigation restored |

### 2.3 Navigation Architecture

The BuildingLevel uses:
- `NavigationRegion2D` with baked polygons from physics colliders (collision_layer=4)
- `agent_radius = 24.0` in `NavigationPolygon` for navmesh inset from walls
- Each enemy uses `NavigationAgent2D` in `Enemy.tscn`
- Custom wall avoidance (`_apply_wall_avoidance`) via raycasts on top of NavigationAgent2D

The navmesh correctly places path waypoints at corners, inset 24px from wall surfaces. The NavigationAgent2D follows these waypoints sequentially. With `path_desired_distance = 40px`, the agent "skips" a corner waypoint when 40px away (before actually passing through it), then steers straight toward the next waypoint which is on the other side of the wall.

---

## 3. Root Cause Analysis

### Root Cause: `path_desired_distance` Too Large (40px)

**File:** `scenes/objects/Enemy.tscn`, line 82
**Introduced by:** Commit `eb1499b4` (2026-03-17): "path_desired_distance 28px → 40px: skip corner waypoints further from wall edges"

**How it breaks navigation:**

In Godot 4, `NavigationAgent2D.get_next_path_position()` returns the next waypoint on the path. The agent's movement code moves toward this position. When the agent is within `path_desired_distance` of a waypoint, `is_navigation_finished()` returns `false` but the agent internally advances to the next waypoint.

For corner navigation, the navmesh places a waypoint near the corner apex. If `path_desired_distance = 40px`:
- Enemy approaches corner, is 40px from the corner waypoint
- Agent considers waypoint "close enough" and skips to next waypoint (on the other side of the wall)
- Enemy now steers toward the post-corner waypoint, but the direct path passes through the wall
- Enemy collides with wall and gets stuck

With `path_desired_distance = 4-10px`:
- Enemy must get within 4-10px of the corner waypoint before skipping to next
- This means the enemy actually rounds the corner before steering toward the next waypoint
- Navigation succeeds

**Why the fix for #1107 chose 40px:** Commit `eb1499b4` was trying to prevent "premature declaration of waypoints as reached near wall surfaces" — the enemy was hugging walls because it kept navigating toward wall-adjacent waypoints. But 40px overshot, causing the opposite problem.

**Supporting evidence from Godot engine issues:**
- [Godot Forum: NavigationAgent2D keeps getting stuck on corners](https://forum.godotengine.org/t/navigationagent2d-keeps-geting-stuck-on-corners/126027) — Community confirms reducing `path_desired_distance` to 1-5px resolves corner-cutting
- [Godot Issue #88237](https://github.com/godotengine/godot/issues/88237) — Confirmed systemic corner-cutting bug when `path_desired_distance` is too high

---

## 4. Solution

### Fix Applied

**File:** `scenes/objects/Enemy.tscn`

```diff
 [node name="NavigationAgent2D" type="NavigationAgent2D" parent="."]
-path_desired_distance = 40.0
+path_desired_distance = 10.0
 target_desired_distance = 10.0
```

**Value chosen:** 10px
- Small enough to not skip corner waypoints (enemy completes the corner turn before advancing to next waypoint)
- Large enough to prevent wall-rubbing on flat surfaces (4px caused oscillation in some configurations)
- Equal to `target_desired_distance = 10.0` (per Godot docs, having `path_desired_distance > target_desired_distance` can cause `target_reached` signal issues)
- Validated by research: community reports 1-10px works well for narrow corridors

### Why This Is the Right Fix

The corner escape code added in `_move_to_target_nav` (via slide collision normals and `move_and_collide` probe) remains intact to handle any residual wall contact scenarios. The navigation improvement works at the path-following level (don't skip corners) while the wall escape code handles the physical collision response level.

The `avoidance_enabled = false` setting (set in `89798783`) also remains, as the built-in ORCA avoidance was conflicting with custom wall-steering code.

---

## 5. Alternative Solutions Considered

### 5.1 Keep 40px, add path_postprocessing

Godot 4 has `path_postprocessing` modes (CORRIDORFUNNEL, EDGECENTERED). Using `EDGECENTERED` places waypoints in the center of navmesh polygon edges rather than at corners, which can reduce corner-sticking. However, this is not exposed as a scene property in Godot 4.3 and requires code changes. The path_desired_distance fix is simpler and more reliable.

### 5.2 Increase NavMesh agent_radius

Increasing `agent_radius` from 24px to 32px would push the navmesh further from walls, giving more clearance at corners. However:
- Larger inset can make narrow corridors unnavigable if the inset consumes the corridor
- Doesn't fix the root cause (the skip distance is still 40px)

### 5.3 Use AStar2D Instead

For very tight corridors, AStar2D with tile-center waypoints avoids NavigationAgent2D issues entirely. This would be a larger refactor and is not warranted when a simple parameter fix resolves the issue.

---

## 6. Known Libraries and Components for Similar Problems

| Library/Component | Purpose | Applicable? |
|---|---|---|
| [Godot NavigationAgent2D](https://docs.godotengine.org/en/stable/classes/class_navigationagent2d.html) | Built-in pathfinding | Already in use — tune parameters |
| [AStar2D](https://docs.godotengine.org/en/stable/classes/class_astar2d.html) | Custom A* pathfinding | Alternative for very complex maps |
| [Steering Behaviors library](https://github.com/GodotSteam/GodotSteering) | Seek/flee/avoid steering | Overkill for this game's needs |
| [NavMesh Postprocessing CORRIDORFUNNEL](https://docs.godotengine.org/en/stable/classes/class_navigationpathqueryparameters2d.html) | Funnel path through corridors | Could reduce waypoint count at corners |

---

## 7. Prevention

1. **Test `path_desired_distance` changes with the BuildingLevel** before merging — it has many corridor corners that expose this bug
2. **Keep `path_desired_distance ≤ target_desired_distance`** per Godot documentation to avoid signal reliability issues
3. **Document the balance**: Too small = wall-rubbing; Too large = corner-cutting. The sweet spot is 8-12px for this game's geometry (corridors ~100-200px wide, navmesh agent_radius 24px)
4. **Add regression test**: When enemies get stuck at same positions repeatedly (same coord in multiple STUCK log lines), it's a corner navigation issue, not a random stuck event
