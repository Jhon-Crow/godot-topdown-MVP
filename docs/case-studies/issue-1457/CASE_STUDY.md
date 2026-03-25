# Case Study: Issue #1457 — Enemy Gets Stuck on Wall Corners (PURSUING State)

**Issue:** #1457 — fix враг не может обогнуть препятствие
**PR:** #1477
**Status:** Investigation Ongoing — second log confirms partial fix, deeper root cause found
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
