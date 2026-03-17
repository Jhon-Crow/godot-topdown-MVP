# Case Study: Issue #1107 — Machete Enemy Pathfinding (Obstacle Avoidance)

## Issue Summary

**Title:** fix враг с мачете (fix machete enemy)

**Description (translated):** The machete enemy does not try to go around obstacles, but walks straight into the wall (directly toward the player). Teach it to effectively avoid obstacles.

**Screenshot:** Enemy pressed against a vertical wall corridor, trying to reach the player by moving straight through it.

---

## Root Cause Analysis

### Codebase Investigation

The enemy AI in `scripts/objects/enemy.gd` has multiple states (IDLE, COMBAT, PURSUING, FLANKING, SEEKING_COVER, IN_COVER, etc.).

**For machete enemies:**
1. **IDLE → PURSUING** (line 1352): When a machete enemy first spots the player, it transitions to PURSUING state (cover-to-cover movement) rather than directly to COMBAT.
2. **PURSUING → COMBAT** (line 2011-2013): When the enemy gets within `CLOSE_COMBAT_DISTANCE` (400px) of the player, it transitions to COMBAT.
3. **COMBAT state machete movement** (lines 1382-1395): Machete enemy in COMBAT calls `_move_to_target_nav(player_pos, combat_move_speed)`.

The `_move_to_target_nav` function (line 4763) uses `NavigationAgent2D` to compute a path, then applies `_apply_wall_avoidance` (raycast-based wall steering).

### The `_get_nav_direction_to` Function (Lines 4757-4761)

```gdscript
func _get_nav_direction_to(target_pos: Vector2) -> Vector2:
    if _nav_agent == null: return (target_pos - global_position).normalized()  # FALLBACK: direct
    _nav_agent.target_position = target_pos
    if _nav_agent.is_navigation_finished(): return Vector2.ZERO
    return (_nav_agent.get_next_path_position() - global_position).normalized()
```

**Critical fallback at line 4758:** If `_nav_agent` is null (NavigationAgent2D not found), returns direct direction toward target — no obstacle avoidance at all.

### Key Issues Identified

#### Issue A: No Stuck Detection in COMBAT State
The global stuck detection (line 806-833) only applies to PURSUING and FLANKING states. When a machete enemy is in COMBAT and gets stuck against a wall, there is **no recovery mechanism**. The enemy stays in COMBAT, keeps applying direct force toward the player, and remains pressed against the wall indefinitely.

#### Issue B: NavigationAgent2D `is_navigation_finished()` Returns True When No Path Found
In Godot 4, `NavigationAgent2D.is_navigation_finished()` returns `true` both when:
1. The target has been reached, AND
2. **No path exists** (target unreachable)

