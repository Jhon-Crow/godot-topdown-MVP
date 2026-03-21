# Case Study: Issue #1273 — Enemy Pathfinding Accounting for Walls and Enemy Size

## Issue Summary

The issue (in Russian): "сделай позфайндинг врагов с учётом стен и размеров врагов"
Translation: "Make enemy pathfinding account for walls and enemy sizes"

Reference: https://github.com/D0NM/GodotRu (Godot pathfinding tutorial repo in Russian)

## Problem Analysis

### Current State of Pathfinding

The project uses Godot 4's `NavigationAgent2D` for enemy movement. The setup at time of filing:

| Component | Value | Location |
|-----------|-------|----------|
| `NavigationPolygon.agent_radius` | `24.0` (bake-time wall erosion) | All level `.tscn` files |
| `NavigationAgent2D.radius` | `24.0` (runtime RVO avoidance) | `scenes/objects/Enemy.tscn` |
| `CollisionShape2D` radius | `24.0` | `scenes/objects/Enemy.tscn` |
| `NavigationAgent2D.max_speed` | `320.0` | `scenes/objects/Enemy.tscn` |
| `NavigationAgent2D.avoidance_enabled` | `true` | `scenes/objects/Enemy.tscn` |
| Enemy model scale (`enemy_model_scale`) | `1.3` (visual only) | `enemy.gd` export var |

### Root Cause: Two Separate Systems Conflated

Godot 4's navigation has two separate radius concepts that are often confused:

1. **`NavigationPolygon.agent_radius`** — bake-time parameter. Erodes the walkable navmesh
   inward by this many pixels from all wall geometry. Determines which areas are physically
   navigable. Set at bake time, not per-agent at runtime.

2. **`NavigationAgent2D.radius`** — runtime RVO (Reciprocal Velocity Obstacles) parameter.
   Controls how the agent avoids *other moving agents*. Does NOT affect navmesh path clearance
   from walls.

**The core problem**: The `NavigationAgent2D.radius` was a fixed 24px in the scene file,
never updated at runtime to reflect the actual enemy body size. Specifically:

- `enemy_model_scale` (default `1.3`) only scales the visual model (`EnemyModel` Node2D),
  NOT the `CollisionShape2D` radius (which stays at 24px). So visually larger enemies look
  bigger but navigate at the same radius as small enemies.
- `NavigationAgent2D.max_speed` was hardcoded to `320.0` regardless of the actual
  `combat_move_speed` export variable (which varies per enemy type).
- Eight level scripts baked the navmesh without explicitly setting `agent_radius`, relying
  solely on the `.tscn`-embedded value. If this value was ever wrong, all enemies would
  clip through walls.

### What GodotRu (D0NM/GodotRu) Demonstrates

The reference repo's `Lessons/L001 Pathfinding2D` shows the minimal correct pattern:
```gdscript
# enemy.gd - basic NavigationAgent2D pathfinding
@onready var nav := $NavigationAgent2D as NavigationAgent2D

func _on_timer_timeout():
    nav.target_position = player.global_position

func _physics_process(delta):
    var direction = to_local(nav.get_next_path_position()).normalized()
    velocity.x = SPEED * delta * direction.x
    velocity.y = SPEED * delta * direction.y
    move_and_slide()
```

The key lesson: the enemy's `NavigationAgent2D` must be configured with the correct
`radius` and `max_speed` to match the enemy's actual physical size and speed.

## Research Findings: Godot 4 Best Practices

### 1. Wall Clearance (NavigationPolygon.agent_radius)

`NavigationPolygon.agent_radius` is a bake-time parameter that erodes the navmesh
polygon inward from all geometry boundaries. Setting this to the enemy body radius
ensures paths never get closer to walls than the enemy can physically fit.

- **Must be set before baking** — cannot be changed at runtime without rebaking
- **Never set to 0.0** — breaks baking precision correction
- For this project: `24.0` matches the `CollisionShape2D` radius in `Enemy.tscn`

### 2. Enemy Size Awareness (NavigationAgent2D.radius)

`NavigationAgent2D.radius` controls RVO avoidance between moving agents. Should match
the physical body radius so agents maintain correct separation.

