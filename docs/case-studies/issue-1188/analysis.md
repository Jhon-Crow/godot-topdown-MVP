# Issue #1188: Enemy Pathfinding Optimization – Case Study

## Problem Statement
> Enemies should not walk into walls and should have cached "tactical" paths, all of this must be optimized.
>
> (Original: враги должны ходить не врезаясь в стены и должны быть закэшированный "такитческие" пути, всё это должно быть оптимизировано.)

---

## Current Architecture (as of branch tip)

### NavigationAgent2D Presence
Every `Enemy.tscn` scene includes a `NavigationAgent2D` node with:
- `path_desired_distance = 40.0`
- `target_desired_distance = 10.0`
- `avoidance_enabled = false`
- `max_speed = 320.0`

### All Levels Have Navigation Regions
`NavigationRegion2D` + `NavigationPolygon` are present in all 13 levels. Source geometry is baked from objects in the `"navigation_source"` group.

### Where NavigationAgent2D IS Used
| Code path | Function | Nav used? |
|-----------|----------|-----------|
| PATROL movement (after PR #1119) | `_process_patrol()` | ✅ Yes |
| SEEKING_COVER | `_move_to_target_nav(_cover_position)` | ✅ Yes |
| RETREATING (most branches) | `_move_to_target_nav(_cover_position)` | ✅ Yes |
| PURSUING (cover-to-cover) | `_move_to_target_nav(_pursuit_next_cover)` | ✅ Yes |
| SEARCHING (spiral waypoints) | direct `_nav_agent.target_position =` | ✅ Yes |
| EVADING_GRENADE | direct `_nav_agent.target_position =` | ✅ Yes |
| Vulnerability sound pursuit | `_move_to_target_nav(_last_known_player_position)` | ✅ Yes |

### Where NavigationAgent2D IS NOT Used (Root Cause)
| Code path | Lines | Issue |
|-----------|-------|-------|
| COMBAT approach phase | ~1571-1577 | `_apply_wall_avoidance(direction_to_player)` only — no navmesh |
| COMBAT clear shot movement | ~1516-1520 | `_apply_wall_avoidance()` only — no navmesh |
| PACIFIST pursuit attacker | ~2434 | `_apply_wall_avoidance()` only — no navmesh |
| `_can_reach_position()` validity check | ~3223-3245 | Single raycast — fails around corners |

### Wall Avoidance Mechanism
`_apply_wall_avoidance()` uses 8 `RayCast2D` nodes (`_wall_raycasts`) to steer away from nearby walls. This is a local reactive approach (works well near walls) but:
- Cannot route around large obstacles or around corners
- Does not know about the NavMesh topology
- When the enemy needs to reach a target around a 90° corner, wall avoidance steers the enemy *along* the wall but never commits to turning the corner

### Cover Search Raycasts
`_find_pursuit_cover_toward_player()` casts 16 raycasts synchronously every time it is called (can be called multiple times per frame during PURSUING state). Already partially throttled with `COVER_SEARCH_COOLDOWN = 0.3s`.

`_can_reach_position()` uses a single physics raycast. This only works for straight-line paths and will incorrectly reject cover positions that require navigating around a corner.

---

## Root Cause Analysis

### Primary Bug: COMBAT Approach Uses No NavMesh
When an enemy transitions to COMBAT and approaches the player (lines ~1563-1583), movement direction is:
```gdscript
var move_direction := direction_to_player  # Direct line to player
move_direction = _apply_wall_avoidance(move_direction)  # Only local steering
velocity = move_direction * combat_move_speed
```
If the player is behind a wall or around a corner, the enemy walks into the wall and stays stuck until `GLOBAL_STUCK_MAX_TIME` (4 seconds) triggers a global stuck recovery.

### Secondary Bug: _can_reach_position Uses Raycast Not NavMesh
`_can_reach_position()` checks if there is a direct line-of-sight to cover using a physics raycast. This incorrectly *rejects* cover around corners (the raycast hits the corner wall), causing `_find_pursuit_cover_toward_player()` to find no valid cover and fall through to the "approach directly" path — which loops back to the primary bug.

### Performance Issue: Redundant _nav_agent Target Reassignment
`_get_nav_direction_to()` sets `_nav_agent.target_position = target_pos` every physics frame (60 fps). NavigationAgent2D internally only recalculates when the target changes (Godot 4 uses async path requests), so most reassignments are no-ops. However, the pattern of calling `_move_to_target_nav` combined with `_apply_wall_avoidance` on top of the navmesh direction is partially redundant — the navmesh already steers around walls.

---

## Solution Implemented

### Fix 1: Use NavMesh in COMBAT Approach Phase
Replace direct-direction + wall-avoidance in COMBAT approach with `_move_to_target_nav(_player.global_position)`. This ensures enemies navigate around corners to reach the player.

The enemy still aims at the player while following the nav path (rotation is set separately after velocity is set).

### Fix 2: Use NavMesh in COMBAT Clear Shot Movement
Replace wall-avoidance-only movement in clear shot seeking with `_move_to_target_nav(_clear_shot_target)`.

### Fix 3: Use NavMesh for PACIFIST Pursuing
Replace wall-avoidance-only movement in pacifist state with `_move_to_target_nav`.

### Fix 4: Use NavigationServer2D for _can_reach_position
Replace single raycast with a NavigationServer2D closest-point check. If the nav mesh has a point near the target, it's reachable. This allows cover-around-corners to be correctly accepted.

---

## Known Alternatives Considered

| Approach | Pros | Cons |
|----------|------|------|
| Godot NavigationAgent2D (current partial, extending) | Built-in, async, navmesh-based, wall-aware | Requires navmesh in every scene (already present) |
| A* grid pathfinding (custom) | Full control | Very expensive to bake for tile-free levels; re-implementing what NavigationAgent already does |
| Steering Behaviors (pure) | Simple | Cannot navigate complex winding corridors reliably |
| Avoidance only (current) | Zero setup | Gets stuck in concave obstacles and at corners |

NavigationAgent2D is the correct choice as the project already uses it and all levels already have NavigationRegion2D baked.

---

## Files Modified
- `scripts/objects/enemy.gd` — COMBAT approach, clear shot, pacifist state, `_can_reach_position`
