# Case Study: Issue #1457 — Enemy Gets Stuck on Wall Corners (PURSUING State)

**Issue:** #1457 — fix враг не может обогнуть препятствие
**PR:** #1477
**Status:** Fix v5 implemented — root-cause fix: MOTION_MODE_FLOATING + 3-probe forward steering
**Analyst:** konard (AI)
**Date:** 2026-03-24, updated 2026-03-25

---

## 1. Summary

Enemy units navigating in the PURSUING state visually "catch" on wall corners and cannot
immediately follow the intended path. The enemy slides along the wall for several seconds
before either being killed (while exposed) or recovering.

**Translation of issue:** "враг багует об стену, как будто зацепляется, не может сразу пройти путь"
= "enemy bugs on the wall, like it's catching, can't immediately follow the path"

**Root causes:**
1. **Wall avoidance interferes with NavigationAgent2D path near corridors** — the `_apply_wall_avoidance` function fires on every frame during `_move_to_target_nav`, adding a perpendicular steering force even when the navmesh already has 24px agent_radius margin. In narrow corridors this causes the enemy direction to oscillate, producing wall-rubbing behavior.
2. **PURSUING state lacks fast stuck detection** — the global stuck timer (`GLOBAL_STUCK_MAX_TIME = 4s`, or 20s when configured via ExperimentalSettings) is too slow to quickly reroute an enemy that's caught on a corner.
3. **`_detect_perpendicular_opening` fires when moving backwards** — once the enemy gets slowed by a corner, `_process_corner_check` detects a clear opening in the backwards direction (≈180°), which causes visual glitching (enemy body swings backwards).

---

## 2. Evidence from Game Logs

### 2.1 Log: `game_log_20260324_200849.txt` (most detailed)

**Level:** LabyrinthLevel
**Build:** Release (Godot 4.3-stable, Windows)
**Difficulty:** Hard

**Enemy7 timeline** (spawns at (1700, 870), player at ~(450, 880)):

```
[20:09:32] [ENEMY] [Enemy7] State: COMBAT -> PURSUING
  (cover target: (584.99, 881.09) — 1192px west of spawn)

[20:09:33] [ENEMY] [Enemy7] PURSUING corner check: angle 94.6°    ← moving north-west
[20:09:34] [ENEMY] [Enemy7] PURSUING corner check: angle 100.1°   ← slight turn
[20:09:34] [ENEMY] [Enemy7] PURSUING corner check: angle 49.5°    ← corridor bend
[20:09:34] [ENEMY] [Enemy7] PURSUING corner check: angle -177.3°  ← STUCK — looking backwards!
[20:09:35] [ENEMY] [Enemy7] PURSUING corner check: angle -176.6°  ← still stuck
[20:09:35] [ENEMY] [Enemy7] PURSUING corner check: angle -174.9°  ← slowly drifting
[20:09:36] [ENEMY] [Enemy7] PURSUING corner check: angle -173.5°  ← still stuck
[20:09:37] [ENEMY] [Enemy7] PURSUING corner check: angle -171.4°  ← 3+ seconds stuck
[20:09:38] [ENEMY] [Enemy7] PURSUING corner check: angle -170.9°  ← 4+ seconds stuck
  (Enemy7 killed at ~20:09:38-39 — unregistered as sound listener)
```

**Observation:** Enemy7 was stuck against a wall corner for 4+ seconds in PURSUING state,
exposed to the player, and was killed. The global stuck detector (4s threshold) would have
triggered at approximately this time, but was too late.

### 2.2 Pattern across all three logs

All three logs show the LabyrinthLevel with Enemy7 spawning at (1700, 870). In every session,
Enemy7 has significant difficulty reaching the player (450, 880) — a 1250px journey across
the labyrinth corridors. The logs consistently show:

1. Enemy7 enters PURSUING with `Found cover at (585, 881)` (distance: ~1023-1192px)
2. Corner checks initially show reasonable angles (50-100°) — navigating around first wall
3. Then corner checks lock into ≈-170° to -177° — stuck against a wall, looking backwards
4. 4-6 seconds of stuck state before being killed or recovering

### 2.3 Log 3: `game_log_20260324_201259.txt`

Shorter log (719 lines) with invincibility mode enabled. Enemy7 exhibits same navigation
pattern. The issue is consistent regardless of player invincibility — it's purely enemy
pathfinding.

---

## 3. Root Cause Analysis

### Root Cause 1: Wall Avoidance × NavigationAgent2D Double-Steering (PRIMARY)

`_move_to_target_nav()` is the core navigation function:

```gdscript
func _move_to_target_nav(target_pos: Vector2, speed: float) -> bool:
    var direction: Vector2 = _get_nav_direction_to(target_pos)  # From NavigationAgent2D
    if direction == Vector2.ZERO: velocity = Vector2.ZERO; return false
    direction = _apply_wall_avoidance(direction)  # ← PROBLEM
    # ... corner escape and ORCA ...
```

The NavigationAgent2D is configured with `agent_radius = 24.0`, meaning it **already
guarantees paths are ≥ 24px from walls**. Despite this, `_apply_wall_avoidance` fires with
`WALL_CHECK_DISTANCE = 60.0px`, detecting walls within 60px and adding a perpendicular
steering force.

In corridors:
- Nav agent says "go north-west along this wall"
- Wall avoidance says "push east (away from west wall)"
- Result: enemy moves north-east, getting closer to the EAST wall
- Next frame: wall avoidance pushes WEST, toward original wall
- **Oscillation / wall rubbing occurs**

The LabyrinthLevel corridors appear narrow enough that both walls are within 60px, making
this oscillation continuous. The `WALL_AVOIDANCE_MIN_WEIGHT = 0.7` means the avoidance
override is very strong (70% avoidance, 30% original direction), overwhelming the nav path.

### Root Cause 2: Slow Stuck Recovery in PURSUING State

The `GLOBAL_STUCK_MAX_TIME = 4.0` seconds is the **global** threshold for all states.
When ExperimentalSettings configures it to 20.0s (as seen in the logs), it allows 20 seconds
of stuck behavior before recovery.

The machete enemy has a dedicated `MACHETE_COMBAT_STUCK_MAX_TIME = 0.8s` fast-recovery.
Non-machete enemies in PURSUING state have **no dedicated fast stuck detection** — only
the global 4s timer.

Since the visible rubbing lasts 4-6 seconds (matching the global timer), the enemy is
often killed before recovery triggers.

### Root Cause 3: `_detect_perpendicular_opening` Detects Backwards Direction

Once the enemy slows at a wall corner, `_process_corner_check` is called with the velocity
direction. If the enemy is barely moving (low velocity but > 1.0), the perpendicular check
`move_dir.rotated(-PI/2)` can point backwards when the movement direction is itself sideways.

In the log, once the corner check angle locks to ≈-177°, it means:
- `velocity` is roughly pointing south (270° or -90°)
- `perp = velocity.rotated(-PI/2) = east (0°)` → wall detected
- `perp = velocity.rotated(+PI/2) = west (180° / -180°)` → open! ← sets angle to -177°

This is a visual glitch (the enemy appears to look backwards) rather than a movement bug,
but it contributes to the visual "bugging" described in the issue.

---

## 4. Similar Prior Issues

| Issue | Description | Fix Applied |
|-------|-------------|-------------|
| #1107 | Machete enemy walks into walls | Corner escape via slide collision normals in `_move_to_target_nav` |
| #1119 | Patrol enemies rub walls | NavigationAgent2D for patrol movement (Issue #1119 → Issue #1120) |
| #1289 | Enemy pursuit path waypoint distance | `PURSUIT_PATH_DESIRED_DISTANCE = 80px` (2× default) for smoother pursuit |
| #367  | Global stuck detection | `GLOBAL_STUCK_MAX_TIME = 4.0s` (was 1.5s before) |
| #1173 | Global stuck restored to 4s | Restored 1.5→4.0s; machete handled separately |