- **Can be set at runtime** (no rebake needed)
- Should be updated in `_ready()` to match the actual `CollisionShape2D` radius
- For enemies with non-default collision sizes, must be set explicitly

### 3. Speed Synchronization (NavigationAgent2D.max_speed)

`NavigationAgent2D.max_speed` must match (or exceed) the actual movement speed passed
to `set_velocity()` for ORCA avoidance to compute correctly. If `max_speed` is too low,
ORCA will clamp the computed velocity and enemies move slower than intended.

### 4. Path Post-Processing

For tile-based/grid levels: `PATH_POST_PROCESSING_EDGECENTERED` centers paths on
polygon edges, reducing zigzag diagonal movement.

For organic/freeform geometry: `PATH_POST_PROCESSING_CORRIDORFUNNEL` gives the
geometrically shortest path.

The project's levels are mostly tile-based but with organic wall shapes — the default
`CORRIDORFUNNEL` is appropriate.

### 5. Multiple Enemy Sizes: Separate Navmeshes

If enemies need genuinely different wall clearances (e.g., a boss that's 2x normal size
can't fit through 48px corridors), the correct approach per Godot docs is:

> "Each type requires its own navigation map and navigation mesh baked with an appropriate
> agent radius."

For this project's current enemies (all 24px collision radius, scale is visual-only),
a single navmesh with `agent_radius = 24.0` is correct.

## Solution

### Fix 1: `_configure_nav_agent()` in `scripts/objects/enemy.gd`

Add a method called in `_ready()` that synchronizes the `NavigationAgent2D` parameters
with the actual enemy dimensions:

```gdscript
## Issue #1273: Sync NavigationAgent2D radius and max_speed with actual enemy size.
## NavigationAgent2D.radius controls RVO avoidance between agents and must match the
## CollisionShape2D radius (24px) so agents maintain correct separation.
## max_speed must be >= combat_move_speed so ORCA velocity clamping doesn't reduce speed.
func _configure_nav_agent() -> void:
    if _nav_agent == null:
        return
    # CollisionShape2D radius is 24px — sync so ORCA keeps correct agent-to-agent distance.
    _nav_agent.radius = 24.0
    # max_speed must cover the fastest movement speed (combat_move_speed).
    _nav_agent.max_speed = maxf(move_speed, combat_move_speed)
    _log_to_file("NavAgent configured: radius=%.0f max_speed=%.0f" % [_nav_agent.radius, _nav_agent.max_speed])
```

### Fix 2: Ensure `agent_radius` is set in all level navigation setups

Eight level scripts baked the navmesh without setting `agent_radius`:
- `arena_level.gd`, `building_level.gd`, `castle_level.gd`, `city_level.gd`
- `labyrinth_level.gd`, `labyrinth2_level.gd`, `revolver_level.gd`, `test_tier.gd`

Fix: set `nav_region.navigation_polygon.agent_radius = 24.0` before baking in all
`_setup_navigation()` methods for consistency and explicitness.

## Files Changed

- `scripts/objects/enemy.gd` — Add `_configure_nav_agent()` called in `_ready()`
- `scripts/levels/arena_level.gd` — Set `agent_radius` before baking
- `scripts/levels/building_level.gd` — Set `agent_radius` before baking
- `scripts/levels/castle_level.gd` — Set `agent_radius` before baking
- `scripts/levels/city_level.gd` — Set `agent_radius` before baking
- `scripts/levels/labyrinth_level.gd` — Set `agent_radius` before baking
- `scripts/levels/labyrinth2_level.gd` — Set `agent_radius` before baking
- `scripts/levels/revolver_level.gd` — Set `agent_radius` before baking
- `scripts/levels/test_tier.gd` — Set `agent_radius` before baking
- `tests/unit/test_enemy_pathfinding_nav_agent.gd` — New unit tests

## References

- Issue #1273: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1273
- GodotRu L001 Pathfinding2D: https://github.com/D0NM/GodotRu/tree/main/Lessons/L001%20Pathfinding2D
- Godot 4 docs: NavigationAgent2D.radius (RVO avoidance radius)
- Godot 4 docs: NavigationPolygon.agent_radius (bake-time navmesh erosion)
- Issue #1146: ORCA avoidance between enemies
- Issue #1216: Patrol point navmesh snap
- Issue #1224: Navmesh bake / overlay fix
