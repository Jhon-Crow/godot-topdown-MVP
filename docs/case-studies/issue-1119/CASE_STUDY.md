# Case Study: Patrolling Enemies Walk in Place — LabyrinthLevel (Issue #1119)

**Issue:** #1119 — fix патрулирующие враги (Fix patrolling enemies)
**PR:** #1120
**Status:** Fixed
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
| 2026-03-18 | PR #1120: increase patrol_offsets to `±200 px`, add regression test |
