# Case Study: Issue #1107 — Machete Enemy Pathfinding (Obstacle Avoidance)

## Issue Summary

**Title:** fix враг с мачете (fix machete enemy)

**Description (translated):** The machete enemy does not try to go around obstacles, but walks straight into the wall (directly toward the player). Teach it to effectively avoid obstacles.

**Original screenshot (`screenshot.png`):** Enemy pressed against a vertical wall corridor, trying to reach the player by moving straight through it.

**Follow-up screenshot (`screenshot_20260317_wall_corner.png`):** After initial fix, enemy still gets stuck at L-shaped wall corners. The player is near the top-left of the inner corner, and the machete enemy is pressed against the corner wall.

**Game log (`game_log_20260317_211211.txt`):** Captured 2026-03-17 during DocksLevel gameplay.

---

## Timeline of Events (from game log)

1. `LoadingDock_Machete` spawns at `(3845.992, 1800)` in DocksLevel
2. Enemy enters COMBAT state, navigates toward player through DocksLevel container maze
3. At ~21:15:03 (line 9009): `[#1107] Machete COMBAT stuck (1.5s), rerouting` — stuck detection from first fix triggers
4. Enemy transitions COMBAT → PURSUING → tries FLANKING to `(248.3807, 1832.972)` near left wall
5. At ~21:15:08 (line 9194): `GLOBAL STUCK: pos=(694.0665, 2079.933)` — enemy is stuck in PURSUING at x=694
6. Transitions to SEARCHING, then back to COMBAT on re-sighting
7. Pattern repeats: COMBAT→stuck→PURSUING→FLANKING stuck→PURSUING→GLOBAL STUCK
8. At ~21:15:58 (line 11780): Another `[#1107]` trigger at a different position
9. At ~21:16:09 (line 12073): `FLANKING stuck at (178.0656, 1768.372)` — left boundary wall

**Pattern:** The enemy gets trapped in a **cycle** of COMBAT→PURSUING→FLANKING→stuck→repeat. The stuck positions consistently have low x values (178, 293, 694) indicating the enemy is being pushed against the left wall of DocksLevel.

---

## Root Cause Analysis

### Root Cause 1: Physics Corner-Sticking (PRIMARY)

When `_move_to_target_nav()` sets `velocity` and then `move_and_slide()` runs:

1. The nav agent computes a path around the L-corner
2. `get_next_path_position()` returns the next waypoint *around* the corner
3. Enemy moves toward that waypoint — but at the corner itself, the physics body collides with the wall
4. `move_and_slide()` slides the enemy along wall1 into wall2
5. At a **concave corner** (inner L-corner), wall1's slide vector points into wall2, and wall2's normal cancels it — the enemy gets physically pinned
6. Next frame: nav agent recomputes path, still points around the corner, same outcome
7. No mechanism existed to apply **escape force** away from the wall surface

This is a well-known issue with `CharacterBody2D.move_and_slide()` at concave corners: the character gets trapped because slide vectors from two walls cancel each other. The solution is to use `get_slide_collision()` normals to add an escape direction to the velocity.

### Root Cause 2: Slow COMBAT Stuck Detection

The `MACHETE_COMBAT_STUCK_MAX_TIME` was 1.5 seconds. During that time, the enemy oscillates back and forth at the corner, which looks bad visually. Reducing to 0.8s makes recovery faster.

### Root Cause 3: COMBAT→PURSUING Cycle

After recovering from COMBAT stuck → PURSUING, the enemy immediately transitions back to COMBAT because it can still see the player through the corner gap. This creates an infinite cycle:
- COMBAT (stuck) → stuck timer triggers → PURSUING → can_see_player → COMBAT (stuck again)

The corner escape fix breaks this cycle by allowing the enemy to actually navigate around the corner rather than just detecting the stuck state.

### Root Cause 4: Flank Target Near Wall Boundary

When the machete enemy transitions to PURSUING, it calls `_find_pursuit_cover_toward_player()`. If no good cover exists, it tries flanking. The `_calculate_flank_position()` computes `player_pos + flank_direction * flank_distance`. Near the left boundary wall (x≈178), computed flank targets land outside or on the nav mesh edge. The enemy navigates to the wall edge, gets stuck there too.

The corner escape fix also helps here, as does the reduced stuck timer (0.8s instead of 1.5s).

---

## Navigation Setup Analysis

