# Case Study: Issue #1271 — Enemies bumping into walls instead of navigating around them

## Issue Summary

**Title (RU):** сделай чтоб враги не долбились об стену а обходили её
**Title (EN):** Make enemies navigate around walls instead of bumping into them

**Reporter suggestion:** Use `NavigationRegion2D` or fix the navmesh overlapping with walls. Use the most recent reliable approach.

## Root Cause Analysis

### What Works (Good)

The game already uses Godot 4's `NavigationAgent2D` + `NavigationRegion2D` stack:

- All 13 levels have `NavigationRegion2D` nodes with `NavigationPolygon` set to bake from collision shapes on layer 4
- All levels call `nav_region.bake_navigation_polygon(false)` at runtime in `_ready()`
- Enemy nodes (`Enemy.tscn`) have `NavigationAgent2D` with `avoidance_enabled = true`, `radius = 24.0`
- The helper `_move_to_target_nav(target_pos, speed)` correctly uses navmesh pathfinding (`_nav_agent.target_position`, `get_next_path_position()`) and includes corner-escape logic

Many states already use `_move_to_target_nav` correctly:
- `PATROL` (fixed in #1119/#1220)
- `SEEKING_COVER` → `_move_to_target_nav(_cover_position, ...)`
- `RETREATING` → `_move_to_target_nav(_cover_position, ...)`
- `FLANKING` → `_move_to_target_nav(_flank_target, ...)`
- `PURSUING` → `_move_to_target_nav(target, ...)`
- Machete `COMBAT` → `_move_to_target_nav(player_pos, ...)`

### What Doesn't Work (Root Cause)

Several code paths still use **direct wall-avoidance raycasts only** (the old approach), bypassing navmesh pathfinding entirely:

#### 1. COMBAT approach phase (`_process_combat_state`, line ~1547)
```gdscript
var move_direction := direction_to_player      # ← straight line to player
move_direction = _apply_wall_avoidance(move_direction)  # ← only raycast-based avoidance
velocity = move_direction * combat_move_speed
```
When the player is behind a wall, the enemy will head straight toward them and get stuck pressing against the wall. The 8-ray wall-avoidance is insufficient for navigating around corners.

#### 2. COMBAT seeking-clear-shot phase (`_process_combat_state`, line ~1492)
```gdscript
var move_direction := (_clear_shot_target - global_position).normalized()
move_direction = _apply_wall_avoidance(move_direction)  # ← only raycast-based
velocity = move_direction * combat_move_speed
```
Same issue for short-range repositioning to find a clear shot.

#### 3. PACIFIST state retaliating movement (`_process_pacifist_state`, line ~2432)
```gdscript
velocity = _apply_wall_avoidance((tgt.global_position - global_position).normalized()) * combat_move_speed
```
Retaliating pacifist uses direct line approach only.

#### 4. PACIFIST state going to cover (`_process_pacifist_state`, line ~2437)
```gdscript
velocity = _apply_wall_avoidance((_cover_position - global_position).normalized()) * move_speed
```
When the cover is behind a wall, the enemy bumps into the wall.

## Existing Infrastructure

### `_apply_wall_avoidance(direction)` (line ~3592)
- Uses 8 `RayCast2D` nodes spread in front
- Detects nearby walls and steers away
- **Weakness:** Only local avoidance, cannot navigate around corners or through passages

### `_move_to_target_nav(target_pos, speed)` (line ~4703)
- Sets `_nav_agent.target_position = target_pos`
- Gets `_nav_agent.get_next_path_position()` as next waypoint
- Calls `_apply_wall_avoidance()` on the nav direction
- Includes corner-escape logic from slide collisions
- **Strength:** True graph-based pathfinding; can route around walls

## Solution

Replace direct `_apply_wall_avoidance()` calls in affected movement code with `_move_to_target_nav()`, matching the pattern already used in PATROL, PURSUING, FLANKING, etc.

### Changes Required

**File:** `scripts/objects/enemy.gd`

1. **COMBAT approach** (line ~1547–1552): Replace direct movement with `_move_to_target_nav(_player.global_position, combat_move_speed)` while still facing the player.

2. **COMBAT seeking-clear-shot** (line ~1492–1496): Replace direct movement with `_move_to_target_nav(_clear_shot_target, combat_move_speed)` while still facing the player.

3. **PACIFIST retaliating** (line ~2432): Replace direct `_apply_wall_avoidance()` with `_move_to_target_nav(tgt.global_position, combat_move_speed)`.

4. **PACIFIST going to cover** (line ~2437): Replace direct `_apply_wall_avoidance()` with `_move_to_target_nav(_cover_position, move_speed)`.

## Godot 4 Best Practices for Navigation

Based on Godot 4 docs and community guidance:
- `NavigationAgent2D.target_position` → sets destination
- `NavigationAgent2D.get_next_path_position()` → returns next waypoint along the baked navmesh path
- `NavigationAgent2D.is_navigation_finished()` → true when arrived
- `NavigationAgent2D.avoidance_enabled = true` → enables ORCA agent-to-agent avoidance
- `NavigationAgent2D.velocity_computed` signal → gets ORCA-safe velocity (already wired up via `_on_avoidance_velocity_computed`)

The navmesh baking uses `parsed_geometry_type = PARSED_GEOMETRY_STATIC_COLLIDERS` with `parsed_collision_mask = 4` (wall layer), ensuring walls are carved out of the walkable area automatically.

## References

- [Using NavigationAgents — Godot 4 docs](https://docs.godotengine.org/en/latest/tutorials/navigation/navigation_using_navigationagents.html)
- [2D navigation overview — Godot 4 docs](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_introduction_2d.html)
- Issue #1119 / #1220: Similar fix for PATROL state
- Issue #318: Previous navigation fix for PURSUING