When no path is found (e.g., if the player is at a position outside the navigation mesh, or the navmesh isn't properly baked), the function returns `true`, causing `_get_nav_direction_to` to return `Vector2.ZERO` (enemy stops). However, if the navmesh is there but paths too close to walls (no margin), the agent follows a path that goes right up to the wall edge and tries to slide along it.

#### Issue C: Async NavigationAgent2D Target Setting
In Godot 4, setting `_nav_agent.target_position = target_pos` is asynchronous — the navigation query is processed in the next physics frame. On the **first frame** after entering COMBAT, `is_navigation_finished()` may return `true` from the previous state, causing the enemy to have zero velocity while its internal target updates. This can create brief "freeze frames" that make the enemy look stuck.

#### Issue D: NavigationPolygon Margin vs Wall Geometry
Per Godot documentation: navigation polygons must have sufficient margin from wall geometry. If the navigation polygon extends to the wall boundary without margin, the computed path will go up to and along the wall edge, causing the agent to repeatedly clip into wall colliders. The `beach_level.gd` bakes with `agent_radius = 24.0` which should help, but inconsistent baking across levels may cause issues.

#### Issue E: Wall Avoidance Raycasts in Wrong Direction
The `_apply_wall_avoidance` function uses 8 raycasts spread from -90° to +90° in front of the movement direction, plus 1 rear check. When the enemy is moving directly toward a wall (following a bad nav path), the center raycast (0°) detects the wall and the function should steer away. However, the steering is based on collision normals — in certain corner cases, perpendicular forces can cancel each other out (e.g., facing into an inside corner of two walls).

---

## Data Collected

### Affected Levels
- **BeachLevel** (5 machete enemies, weapon_type = 3)
- **DecadenceLevel** (3 machete enemies)
- **DocksLevel** (2 machete enemies)

### Navigation Setup
All levels use `NavigationRegion2D` with pre-baked navigation polygons. Beach level bakes at runtime with `agent_radius = 24.0`. Castle and some others only warn if NavigationRegion2D is missing.

### Enemy Configuration
- `NavigationAgent2D` exists in `scenes/objects/Enemy.tscn` with:
  - `path_desired_distance = 4.0`
  - `target_desired_distance = 10.0`
  - `avoidance_enabled = true`
  - `max_speed = 320.0`

---

## Research: Godot 4 Pathfinding Best Practices

### NavigationAgent2D Core Architecture
- Pathfinding (navmesh-based path computation) and avoidance (RVO) are **independent subsystems**
- Avoidance does NOT know about walls — it only reasons about agent velocities
- Static obstacles should be in the navigation mesh polygon boundaries, NOT in `NavigationObstacle2D`
- `is_navigation_finished()` returns `true` for both "arrived" and "no path found" — must check both cases

### Known Issues in Godot 4 (Pre-4.1)
- **#60546**: 2D navigation lacked agent radius baking (paths hug corners) — fixed in 4.1
- **#57967**: NavigationObstacle2D on static bodies causes large avoidance arcs — using nav mesh boundaries is correct
- **#69988**: RVO instabilities when avoidance updated every frame — fixed in 4.1

### Why Enemies Walk Into Walls
1. Navigation polygon edge flush with wall geometry (no margin) → path leads to wall edge
2. RVO avoidance pushes agent sideways off the navmesh into a wall
3. Target set before navigation map is synchronized (goes to wrong position)
4. No path found → some engines fall back to direct movement (this codebase has this at line 4758)

---

## Proposed Solutions

### Solution 1: Add Stuck Detection to COMBAT State (Minimal Fix)
Add stuck detection to the COMBAT state for machete enemies. If the enemy hasn't moved significantly for N seconds while in COMBAT, transition to PURSUING which uses cover-to-cover navigation and has existing stuck recovery.

**Pros:** Minimal code change, low risk
**Cons:** Doesn't fix the underlying pathfinding issue, just recovers from getting stuck

### Solution 2: Use NavigationAgent2D `velocity_computed` Signal (RVO Proper Integration)
Currently, the code calls `move_and_slide()` directly with the velocity computed from the nav path direction. Godot's RVO avoidance requires calling `nav_agent.set_velocity(desired_vel)` and then using the velocity from the `velocity_computed` signal. Without this, the avoidance system runs but its output isn't used for wall avoidance.

**Pros:** Uses avoidance correctly for agent-to-agent separation
**Cons:** Avoidance doesn't avoid static walls — this won't fix wall collision

### Solution 3: Re-route Navigation When Wall Collision Detected (Recommended)
When the machete enemy detects it's stuck against a wall (e.g., velocity is low while desired velocity is high, or raycast ahead shows wall AND nav path leads through it), force a new pathfinding query or transition to FLANKING state to find an alternate route.

**Pros:** Directly addresses the symptom
**Cons:** Adds complexity

### Solution 4: Use Path Intermediate Points (Best Practice)
For the COMBAT state machete movement, instead of always targeting `_player.global_position` (which may be unreachable), use the navigation path's intermediate waypoints. The `_move_to_target_nav` function already does this via `get_next_path_position()`. But the issue is that when `is_navigation_finished()` returns `true` (no path), the fallback should trigger a recovery.

**Recommended Combined Fix:**
1. Add navigation path validity check — distinguish "no path found" from "arrived at target"
2. When no path is found, use a fallback behavior (e.g., move to last known reachable position near player, or transition to PURSUING)
3. Add stuck detection to COMBAT state for machete enemies
4. Add debug logging for navigation failures

### Solution 5: NavigationAgent2D with Proper Deferral
Ensure `target_position` is set with proper frame deferral to avoid the async issue where `is_navigation_finished()` returns stale `true` on the first frame.

---

## Implemented Fix

See `scripts/objects/enemy.gd` and `scripts/components/machete_component.gd` for the implementation.

### Changes Made:
1. **Added stuck detection to COMBAT state for machete enemies** — if the enemy's velocity is near zero while trying to move toward the player (and not attacking/dodging), and it has been stuck for > threshold seconds, it transitions to FLANKING or PURSUING state to find an alternate route.
2. **Added navigation validity helper** — check if the navigation path is actually valid (target reachable) before using direct movement. When path is invalid, use the nearest navigable position to the target.
3. **Improved wall collision recovery** — when a raycast detects a wall directly ahead AND the nav agent path is still pointing toward it, force a navigation re-query by briefly setting target to a nearby reachable position.

---

## References

- Godot 4 Navigation Docs: https://docs.godotengine.org/en/stable/tutorials/navigation/
- GitHub #60546: NavigationAgent2D radius not applied in 2D (fixed 4.1)
- GitHub #57967: NavigationObstacle2D radius issue
- GitHub #69988: Navigation Avoidance rework (Godot 4.1)
- Project issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1107
