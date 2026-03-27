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

## Fix Implementation (v1 — 2026-03-26)

**Files modified:**
1. `scripts/objects/enemy.gd` — `_check_wall_ahead()`: reduce lateral avoidance to 0.15× when center is clear; `_process_pursuing_state()`: add cover-approach stuck timer
2. `scenes/objects/Enemy.tscn` — Set `path_max_distance = 100.0`

**Fix details:** See git diff for the exact changes.

---

## Follow-up Issue: Enemy Stuck in Narrow Passage (Lower Part)

### New Log: `game_log_20260326_161950.txt`

After deploying v1 fix, owner reported a new stuck scenario:

> "застревает в нижней части прохода (добавить отталкивание стенам)"
> ("gets stuck in the lower part of the passage — add wall repulsion")

**Key data from new log:**
- Scene: LabyrinthLevel
- Enemy3 spawned at (700, 750), cover target at ~(561, 764) — moves LEFT through corridor
- Enemy4 spawned at (800, 900), cover target at ~(584, 906) — moves LEFT through lower passage
- Enemy4 shows repeated PURSUING corner checks over ~12 seconds (16:20:12 → 16:20:30)
  - Oscillating angles: -61°, -115°, -80°, -89°, 19°, 32°, -12°, -10°, -146°, -112°, -65°
  - Same oscillation pattern as original issue, but in a **different location** (lower passage)

### Root Cause of Follow-up Issue

The v1 fix reduced all side-ray avoidance to **0.15×** whenever the center ray was clear. This correctly prevented corner-sticking when routing along a wall edge, but was **too aggressive** for narrow corridor navigation:

**Original bug scenario (corner sticking):**
- Enemy routes along a wall edge at a corner
- Side ray hits the SAME wall being followed (wall is parallel to movement)
- Wall normal: mostly perpendicular to movement direction
- `abs(normal.dot(perpendicular))` ≈ **HIGH** (~0.9)
- → Needs REDUCED avoidance to avoid corner sticking

**New bug scenario (narrow passage):**
- Enemy navigates through a corridor (e.g., moving left through passage at y≈906)
- Side rays hit passage walls above and below (walls perpendicular to movement)
- Wall normal: points across the corridor (aligned with lateral direction)
- `abs(normal.dot(perpendicular))` ≈ **HIGH** (~0.9)
- → Needs FULL avoidance to maintain corridor centering

Wait — both cases have high `abs(normal.dot(perpendicular))` when perpendicular is defined as 90° rotation of direction. Let me re-examine:

**Correct analysis:**

For movement direction = LEFT (−1, 0):
- `perpendicular = Vector2(-direction.y, direction.x) = Vector2(0, -1)` = pointing UP

**Corridor walls (above/below when moving left):**
- Top wall normal: (0, +1) pointing DOWN (into corridor)
- `normal.dot(perpendicular)` = (0,1)·(0,−1) = **−1.0** → `abs` = **1.0** = HIGH
- This IS a passage wall → full avoidance needed ✓

**Corner edge wall (when routing along it, moving left):**
- Wall is to the LEFT, wall normal: (−1, 0) pointing RIGHT or (+1, 0)
- `normal.dot(perpendicular)` = (±1,0)·(0,−1) = **0.0** = LOW
- This IS a corner edge → reduced avoidance needed ✓

So the `lateral_alignment = abs(normal.dot(perpendicular)) > 0.7` threshold correctly distinguishes:
- **High alignment (> 0.7)**: passage walls perpendicular to motion → full avoidance
- **Low alignment (≤ 0.7)**: corner walls parallel to motion → reduced avoidance

### Fix v2 — Collision-Normal-Aware Avoidance

**New logic in `_check_wall_ahead` (v2):**

```gdscript
var wall_normal: Vector2 = raycast.get_collision_normal()
var lateral_alignment: float = absf(wall_normal.dot(perpendicular))
var scale: float = 1.0 if (not center_clear or lateral_alignment > 0.7) else 0.25
```

- If center is blocked → full avoidance (wall directly ahead, emergency case)
- If center is clear AND wall normal aligns laterally (> 0.7) → full avoidance (passage wall)
- If center is clear AND wall normal is NOT lateral (corner edge) → 0.25× avoidance (reduced)

