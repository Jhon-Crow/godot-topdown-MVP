# Case Study: Issue #1226 — Enemy AI Cross-Room Routing

**Issue:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1226
**PR:** https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1232
**Date:** 2026-03-21

---

## Problem Statement

The owner reported:
1. Enemies stall when the player moves into a different room
2. In debug display (F7), passage waypoints should be visible
3. FPS dropped significantly and doesn't recover
4. Enemies in office 2 still get stuck in the lower-left corner
5. Enemies in idle state sometimes walk directly toward the player

---

## Evidence

### Game Logs Analyzed
- `game_log_20260321_065153.txt` (6672 lines)
- `game_log_20260321_065417.txt` (789 lines)

### Screenshot
- `screenshot_enemy_stuck_office2.png`: Two enemies in IDLE state clustered in the lower-left corner of Office 2 with a red arrow pointing to their stuck position

---

## Timeline / Sequence of Events

1. **Initial Issue (#1226)**: Enemies stall when the player moves to a different room because `_find_pursuit_cover_toward_player()` only performs a local raycast search within `COVER_CHECK_DISTANCE`. When the player is in a different room, no local cover toward the player exists.

2. **Initial Fix (ca57376f)**: Added 12 `Marker2D` waypoints at doorways in `BuildingLevel.tscn`, tagged `passage_waypoints`. When no local cover is found, the enemy queries the group to find the nearest waypoint closer to the player.

3. **Refactor (4c3d195)**: Switched from push-based to pull-based approach using scene groups to stay under 5000-line CI limit.

4. **Owner Feedback (2026-03-21)**: After testing, multiple new problems were observed:
   - FPS drop
   - Enemies still stuck in Office 2 lower-left corner
   - Idle enemies walking toward player
   - Waypoints not visible in F7 debug display

---

## Root Cause Analysis

### RCA-1: FPS Drop — `get_nodes_in_group()` called every physics frame per enemy

**Location:** `scripts/objects/enemy.gd:3214`

```gdscript
for wp in get_tree().get_nodes_in_group("passage_waypoints"):
```

**Problem:** `get_tree().get_nodes_in_group()` is called inside `_find_pursuit_cover_toward_player()`. This function is called:
- Every frame while `_has_pursuit_cover == false` in PURSUING state
- When an enemy can't find local cover (which happens every time player is in another room)
- For **every enemy** independently

With 8-12 enemies all simultaneously failing to find local cover and each calling `get_nodes_in_group()` every physics frame (60×/sec), this creates O(enemies × frames × nodes) work per second — significant overhead.

**Fix:** Cache the waypoint nodes at scene initialization (in `_ready()`), refresh cache only when the group changes. This turns O(n tree traversal) into O(1) array access.

### RCA-2: Enemy Stuck in Office 2 — Waypoint routing algorithm rejects useful waypoints

**Location:** `scripts/objects/enemy.gd:3216`

```gdscript
if wp.global_position.distance_to(player_pos) < my_distance_to_player and d >= 50.0 and d < best_d:
```

**Problem:** The waypoint selection criterion requires the waypoint to be **closer to the player** than the enemy's current straight-line distance. This fails for concave/corridor maps:

**Scenario:**
- Enemy3 at (700, 750) in Office 2 (bounded x:524-912, y:712-1000)
- Player at (450, 1400) in Lobby
- Distance enemy→player: `sqrt((700-450)² + (750-1400)²) ≈ 697px`
- Waypoint P2_Office2_to_Corridor at (950, 700)
- Distance P2→player: `sqrt((950-450)² + (700-1400)²) ≈ 860px`

**P2 is rejected because 860 > 697!** But P2 is the correct doorway to exit Office 2. The Manhattan/Euclidean distance doesn't account for the wall structure — going through the doorway (north-east) is necessary even though it moves "away" in straight-line distance.

The enemy has no valid waypoint to exit Office 2 and stays stuck.

**Fix:** Remove the strict "waypoint must be closer to player than enemy" condition. Instead, score waypoints by navigation mesh path length (not straight-line distance), or use a two-phase approach: first route to the nearest unobstructed waypoint, then use navigation to reach the player.

### RCA-3: Idle Enemies Walking Toward Player — Memory system triggers pursuit on sound cues

**Location:** `scripts/objects/enemy.gd:1341-1352`, `scripts/ai/enemy_memory.gd`

```gdscript
if _memory and _memory.has_target():
    if _memory.is_high_confidence():
        _transition_to_pursuing()
    elif _memory.is_medium_confidence():
        _transition_to_pursuing()
```

**Constants:**
- `SOUND_CASING_KICK_CONFIDENCE = 0.5`
- `MEDIUM_CONFIDENCE_THRESHOLD = 0.5`

**Problem:** When the player fires a weapon, a CASING_KICK sound event is broadcast. This gives nearby enemies exactly 0.5 confidence, which equals `MEDIUM_CONFIDENCE_THRESHOLD`. The condition `is_medium_confidence()` returns true for `confidence >= 0.5`, so enemies immediately leave IDLE to pursue.

**Evidence from log:**
```
[52:45] [ENEMY] [Enemy4] Heard CASING_KICK at (501.6093, 666.7013), intensity=0.21, dist=109
[52:40] [ENEMY] [Enemy1] Memory: medium confidence (0.62) - transitioning to PURSUING
[52:40] [ENEMY] [Enemy1] State: IDLE -> PURSUING
```

**Issue:** This is actually *expected behavior* — enemies should investigate gunfire sounds. However, the owner reports it as a bug: "sometimes enemies in idle state walk directly toward the player." This likely means the memory position is pointing in a direction that happens to lead directly to the player even from a different room, making it look like the enemy has wall-vision.

**Actual bug:** When the enemy reaches the suspected position but finds no player, the memory should decay more aggressively. Additionally, if `SOUND_CASING_KICK_CONFIDENCE (0.5)` is exactly equal to `MEDIUM_CONFIDENCE_THRESHOLD (0.5)`, it creates a sensitive triggering threshold.

### RCA-4: Waypoints Not Visible in F7 Debug — No debug visualization added

**Location:** `scripts/objects/enemy.gd:4582` (`_draw()` function)

The `_draw()` function draws FOV cones, cover positions, flank positions, pursuit targets, and memory positions — but does not visualize passage waypoints. When F7 debug mode is enabled, the player/designer cannot see where waypoints are placed to verify correctness.

**Fix:** Add waypoint visualization in `_draw()` when debug mode is enabled.

---

## Proposed Solutions

### Solution 1 (FPS Fix): Cache waypoint nodes at `_ready()`

```gdscript
var _cached_passage_waypoints: Array[Node] = []

func _ready() -> void:
    # ... existing code ...
    _cached_passage_waypoints = get_tree().get_nodes_in_group("passage_waypoints")
```

Then replace `get_tree().get_nodes_in_group("passage_waypoints")` with `_cached_passage_waypoints`.

**Trade-off:** Cache becomes stale if waypoints are dynamically added/removed at runtime. For BuildingLevel where waypoints are static, this is safe.

### Solution 2 (Office 2 Routing Fix): Remove player-proximity constraint; use nearest-doorway routing

Instead of requiring waypoints to be straight-line closer to the player, pick the **nearest navigable waypoint** and route toward it. The waypoint's role is simply to get the enemy through a doorway — not to be the final destination. Once past the doorway, the navigation mesh handles routing.

**New algorithm:**
```gdscript
# Pick nearest waypoint that the enemy hasn't come from
var best_wp := Vector2.ZERO
var best_d := INF
for wp in _cached_passage_waypoints:
    var d := global_position.distance_to(wp.global_position)
    if d >= 50.0 and d < best_d:
        best_d = d
        best_wp = wp.global_position
```

This is simpler and doesn't incorrectly reject waypoints based on Euclidean distance.

### Solution 3 (Debug Visualization): Draw waypoints in `_draw()`

In the `_draw()` function, after the existing debug visualizations, add:
```gdscript
# Draw passage waypoints
if _cached_passage_waypoints.size() > 0:
    for wp in _cached_passage_waypoints:
        var to_wp := wp.global_position - global_position
        draw_circle(to_wp, 6.0, Color.LIME_GREEN)
```

**Alternative:** Draw waypoints from a dedicated level debug script (not per-enemy), since each enemy would draw them independently causing overdraw.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/objects/enemy.gd` | Cache passage waypoints; fix routing algorithm; add debug visualization |
| `scenes/levels/BuildingLevel.tscn` | Verify/correct waypoint positions for Office 2 |
| `docs/case-studies/issue-1226/analysis.md` | This document |

---

## References

- [Godot Navigation Groups](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_introduction_2d.html)
- [A* Pathfinding for Games](https://theory.stanford.edu/~amitp/GameProgramming/)
- [Patrol Point Routing (Issue #1216 case study)](../issue-1216/analysis.md)
