# Issue #1357: Enemies Cannot Follow Planned Path (Stuck at Wall)

## Problem

Enemies get stuck at walls when trying to navigate corners during path-following movement (PURSUING, COMBAT states). The issue is visible when multiple enemies converge on the same path through a corridor with a turn — they pile up at the corner and cannot proceed.

**Owner's observation:** "возможно проблема в коллизиях врагов (до их добавления враги хорошо проходили поворот)" — the problem appeared after enemy-enemy collisions were added; before that, enemies navigated corners correctly.

## Root Cause

`Enemy.tscn` sets `collision_mask = 6` (binary `110`), which means the `CharacterBody2D` physically collides with both:
- **Layer 2 (value 2):** Other enemies
- **Layer 3 (value 4):** Walls/obstacles

When multiple enemies navigate a tight corner simultaneously:

1. **Physical enemy-enemy collision** via `move_and_slide()` pushes enemies laterally
2. This pushes them into the wall at the corner
3. The **corner escape logic** (Issue #1107, line 4738) reads `get_slide_collision()` normals — but these normals now include **enemy collision normals mixed with wall normals**, producing incorrect escape vectors
4. **Wall avoidance raycasts** (Issue #1146) detect the nearby wall and apply up to 70% weight against the nav direction
5. The combined effect: enemies oscillate between being pushed by other enemies and being steered away from walls, resulting in deadlock at the corner

This is a **redundant collision** problem. Enemy-enemy avoidance is already handled at a higher level by:
- **ORCA avoidance** via `NavigationAgent2D` (Issue #1146)
- **Separation steering** force (`_apply_separation_force`, 60px radius, 280 px/s²)
- **Tactical yielding** in narrow passages (`TacticalMovementComponent`, Issue #1249)

The `CharacterBody2D` physical collision between enemies adds a fourth, conflicting avoidance mechanism that fights the navigation path at corners.

## Previous Attempts

| PR | Approach | Result |
|----|----------|--------|
| #1358 | Navmesh polygon count guard, patrol snap fixes | Did not address corner stuck; AI was broken |
| #1396 | Nav direction guard (limit wall avoidance to <90°) | Still stuck at corners |

Both previous attempts focused on wall avoidance weights or patrol point initialization, missing the actual cause: enemy-enemy physical collision contaminating the corner escape logic.

## Fix

**Change `collision_mask` from `6` to `4`** in all four enemy scene files:
- `scenes/objects/Enemy.tscn`
- `scenes/objects/EnemySwatShield.tscn`
- `scenes/objects/EnemyDroneOperator.tscn`
- `scenes/objects/RadioJammerEnemy.tscn`

All four use the same `enemy.gd` script and had `collision_mask = 6`. This removes enemy-enemy physical collision (layer 2) while keeping wall collision (layer 3). Enemy-enemy avoidance continues to work through the three existing soft mechanisms (ORCA, separation, tactical yielding), which cooperate with the navigation path rather than fighting it.

### What changes:
- `collision_mask = 6` → `collision_mask = 4` (only collide with walls/obstacles) in all enemy CharacterBody2D scenes
- Zero lines added to `enemy.gd` (critical: file is at 4991/5000 line limit)

### What stays the same:
- `collision_layer = 2` (enemies are still on layer 2 for other systems to detect)
- ORCA avoidance, separation steering, tactical yielding — all unchanged
- Wall avoidance raycasts, corner escape logic — all unchanged
- `HitArea` collision — unchanged (layer 2, mask 16 for projectiles)

## References

- [Godot docs: CharacterBody2D collision](https://docs.godotengine.org/en/stable/classes/class_characterbody2d.html)
- [Godot docs: NavigationAgent2D avoidance](https://docs.godotengine.org/en/stable/classes/class_navigationagent2d.html)
- [RVO2/ORCA algorithm](https://gamma.cs.unc.edu/ORCA/) — the avoidance algorithm used by Godot's NavigationAgent2D
- Issue #1146: ORCA avoidance implementation
- Issue #1249: Tactical yielding for narrow passages
- Issue #1107: Corner escape logic
