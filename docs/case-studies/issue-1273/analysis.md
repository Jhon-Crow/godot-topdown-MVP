# Case Study: Issue #1273 — Enemy Pathfinding Accounting for Walls and Enemy Sizes

## Problem Statement

The issue requests enemy pathfinding that accounts for:
1. **Walls** — enemies should navigate around obstacles using proper pathfinding, not just raycast-based wall avoidance
2. **Enemy sizes** — the navmesh erosion margin should match the enemy's collision radius so enemies don't clip walls

**Original request (translated from Russian):** "Make enemy pathfinding that accounts for walls and enemy sizes."

---

## Root Cause Analysis

### Finding 1: State Classes Using Raycast-Only Avoidance

The `idle_state.gd` patrol movement and `pursuing_state.gd` approach/cover movement both use raw `_apply_wall_avoidance()` (8 radial raycasts) directly instead of calling `_move_to_target_nav()` which correctly uses `NavigationAgent2D`.

**`idle_state.gd` (lines 67-71) — BEFORE:**
```gdscript
if enemy.has_method("_apply_wall_avoidance"):
    direction = enemy._apply_wall_avoidance(direction)
enemy.velocity = direction * enemy.move_speed
```

**`pursuing_state.gd` (lines 63-69) — BEFORE:**
```gdscript
var direction: Vector2 = (enemy._player.global_position - enemy.global_position).normalized()
if enemy.has_method("_apply_wall_avoidance"):
    direction = enemy._apply_wall_avoidance(direction)
enemy.velocity = direction * enemy.combat_move_speed
```

This means patrol enemies and pursuing enemies can still press into walls, since raycasts only deflect the direction vector — they don't compute a full path around the obstacle.

### Finding 2: enemy.gd Already Has the Correct Pattern

`enemy.gd` (lines 4092-4094) correctly uses `_move_to_target_nav` for patrol:
```gdscript
# Issue #1220: use _move_to_target_nav so patrol gets the same wall-avoidance + ORCA +
# slide-collision corner-escape used by PURSUING/FLANKING, preventing wall-pressing.
if not _move_to_target_nav(target_point, move_speed):
```

The state class files are a newer refactored architecture that was not yet updated to match this correct pattern.

### Finding 3: NavigationAgent2D Radius vs CollisionShape Radius

In `Enemy.tscn`:
- `CircleShape2D_enemy` (collision): `radius = 24.0`
- `NavigationAgent2D`: `radius = 24.0`
- All level `NavigationPolygon`: `agent_radius = 24.0`

These values are consistent — the navmesh is eroded by exactly the enemy's collision radius, which prevents enemies from being routed too close to walls. This is correct for the current standard enemy.

---

## Solution

Update `idle_state.gd` and `pursuing_state.gd` to use `_move_to_target_nav()` instead of manual direction + `_apply_wall_avoidance()`, following the established pattern in `enemy.gd`.

### What `_move_to_target_nav()` provides vs raw `_apply_wall_avoidance()`:

| Feature | `_apply_wall_avoidance()` | `_move_to_target_nav()` |
|---------|--------------------------|------------------------|
| Wall avoidance | ✅ (raycasts, local) | ✅ (raycasts + nav path) |
| NavigationAgent2D path planning | ❌ | ✅ |
| ORCA multi-agent avoidance | ❌ | ✅ |
| Corner escape (slide collision) | ❌ | ✅ |
| Wall size awareness (agent_radius) | Partial (raycasts hit at body edge) | ✅ (navmesh eroded by agent_radius) |

### Best Practices (from Godot docs and D0NM/GodotRu reference)

1. **Always use NavigationAgent2D for path-following** — `NavigationServer2D` uses A* on the baked navmesh polygon, properly routing around concave obstacles that raycasts miss.
2. **Match `agent_radius` on navmesh to enemy collision radius** — already correctly set to 24.0 across all levels and the NavigationAgent2D.
3. **Feed intended velocity to ORCA** — already done in `_move_to_target_nav()` via `set_velocity()`.
4. **Handle `is_navigation_finished()` for arrival detection** — `_move_to_target_nav()` returns `false` when arrived, which the state can use to trigger the wait phase.

---

## Changes Made

1. **`scripts/ai/states/idle_state.gd`**: Replaced direct `_apply_wall_avoidance` + velocity assignment with `_move_to_target_nav` call, with fallback for missing nav agent. Also added arrival detection based on the return value.

2. **`scripts/ai/states/pursuing_state.gd`**: Replaced direct `_apply_wall_avoidance` in `_process_approach_phase()` and `_process_cover_movement()` with `_move_to_target_nav` calls.

3. **`tests/unit/test_enemy_states.gd`**: Updated mock enemy to include `_move_to_target_nav` and removed assertion that `_apply_wall_avoidance` is called by patrol (it is now called internally by `_move_to_target_nav` on the real enemy, not directly from the state).

---

## References

- [Godot NavigationAgent2D docs](https://docs.godotengine.org/en/stable/classes/class_navigationagent2d.html)
- Reference repo: https://github.com/D0NM/GodotRu
- Issue #1220 (patrol wall-pressing fix in enemy.gd)
- Issue #1107 (corner escape via slide collision)
- Issue #1146 (ORCA multi-agent avoidance)
