# Case Study: Issue #1107 — Enemy with Machete Walks into Walls

## Problem Description
Enemies (specifically the machete enemy, but affecting all PATROL-behavior enemies) get permanently stuck in corners or near obstacles. They oscillate between P3:corner and P4:velocity rotation states and never make progress toward their patrol points.

## Game Log Evidence (game_log_20260318_122059.txt)

From the BuildingLevel session starting at 12:21:04:

- **Enemy7** spawned at (1600, 900), PATROL behavior
  - STUCK at (1611, 899) after 1.5s — barely moved 11px
  - Pattern: rapid `PATROL corner check: angle ~89.5°` repeating every 0.3s
  - PATROL STUCK fires repeatedly at same position across multiple attempts

- **Enemy10** spawned at (1200, 1550), PATROL behavior
  - STUCK at (1200, 1601.992) after 1.5s — moved 52px south
  - Oscillates between y=1602 (stuck south) and y=1424 (stuck north)
  - `corner_timer` oscillates: `P3:corner -> P4:velocity -> P3:corner -> P4:velocity`

## Root Cause Analysis

### Timeline of Regressions

| Commit | Change | Effect |
|--------|--------|--------|
| Before `89798783` | Patrol used `_apply_wall_avoidance()` directly | Working correctly |
| `89798783` (Issue #1107 fix) | Added `NavigationAgent2D` to patrol, `path_desired_distance 4→28` | Nav path avoidance, wall-rubbing reduced |
| `eb1499b4` (Issue #1107 fix 2) | `path_desired_distance 28→40`, wall escape logic added | Corner-cutting regression |
| `1ea1d7e6` (Issue #1175 fix) | `path_desired_distance 40→10` | Corner-cutting fixed, but wall-contact stuck persists |

### Why Enemies Get Stuck

1. **Enemy7 at (1600, 900)** spawns with its collision circle (radius 24) overlapping **Table2** at (1550, 950) — a 80x80 static body. The overlap is at x=1576-1590, y=910-924.

2. The `_process_patrol` function (post-issue-#1107) calls:
   ```gdscript
   var dir := (_nav_agent.get_next_path_position() - global_position).normalized()
   velocity = dir * move_speed; move_and_slide(); _push_casings()
   ```

3. The nav direction points WEST toward patrol point (1500, 900), but Table2 causes a physics collision that pushes the enemy and slides it. The nav direction doesn't account for wall contact.

4. The old backup branch code used `_apply_wall_avoidance(direction)` which uses raycasts to detect walls ahead and steers around them — this handles the overlap scenario correctly.

5. **Double `move_and_slide()` problem**: `_process_patrol` called `move_and_slide()` at line 4057, and `_physics_process` calls it again at line 865. This means patrol enemies called `move_and_slide()` twice per frame.

### Corner Oscillation Pattern
The `_process_corner_check` fires when a perpendicular opening is detected (raycast finds no wall in perpendicular direction). At positions like (1611, 899) inside Room4, there are always open directions, causing `corner_timer` to fire every 0.3s — creating the P3:corner → P4:velocity oscillation seen in logs.

This oscillation does NOT prevent movement but indicates the enemy is at a corner or intersection continuously.

## Fix Applied

Modified `_process_patrol` in `scripts/objects/enemy.gd`:

1. **Removed `move_and_slide()` from patrol** — it was called here AND in `_physics_process`, causing double execution.

2. **Added `_apply_wall_avoidance(dir)`** — same raycast-based wall steering that the old backup branch used.

3. **Added slide-normal corner escape** — same logic as `_move_to_target_nav()`, blends wall collision normals into movement direction when enemy is in contact with a wall.

The patrol function now uses the same wall-handling approach as all other movement states.

## References

- [Godot Forum: NavigationAgent2D stuck on corners](https://forum.godotengine.org/t/navigationagent2d-keeps-geting-stuck-on-corners/126027)
- [Godot Issue #88237: corner-cutting with high path_desired_distance](https://github.com/godotengine/godot/issues/88237)
- PR #999 (backup 11.03.2026): backup branch reference implementation
- Issue #1119: NavigationAgent2D routing introduced to patrol
- Issue #1175: path_desired_distance regression (companion issue)
