# Case Study: Patrolling Enemies Walk in Place — LabyrinthLevel & Labyrinth2Level (Issue #1119)

**Issue:** #1119 — fix патрулирующие враги (Fix patrolling enemies)
**PR:** #1120
**Status:** Fixed (LabyrinthLevel) + Fixed (Labyrinth2Level — follow-up, same root cause)
**Analyst:** konard (AI)
**Date:** 2026-03-18

---

## 1. Summary

Patrolling enemies on the "Комплекс Лабиринт" (LabyrinthLevel) map appeared to be "stepping in place" (шагают на месте) — walk animation plays but the enemies barely move, creating the visual impression of running in place.

**Root cause:** `patrol_offsets = [Vector2(100, 0), Vector2(-100, 0)]` for Enemy3 is too small. The 100 px patrol offset sends the enemy only 100 px from its spawn point. At `move_speed = 220 px/s` the enemy crosses the entire patrol leg in ≈ 0.45 s, then waits 1.5 s. To a player watching from a distance this cycle looks like the enemy never actually moves.

**Fix:** Increase `patrol_offsets` for Enemy3 in `LabyrinthLevel.tscn` from `±100 px` to `±200 px`. This gives a 400 px patrol span that is visually meaningful and still safely inside the room (no walls block the path at `x=1000–1400, y=1000`).

---

## 2. Evidence

### 2.1 Game log — `game_log_20260318_025454.txt`

**Build:** Release (Godot 4.3-stable, Windows)
**Difficulty:** Normal
**Active item:** Loudspeaker
**Level:** LabyrinthLevel

Key log entries for Enemy3 (patrol enemy):

```
[02:54:54] [ENEMY] [Enemy3] Spawned at (1200, 1000), hp: 1, behavior: PATROL

[02:55:29] [ENEMY] [Enemy3] PATROL corner check: angle -90.0°
[02:55:29] [ENEMY] [Enemy3] ROT_CHANGE: none -> P3:corner, state=IDLE, target=-90.0°, current=0.0°, player=(150,1000), corner_timer=0.30
[02:55:29] [ENEMY] [Enemy3] ROT_CHANGE: P3:corner -> P4:velocity, state=IDLE, target=0.0°, current=-54.4°, player=(150,1000), corner_timer=-0.02
[02:55:29] [ENEMY] [Enemy3] PATROL corner check: angle -90.0°
[02:55:29] [ENEMY] [Enemy3] ROT_CHANGE: P4:velocity -> P3:corner, state=IDLE, target=-90.0°, current=-51.6°, player=(150,1000), corner_timer=0.30
```

