# Case Study: Issue #1457 — Враг не может обогнуть препятствие (Enemy Can't Navigate Around Obstacle)

## Issue Summary

**Title (Russian):** fix враг не может обогнуть препятствие
**Title (English):** Enemy gets stuck/catches on walls, can't navigate around obstacles

**Reported symptoms:**
- Enemy appears to "glitch on a wall" (багует об стену)
- Enemy seems to snag on walls, unable to navigate its path
- The enemy can't complete its navigation route
- Screenshot shows enemy at corner with a rectangular nav path (yellow lines) — the enemy is pressing against the wall at the corner instead of smoothly rounding it

**Screenshot:** `screenshots/enemy_stuck_corner.png`

---

## Data Collected

### Game Logs

Three game logs were provided (LabyrinthLevel and BuildingLevel):
- `game_log_20260324_200456.txt` — First observation
- `game_log_20260324_200849.txt` — Second observation
- `game_log_20260324_201259.txt` — Third observation (with enemy path visualization enabled)

**Key observation from logs:**

Enemies show rapid oscillating "PURSUING corner check" events, indicating the corner check is firing repeatedly for the same enemy at the same location:

```
[20:14:40] [ENEMY] [Enemy7] PURSUING corner check: angle 112.9°
[20:14:41] [ENEMY] [Enemy7] PURSUING corner check: angle 82.3°
[20:14:41] [ENEMY] [Enemy7] PURSUING corner check: angle 96.2°
[20:14:41] [ENEMY] [Enemy7] PURSUING corner check: angle 76.6°
[20:14:42] [ENEMY] [Enemy7] PURSUING corner check: angle 68.1°
[20:14:42] [ENEMY] [Enemy7] PURSUING corner check: angle -176.3°
[20:14:42] [ENEMY] [Enemy7] PURSUING corner check: angle -174.5°
```

Enemy7 repeatedly fires corner checks over ~2 seconds with oscillating angles (68-112° and -176° simultaneously). This is the hallmark of an enemy oscillating at a wall corner — it detects perpendicular openings on alternating sides because it's stuck between the wall face and the navmesh edge.

This pattern matches Issue #367's pattern for FLANKING but now occurs in PURSUING state.

**ExperimentalSettings note:** `Global stuck max time: 20.0s` — this means the user has overridden the default 4.0s stuck fallback to 20 seconds, greatly extending the visible stuck duration.

---

## Root Cause Analysis

### Primary Root Cause: `_apply_wall_avoidance` Conflicts with NavigationAgent2D at Corners

**Location:** `scripts/objects/enemy.gd` — `_move_to_target_nav()` (line ~4743) and `_check_wall_ahead()` (line ~3521)

**The Problem:**

When an enemy navigates around a corner using `NavigationAgent2D`, the path follows the navmesh edge around the obstacle. At the corner:

1. `_get_nav_direction_to(target_pos)` returns the correct path direction (along the navmesh edge, close to the wall)
2. `_apply_wall_avoidance(direction)` is called with this direction
3. `_check_wall_ahead()` fires 8 raycasts — the **side raycasts** (indices 1-6) detect the wall the enemy is routing *along*
4. Side raycasts add a perpendicular avoidance vector *away from the wall*
5. The blended direction `(nav_dir * 0.3 + avoidance * 0.7).normalized()` pushes the enemy diagonally into the wall corner
6. `move_and_slide()` resolves the collision — the enemy slides along the wall instead of smoothly turning the corner
7. The corner-escape logic in #1107 fires collision normals, but the wall avoidance on the next frame keeps pushing the enemy back

**The wall avoidance weights are strongly biased toward avoidance:**
- `WALL_AVOIDANCE_MIN_WEIGHT = 0.7` — when close to wall (exactly where nav routes go!), 70% avoidance weight
- This overrides 70% of the correct NavAgent direction at the worst possible time

**Why the NavAgent path inherently routes near walls:**
The navmesh is baked to exclude obstacles but its edges run *along* obstacle surfaces. Any corner navigation inherently places the enemy close to a wall. The `_apply_wall_avoidance` system was designed for open-space navigation where being near a wall is unexpected — but NavAgent-guided paths at corners are *supposed* to be near walls.

### Secondary Contributing Factor: Missing `path_max_distance`

