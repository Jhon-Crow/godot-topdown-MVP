# Case Study: Issue #1146 — Враги проходят друг сквозь друга (Enemy Collision / Separation)

## Problem Statement

Enemies pass through each other (no collision between enemies). Additionally, once enemies
can no longer walk through each other, they should move sensibly — without blocking each
other or getting stuck.

**Confirmed by owner on 2026-03-18:** After initial fix attempt (ORCA avoidance enabled),
enemies still walk through each other. Game log `game_log_20260318_103045.txt` was provided
for deep analysis.

---

## Timeline of Events

| Time | Event |
|------|-------|
| 2026-03-18 10:30:45 | Game session started, LabyrinthLevel loaded |
| 2026-03-18 10:30:45 | 5 enemies spawned (Enemy1–Enemy5) at positions (400,300), (900,950), (1200,1000), (1650,650), (1500,300) |
| 2026-03-18 10:30:50 | Enemy3, Enemy2 detect player, transition IDLE → COMBAT / PURSUING |
| 2026-03-18 10:30:51–10:32:19 | Active combat, 10 enemies on field after F8 spawns |
| 2026-03-18 10:32:19 | Session ended |

**Key observation from log:** Zero collision-related messages are logged during the entire
session. No `move_and_slide()` collision reactions between enemies are recorded. This
confirms that at the physics layer, enemies are completely transparent to each other.

---

## Root Cause Analysis

### Root Cause 1 (PRIMARY — NOT FIXED in first attempt): Wrong `collision_mask` on Enemy body

`scenes/objects/Enemy.tscn` line 25:
```
collision_layer = 2   # enemy body is on layer 2 ("enemies")
collision_mask = 4    # only scans layer 3 ("obstacles")
```

**Physics layer map** (from `project.godot`):
| Bit value | Layer name |
|-----------|-----------|
| 1 (0b0001) | player |
| 2 (0b0010) | enemies |
| 4 (0b0100) | obstacles |
| 8 (0b1000) | pickups |
| 16 (0b10000) | projectiles |

With `collision_mask = 4`, each enemy's `CharacterBody2D` scans **only obstacles** (walls,
etc.) during `move_and_slide()`. Since enemies are on layer 2 but no enemy has layer 2 in
their mask, **`move_and_slide()` never resolves collisions between enemies** — they pass
through each other as if they were ghosts.

**Fix:** Change `collision_mask = 4` → `collision_mask = 6` (`4 | 2` = obstacles + enemies).
This makes `move_and_slide()` resolve enemy-vs-enemy collisions with hard separation.

### Root Cause 2: `avoidance_enabled = false` in NavigationAgent2D (partially addressed)

`scenes/objects/Enemy.tscn` previously had:
```
avoidance_enabled = false
```

Godot 4's `NavigationAgent2D` with `avoidance_enabled = true` implements the **ORCA
(Optimal Reciprocal Collision Avoidance)** algorithm. When disabled, the agent never
computes avoidance velocities for nearby agents, so enemies ignore each other at the
navigation level.

This was fixed in the first PR attempt (`avoidance_enabled = true`), but without fixing
root cause 1 (the collision mask), enemies still passed through each other because
`move_and_slide()` did not enforce physical separation.

### Root Cause 3: No separation steering force in `enemy.gd` (addressed)

The `_move_to_target_nav()` helper computed a direction toward the path waypoint and applied
wall avoidance, but added no force to push enemies away from each other. Added
`_apply_separation_force()` as a backup for spawn-overlap scenarios.

---

## Why ORCA Alone Was Insufficient

ORCA (Optimal Reciprocal Collision Avoidance) is a **steering algorithm** — it adjusts
velocity directions to prevent future overlaps. It does **not** resolve existing overlaps.
If two enemies spawn at the same point or walk into each other, ORCA tries to steer them
apart, but `move_and_slide()` must actually enforce the collision for the bodies to not
overlap. Without layer 2 in the collision mask, `move_and_slide()` simply does not push
enemies apart — the physics engine never "sees" enemy-vs-enemy contacts.

This is the **critical missing fix** that the first iteration missed.

---

## Solution

### Change 1: Collision mask fix (PRIMARY FIX)

`scenes/objects/Enemy.tscn`:
```
collision_mask = 6  # layer 2 (enemies) + layer 3 (obstacles)
```

This enables hard physical separation — enemies can no longer overlap at the Godot physics
engine level. `move_and_slide()` will push enemies apart on every physics tick.

### Change 2: NavigationAgent2D avoidance (COMPLEMENTARY)

`scenes/objects/Enemy.tscn`:
```
avoidance_enabled = true
max_neighbors = 10
time_horizon_agents = 1.5
```

This enables ORCA steering to proactively steer enemies away from each other's predicted
paths, reducing clumping and jamming before physical contact occurs.

### Change 3: Velocity integration for ORCA (COMPLEMENTARY)

`scripts/objects/enemy.gd`:
- Connect `velocity_computed` signal in `_ready()` when avoidance is enabled
- Feed intended velocity to `_nav_agent.set_velocity()` before moving
- Apply ORCA-safe velocity in `_on_avoidance_velocity_computed()` callback
- `_apply_separation_force()` — group-query repulsion for spawn overlap edge cases

---

## Evidence from Game Log (`game_log_20260318_103045.txt`)

1. **Zero collision events between enemies** during the entire 3-minute session — confirms
   the physics engine never detected enemy-vs-enemy contacts.
2. **10 enemies active simultaneously** at peak — significant crowding with zero reported
   separation reactions.
3. **FPS drops** at 10:30:46 (15 fps), 10:32:03 (29 fps), 10:32:06 (24 fps) — may be
   related to enemy pathfinding without spatial separation increasing navigation complexity.
4. **No NavigationAgent avoidance callbacks logged** — despite `avoidance_enabled = true`
   being set in the first fix attempt, the lack of collision response from `move_and_slide()`
   means enemies never experience the physical feedback that would make ORCA effective.

---

## References

- Godot docs: NavigationAgent2D avoidance — https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationagents.html
- Godot docs: CharacterBody2D.collision_mask — https://docs.godotengine.org/en/stable/classes/class_physicsbody2d.html#class-physicsbody2d-property-collision-mask
- ORCA algorithm: van den Berg et al. 2011 — reciprocal velocity obstacles
- Issue #341, #424: casing push force (same pattern of using nearby body queries)
- RadioJammerEnemy.tscn already enables avoidance for radio jammer enemies (collision_mask confirmed as 6)
- Game log analysis: `docs/case-studies/issue-1146/game_log_20260318_103045.txt`