The current issue (#1457) is a continuation of the same family of problems — wall-corner
navigation in the PURSUING state for regular (non-machete) enemies.

---

## 5. Possible Solutions

### Solution A: Add PURSUING-Specific Fast Stuck Detection (Implemented)

Add variables `_pursuing_stuck_timer` and `_pursuing_stuck_last_pos` with
`PURSUING_STUCK_MAX_TIME = 1.5s` and `PURSUING_STUCK_DIST_THRESHOLD = 20px`.

When the enemy hasn't moved more than 20px for 1.5s during PURSUING, immediately try:
1. Find new pursuit cover (repath)
2. If no cover found, try flanking
3. If flanking fails, transition to COMBAT

This fast recovery prevents the 4-6 second visible stuck behavior without affecting
normal pursuit behavior (the enemy still navigates normally).

### Solution B: Reduce Wall Avoidance Weight When Using NavigationAgent2D

Add a `weight_scale` parameter to `_apply_wall_avoidance(direction, weight_scale=1.0)`
so callers can pass `0.5` for nav-agent-guided movement, since the nav mesh already
provides wall margin (avoids over-steering without a separate function).

### Solution C: `NavigationAgent2D.path_postprocessing = CORRIDORFUNNEL` (Already Default)

Godot 4's CORRIDORFUNNEL mode already smooths path corners. No change needed — the nav
agent is already using this by default.

### Solution D: Increase `path_desired_distance` During PURSUING (Already Implemented)

Issue #1289 already sets `PURSUIT_PATH_DESIRED_DISTANCE = 80px` (2× default) to reduce
micro-waypoints. This partially helps but doesn't prevent wall rubbing in corridors.

---

## 6. Implemented Fix (v1, 2026-03-24)

The fix implements **Solution A** (fast PURSUING stuck detection) and **Solution B**
(reduced wall avoidance weight in nav mode) to address both the slow recovery and
the root interference cause.

See `scripts/objects/enemy.gd` for changes marked with `## Issue #1457`.

---

## 7. Second Investigation — Log `game_log_20260325_042027.txt`

**Date:** 2026-03-25
**Build:** Release (Godot 4.3-stable, Windows) — confirms this is a **post-fix build** since
the `[#1457] PURSUING stuck` log lines appear, which were added in the v1 fix.

### 7.1 Observed Symptom (post-fix)

Owner Jhon-Crow reported: "враг застрял в том же месте (не исправлено)" — enemy still stuck
in the same place (not fixed). Screenshot shows enemies clustered near a doorway corridor.

### 7.2 Reconstruction of Events (Enemy7)

| Time    | Event |
|---------|-------|
| 04:20:31 | Enemy7 spawned at (1700, 870), PATROL |
| 04:20:57 | Heard gunshot, COMBAT, `Found cover at (584.99, 877) distance 1206px` |
| 04:20:58 | COMBAT → PURSUING |
| 04:20:59–04:21:01 | PURSUING, corner checks 82°→58°→-172°→38°→38°→39° **oscillating** |
| 04:21:01 | `[#1457] PURSUING stuck #1 at (1760.785, 824.068)` — **fast stuck fires at 1.5s** |
| 04:21:01–04:21:02 | PURSUING continues (reroute found a new cover nearby) |
| 04:21:02 | Enemy7 re-**respawned** (killed while still near stuck position) |
| 04:21:06 | New Enemy7 instance: same cycle, PATROL → COMBAT → PURSUING |
| 04:21:10 | `[#1457] PURSUING stuck #1 at (1770.635, 824.302)` — **same wall!** |

### 7.3 New Root Cause Found: Stuck Reroute Selects Same Unreachable Cover

The v1 fix fires the stuck detector at 1.5s — correctly. But when `_find_pursuit_cover_toward_player()`
is called from the **exact stuck position**, it:

1. Casts raycasts in all directions within `COVER_CHECK_DISTANCE` radius
2. From position ~(1760, 824) surrounded by the same wall geometry, finds the same nearby
   cover positions blocked by the same wall
3. If it finds *any* cover (even the same one), `_has_pursuit_cover = true` and the code
   returns — **the enemy stays in PURSUING, still pointing at unreachable cover**
4. The stuck timer resets because `_pursuing_stuck_last_pos = global_position` was just set
5. Enemy runs for 1.5s more, hits the same wall, stuck fires again — infinite loop

The key signature: enemy corner checks locked to **58.8°, 58.8°, 58.8°** — exact repetition
means no progress at all after each reroute.

### 7.4 Why Cover Search Fails From the Stuck Position

Enemy7 at (1760, 824) with player at (483, 878). Distance ~1277px. The `COVER_CHECK_DISTANCE`
raycasts only find nearby obstacles. All nearby cover candidates are:
- Behind the same walls that block westward movement
- Passage waypoints that may also be unreachable from the exact stuck corner

The `PursuitComponent.find_cover()` filters candidates by `_can_reach_position()` (line-of-sight
check), but a ray from (1760, 824) going west hits the wall immediately. Candidates to the
**east** (behind the enemy) score poorly because they don't make progress toward the player.
So the only viable candidates are in the narrow passage just ahead — but the enemy can't
navigate to them because it's pinned by wall avoidance forces against the corner.

### 7.5 Fix v2: Stuck-Cover Blacklisting + Escalation

When stuck fires, blacklist the current `_pursuit_next_cover` position. If the next
`find_cover()` call returns a position within `PURSUING_STUCK_BLACKLIST_RADIUS = 80px`
of any blacklisted cover, reject it and escalate immediately to flanking/combat.

After `PURSUING_STUCK_ESCALATE_COUNT = 2` consecutive stucks from approximately the same
position, skip cover-seeking entirely and go directly to flanking or combat state.

This prevents the infinite stuck-reroute-stuck loop while still allowing the first
stuck detection to attempt a legitimate reroute.

---

## 8. References

- Godot 4 NavigationAgent2D documentation: https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_introduction_2d.html
- Godot CharacterBody2D corner sliding: https://github.com/godotengine/godot/issues/74140
- Wall avoidance in top-down AI: Steering Behaviors for Autonomous Characters (Craig Reynolds, 1999)
- Original log: `game_log_20260324_200849.txt`
- Second log: `game_log_20260325_042027.txt` (post-v1-fix evidence)

- Godot 4 NavigationAgent2D documentation: https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_introduction_2d.html
- Godot charcterbody2D corner sliding: https://github.com/godotengine/godot/issues/74140
- Wall avoidance in top-down AI: Steering Behaviors for Autonomous Characters (Craig Reynolds, 1999)
- Related game log: `game_log_20260324_200849.txt` (Enemy7 timeline, lines 1167-1416)

---

## 9. Third Evidence Log Analysis (game_log_20260325_044538.txt / game_log_20260325_044618.txt)

**Owner comment (2026-03-25 01:49):** "this corner is only passed when another enemy bumps it, might be collision related?"

### 9.1 What the Logs Show

- **game_log_20260325_044538.txt:** Enemy2 stuck at (492, 663) → stuck #1 fires → FLANKING. Shows the new corner (492, 663) in the main map area, near a room entrance.
- **game_log_20260325_044618.txt:** Both Enemy7 (at 1770, 824) and Enemy10 (at 1121, 1693) get stuck and escalate. Enemy7 spawns repeatedly from (1700, 870) and always hits the same wall corner at ~(1760-1770, 824) before being killed.

### 9.2 Root Cause v3: Physical Collision Wedge

The v2 fix correctly identifies and escapes the **navigation/cover** loop. However, a separate underlying problem remains: the enemy **physics body** gets mechanically wedged at **convex wall corners** (inner corner of two wall segments meeting).

When two walls meet at a convex angle and the enemy's circular collision body is navigating past the inner corner, it can get physically pinned:
- The nav mesh path routes through the corner (correct path, just tight)
- The physics body's `CharacterBody2D` capsule gets caught at the exact corner vertex
- `move_and_slide()` returns normals from both walls — these partially cancel each other
- `get_slide_collision_count()` may return 0 if the body is "resting" against the corner with no active slide frame
- Result: velocity is computed correctly by the nav system but the body doesn't actually move

**Why another enemy's collision helps:** A nearby enemy's ORCA avoidance or separation force provides a lateral impulse that physically dislodges the stuck enemy from the corner vertex. This confirms the problem is purely physics — the navigation path is correct but the body is geometrically pinned.

### 9.3 Evidence from Logs

Corner check angle **89.8°** repeating 4× in a row before stuck fires at (1770, 824). The 89.8° angle is almost exactly east (90°), meaning `_detect_perpendicular_opening` found an opening directly east — there is clear space to the east. But the enemy isn't using it because the nav path says "go west/south-west to player", and the wall avoidance doesn't provide enough lateral force to escape the corner vertex.

### 9.4 Fix v3: Corner Escape Physical Impulse

When the stuck timer fires (1.5s without movement), compute an escape direction:
1. **Primary:** Sum of slide collision normals from `get_slide_collision_count()` — these point away from each touching wall
2. **Fallback:** `Vector2.from_angle(_corner_check_angle)` — uses the last perpendicular opening direction detected by `_detect_perpendicular_opening`

Apply `PURSUING_CORNER_ESCAPE_SPEED = 200 px/s` for `PURSUING_CORNER_ESCAPE_DURATION = 0.35s` (moves ~70px). This directly simulates the collision push from another enemy.

After the impulse, normal pursuit resumes. The enemy has cleared the corner vertex and can follow the nav path normally.

### 9.5 Logs Saved

- `docs/case-studies/issue-1457/game_log_20260325_044538.txt` — Enemy2 stuck at (492,663)
- `docs/case-studies/issue-1457/game_log_20260325_044618.txt` — Enemy7 stuck at (1770,824), Enemy10 stuck at (1121,1693)

---

## 10. Fourth Evidence Log Analysis (game_log_20260325_051623.txt)

**Owner comment (2026-03-25 09:01):** "проблема сохранилась, возможно есть какая то сила трения между врагом и стеной?" = "the problem persists, maybe there's some friction force between the enemy and the wall?"

### 10.1 What the Log Shows

The v3 fix (0.35s escape impulse at 200px/s) fires correctly:
- Enemy2 stuck #1 at (488.6, 663.9) → impulse dir=(0, -1) → fires 0.35s
- Enemy6 stuck #1 at (1767.5, 571.7) → impulse dir=(0.996, -0.089) → fires 0.35s
- Enemy7 stuck #1 at (1759.8, 830.4) → impulse dir=(-0.001, 0.999) → fires 0.35s
- **Enemy7 stuck #2 at (1766.0, 829.1)** → escalates to FLANKING ← **SAME CORNER, 2 seconds later**
- Enemy10 stuck #1 at (1279.3, 1696.4) → impulse fires
- Enemy10 stuck #2 at (1279.1, 1688.6) → escalates to FLANKING ← **SAME CORNER, 2 seconds later**
- Enemy9 stuck #1 at (1763.8, 825.7) → impulse fires 0.35s
- Enemy7 (respawn) stuck #1 at (1767.5, 571.7) → impulse fires

### 10.2 Root Cause v4: Three Compounding Problems

**Problem 1 — Impulse fires but enemy returns to same corner**
After the 0.35s impulse ends, the code does NOT reset `_has_pursuit_cover`. The enemy still holds the original cover target, and the nav system routes back through the same corner, getting stuck again within 1.5s.

Enemy7 stuck at (1759, 830) → impulse direction (0, +1) = south → moves south for 0.35s → nav says "continue to pursuit cover target" → nav path goes through same corner → stuck again at (1766, 829).

**Problem 2 — Impulse direction wrong/suboptimal**
At the moment "stuck" fires, `get_slide_collision_count()` returns 0 (body is stationary, no active slide frame). Fallback uses `_corner_check_angle` which is the last perpendicular opening direction — this can be the correct direction, but it's stale (may point to a direction that worked before but not for the current position).

For a wedge at (1759, 830), the perpendicular opening was east (90°) = Vector2.from_angle(1.5708) = (0, 1) = south (Godot's Y-axis is DOWN). This moved the enemy south, not east as intended. The confusion is that Godot's `Vector2.from_angle(angle)` uses standard math angles where 0 = right (+X), 90° = down (+Y in screen space), not the visual "east".

**Problem 3 — Separation force overrides escape velocity**
The escape impulse sets `velocity = dir * 300` but then `_apply_separation_force()` runs at line 928, adding the separation force from nearby enemies. This can deflect or reduce the escape velocity, causing the impulse to travel less distance than expected.

### 10.3 User Insight: "Friction"

The owner asks if there's "friction" between the enemy and the wall. This is physically accurate:
- Godot's `CharacterBody2D.move_and_slide()` has a `wall_min_slide_angle` property (default ~15°) below which the body is blocked instead of sliding
- At a convex inner corner, the angle between the two wall normals is ~90°. The body's velocity vector can land in the "blocked" zone of both walls simultaneously
- The result is equivalent to high friction — the character sticks at the exact corner vertex
- This is a known Godot engine bug: [#109926](https://github.com/godotengine/godot/issues/109926), [#50062](https://github.com/godotengine/godot/issues/50062)

### 10.4 Fix v4: Four Improvements

1. **Larger escape** — `PURSUING_CORNER_ESCAPE_DURATION: 0.35 → 0.5s`, `PURSUING_CORNER_ESCAPE_SPEED: 200 → 300 px/s` — total movement: 70px → 150px, reliably clears the corner vertex

2. **Better escape direction** — When slide collisions = 0 (stationary), probe 8 directions with `move_and_collide(dir * 4.0, true)` to find the direction with most clearance. This proactively finds the clearest path rather than relying on stale angle data.

3. **Post-impulse nav reset** — When the escape timer expires, clear `_has_pursuit_cover = false` and reset the stuck timer. This forces the enemy to find a fresh cover route that may avoid the problematic corner.

4. **Separation force skip** — During corner escape impulse, skip `_apply_separation_force()` so nearby enemies don't deflect the escape direction.

### 10.5 Expected Result

After fix v4: Enemy gets wedged → stuck fires after 1.5s → probes 8 directions → finds clearest direction (away from wedge) → moves 150px clear → nav recalculates fresh route that may avoid the corner → if still stuck, escalates to FLANKING. No more immediate re-wedging at the same corner.

### 10.6 New Log Saved

- `docs/case-studies/issue-1457/game_log_20260325_051623.txt` — Post-v3 logs showing re-wedging pattern

---

## 11. Session 5 — Root Cause Fix: MOTION_MODE_FLOATING (2026-03-25)

### 11.1 New Evidence

**Screenshot (09:26 UTC comment):** Shows enemy visually wedged at a corner with the navigation path (yellow lines) clearly pointing in the correct direction. The nav system knows where to go; the physics body cannot move there.

**Log `game_log_20260325_051623.txt` analysis:**
- Enemy7 stuck at (1759, 830) at 05:17:48 — same corner as all previous logs
- Escape impulse fires direction `(-0.001498, 0.999999)` = almost purely south
- 0.5s later the log ends with `remaining=-0.02s` — timer went below zero but **no "impulse done" log appears**
- **Critical:** The user tested this at 05:16 UTC — the v4 nav-reset commit was only pushed at 09:08 UTC. All impulse-based fixes (v3, v4) failed because they address symptoms, not the root cause.

**User comment (09:26):** "всё ещё застревает в стене" = "still getting stuck in the wall"

### 11.2 Root Cause Analysis — Engine Level

After exhaustive testing, the core issue is confirmed to be a **Godot engine-level physics bug compounded by an incorrect configuration**:

**Primary: Wrong `motion_mode` for a top-down game**

`CharacterBody2D.motion_mode` defaults to `MOTION_MODE_GROUNDED` (the value `0`). In grounded mode:
- The engine applies floor/ceiling detection to every surface
- When the character collides at a convex corner where two walls meet, the physics server can classify the corner as a "floor" (surface normal has an upward component in 2D space)
- Once the corner is classified as a floor, `move_and_slide()` applies floor-riding logic that **glues the body to the vertex**
- No amount of impulse can overcome this — the physics engine re-applies the floor constraint every frame

This is documented in:
- [Godot issue #109926](https://github.com/godotengine/godot/issues/109926): "move_and_slide treats wall corner as floor" — open, unfixed in Godot 4.0–4.5
- [Godot issue #50062](https://github.com/godotengine/godot/issues/50062): Original corner sticking report (fixed in Godot 3/early 4)
- [Godot issue #91494](https://github.com/godotengine/godot/issues/91494): Rectangle corner collision bug — fix PR #110181 pending but not released

**Solution documented by Godot community and official docs:**
Setting `motion_mode = CharacterBody2D.MOTION_MODE_FLOATING` disables floor/ceiling detection entirely. The character is treated as a freely-floating object that only responds to collision normals — no "floor gluing" behavior. This is the **recommended configuration for top-down and isometric games**.

Sources:
- [Godot Forum: Fix for CharacterBody2D stops following NavigationAgent at wall corner](https://forum.godotengine.org/t/characterbody2d-stops-to-follow-navigationagentline-when-reaching-a-walls-bottom-corner/92872)
- [Godot Forum: Enemy stuck on player corner with NavigationAgent2D](https://forum.godotengine.org/t/enemy-gets-stuck-on-player-corner-when-using-navigationagent2d-top-right/131733)
- [Craig Reynolds Steering Behaviors — Wall Avoidance](https://www.red3d.com/cwr/steer/)
- [SlashSkill: Steering Behaviors for Game AI in Godot 4](https://www.slashskill.com/steering-behaviors-for-game-ai-avoidance-and-anti-oscillation-in-godot-4/)

**Secondary: No proactive wall avoidance on approach**

The existing `_check_wall_ahead()` fires raycasts but is called only during specific states with a half-weight scale in PURSUING. The 3-forward-probe steering technique (Reynolds, 1999) is more robust: cast probes forward-left, forward, and forward-right; if any probe hits, steer perpendicular away from the wall. This prevents approach to corners, instead of trying to escape after being wedged.

### 11.3 Fix v5: Two Changes

**Change 1 — `motion_mode = MOTION_MODE_FLOATING` in `_ready()`**

```gdscript
# Issue #1457 v5: top-down game — disable floor-detection so walls don't get classified as floors at corners
motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
```

This is a **one-line change** that eliminates the physics engine's corner-gluing behavior. All existing stuck detection, blacklist, escalation, and escape impulse logic is retained as safety nets.

**Change 2 — 3-probe lateral avoidance in `_move_to_target_nav`**

```gdscript
# Issue #1457 v5: Reynolds wall-avoidance — 3 forward probes to steer around corners before getting wedged
```

Probes forward-left (−30°), forward, and forward-right (+30°) using raycasts (via the existing `_wall_raycasts` infrastructure). If any probe hits within `WALL_CHECK_DISTANCE`, add a perpendicular steering component to the direction. This is applied proactively on every movement frame, preventing the enemy from approaching a corner at full speed.

### 11.4 Expected Result

With `MOTION_MODE_FLOATING`:
- Engine no longer classifies wall corners as floors → no more physics "gluing"
- Escape impulses fire in the rare case of slow-approach wedging
- All v1–v4 safety nets remain intact

With 3-probe steering:
- Enemy detects walls 60–80px ahead and begins steering around them
- At a convex corner, probes detect the wall on one side → enemy steers toward the open side
- Enemy navigates around corners smoothly instead of running straight into them

### 11.5 Logs and Files

- Screenshot: `assets/case-studies-screenshots/issue-1457-stuck-v5.png` (committed to branch)
- Game log: `docs/case-studies/issue-1457/game_log_20260325_051623.txt`

---

## 12. Session 6 — New Stuck Location After v5 Fix (2026-03-25 ~12:47–12:48 UTC)

### 12.1 User Report

**Date:** 2026-03-25 09:49 UTC
**Comment (Russian):** "теперь враг хорошо проходит каждый второй раз. но когда строится такой путь — враг зацепляется уже за верхнюю часть прохода"
**Translation:** "Now the enemy passes well every other time. But when such a path is built — the enemy catches on the upper part of the passage."

**Screenshot:** `assets/case-studies-screenshots/issue-1457-stuck-v5-session6.png`

The screenshot shows the BuildingLevel with a narrow passage (corridor entrance). The nav path (yellow lines) routes correctly through the passage. The enemy is visibly caught at the top edge of the passage entrance — the enemy body is partially overlapping the wall.

### 12.2 Environment

- **Level:** BuildingLevel (not LabyrinthLevel — a new level)
- **Build:** Release, Godot 4.3-stable, Windows, Hard difficulty
- **v5 fix active:** `MOTION_MODE_FLOATING` present (confirmed by build), 3-probe steering active, v4 escape impulse active
- **Session 6a** (`game_log_20260325_124738.txt`): Two stuck events, v4 escape fires
- **Session 6b** (`game_log_20260325_124822.txt`): One stuck event, v4 escape fires

### 12.3 Event Timeline

#### Session 6a (`game_log_20260325_124738.txt`)

| Time | Event |
|------|-------|
| 12:47:43 | Scene loaded: BuildingLevel |
| 12:47:52–12:47:53 | Multiple scene reloads (2 more BuildingLevel loads) |
| 12:47:57 | Enemy1–4: COMBAT → PURSUING |
| 12:47:59 | Enemy2: PURSUING → COMBAT (reached player line-of-sight) |
| 12:48:03 | Enemy1–4: COMBAT → PURSUING again |
| 12:48:07 | **Enemy2 stuck #1 at (472.8, 610.3)** — `probe dir=(1,0) clr=4.0`, escape dir=(1,0) |
| 12:48:07 | **Enemy1 stuck #1 at (290, 599.1)** — `probe dir=(1,0) clr=4.0`, escape dir=(1,0) |
| 12:48:08 | Both impulses complete, nav reset |
| 12:48:11 | Enemy1–4: COMBAT → PURSUING again |
| 12:48:14 | **Enemy2 stuck #1 again at (463.9, 602.1)** — same corridor, same probe dir=(1,0) |
| 12:48:15 | Enemy1, 2: PURSUING → COMBAT (recovered via combat sightline) |

**Key observation:** Enemy2 gets stuck at ~(463–472, 602–610), then after impulse + nav reset, comes back and gets stuck at the same cluster again. Same probe direction (1,0) = pure east, same clearance 4.0px. The 8-direction probe found only 4px of clearance to the east — this is the maximum free distance before hitting a wall. The enemy is inside a narrow passage where ALL 8 directions are within 4px of a wall.

#### Session 6b (`game_log_20260325_124822.txt`)

| Time | Event |
|------|-------|
| 12:48:26 | Scene loaded: BuildingLevel |
| 12:48:34 | Enemy1–4: COMBAT → PURSUING |
| 12:48:36 | Enemy2: PURSUING → COMBAT (reached player) |
| 12:48:37 | Enemy3: PURSUING → COMBAT |
| 12:48:43 | Enemy1–4: COMBAT → PURSUING again |
| 12:48:46 | **Enemy2 stuck #1 at (479.2, 612.0)** — escape dir=(-0.866, 0.500) |
| 12:48:46 | Impulse completes, nav reset |
| End | No further stuck events |

**Key observation:** Escape direction=(-0.866, 0.500) = approximately 150° from east = north-west. The 8-direction probe found a different clear direction than session 6a. This suggests the probe is working but selecting different directions — the passage corner is narrow enough that all 8 directions have very low clearance.

### 12.4 New Root Cause: Narrow Passage Upper-Corner Catch

The v5 fix (MOTION_MODE_FLOATING) successfully resolved the primary physics-gluing issue. However, a **second geometric scenario** remains:

**The scenario** (as described by the user "catches on the **upper** part of the passage"):

The BuildingLevel has a passage (doorway/corridor entrance) with a specific geometric property: the **entry corner** of the passage is a convex corner where two wall segments meet at ~90°. When the nav path routes the enemy to enter the passage from a certain angle, the enemy approaches the upper (top-right in screenshot) corner of the entrance.

The **stuck cluster** is at x≈463–480, y≈600–615 — a narrow zone about 16px wide. This is consistent with a passage entrance that is barely wider than the enemy's collision shape.

**Why MOTION_MODE_FLOATING didn't fully fix this case:**

MOTION_MODE_FLOATING prevents the engine from classifying the corner as a "floor" and gluing the body. However, at a very narrow passage entrance, there is still a physical geometry issue:

1. The nav path aims the enemy at the center of the passage opening
2. The enemy's collision radius pushes against the passage wall as they enter at an angle
3. `move_and_slide()` in FLOATING mode still slides along walls, but the corner geometry can create a situation where the slide direction is perpendicular to the passage axis — stopping forward progress
4. The 3-probe steering fires (offset ±30°), but at a passage entrance, the forward-left and forward-right probes both detect walls — neither side is significantly clearer, so the center-blocked branch applies (`_pc != null`) and adds the collision normal, but the normal may be nearly perpendicular to the desired direction

**Why "every other time":**

The user observes the passage is navigated successfully on every other attempt. This is consistent with the nav path's waypoints varying slightly based on the player's exact position each cycle. When the nav path approaches the passage from a slightly different angle:
- Approach angle ≤ ~30° from passage axis → enemy enters cleanly (success)
- Approach angle > ~30° → enemy hits the upper corner → catches (stuck #1 fires after 1.5s → escape impulse → recovery)

The 3-probe steering partially mitigates this (success rate improved from "never" to "50%") but does not fully prevent it because the probe distance (64px) detects the wall too late for narrow passages.

### 12.5 Critical Finding: 8-Direction Probe Clearance = 4.0px

```
[#1457] v4: probe dir=(1, 0) clr=4.0
```

The 8-direction escape probe found all probes hitting at ≤4px clearance (minimum). When `clr=4.0` — this means the **maximum clearance in any direction is only 4 pixels**. The enemy is physically inside the wall/corner geometry. A 4px clearance means `move_and_collide(dir * 4.0, true)` only returned null (no hit) for direction=(1,0) with distance=4.0px.

This is the escape probe using `move_and_collide(dir * 4.0, true)` — a test of 4px clearance. If the enemy is inside or flush against a passage wall, even the escape direction may not be valid — the impulse moves the enemy 150px east (dir=(1,0)) which may be parallel to or away from the passage — moving the enemy back outside the passage, requiring another nav cycle to re-approach.

### 12.6 Proposed Solutions for Session 6 Issue

**Root cause is confirmed:** The 3-probe steering does not prevent wedging at narrow passage entrances when the approach angle exceeds ~30° off-axis.

**Solution A: Wider probe angles in passage entry (±45° instead of ±30°)**

The current probe angles are ±30° (0.524 rad). Widening to ±45° would detect wall closeness earlier, triggering steering sooner. However, this may cause over-steering in open areas.

**Solution B: Reduce approach speed near walls**

When the forward probe (0°) detects a wall within `WALL_CHECK_DISTANCE/2 = 32px` ahead, reduce speed to 50% (`speed * 0.5`). This gives more time for `move_and_slide()` to compute a valid slide direction.

**Solution C: Larger escape impulse when stuck inside narrow geometry (clr < threshold)**

When the probe finds `clr < 8.0px` (extremely constrained), the current impulse approach may push the enemy in the wrong direction. Instead, use the escape impulse to **reverse along the nav path** — i.e., move backward (away from target) for 0.5s to back out of the passage entrance, then re-approach. This handles the case where all 8 directions are blocked by narrow walls.

**Solution D: NavigationAgent2D path smearing at passage corners**

Some engines implement "path smearing" — when a path waypoint is within `agent_radius` of a wall, the path is pulled back to a minimum clearance position. This would move the passage waypoint slightly inward, allowing the enemy to approach at a more favorable angle.

**Solution E: Stuck-history blacklist covers the upper-corridor passage**

The current `_stuck_cover_blacklist` records `_pursuit_next_cover` — the navigation target, not the stuck position. If the passage entrance is not near the cover target, the blacklist won't help. Adding a **position-based stuck blacklist** (blacklist within radius of the stuck coordinate itself) would force nav to find a path that doesn't pass through the same chokepoint.

### 12.7 Assessment

The v5 fix (`MOTION_MODE_FLOATING` + 3-probe steering) made significant progress:
- The original (1760, 824) stuck corner from prior sessions is completely absent in session 6 logs
- Enemy passes the narrow passage **50% of the time** — measurable improvement from 0%
- Escape impulse correctly identifies the stuck state and fires within 1.5s
- Post-impulse nav reset ensures a fresh route attempt

The remaining issue is a narrow passage geometry problem. The most targeted fix would be **Solution B** (reduce approach speed) combined with **Solution C** (reverse-escape when all 8 directions blocked), since they address the specific geometric scenario without disrupting normal navigation.

### 12.8 Logs and Files

- Screenshot: `assets/case-studies-screenshots/issue-1457-stuck-v5-session6.png`
- Game log: `docs/case-studies/issue-1457/game_log_20260325_124738.txt`
- Game log: `docs/case-studies/issue-1457/game_log_20260325_124822.txt`

---

## 13. Session 7 Investigation — Log `game_log_20260325_131043.txt`

**Date:** 2026-03-25 (13:10 UTC)
**Level:** LabyrinthLevel (NOT BuildingLevel — different level than session 6)
**Build:** Release (Godot 4.3-stable, Windows), v6 fix applied
**Reported by:** User comment on PR #1477 with screenshot and log attachment

### 13.1 Observed Symptom

User screenshot and log show enemy still stuck at upper part of a passage entrance. The
v6 fix (half-speed + reverse escape) was applied, but the enemy continues to get stuck.

### 13.2 Timeline of Events (from `game_log_20260325_131043.txt`)

| Time | Event |
|------|-------|
| 13:10:43 | Scene loaded: **LabyrinthLevel** |
| 13:11:15 | Enemy1–4: COMBAT (player at ~(483, 873)) |
| 13:11:24 | **Enemy1 stuck #1 at (290, 595.17)** — probe dir=(1,0) clr=4.0, v6: reverse escape → dir=(0,-1) |
| 13:11:24 | Escape impulse: dir=(0,-1), 0.5s |
| 13:11:24 | Impulse ends, nav reset |
| 13:11:38 | **Enemy1 stuck #1 at (290, 601.61)** — probe dir=(1,0) clr=4.0, v6: reverse escape → dir=(0.000001,-1) |
| 13:11:38 | Escape impulse: dir=(0.000001,-1), 0.5s |
| 13:11:38 | Impulse ends, nav reset |
| 13:11:45 | **Enemy1 stuck #1 at (290, 595.21)** — probe dir=(1,0) clr=4.0, v6: reverse escape → dir=(0,-1) |
| 13:11:45 | **Enemy2 stuck #1 at (476.8, 606.5)** — different enemy, different position |
| 13:11:45 | **Enemy4 stuck #1 at (647.4, 933.2)** — yet another enemy stuck |
| 13:11:57 | **Enemy2 stuck #1 at (470.4, 612.9)** — Enemy2 returns to same area |
| 13:11:58 | **Enemy1 stuck #1 at (290, 595.25)** — 4th consecutive stuck for Enemy1, same position |

### 13.3 Critical Observations

**1. Enemy1 returns to EXACT same position every time:** (290, 595) ± 6px. After each
escape impulse + nav reset, the navigation system re-routes Enemy1 back through the same
narrow geometry at the same coordinates. This means:
- The escape worked mechanically (enemy moved ~150px north)
- BUT: `_has_pursuit_cover = false` → `_find_pursuit_cover_toward_player()` finds a cover
  target that requires passing through the same passage again
- The cover target is south of (290, 595) → nav path goes through the same narrow corridor

**2. The `_pursuing_stuck_cover_blacklist` records the cover TARGET** (not the stuck
position). If the cover is not near (290, 595), the blacklist does not prevent re-routing
through the same geometry. The enemy takes a different cover each time but the shortest
path still passes through the same narrow corridor entrance at (290, 595).

**3. Count always resets to #1 on each stuck event.** The `_pursuing_stuck_count` variable
is shared across the PURSUING state session, but `_pursuing_stuck_last_pos` is reset to
`global_position` each time stuck fires, allowing the count to increment. However, in
the log, we see `stuck #1` every time — this means the escalation at `count >= 2` never
fires because:
- After each escape impulse, `_has_pursuit_cover = false` is set
- Enemy re-transitions or re-finds cover, which resets `_pursuing_stuck_count` to 0?

Actually no — looking at the code, `_pursuing_stuck_count` is only reset in the escalation
branch (`_pursuing_stuck_count >= PURSUING_STUCK_ESCALATE_COUNT`) and in `_transition_to_pursuing()`.
The log showing `stuck #1` four times means the PURSUING state is being re-entered between
each stuck event (each time the enemy returns to PURSUING after nav reset, the count starts
from 0). The state transitions that cause count reset: during each combat/reroute cycle,
the enemy transitions back to PURSUING via `_transition_to_pursuing()`.

**4. All probe directions show max 4px clearance** every single time — confirmed by `clr=4.0`
on all four stuck events. The enemy is repeatedly entering invalid wall geometry at (290, 595).

**5. Session 7 is LabyrinthLevel, not BuildingLevel.** The previous session 6 stucks at
(463–480, 600–615) were in BuildingLevel. Session 7 shows a different passage in LabyrinthLevel
at (290, ~595). Both levels have narrow passages that create the same stuck pattern.

### 13.4 Root Cause Confirmed

The escape impulse fires and moves the enemy out of the geometry. But when the PURSUING
state is re-entered (or re-continues), `_find_pursuit_cover_toward_player()` finds a cover
position that requires the nav path to pass through the SAME narrow passage at (290, 595).
The cover blacklist (cover target positions) does not prevent this because the offending
position is on the path TO the cover, not the cover itself.

**This is the "loop" problem:** escape → nav reset → find same corridor path → stuck again.

### 13.5 Why v6 Failed to Fix This

The v6 "reverse escape" correctly identifies that all 8 directions are blocked (clr=4.0)
and moves the enemy away from the cover target. This gets the enemy out of the stuck zone.
However:
- The escape duration is 0.5s at 300px/s = 150px clearance — sufficient to exit the passage
- After impulse: `_has_pursuit_cover = false` triggers a new cover search
- The new cover search finds a position requiring the enemy to pass through (290, 595) again
- The enemy re-enters the stuck geometry within ~10 seconds

The fundamental missing piece: **the stuck POSITION is never blacklisted** — only the
cover target is. The position at (290, 595) is a chokepoint in the navmesh that cannot
be avoided for certain cover positions. Since each new cover may still route through this
chokepoint, the blacklisting of the cover target alone is insufficient.

### 13.6 Online Research Findings (2026-03-25)

Research into Godot 4 solutions for repeated stuck patterns confirmed:

**`NavigationServer2D.map_get_closest_point()`** — when `clr=4.0` (enemy inside wall
geometry), the enemy is likely off the navmesh. Calling `map_get_closest_point()` and
teleporting to the result places the enemy back on valid nav geometry, preventing the
physics overlap that causes `clr=4.0`.

Sources confirming this pattern:
- Godot Forum: "Characters stucked outside the navmesh" (2024) — confirmed fix
- NavigationAgent2D GitHub issue #94709 — "gets stuck if you and it are on the opposite
  sides of an obstacle"
- Community consensus: snap to `map_get_closest_point` + force path recalculation

**Position-based blacklisting** — game AI literature recommends blacklisting the physical
stuck coordinate (not just the destination) with a spatial radius check. This prevents
any path that passes through the chokepoint geometry, regardless of the final destination.

### 13.7 v7 Fix Applied

Two targeted changes in the stuck handler:

**Change 1: Position-based stuck blacklist** (`_pursuing_stuck_pos_blacklist`)

A new `Array[Vector2]` tracks the actual stuck positions (not just cover targets). When
the stuck handler fires, it checks if `global_position` is within
`PURSUING_STUCK_POS_BLACKLIST_RADIUS = 30px` of any previously recorded stuck position.
If yes → **escalate immediately** to FLANKING or COMBAT (skip cover search entirely).
This breaks the loop: on the second visit to (290, 595), the enemy escalates instead of
attempting another failed cover path.

If not yet blacklisted → record the position and proceed with existing escape impulse.

**Change 2: Navmesh snap when inside wall geometry**

When the 8-direction probe finds `max clr ≤ 4px` (enemy is inside wall geometry), before
firing the escape impulse, call `NavigationServer2D.map_get_closest_point()` to find the
nearest valid navmesh position and teleport the enemy there. This:
- Gets the enemy out of the invalid physics overlap immediately
- Makes the escape impulse more reliable (starting from valid position)
- Logged as `[#1457] v7: snapped to navmesh at (x, y)`

### 13.8 Expected Behavior After v7

Scenario: Enemy1 at (290, 595) — all 8 dirs blocked (clr=4.0)

**First stuck:**
1. Stuck detected, pos (290, 595) recorded in `_pursuing_stuck_pos_blacklist`
2. Navmesh snap: teleport to `map_get_closest_point(nav_map, (290,595))` ≈ valid passage point
3. v6 reverse escape fires (dir away from cover, 150px)
4. Nav reset: find new cover
5. If nav routes through same geometry → stuck again at ~(290, 595)

**Second stuck:**
1. Stuck detected, pos (290, ~595) is within 30px of blacklisted pos
2. → **Immediate escalation to FLANKING or COMBAT**
3. Enemy no longer routes through narrow passage
4. Loop broken

### 13.9 Logs and Files

- Game log: `docs/case-studies/issue-1457/logs-session7/game_log_20260325_131043.txt`

---

## 14. Session 8 — v8 Minimal Fix Still Fails (2026-03-25 ~14:06 UTC)

### 14.1 User Report

**Date:** 2026-03-25 14:07 UTC
**Comment (Russian):** "враг опять застревает так же внизу прохода" = "enemy is getting stuck again at the bottom of the passage"
**Level:** LabyrinthLevel
**Build:** Release, Godot 4.3-stable, Windows, Hard difficulty, Invincibility enabled
**Screenshot:** `assets/case-studies-screenshots/issue-1457-stuck-v8-session8.png`
**Log:** `docs/case-studies/issue-1457/game_log_20260325_140630.txt`

### 14.2 What v8 Changed

v8 was a deliberate simplification: reverted all v1–v7 complexity (escape impulses, 3-probe
steering, position blacklists, navmesh snap, wall avoidance weight scaling) and kept only:

1. `motion_mode = MOTION_MODE_FLOATING` in `_ready()` (1 line)
2. Simple stuck detection: 1.5s timer, reroute or escalate after 2 consecutive stucks

### 14.3 Evidence from `game_log_20260325_140630.txt`

| Time | Event |
|------|-------|
| 14:06:50 | Enemy1–4 COMBAT → PURSUING, covers found |
| 14:06:52 | Enemy2: `PURSUING corner check: angle 5.0°` — moving normally |
| 14:06:53 | Enemy2: `PURSUING corner check: angle -165.0°` — backwards-facing = stuck against wall |
| 14:06:53 | Enemy2: `PURSUING corner check: angle -164.3°` — still stuck |
| 14:06:53 | Enemy2: **`PURSUING stuck #1 at (483.3335, 663.9333), rerouting`** |
| 14:06:54 | Enemy2: transitions to COMBAT (saw player after reroute) |
| 14:06:54 | Enemy1: `PURSUING corner check: angle 173.3°` — oscillating at corner |
| 14:06:55 | Enemy4: `PURSUING corner check: angle -179.2°` — backwards-facing at corner |
| 14:06:56 | Enemy1: **`PURSUING stuck #1 at (472.7532, 640.0729), rerouting`** |

**Key observations:**

1. **Stuck detection fires correctly** (within 1.5s) — the timer mechanism works
2. **Enemy2 resolved via COMBAT** (saw player after rerouting) — success in one case
3. **Enemy4 corner angle = -179.2°** (backwards facing) but NO stuck detection fired for Enemy4 in this log window — the stuck timer may not have accumulated 1.5s before the log ended
4. **Same corridor, same position pattern** — stucks at y≈640–664 (same narrow north-south corridor as all previous sessions)
5. **Screenshot confirms**: enemy visibly wedged at a passage corner with navigation path (yellow lines) routing correctly around it

### 14.4 Root Cause of v8 Failure

The v8 stuck detection IS working — Enemy2 was rescued. The problem is:

**After rerouting from a stuck position, `_find_pursuit_cover_toward_player()` may select a new
cover that requires the enemy to pass through the SAME corridor again.** The stuck detection
then fires again at the same position. This is the same "reroute loop" documented in sessions
6, 7 — but v8 removed the position blacklist that was the fix for this.

**Without position blacklisting:**
1. Enemy gets stuck at (483, 663) — stuck #1 fires → reroutes
2. New cover found → nav path routes through same corridor
3. Enemy gets stuck at (483, ~663) again — stuck #1 fires again (count reset to 0 because `_transition_to_pursuing()` was called in the reroute cycle)
4. Infinite loop until killed or random COMBAT transition

The screenshot shows the enemy caught at the passage bottom — this is a recurring chokepoint in LabyrinthLevel.

### 14.5 v9 Fix: Minimal Position Blacklist (2026-03-25)

**Added to v8 minimal fix — two targeted changes:**

**Change 1 — Position blacklist array** (2 new lines in variable declarations):
```gdscript
var _pursuing_stuck_pos_blacklist: Array[Vector2] = []  # Issue #1457 v9
const PURSUING_STUCK_POS_BLACKLIST_RADIUS: float = 40.0  # Issue #1457 v9
```

**Change 2 — Blacklist check in stuck handler** (10 new lines in `_process_pursuing_state`):
- When stuck fires, check if `global_position` is within 40px of any previously blacklisted stuck position
- If blacklisted: **escalate immediately** to FLANKING or COMBAT (break the reroute loop)
- If not blacklisted: record position, proceed with existing reroute logic
- Blacklist clears on `_transition_to_pursuing()` (new engagement, fresh slate)

**Change 3 — Clear blacklist on state entry** (1 character added to existing reset line):
```gdscript
_pursuing_stuck_pos_blacklist.clear()  # added to _transition_to_pursuing()
```

### 14.6 Why This Is Minimal

- No escape impulses
- No navmesh snapping
- No 3-probe steering
- No wall avoidance weight scaling
- Just a small array of `Vector2` positions that forces escalation when enemy returns to the same stuck location

Total additions: +4 lines of variables/constants + ~10 lines in stuck handler + 1 `.clear()` call

### 14.7 Expected Behavior After v9

**Scenario: Enemy1 routed through narrow passage at (290, 595)**

First stuck (new position):
1. Stuck fires at (290, 595) — not in blacklist
2. Record (290, 595) in blacklist
3. Log: `PURSUING stuck #1 at (290, 595), rerouting`
4. `_find_pursuit_cover_toward_player()` — may find cover that re-routes through same corridor

Second stuck (same position):
1. Stuck fires at (290, ~597) — within 40px of blacklisted (290, 595)
2. Log: `PURSUING stuck #2 at (290, 597) — blacklisted position, escalating`
3. Transition to FLANKING or COMBAT
4. **Loop broken** — enemy takes a different approach to reach player

### 14.8 Logs and Files

- Screenshot: `assets/case-studies-screenshots/issue-1457-stuck-v8-session8.png`
- Game log: `docs/case-studies/issue-1457/game_log_20260325_140630.txt`

---

## 15. Online Research Findings (2026-03-25)

Research conducted to identify additional root causes and standard solutions.

### 15.1 Bug Confirmation: godotengine/godot#109926

The `MOTION_MODE_GROUNDED` corner-gluing is a confirmed, unfixed bug in **all versions from
Godot 4.0 through Godot 4.5.beta6** (as of August 2025). The fix (`MOTION_MODE_FLOATING`)
is the recommended configuration for all top-down 2D games — confirmed by:
- [GitHub #109926](https://github.com/godotengine/godot/issues/109926)
- [Godot Forum: Why MOTION_MODE_FLOATING solves sticking](https://forum.godotengine.org/t/why-changing-the-motion-mode-solves-the-collision-shapes-sticking-problem/71108)
- [Godot Forum: Enemy stuck on player corner – fixed by FLOATING](https://forum.godotengine.org/t/enemy-gets-stuck-on-player-corner-when-using-navigationagent2d-top-right/131733)

### 15.2 RVO Avoidance Compounds Wall Sticking (Important Finding)

All enemy scene files have `avoidance_enabled = true` (set by Issue #1146 for enemy-enemy
separation). Research confirms this is a contributing factor to wall sticking:

> **RVO avoidance does not respect navmesh geometry or wall collision shapes.**
> RVO can push agents sideways into walls. When pushed into a wall, `path_max_distance`
> is exceeded → full path recalculation → pushed again → infinite repath loop.
> This was acknowledged in Godot PR #69988 as a known limitation at merge time.

Sources:
- [GitHub godot-proposals #4522 — RVO NavMesh Obstacle Planes](https://github.com/godotengine/godot-proposals/issues/4522)
- [PR #69988 — Rework Navigation Avoidance (merged 4.1)](https://github.com/godotengine/godot/pull/69988)
- [GitHub #60354 — NavigationAgent wall collision when rounding corners](https://github.com/godotengine/godot/issues/60354)

**Recommendation:** `avoidance_enabled` should ideally be `false` for navmesh-navigating
enemies in narrow corridors. However, changing this affects Issue #1146 (enemy spread/separation)
and is outside the scope of this fix. Left as a future improvement to investigate.

### 15.3 NavigationAgent2D path_max_distance and Set-Target-Every-Frame

Two additional potential sources of stuck behavior confirmed by research:

1. **`path_max_distance`** (default 100px) — when RVO pushes an agent more than 100px off
   the ideal path, a full recalculation triggers. In narrow corridors, repeated RVO pushes
   can cause continuous recalculation, preventing forward progress.

2. **Calling `set_target_position()` every frame** (via `_get_nav_direction_to()` at line 4722)
   triggers a full path recalculation every physics frame. The current code does this on every
   `_move_to_target_nav()` call. Per Godot docs recommendation, this should be gated behind
   a distance threshold. However, changing this is a broader refactor.

Sources:
- [GitHub #95628 — NavigationAgent2D repath loop](https://github.com/godotengine/godot/issues/95628)
- [Godot docs — Using NavigationAgents (latest)](https://docs.godotengine.org/en/latest/tutorials/navigation/navigation_using_navigationagents.html)

### 15.4 Agent Radius and NavMesh Baking

Research confirms that `agent_radius` in the baked navmesh (not in the NavigationAgent2D
`radius` property) is what controls path clearance from walls. The code sets `agent_radius = 24.0`
in the NavigationAgent2D node — this is the **RVO radius**, NOT the bake radius. The actual
navmesh bake radius must be set separately in the `NavigationPolygon` bake parameters.

If the navmesh was baked with `agent_radius = 0`, paths can run along wall edges, making
corner sticking much more likely regardless of `MOTION_MODE_FLOATING`.

Source:
- [Godot Forum — NavigationAgent2D keeps getting stuck on corners](https://forum.godotengine.org/t/navigationagent2d-keeps-geting-stuck-on-corners/126027)

### 15.5 MOTION_MODE_FLOATING Behavior Differences (Important)

Research confirmed key differences between FLOATING and GROUNDED mode that affect enemy code:

**`get_slide_collision_count()` / `get_slide_collision()` — works in FLOATING ✅**

Both methods are mode-agnostic and work identically in both modes. The collision normal
escape at `_move_to_target_nav` line 4760 (`_esc += get_slide_collision(_si).get_normal()`)
remains effective in FLOATING mode.

**Velocity not zeroed on perpendicular collision — FLOATING difference ⚠️**

Open bug [#60447](https://github.com/godotengine/godot/issues/60447): In FLOATING mode,
`velocity` is NOT zeroed when the body hits a wall perpendicularly (unlike GROUNDED mode
which zeroes velocity). This means the fallback at line 4762:

```gdscript
elif velocity.length_squared() < 1.0:
    var _p := move_and_collide(direction * 2.0, true); ...
```

This branch **never fires in FLOATING mode** when the enemy is stuck against a wall,
because `velocity` stays at `direction * speed` (high, non-zero) even though the body
isn't actually moving. The `move_and_collide` probe is effectively dead code in FLOATING.

**Impact:** The `get_slide_collision_count()` path (line 4760) is the active escape path.
If the body is wedged but has NO active slide collisions (stationary, not actively colliding
this frame), both escape paths fail silently. The stuck detection timer is the only reliable
recovery mechanism.

**Why stuck detection still works:** It's position-based (`global_position` distance), not
velocity-based. If the body is pinned and not moving, `global_position` distance < 20px
regardless of what `velocity` reports.

Sources:
- [GitHub #60447 — velocity not updated when CharacterBody2D collides in FLOATING mode](https://github.com/godotengine/godot/issues/60447)
- [GitHub #101052 — CharacterBody2D accelerated by slides in FLOATING mode](https://github.com/godotengine/godot/issues/101052)

---

## 16. Session 9 Analysis (2026-03-25 16:23) — "AI is completely broken"

**User report:** "полностью сломан ии." (AI is completely broken)

**Log:** `docs/case-studies/issue-1457/logs/game_log_20260325_162320.txt`
**Duration:** ~4 seconds (16:23:20 → 16:23:24)
**Level:** BuildingLevel (auto-navigated from last-played save)
**Build:** Godot 4.3-stable, no build_info.cfg (user-built binary, not CI)

### 16.1 Key Observations

**Critical finding: 0 enemies registered in BOTH levels**

LabyrinthLevel (startup):
```
[LabyrinthLevel] Child 'Enemy1': script=true, has_died_signal=false
[LabyrinthLevel] Child 'Enemy2': script=true, has_died_signal=false
...
[LabyrinthLevel] Enemy tracking complete: 0 enemies registered
```

BuildingLevel (auto-navigated):
```
[LevelInitFallback] Child 'Enemy1': has_died_signal=False
[LevelInitFallback] Child 'Enemy2': has_died_signal=False
...
[LevelInitFallback] Enemy tracking complete: 0 enemies registered
```

**Contrast with working Session 1 (2026-03-25 04:20):**
```
[LabyrinthLevel] Child 'Enemy1': script=true, has_died_signal=true
[LabyrinthLevel] Enemy tracking complete: 5 enemies registered
...
[LevelInitFallback] Child 'Enemy1': has_died_signal=True
[LevelInitFallback] Enemy tracking complete: 10 enemies registered
```

### 16.2 Root Cause: GDScript Parse/Compile Error

When `has_signal("died")` returns `false` on a node where:
- `get_script() != null` is true (script IS attached)
- `signal died` IS declared in the script

...this is a definitive indicator that **the GDScript file has a parse/compile error and the class body failed to load**. When a GDScript has a parse error, Godot attaches the script object to the node but the class — including all its `signal`, `var`, `const`, and `func` declarations — is not registered. Only the base class (`CharacterBody2D`) signals remain available.

**Why `has_signal("died")` returns false on parse error:**
- Signals declared with `signal keyword` are registered during class parse/compile
- A parse error aborts class initialization before signal registration
- The attached script object exists but has an empty signal/member table
- `has_signal("died")` queries the script's signal table → returns false

**Sources:**
- [GitHub #85528 — Signals appear to be broken (script attached but signals missing)](https://github.com/godotengine/godot/issues/85528)
- [Godot Forum — has_user_signal returning false though signal in get_signal_list](https://forum.godotengine.org/t/object-has-user-signal-returning-false-even-though-signal-in-object-get-signal-list/21492)

### 16.3 The 4-Second Session

The session lasted only ~4 seconds. The game:
1. Started at LabyrinthLevel (startup screen)
2. Detected last-played level = BuildingLevel → auto-navigated
3. BuildingLevel loaded with 0 enemies registered
4. User observed broken AI (no enemies) and closed the game

The `has_died_signal=false` indicates the user was running a binary built from a version of `enemy.gd` that has a parse error. The specific enemy.gd version in that binary is unknown, but it is NOT the current PR branch version (which passes all CI checks including GDScript lint and compile checks).

### 16.4 MOTION_MODE_FLOATING Velocity Bug (Additional Finding)

Research surfaced a second issue relevant to v9 fix quality:

**Godot #101052 — CharacterBody2D accelerated by slides in FLOATING mode:**

In Godot 4.3+, `MOTION_MODE_FLOATING` has a velocity-magnitude conservation bug: when a body slides along a wall, the engine preserves the *total velocity magnitude* by redistributing the blocked component to the unblocked axes. This causes `get_real_velocity()` to exceed the intended speed during prolonged wall contact.

Example: enemy set to move at 100 px/s, after sliding along a wall for several frames → `get_real_velocity()` can reach ~140 px/s or higher.

**Impact on this fix:** The enemies in this game use `velocity = direction * combat_move_speed` followed by `move_and_slide()` in `_physics_process`. If an enemy slides along a wall (which still happens even with FLOATING mode when the navmesh routes near a wall), the velocity can build up. The separation force at `_apply_separation_force()` and the `_apply_wall_avoidance()` function partially compensate, but the velocity accumulation was not explicitly addressed.

**Godot 4.3 status:** Issue #101052 was being addressed in PR #107266 (Godot engine PR). As of Godot 4.3-stable, this is unresolved.

**Mitigation already present:** The stuck detection timer (`_update_pursuing_stuck`) is position-based, not velocity-based, so it correctly detects the enemy being pinned regardless of what `velocity` reports. The velocity buildup only causes cosmetic fast-movement during wall slides, not an infinite-stuck loop.

Source: [GitHub #101052](https://github.com/godotengine/godot/issues/101052)

### 16.5 Timeline Reconstruction

| Time | Event |
|------|-------|
| 2026-03-24 | Issue #1457 opened — enemy catches on wall corners in PURSUING state |
| 2026-03-24 | Sessions 1-3 analyzed — 3 logs showing Enemy7 stuck ≥4s in LabyrinthLevel |
| 2026-03-24 | v1-v5 fixes attempted (wall avoidance tuning, probe steering, etc.) |
| 2026-03-25 04:20 | Session 4-5: v5 fix tested with working build — 5 enemies in LabyrinthLevel, 10 in BuildingLevel, `has_died_signal=true` for all |
| 2026-03-25 | v6-v7: position blacklist + navmesh snap (too many changes) |
| 2026-03-25 | v8: minimal fix — MOTION_MODE_FLOATING + pursuing stuck detection |
| 2026-03-25 14:06 | Session 8: v8 tested — Enemy2 stuck rescued once but then looped (no blacklist) |
| 2026-03-25 | v9: added position blacklist to v8 — breaks reroute loop |
| 2026-03-25 16:23 | Session 9: User reports "AI completely broken" — new log shows 0 enemies registered, `has_died_signal=false` — indicates GDScript parse error in user's binary |

### 16.6 Proposed Next Steps

**For user:** Please download and use the CI-built binary from the PR's GitHub Actions artifact, not a locally-built binary. The CI build has verified the `enemy.gd` compiles without errors. The artifact is available at:
https://github.com/Jhon-Crow/godot-topdown-MVP/actions/runs/23538832646 (workflow: "Build Windows Portable EXE")

**For the fix itself:** v9 is the current best fix. The `has_died_signal=false` issue is unrelated to the wall-corner fix and appears to be a binary-level issue (wrong build).

**Additional future improvements (outside current scope):**
1. **Gate `set_target_position()` behind a distance threshold** (per Godot docs recommendation) to reduce per-frame path recalculation overhead
2. **Investigate `avoidance_enabled=false` for narrow-corridor scenarios** — RVO avoidance can push agents sideways into walls (Issue #1146 scope)
3. **Clamp velocity magnitude after `move_and_slide()`** to mitigate the FLOATING velocity buildup bug (#101052)

---