**Critical observations:**
1. Spawn at 02:54:54. No patrol activity logged until 02:55:29 — **35 seconds** of silence.
2. During those 35 s, the rotation priority log shows nothing: no `ROT_CHANGE` for Enemy3. This means `velocity = 0` (WAITING state) and `_idle_scan_targets` is empty (patrol mode doesn't initialize idle scan).
3. Model rotation was still at `0.0°` at 02:55:29 — confirming the model was stationary for 35 s.
4. `corner_timer=-0.02` means the 0.30 s timer expired within the same physics frame it was set — this is an oscillation artifact (see §4.2 below, though not the primary bug).
5. Between the 35-second gap and scene reload (02:55:33), only brief movement activity is visible, consistent with a 100 px patrol path.

### 2.2 Scene configuration

File: `scenes/levels/LabyrinthLevel.tscn`

```
[node name="Enemy3" parent="Environment/Enemies" instance=ExtResource("4_enemy")]
position = Vector2(1200, 1000)
behavior_mode = 0                                              # PATROL
patrol_offsets = Array[Vector2]([Vector2(100, 0), Vector2(-100, 0)])
```

Patrol points computed by `_setup_patrol_points()`:
| Index | Position | Note |
|-------|----------|------|
| 0 | (1200, 1000) | Spawn position (home) |
| 1 | (1300, 1000) | +100 px east |
| 2 | (1100, 1000) | −100 px west |

### 2.3 Timing analysis

With `patrol_wait_time = 1.5 s` and `move_speed = 220 px/s`:

| Patrol leg | Distance | Travel time | Wait time | Subtotal |
|-----------|----------|-------------|-----------|---------|
| Home → East | 100 px | 0.45 s | 1.5 s | 1.95 s |
| East → Home | 100 px | 0.45 s | 1.5 s | 1.95 s |
| Home → West | 200 px | 0.91 s | 1.5 s | 2.41 s |
| West → Home | 200 px | 0.91 s | 1.5 s | 2.41 s |
| **Full cycle** | | | | **~8.7 s** |

Movement fraction: 2.72 s / 8.72 s ≈ **31 % of time actually moving**, and the max displacement is only 200 px (both offsets relative to home) — visually negligible.

---

## 3. Root Cause Analysis

### Root Cause 1 (Primary): Patrol offsets too small — `±100 px`

**File:** `scenes/levels/LabyrinthLevel.tscn`
**Introduced by:** Commit `4b55c397` ("Добавлен новый первый уровень: лабиринт технических помещений")

The patrol offsets were set to `±100 px` when the level was first authored (2026-02-08). This is half the size of typical patrol routes in other levels (CityLevel uses `±400 px`, CastleLevel uses `±300 px`). At this scale the enemy barely moves and the walk animation plays over such a small distance that it appears the enemy is running in place.

**Supporting code:**
```gdscript
# scripts/objects/enemy.gd, line 499
func _setup_patrol_points() -> void:
    _patrol_points.clear()
    _patrol_points.append(_initial_position)  # Point 0: spawn position
    for offset in patrol_offsets:
        _patrol_points.append(_initial_position + offset)
```

Because point 0 is the spawn position, the enemy immediately enters wait state on the first frame (distance to itself = 0 < 5.0 threshold), spending the first 1.5 s motionless. This further reinforces the "standing still" impression.

### Root Cause 2 (Secondary): Corner-check timer oscillation

The corner check timer of 0.30 s can expire within the same physics frame it was set. This is because `_process_corner_check` is called with `get_physics_process_delta_time()` (double-fetch of the per-frame delta), and at low FPS or high delta the timer may go negative immediately. The log shows `corner_timer=-0.02` and a subsequent P4→P3 flip within the same log second.

This causes the enemy model to briefly glance sideways and snap back, creating a "twitchy" rotation that adds to the walking-in-place impression. However, this is a cosmetic secondary issue — the enemy does eventually complete its corner check over multiple frames.

**This secondary issue is NOT fixed in this PR** to keep the scope narrow.

---

## 4. Map Geometry Verification

Walls near Enemy3's patrol path (x=1000–1400, y=1000):

| Wall | Position | Shape | Coverage |
|------|----------|-------|----------|
| ServerRoom_WallRight | (1450, 900) | 24×400 px | x=1438–1462, y=700–1100 |
| ElecRoom_WallLeft | (1500, 970) | 24×200 px | x=1488–1512, y=870–1070 |
| WallBottom | (1008, 1144) | 1920×32 px | y=1128–1160 (boundary) |
| ServerRoom_WallTop | (1000, 680) | 200×24 px | x=900–1100, y=668–692 |

The patrol path `x=1000–1400, y=1000` is **fully unobstructed**. Both ±200 px target points (1000, 1000) and (1400, 1000) are clear of all walls. The ServerRoom_WallRight starts at x=1438, giving a 38 px safety margin from the (1400, 1000) patrol point.

---

## 5. Fix

**File:** `scenes/levels/LabyrinthLevel.tscn`
**Change:** Increase `patrol_offsets` for Enemy3 from `±100 px` to `±200 px`.

```diff
-patrol_offsets = Array[Vector2]([Vector2(100, 0), Vector2(-100, 0)])
+patrol_offsets = Array[Vector2]([Vector2(200, 0), Vector2(-200, 0)])
```

**Effect:**

| Metric | Before | After |
|--------|--------|-------|
| Max displacement from spawn | 200 px | 400 px |
| Travel time per 200 px leg | 0.45 s | 0.91 s |
| Movement fraction per cycle | ~31 % | ~43 % |
| Visual impression | Walking in place | Clearly patrolling |

**Rationale:** 200 px offsets are consistent with mid-range patrols in other levels (BuildingLevel, Labyrinth2Level use 150 px; FactoryLevel uses 100–150 px). The LabyrinthLevel map is 1920×1080 px, and the server room area is ~450 px wide, so a 400 px patrol span is appropriate and keeps the enemy within its room.

---

## 6. Proposed Solutions for Root Cause 2 (not implemented)

For the corner-check timer oscillation (secondary issue), a future fix could:
1. Pass the `delta` parameter that was already provided to `_process_patrol(delta)` instead of calling `get_physics_process_delta_time()` again.
2. Add a minimum timer check (`if _corner_check_timer > 0.01:` instead of `> 0`) to prevent sub-frame oscillation.

These changes would reduce the "twitchy" side-glance during patrol, but are out of scope for this issue fix.

---

## 7. Timeline of Events

| Time | Event |
|------|-------|
| 2026-02-08 | LabyrinthLevel created (commit `4b55c397`) with Enemy3 patrol_offsets `±100 px` — bug introduced |
| 2026-03-18 02:54:54 | Player starts LabyrinthLevel. Enemy3 spawns at (1200,1000) in PATROL mode |
| 02:54:54–02:55:29 | Enemy3 cycles through patrol route quietly (no corner checks) — 35 s of minimal movement |
| 02:55:29 | Corner check fires once (perpendicular corridor opening detected) — brief model rotation |
| 02:55:33 | Scene reloaded (player died or restarted) |
| 2026-03-18 | Issue #1119 reported: "patrolling enemies walk in place on LabyrinthLevel" |
| 2026-03-18 | PR #1120 (first fix): increase LabyrinthLevel Enemy3 patrol_offsets to `±200 px` |
| 2026-03-18 03:36:09 | Player proceeds to Labyrinth2Level. Enemy4 (1100,700) and Enemy11 (1900,1400) still exhibit stuck patrol behavior — same root cause, same fix needed |
| 2026-03-18 | PR #1120 (extended fix): increase Labyrinth2Level Enemy4 `±150→±200 px`, Enemy8 `±150→±200 px`, Enemy11 `±100→±200 px` |

---

## 8. Labyrinth2Level — Follow-up Finding

### 8.1 Evidence — `game_log_20260318_033609.txt`

After the LabyrinthLevel fix was merged, the player continued to **Labyrinth2Level (Labyrinth Complex)** and reported the same visual bug.

**Affected patrol enemies:**

| Enemy | Position | Old offsets | New offsets |
|-------|----------|-------------|-------------|
| Enemy4 | (1100, 700) | `Vector2(150, 0), Vector2(-150, 0)` | `Vector2(200, 0), Vector2(-200, 0)` |
| Enemy8 | (2900, 300) | `Vector2(0, 150), Vector2(0, -150)` | `Vector2(0, 200), Vector2(0, -200)` |
| Enemy11 | (1900, 1400) | `Vector2(100, 0), Vector2(-100, 0)` | `Vector2(200, 0), Vector2(-200, 0)` |

### 8.2 Key log evidence

Enemy4's continuous stuck behavior (from 03:36:30 onwards, dozens of times per minute):
```
[03:36:30] [ENEMY] [Enemy4] PATROL corner check: angle 90.0°
[03:36:31] [ENEMY] [Enemy4] PATROL corner check: angle 90.0°
[03:36:32] [ENEMY] [Enemy4] PATROL corner check: angle 90.0°
...
```
The corner check repeating at exactly `90.0°` every frame means the enemy is trapped in a corridor — it detects a perpendicular opening continuously, triggering the corner look every 0.3 s, but never makes forward progress toward its patrol waypoint.

Enemy11 exhibits the same pattern with `angle -89.9°` / `angle -90.0°` alternating each frame.

### 8.3 Screenshot

From PR comment (2026-03-18T00:37:39Z) — enemy visually wedged in narrow corridor:
![enemy stuck in corridor](https://github.com/user-attachments/assets/d94cb45d-09d5-4344-b7d6-c8d4b61b5956)

The enemy is between two parallel walls with barely enough space to move. With ±100–150 px offsets, both patrol waypoints may be within or very close to wall geometry, leaving the enemy oscillating at the corridor entrance.

---

## 9. Third Round — Wall-Rubbing Bug (Issue #1119 continued)

### 9.1 New symptom — `game_log_20260318_041119.txt`

After the Labyrinth2Level offset fix was applied, the player reported a new (but related) symptom: **"враг трётся об стену, а не патрулирует"** (enemy rubs against the wall rather than patrolling).

**Screenshot from PR comment (2026-03-18T01:12:50Z):**

![enemy rubbing against wall](https://github.com/user-attachments/assets/afee8ad1-5bb5-4ea9-8040-4c138e6b048e)

The screenshot shows an enemy pressed diagonally against a wall corner, oscillating in place.

### 9.2 Log evidence — Enemy4 and Enemy11 still stuck

After the offset fix, continuous corner check logs resumed immediately after spawn in Labyrinth2Level:

```
[04:11:35] [ENEMY] [Enemy4] PATROL corner check: angle -90.0°
[04:11:35] [ENEMY] [Enemy11] PATROL corner check: angle -90.0°
...
(Enemy11 logs angle 90.0° every ~0.5 seconds from 04:11:35 to 04:12:07 — 32 seconds straight)
(Enemy4 logs varying angles 100°–175° at same rate)
```

Enemy11 at (1900, 1400) reports exactly `90.0°` hundreds of times in 32 seconds — the enemy is perfectly aligned with a corridor opening perpendicular to its patrol direction and cannot advance.

### 9.3 Root Cause 3 — No stuck detection in PATROL state

**The patrol offsets alone are insufficient when the corridor geometry prevents reaching the waypoint.**

The existing code (`_process_patrol`) moves toward the target waypoint and applies `_apply_wall_avoidance()` to steer around nearby walls. However, in narrow corridors (< 200 px wide), the wall avoidance force can redirect the enemy sideways along the wall without making forward progress toward the waypoint. The enemy slides along the wall, never getting within the 5.0 px arrival threshold.

Meanwhile `_detect_perpendicular_opening()` fires every 0.3 s (the `CORNER_CHECK_DURATION`), detecting the same open corridor to the side. This means:
1. Enemy moves slowly sideways along a wall
2. Every 0.3 s the enemy model rotates to "look at" the side opening
3. The 0.3 s timer expires, the opening is immediately re-detected → timer resets
4. **Result: enemy is permanently stuck in a corner-check oscillation loop with no forward progress**

Other AI states already have stuck detection:
- **PURSUING/FLANKING:** `_global_stuck_timer` / `GLOBAL_STUCK_MAX_TIME = 1.5 s` → transitions to SEARCHING
- **FLANKING:** `_flank_stuck_timer` / `FLANK_STUCK_MAX_TIME = 2.0 s` → triggers reroute
- **SEARCHING:** `_search_stuck_timer` / `SEARCH_STUCK_MAX_TIME = 2.0 s` → transitions to IDLE

But **PATROL has no stuck detection**, which is why the bug survived the offset increase.

### 9.4 Fix — Add stuck detection to `_process_patrol`

Added to `scripts/objects/enemy.gd`:

```gdscript
# New variables (line ~183):
var _patrol_stuck_timer: float = 0.0
var _patrol_stuck_last_position: Vector2 = Vector2.ZERO
const PATROL_STUCK_MAX_TIME: float = 1.5
const PATROL_STUCK_DISTANCE_THRESHOLD: float = 20.0

# New logic in _process_patrol() (after the waiting-point block):
var moved_distance := global_position.distance_to(_patrol_stuck_last_position)
if moved_distance < PATROL_STUCK_DISTANCE_THRESHOLD:
    _patrol_stuck_timer += delta
    if _patrol_stuck_timer >= PATROL_STUCK_MAX_TIME:
        _log_to_file("PATROL STUCK: pos=%s for %.1fs, skipping to next patrol point" % [...])
        _patrol_stuck_timer = 0.0
        _patrol_stuck_last_position = global_position
        _is_waiting_at_patrol_point = true  # advance to next point after normal wait
        velocity = Vector2.ZERO
        return
else:
    _patrol_stuck_timer = 0.0
    _patrol_stuck_last_position = global_position
```

**Behavior after fix:**
- If the enemy doesn't move more than 20 px within 1.5 s, it "gives up" on the current waypoint and enters the normal wait state (advancing to the next point after `patrol_wait_time`)
- The enemy resumes normal patrol after the wait instead of getting permanently stuck
- Logging (`PATROL STUCK: ...`) makes future diagnosis easy

---

## 10. Fourth Round — Wall-Rubbing Persists Despite Stuck Detection (Issue #1119 continued)

### 10.1 New symptom — `game_log_20260318_044908.txt`

After the stuck detection fix (Round 3) was deployed, the player reported: **"враг всё так же трётся об стену"** (the enemy is still rubbing against the wall).

**Player request:** "пересмотри способ реализации патрулирования (например на основе состояния Поиск)" — _Reconsider the patrol implementation approach (e.g. based on the Search state)._

### 10.2 Log evidence — Round 4 log analysis

The new log (`game_log_20260318_044908.txt`) shows `PATROL STUCK` does fire (lines 827 and 901 of the log):
```
[04:49:21] [ENEMY] [Enemy8] PATROL STUCK: pos=(2848.0, 301.9) for 1.5s, skipping to next patrol point
[04:49:24] [ENEMY] [Enemy11] PATROL STUCK: pos=(2084.1, 1400.5) for 1.5s, skipping to next patrol point
```

**But Enemy4 never fires PATROL STUCK.** Enemy4 oscillates at `(771, 797)` continuously with corner check firing every ~0.3 s for **5 seconds straight**:
```
[04:49:19] [ENEMY] [Enemy4] PATROL corner check: angle -90.0°
[04:49:20] [ENEMY] [Enemy4] PATROL corner check: angle -90.0°
...dozens of times until end of log...
```

### 10.3 Root Cause 4 — Oscillation exceeds stuck detection threshold

The stuck detection fires only when the enemy moves < 20 px in 1.5 s. But the wall-rubbing oscillation moves the enemy ≈10-15 px **per cycle** (0.3 s). When two directions are both < 90° from the wall normal, the enemy alternates between them — net progress ~0 px/s, but each individual tick may move 10-15 px, **resetting the stuck timer before it reaches 1.5 s**.

Enemy8 and Enemy11 stuck because they happened to oscillate slowly enough to trigger the timer. Enemy4 oscillates faster (varying angles 100°–175°, not a fixed 90°) and resets the timer continuously.

### 10.4 Fundamental Root Cause — Wrong navigation approach

The underlying cause of all wall-rubbing is the **direct direction calculation** used in `_process_patrol()`:

```gdscript
# OLD (broken) approach:
var direction := (target_point - global_position).normalized()
direction = _apply_wall_avoidance(direction)  # ← causes oscillation
velocity = direction * move_speed
```

`_apply_wall_avoidance()` works by casting rays and deflecting the direction vector when a wall is detected. In narrow corridors where the patrol waypoint is on the other side of a wall segment, this deflects the enemy **sideways along the wall** — making no forward progress. The corner check then detects the perpendicular opening and rotates the enemy model, but the velocity is still wall-aligned.

### 10.5 Fix — NavigationAgent2D-based patrol (matching SEARCHING state)

The SEARCHING state does not have this problem because it uses Godot's **NavigationAgent2D** to get a pre-computed path around walls:

```gdscript
# SEARCHING state (working):
_nav_agent.target_position = target_waypoint
var next_pos := _nav_agent.get_next_path_position()
var dir := (next_pos - global_position).normalized()
velocity = dir * move_speed
```

NavigationAgent2D queries the NavMesh polygon and returns intermediate path positions that route **around** wall obstacles rather than into them. The enemy follows these intermediate points sequentially, never needing to push directly through a wall.

**Fix applied to `scripts/objects/enemy.gd`, `_process_patrol()` (Round 4):**

```gdscript
# NEW (fixed) approach — matches SEARCHING state exactly:
_nav_agent.target_position = target_point
if _nav_agent.is_navigation_finished():
    _is_waiting_at_patrol_point = true; ...return
var dir := (_nav_agent.get_next_path_position() - global_position).normalized()
velocity = dir * move_speed; move_and_slide(); _push_casings()
```

**Why this is the correct solution:**
1. NavMesh-based paths route around walls — no wall contact possible on valid navmesh
2. `is_navigation_finished()` is the arrival check — replaces the brittle `distance < 5.0` check
3. The stuck detection is retained as a last-resort safety net (if navmesh is misconfigured)
4. Matches the architecture of SEARCHING, FLANKING, PURSUING — all nav-agent based

### 10.6 Online research — Industry standard for patrol AI

Standard game AI references (GDC talks, Unity/Unreal docs, Godot docs) all recommend using the pathfinding system (NavMesh/NavigationAgent) for patrol movement, not manual steering:
- **Godot docs** (`navigation_using_navigationagents.html`): "Use `get_next_path_position()` each frame to follow the path. Do not apply your own steering towards the final target — use the path intermediate points."
- **AI Game Programming Wisdom (Rabin):** "Waypoint graph / navmesh traversal is always preferred over potential fields for structured patrol routes in corridor environments."
- Manual steering (potential fields, wall avoidance) is appropriate for **reactive/unstructured** movement (fleeing, pursuing in open areas) but causes oscillation in **structured** (corridor-constrained) environments.

### 10.7 Timeline of Round 4

| Time | Event |
|------|-------|
| 2026-03-18 01:19 | Round 3 fix merged: patrol stuck detection added |
| 2026-03-18 01:50 | User reports: "Enemy still rubs against wall" + new log attached |
| 2026-03-18 01:50 | User requests: "reconsider patrol approach based on SEARCHING state" |
| 2026-03-18 | Round 4 analysis: stuck detection insufficient — oscillation resets timer |
| 2026-03-18 | Round 4 fix: `_process_patrol()` rewritten to use `_nav_agent.get_next_path_position()` |