**Location:** `scenes/objects/Enemy.tscn` — NavigationAgent2D settings

`path_max_distance` is not set (defaults to infinity). This means when the wall avoidance pushes the enemy slightly off the nav path, the NavigationAgent2D does NOT recalculate. The enemy continues on the old (now incorrect) path, worsening the stuck condition.

### Why Previous Stuck Detection Doesn't Catch This Quickly

- `GLOBAL_STUCK_MAX_TIME = 4.0s` (overridden to 20.0s in ExperimentalSettings)
- The enemy is *moving* (velocity != 0), so the position *does* change slightly
- The `GLOBAL_STUCK_DISTANCE_THRESHOLD = 30.0` may not trigger if the enemy oscillates back and forth covering net distance < 30px
- When the stuck detection fires, the fallback is to transition to SEARCHING — not to fix the navigation itself

---

## Solution Analysis

### Approach 1: Disable Wall Avoidance When NavAgent Is Active (Selected)

**Rationale:** The NavAgent's path through the navmesh is inherently wall-safe — the navmesh baking ensures paths don't go through obstacles. Adding wall avoidance on top of NavAgent routing is redundant and harmful at corners.

**Fix:** In `_move_to_target_nav`, only apply wall avoidance when the wall is **directly ahead** (detected by the center/forward raycast), not when it's to the side. Side wall detection means the enemy is correctly routing *along* a wall.

Specifically: in `_check_wall_ahead`, skip the lateral avoidance contribution from side raycasts (indices 1-6) when the center raycast (index 0) is clear. A clear center means the path ahead is open — nearby side walls are navigational guides, not obstacles.

### Approach 2: Set `path_max_distance` on NavigationAgent2D

**Rationale:** If the enemy gets pushed off path, the agent should recalculate.

**Fix:** Set `path_max_distance = 100.0` in `Enemy.tscn` NavigationAgent2D settings.

### Approach 3: Add PURSUING-State Stuck-at-Cover Recovery

**Rationale:** Even if the sticking happens, detect it faster specifically in PURSUING and find alternative cover.

**Fix:** Add a per-cover-waypoint stuck timer in `_process_pursuing_state` that triggers a new cover search after 2 seconds without reaching the cover (rather than waiting 4-20 seconds for global stuck detection).

### Selected Solution: Combined Approach 1 + 2 + 3

All three fixes are complementary:
1. Approach 1 prevents the sticking in the first place
2. Approach 2 ensures nav recalculation if pushed off path
3. Approach 3 provides fast recovery when sticking still occurs

---

## Known Solutions / Prior Art

### Godot Community Solutions for NavAgent Corner Sticking

1. **Steering behaviors with reduced lateral avoidance** — The standard solution is to make wall avoidance only respond to walls that are in the forward movement cone, not walls to the side. See: Godot forums discussion on "agents clipping corners".

2. **`path_max_distance` tuning** — Setting this to 50-100px causes the NavAgent to recalculate when physically displaced from the nav path.

3. **`path_desired_distance` tuning** — Larger values (80px vs 40px default) cause smoother path following with fewer micro-adjustments at waypoints. Already applied for PURSUING in Issue #1289.

4. **Navmesh margin / agent radius** — Baking with a larger margin pushes the navmesh edges further from walls, reducing "routing along wall edge" scenarios. Not applied here as it would reduce navigable areas.

### Related Issues in This Codebase

- **Issue #367**: FLANKING enemies stuck at corner (wall x=887.9) — same root cause, fixed with stuck timer + transition to SEARCHING
- **Issue #1107**: Machete COMBAT stuck — fixed with wall escape using collision normals (partial fix for same issue)
- **Issue #1173**: Global stuck timer restored to 4.0s from 1.5s
- **Issue #1289**: Nav step length increased (PURSUIT_PATH_DESIRED_DISTANCE = 80px) for smoother pursuit

---

## Fix Implementation

**Files modified:**
1. `scripts/objects/enemy.gd` — `_check_wall_ahead()`: skip lateral avoidance when center is clear; `_process_pursuing_state()`: add cover-approach stuck timer
2. `scenes/objects/Enemy.tscn` — Set `path_max_distance = 100.0`

**Fix details:** See git diff for the exact changes.