| Level | agent_radius | Bake Method |
|-------|-------------|-------------|
| BeachLevel | 24.0 | `bake_navigation_polygon()` |
| DocksLevel | 24.0 | `bake_navigation_polygon()` |
| DecadenceLevel | 24.0 | `bake_navigation_polygon()` |
| FactoryLevel | 24.0 | `bake_navigation_polygon()` |
| BuildingLevel | ❌ none | `bake_from_source_geometry_data()` |
| CastleLevel | ❌ none | `bake_from_source_geometry_data()` |
| CityLevel | ❌ none | `bake_from_source_geometry_data()` |
| LabyrinthLevel | ❌ none | `bake_from_source_geometry_data()` |

Levels using `bake_from_source_geometry_data()` without `agent_radius` produce nav meshes where paths go right up to the wall geometry boundary (zero margin). This makes corner sticking worse because the path endpoint is at the wall surface itself.

DocksLevel (where the issue was observed) correctly sets `agent_radius = 24.0`, but even with margin, the **physics body** of the enemy (which has its own collision shape) can still get pinned at concave corners because the navmesh margin applies to path computation, not to the actual physics collision resolution.

---

## Godot 4 Research Findings

### CharacterBody2D.move_and_slide() at Concave Corners

In Godot 4, `CharacterBody2D.move_and_slide()` handles wall sliding by computing the velocity component parallel to the wall surface. At a concave corner:
- Wall1 normal: `N1`
- Wall2 normal: `N2`
- Projected velocity along Wall1: `v - (v·N1)*N1`
- If this projected velocity points into Wall2: `(v - (v·N1)*N1) · N2 < 0`
- Then the remaining velocity component is zero → character is stuck

**Fix**: Use `get_slide_collision(i).get_normal()` to read what walls were hit, then add those normals as a bias to the next frame's movement direction. This "escape" direction pushes the character away from the corner.

### Godot GitHub Issues
- **#60546**: 2D navigation agent radius not applied in path baking (fixed in 4.1)
- **#57967**: NavigationObstacle2D issues with static bodies
- **#69988**: RVO avoidance rework (Godot 4.1)
- **#88540**: CharacterBody2D stuck in corners — confirmed behavior, escape via collision normals recommended

### Best Practices for Corner Navigation
1. **Use `get_slide_collision()` normals**: After `move_and_slide()`, check collision normals and add them to velocity direction next frame
2. **Shorter stuck timer**: Detect stuck state faster (0.8s vs 1.5s) for better responsiveness
3. **Agent radius**: Set `agent_radius = 24.0` in ALL levels' nav baking (not just 4 of 8)
4. **Navigation Server nearest point**: When target is outside nav mesh, use `NavigationServer2D.map_get_closest_point()` to clamp target

---

## Implemented Fix (PR #1108, Session 2)

### Change 1: Corner Escape in `_move_to_target_nav` (line 4768-4770)

```gdscript
var _esc: Vector2 = Vector2.ZERO  # Issue #1107: Corner escape via slide collision normals
for _si: int in range(get_slide_collision_count()): _esc += get_slide_collision(_si).get_normal()
if _esc.length_squared() > 0.01: direction = (direction + _esc.normalized() * 0.6).normalized()
```

**Mechanism**: Reads wall collision normals from the **previous frame's** `move_and_slide()`. If any walls were hit, the combined normals point away from the walls. This direction is blended 60% into the movement direction, steering the enemy away from the wall corner. Applied to ALL enemies (not just machete) since the underlying physics issue affects everyone.

**Why 0.6 blend weight**: Strong enough to escape corners but not so strong that it overrides the nav path entirely and causes enemies to ignore obstacles.

### Change 2: Faster COMBAT Stuck Timer (line 261)

```gdscript
const MACHETE_COMBAT_STUCK_MAX_TIME: float = 0.8  # was 1.5
```

Detects stuck state in 0.8 seconds instead of 1.5 seconds. Since the corner escape fix should prevent most sticking, this timer is now a safety net that fires less often but faster when needed.

### Previous Fix (Session 1, still active)

- Stuck detection in COMBAT state for machete enemies (COMBAT→PURSUING after 0.8s stuck)
- Improved `_get_nav_direction_to` fallback for unreachable targets

---

## References

- Godot 4 Navigation Docs: https://docs.godotengine.org/en/stable/tutorials/navigation/
- Godot 4 CharacterBody2D.move_and_slide(): https://docs.godotengine.org/en/stable/classes/class_characterbody2d.html
- GitHub #60546: NavigationAgent2D radius not applied in 2D (fixed 4.1)
- GitHub #57967: NavigationObstacle2D radius issue
- GitHub #69988: Navigation Avoidance rework (Godot 4.1)
- GitHub #88540: CharacterBody2D corner sticking
- Project issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1107
- Game log: `docs/case-studies/issue-1107/game_log_20260317_211211.txt`
- Follow-up screenshot: `docs/case-studies/issue-1107/screenshot_20260317_wall_corner.png`
