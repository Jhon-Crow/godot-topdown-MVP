# Case Study: Issue #1632 — Original Enemy Teleports Through Walls on Illusion Spawn

## Overview

**Issue**: When a gas-mask enemy throws a chemical grenade and illusory copies are spawned (`ChemicalCloud._spawn_illusions_for_nearby_enemies`), the original enemy is teleported to a randomly chosen offset position. In narrow corridors, this sometimes placed the enemy inside wall geometry.

**Status**: Updated in PR #1646 after two follow-up reports: wall placement persisted at lower frequency after the nav-mesh-only fix, then the physics validation raised performance concerns in long chemical-cloud sessions.

**Input logs**:
- `logs/game_log_20260327_223228.txt` (session from 2026-03-27 22:32-22:33)
- `logs/game_log_20260327_231057.txt` (performance follow-up)
- `logs/game_log_20260327_232137.txt` (performance follow-up)
- `logs/game_log_20260327_233304.txt` (performance follow-up)
- `logs/performance-key-lines.txt` (extracted chemical-cloud and FPS events)

---

## Timeline of Events (from game log)

| Time | Event |
|------|-------|
| 22:32:50 | Chemical cloud spawned at (193.4, 2569.0), radius=600 |
| 22:32:50 | Enemy moved (192.4, 2547.2) → (97.5, 2478.1), offset **−113.6px** — HIGH RISK |
| 22:32:50 | Enemy moved (201.1, 2607.9) → (140.7, 2521.0), offset **105.8px** — HIGH RISK |
| 22:32:52 | `[ForkGuardRight] Warning: No valid flank position (both sides behind walls)` |
| 22:33:01 | Second cloud spawned at (79.2, 2670.6) |
| 22:33:01 | Enemy moved (61.0, 2762.1) → (157.3, 2723.3), offset **103.9px** — HIGH RISK |
| 22:33:10 | Third cloud spawned at (120.4, 2604.9) |
| 22:33:10 | Enemy moved (159.0, 2317.7) → (103.0, 2402.8), offset **101.9px** — HIGH RISK |
| 22:33:13 | `[ForkGuardUp] FLANKING stuck (2.0s), pos=(177.7, 1158.6)` |
| 22:33:37 | Fourth cloud spawned, 3 enemies moved with offsets 101–114px — HIGH RISK |

### All Original Enemy Movements (13 total)

| Time | From | To | Offset magnitude | Risk |
|------|------|----|-----------------|------|
| 22:32:50 | (200.0, 2701.3) | (130.8, 2736.7) | 77.7 px | medium |
| 22:32:50 | (201.1, 2607.9) | (140.7, 2521.0) | **105.8 px** | HIGH |
| 22:32:50 | (192.4, 2547.2) | (97.5, 2478.1) | **117.4 px** | HIGH |
| 22:33:01 | (61.0, 2762.1) | (157.3, 2723.3) | **103.9 px** | HIGH |
| 22:33:01 | (264.0, 1656.3) | (188.0, 1641.0) | 77.5 px | medium |
| 22:33:10 | (200.7, 2621.3) | (274.5, 2657.2) | 82.0 px | medium |
| 22:33:10 | (159.0, 2317.7) | (103.0, 2402.8) | **101.9 px** | HIGH |
| 22:33:10 | (256.2, 2369.0) | (311.8, 2340.1) | 62.7 px | medium |
| 22:33:19 | (200.0, 2752.7) | (250.8, 2856.2) | **115.3 px** | HIGH |
| 22:33:26 | (242.1, 2721.5) | (245.5, 2656.5) | 65.1 px | medium |
| 22:33:37 | (204.1, 2621.0) | (304.9, 2615.3) | **101.0 px** | HIGH |
| 22:33:37 | (178.1, 2580.5) | (209.5, 2685.0) | **109.1 px** | HIGH |
| 22:33:37 | (299.2, 2313.9) | (275.0, 2202.3) | **114.2 px** | HIGH |

**8 of 13 moves (62%) had offsets ≥100 px** — these are the risky ones.

---

## Root Cause Analysis

### Root Cause 1: Nav-mesh Snap Tolerance Is Too Permissive

The fix in PR #1646 introduced `_is_position_on_nav_map()` with `NAV_SNAP_TOLERANCE = 50.0` px.

`NavigationServer2D.map_get_closest_point(nav_map, pos)` returns the **nearest point on the nav-mesh surface**. When a candidate position is inside a wall:
- The closest nav-mesh point is the nearest edge of the nav-mesh polygon — usually the inside edge of the wall.
- If the wall is **thinner than 50 px**, the snapped distance is less than 50 px → the position is falsely accepted.

Common wall thicknesses in tilemaps: 16–64 px. Many corridor walls are ≤50 px thick.

### Root Cause 2: Nav-mesh Geometry ≠ Physical Geometry

The nav-mesh is baked from physics geometry with a safety margin (`agent_radius` in the NavigationPolygon). However:
- The nav-mesh boundary can be offset from the physical wall by the agent radius (typically 10–20 px).
- A point just inside the physical wall may still be within 50 px of the nav-mesh edge.
- The nav-mesh check confirms reachability for navigation, not physical overlap with wall collision shapes.

### Root Cause 3: No Physical Overlap Check

The codebase already has a proven pattern for checking if a position is inside a wall:

```gdscript
# From enemy.gd line 3089 — checks if a point is inside a wall (obstacles layer)
var pq := PhysicsPointQueryParameters2D.new()
pq.position = candidate_pos
pq.collision_mask = 4  # Layer 3 = obstacles/walls
if not space_state.intersect_point(pq, 1).is_empty():
    # Position is inside a wall — reject it
```

