# Case Study: Issue #1146 — Враги проходят друг сквозь друга (Enemy Collision / Separation)

## Problem Statement

Enemies pass through each other (no collision between enemies). Additionally, once enemies
can no longer walk through each other, they should move sensibly — without blocking each
other or getting stuck.

---

## Root Cause Analysis

### 1. `avoidance_enabled = false` in `Enemy.tscn`

`scenes/objects/Enemy.tscn` line 84:
```
avoidance_enabled = false
```

Godot 4's `NavigationAgent2D` with `avoidance_enabled = true` implements the **ORCA
(Optimal Reciprocal Collision Avoidance)** algorithm. When disabled, the agent never
computes avoidance velocities for nearby agents, so enemies ignore each other at the
navigation level.

### 2. Collision mask does not include other enemies

`scenes/objects/Enemy.tscn` line 25:
```
collision_mask = 4
```

Bit 3 (value 4) = static obstacles only. Bit 2 (value 2) = enemy bodies (`collision_layer = 2`).
Because the mask excludes bit 2, `CharacterBody2D` physics bodies of enemies never
register collisions with each other, so `move_and_slide()` does not push them apart.

### 3. No separation steering force in `enemy.gd`

The `_move_to_target_nav()` helper (line 4748) computes a direction toward the path
waypoint and applies wall avoidance, but never adds any force to push enemies away from
each other. Even with avoidance enabled at the NavigationAgent level, the computed
avoidance velocity must be fed back via `NavigationAgent2D.set_velocity()` and listened
to via `velocity_computed` signal to actually steer the character.

---

## Solution Design

### Option A: NavigationAgent2D ORCA avoidance (preferred)

Enable `avoidance_enabled = true` on the NavigationAgent2D and wire the
`velocity_computed` callback so the computed safe velocity is applied to `velocity`
before each `move_and_slide()`.

**Pros:** Godot-native, proven algorithm, handles many agents efficiently, no extra
raycasts needed.
**Cons:** Requires a small amount of integration code; avoidance is "soft" (doesn't
guarantee zero overlap if agents are already overlapping).

### Option B: Collision mask change (physical separation)

Add bit 2 to `collision_mask` so enemies collide physically:
```
collision_mask = 6  # layer 2 (enemies) + layer 3 (obstacles)
```

**Pros:** Hard separation — enemies literally cannot overlap.
**Cons:** Can cause clumping/jamming in narrow corridors; enemies may block each other
from reaching a target.

### Option C: Separation steering force

In each physics tick, query nearby enemies via group, compute a repulsion vector, and
blend it into the velocity.

**Pros:** Smooth, configurable, no scene changes.
**Cons:** O(N²) queries if not using spatial acceleration; needs tuning.

### Chosen Solution: A + C combined

1. **Scene change** — `Enemy.tscn`: `avoidance_enabled = true` (ORCA for
   NavigationAgent2D agents).
2. **Code change** — `enemy.gd`: connect `velocity_computed` signal; in
   `_move_to_target_nav` and the main `_physics_process` call `_nav_agent.set_velocity(velocity)`
   so ORCA gets the intended velocity and returns a safe one.
3. **Separation force** — add `_apply_separation_force(velocity, delta)` as a lightweight
   group-query-based push that runs on every movement tick to handle cases where ORCA is
   slow to react (e.g., initial overlap from spawning).

RadioJammerEnemy already uses `avoidance_enabled = true` (line 81 of
`RadioJammerEnemy.tscn`), confirming this is the correct approach.

---

## References

- Godot docs: NavigationAgent2D avoidance — https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationagents.html
- ORCA algorithm: van den Berg et al. 2011 — reciprocal velocity obstacles
- Issue #341, #424: casing push force (same pattern of using nearby body queries)
- RadioJammerEnemy.tscn already enables avoidance for radio jammer enemies