Scale increased from 0.15 to 0.25 for corner case to provide some repulsion even at corners.

**Why this works:**
- Passage walls have normals pointing across the passage (lateral alignment HIGH) → full avoidance keeps enemy centered
- Corner edges have normals pointing forward/backward relative to motion (lateral alignment LOW) → reduced avoidance prevents corner sticking

**Files modified (v2):**
1. `scripts/objects/enemy.gd` — `_check_wall_ahead()`: use collision normal dot product to scale side-ray avoidance
2. `docs/case-studies/issue-1457/game_log_20260326_161950.txt` — new log showing follow-up issue

---

## Follow-up Issue: Enemy Still Stuck in Narrow Passage (v2 Insufficient)

### New Log: `game_log_20260327_100332.txt`

After deploying v2 fix, owner reported still stuck:

> "не исправлено" ("not fixed")

**Key data from new log (BuildingLevel, ~10:03:43–10:03:47):**
- Enemy1-4 enter PURSUING at 10:03:43
- Enemy2: repeated PURSUING corner checks at nearly constant ~7° angle for 2+ seconds
  - 10:03:45: 7.3° → 7.6° → 7.8° → 7.9° (10:03:47)
  - A nearly constant angle means the enemy is barely advancing — essentially frozen
- Compare with earlier logs: Enemy2 varied widely in old logs (angles -173°, 24°, 20° etc.) = was moving faster

### Root Cause of v2 Failure: Normalization Amplifies Bilateral Cancellation

The v2 fix correctly identified the two wall types and applied the right avoidance scale. However, it missed a fundamental issue with `avoidance.normalized()`:

**Scenario: Enemy navigating through a narrow corridor with walls on BOTH sides:**
1. Left passage wall detected → `avoidance += perpendicular * weight` = push RIGHT
2. Right passage wall detected → `avoidance -= perpendicular * weight` = push LEFT
3. Both walls get `scale = 1.0` (both are passage walls, `lateral_alignment > 0.7`)
4. If walls are nearly equidistant: left push ≈ right push → they nearly CANCEL
5. Net avoidance vector ≈ (0.03, 0.0) — tiny residual from slight distance imbalance
6. `avoidance.normalized()` → (1.0, 0.0) — amplified to FULL UNIT VECTOR pointing right
7. Blended with nav direction at weight 0.7 → `(navdir * 0.3 + (1,0) * 0.7).normalized()`
8. Enemy is pushed hard to the right, scrapes the right wall, velocity drops near zero

This is worse than having no avoidance at all in this scenario. The NavAgent path through the navmesh already knows the correct route through the corridor.

**Secondary issue (center ray):**
The original `i == 0` case added `perpendicular * base_weight` when the center hits a wall. This always steers "right" (clockwise 90° of direction), regardless of which direction actually leads to open space. For a wall directly ahead, the correct response is to follow the wall normal.

### Fix v3 — Bilateral Passage Suppression

**Core changes to `_check_wall_ahead`:**

1. **Bilateral passage detection**: Track whether passage walls are detected on BOTH left AND right sides (with center clear). When both sides are enclosed in passage walls, return `Vector2.ZERO` — let the NavAgent handle navigation unimpeded.

2. **Center ray correction**: Use `raycast.get_collision_normal() * base_weight` instead of `perpendicular * base_weight` for the center ray. This steers using the actual wall geometry rather than always turning clockwise.

3. **Minimum threshold**: Raise normalization guard from `> 0` to `> 0.01` to prevent normalizing floating-point noise.

**Why this works:**
- When the enemy is traversing a narrow passage: both sides detect walls → bilateral detection fires → return ZERO → NavAgent leads unimpeded ✓
- When only one side detects a wall (approaching a passage entrance, near a single wall): normal avoidance applies ✓
- When center is blocked (wall directly ahead): center ray uses collision normal to steer the correct direction ✓
- Corner edges: only one side (non-lateral normal) → bilateral condition not met → avoidance still applied at 0.25× ✓

**Files modified (v3):**
1. `scripts/objects/enemy.gd` — `_check_wall_ahead()`: bilateral passage detection, center ray collision-normal fix, minimum threshold
2. `docs/case-studies/issue-1457/game_log_20260327_100332.txt` — new log showing v2 failure