This uses Godot's physics engine to directly test overlap with colliders. The nav-mesh check **does not** do this — it only measures distance to the nearest nav polygon surface point.

### Root Cause 4: No Line-of-Sight Check Between Old and New Position

Even if the destination is on the navmesh, the straight line from the enemy's current position to the target may cross a wall. Moving through a wall (even briefly via `global_position =`) clips the enemy into geometry, and the physics engine may not push them out correctly.

### Root Cause 5: Center Candidate Could Short-Circuit Random Placement

The first physics-validation draft shuffled all candidate indices, including index `0` (the original center position). Because the center was accepted immediately as always valid, any shuffle that put index `0` before valid non-center offsets would keep the real enemy in place without testing those offsets.

That behavior did not cause wall clipping, but it weakened the "random position for the original" behavior requested in issue #1361. The final selection now shuffles and validates only non-center offsets first, and uses center strictly as the fallback when no random offset is safe.

---

## Performance Follow-up

The owner reported on 2026-03-27 that the fix appeared to affect performance heavily and attached three more logs. Those logs show:

| Log | Chemical cloud pattern | FPS pattern |
|-----|------------------------|-------------|
| `game_log_20260327_231057.txt` | Repeated radius-600 clouds spawning capped illusion batches | FPS drops continue while clouds/illusions remain active |
| `game_log_20260327_232137.txt` | Many clouds spawn 10 illusion copies for 11-13 enemies | Drops range from high 20s down to single digits after cloud spawn |
| `game_log_20260327_233304.txt` | Multiple overlapping clouds, frequent per-cloud cap hits, global cap hits | Drops continue for the 20s cloud/illusion lifetime |

The log evidence points to the sustained cost of active chemical clouds and illusion copies, not only the one-time placement validation. The validation checks run during spawn candidate selection, while the severe FPS drops persist for many seconds after the spawn line and often until the cloud dissipates.

Still, the final implementation keeps validation allocation-light:

- One validation context is created per enemy placement batch.
- One `PhysicsPointQueryParameters2D` and one `PhysicsRayQueryParameters2D` are reused for all candidates in that batch.
- Only non-center candidates are validated. Center is not queried because it is the fallback no-move position.

---

## Evidence from the Log

### High-Risk Moves That May Have Caused Issues

Move at 22:32:50: **enemy at (192.4, 2547.2) moved to (97.5, 2478.1), offset = (−113.6, −29.7)**

This is an x-displacement of 113.6 px to the **left** from an enemy near x=192. In the LabyrinthLevel, the leftmost playable area near y=2547 is approximately x=75–90 (based on cloud position at x=193 and enemy starting positions near x=200). Moving left 113 px from x=192 puts the enemy at x=97 — potentially near or inside a left corridor wall.

### ForkGuardRight "No Valid Flank Position" Warnings

These warnings appear immediately after the first batch of illusion spawns (line 1194, 2.0s after the moves). The guard was likely stuck because it was teleported to a position near a wall and the AI's flank position calculation found no valid options.

---

## Solution

### Implemented Fix (PR #1646, first round)

Added nav-mesh validation via `NavigationServer2D.map_get_closest_point()` with 50 px tolerance. This reduced frequency but did not eliminate the bug.

### Improved Fix (Implemented)

Replace (or supplement) the nav-mesh check with **physics-based overlap detection**:

1. **Primary check**: Use `PhysicsDirectSpaceState2D.intersect_point()` with `collision_mask = 4` (obstacles layer) to directly check if the candidate position is inside a wall collider.

2. **Secondary check** (defense in depth): Keep the nav-mesh check as an additional guard. Reduce `NAV_SNAP_TOLERANCE` to 20 px (matching agent radius).

3. **Line-of-sight check**: Cast a ray from `enemy.global_position` to `candidate_pos` with `collision_mask = 4`. Reject candidates where the path crosses a wall.

4. **Preserve random original placement**: Shuffle only non-center candidates first. Keep index `0` as a deterministic fallback only if every random candidate fails validation.

5. **Reduce validation overhead**: Reuse physics query parameter objects inside a validation context instead of allocating new query objects for every candidate.

The combined approach matches the physics-query pattern used elsewhere in the codebase while avoiding the nav-mesh false positives that caused the wall placement bug.

---

## Files Involved

| File | Role |
|------|------|
| `scripts/effects/chemical_cloud.gd` | Main fix location — `_spawn_illusions_for_nearby_enemies()`, `_create_position_validation_context()`, and `_is_position_valid()` |
| `scripts/effects/illusion_effect.gd` | IllusionEffect node — not involved in position validation |
| `scripts/components/enemy_teleport_component.gd` | Reference: uses same nav-mesh approach (50px tolerance) |
| `scripts/characters/player.gd` | Reference: `_is_spawn_position_valid()` uses physics overlap check (correct approach) |

---

## References

- [Godot 4 NavigationServer2D.map_get_closest_point](https://docs.godotengine.org/en/stable/classes/class_navigationserver2d.html#class-navigationserver2d-method-map-get-closest-point) — returns closest point on nav-mesh surface, does NOT detect interior-of-wall positions
- [Godot 4 PhysicsDirectSpaceState2D.intersect_point](https://docs.godotengine.org/en/stable/classes/class_physicsdirectspacestate2d.html#class-physicsdirectspacestate2d-method-intersect-point) — detects if a point is inside a collider, even when origin is inside
- PR #1646: Initial fix (nav-mesh validation)
- Issue #1632: Original report
- Issue #1355: Similar problem in `EnemyTeleportComponent` — solved with same nav-mesh approach (partial fix)
