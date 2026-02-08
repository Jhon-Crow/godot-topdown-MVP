# Case Study: Issue #640 — Flashlight Passes Through Wall

## Problem Statement

When the player stands flush against a wall, the flashlight beam passes through and illuminates the other side. The issue was reported in Russian: "фонарь проходит сквозь стену если игрок стоит в упор к стене" (the flashlight passes through the wall if the player stands right up against the wall).

## Timeline

1. **Issue reported** — The flashlight beam visually shines through walls when the player's collision shape touches a wall.
2. **First fix attempt** — Moved the `PointLight2D` back 2px from the wall when a wall was detected between the player center and the flashlight barrel position.
3. **User feedback (comment 1)** — "сейчас фонарь не проходит сквозь стену, но светит внутрь стены если игрок в упор" — The light no longer passes through the wall, but it still illuminates the wall body itself. The nearest face of the wall should stop the light.
4. **Second fix attempt** — Changed approach to move `PointLight2D` all the way back to the player center (instead of 2px from wall), so the wall's `LightOccluder2D` is fully between the light source and the wall geometry.
5. **User feedback (comment 2)** — Two remaining issues: (1) "светит в стену" — light still shines into the wall, (2) "остаточное свечение - за стеной" — residual glow visible behind the wall.
6. **Third fix** — Three-pronged approach addressing both the main beam and scatter light: dynamic `texture_scale` reduction, sharp shadow filter near walls, and scatter light suppression.
7. **User feedback (comment 3)** — "визуально всё правильно" (visually everything is correct), BUT two gameplay logic issues: (1) "враги ослепляются если игрок светит в них сквозь стену в упор" — enemies get blinded when the player shines at them through a wall at close range, (2) "враги видят фонарь если игрок светит сквозь стену в упор, хотя визуально свет не проходит" — enemies detect the flashlight through a wall at close range, even though visually the light doesn't pass through.
8. **Fourth fix** — When wall-clamped, suppress blindness checks and enemy flashlight detection logic.
9. **User feedback (comment 4)** — "враги всё ещё реагируют на невидимый за стеной луч фонаря" (enemies still react to the invisible flashlight beam behind the wall). Game logs `game_log_20260208_174653.txt` and `game_log_20260208_174718.txt` show Enemy3 and Enemy4 repeatedly detecting the flashlight beam through walls while the player stands flush.
10. **Fifth fix** — Root cause #6 identified: the wall detection only checked the center→barrel path, missing the case where the barrel is on the player's side but the beam direction immediately enters a wall. Added beam-direction wall detection within `BEAM_WALL_CLAMP_DISTANCE` (30px) of the barrel.
11. **User feedback (comment 5)** — "не исправлено" (not fixed). Game log `game_log_20260208_184413.txt` shows enemies (Enemy1, Enemy2, Enemy3, Enemy4) still detecting flashlight through walls, with no wall-clamping log entries.
12. **Sixth fix (current)** — Root cause #7 identified: `hit_from_inside=false` (Godot default) means raycasts starting inside a wall body don't detect it. When the barrel is at the wall boundary (floating-point edge case), both the center→barrel and beam-direction raycasts can miss the wall. Additionally, the detection component's `_check_beam_reaches_point()` casts from the barrel position which may be inside the wall. Added: (a) `hit_from_inside = true` on wall-clamping raycasts, (b) secondary player-center-based wall check in `FlashlightDetectionComponent` as catch-all defense.

## Root Cause Analysis

### Root Cause 1: PCF Shadow Filter Penumbra Bleed

The `PointLight2D` uses `shadow_filter = SHADOW_FILTER_PCF5` with `shadow_filter_smooth = 6.0`. PCF (Percentage Closer Filtering) deliberately blurs shadow edges to create soft shadows. When the light source is close to a `LightOccluder2D`, this softening creates a visible penumbra that bleeds light around the occluder edges — illuminating the wall body itself.

Even after moving the light to the player center (16px from wall), the cone texture with `texture_scale = 6.0` extends approximately 6144px forward. The large texture scale combined with PCF smoothing means the shadow boundary around the wall's occluder has significant bleed.

### Root Cause 2: Scatter Light Positioned on LightOccluder2D Boundary

The scatter light (Issue #644 feature) is a secondary `PointLight2D` placed at the beam's wall impact point. When positioned exactly ON a `LightOccluder2D` boundary, Godot's 2D shadow system cannot reliably determine inside vs. outside — it has no concept of polygon faces like 3D. This causes the scatter light to leak through to the other side of the wall.

This is a documented Godot engine limitation:
- [GitHub Issue #79783](https://github.com/godotengine/godot/issues/79783): 2D Light Occlusion appears broken when light overlaps occluder
- [Godot Forum](https://forum.godotengine.org/t/pointlight2d-clipping-through-light-occluder/90885): PointLight2D clipping through light occluder in Godot 4.3

### Root Cause 3: Scatter Light Not Suppressed When Beam is Wall-Clamped

When the main beam's `PointLight2D` was moved back to the player center due to wall proximity, the scatter light continued to operate independently — still casting a glow at the wall surface. This created the "residual glow behind the wall" that the user reported.

## Technical Details

### Node Hierarchy

```
Player (CharacterBody2D, collision_radius=16px)
└── PlayerModel (Node2D)
    └── FlashlightEffect (Node2D, position=Vector2(20, 0))
        ├── PointLight2D (cone texture, texture_scale=6.0, energy=8.0)
        └── ScatterLight (PointLight2D, radial gradient, texture_scale=3.0, energy=0.4)
```

### Key Measurements

| Property | Value | Significance |
|----------|-------|-------------|
| Player collision radius | 16px | Minimum distance from player center to wall |
| Flashlight barrel offset | 20px | FlashlightEffect position on PlayerModel |
| Cone texture size | 2048px | Base size of flashlight_cone_18deg.png |
| Cone texture_scale | 6.0 | Effective reach: 2048 * 6 / 2 = 6144px |
| Shadow filter | PCF5 | 5-sample Percentage Closer Filtering |
| Shadow filter smooth | 6.0 | High smoothness = significant penumbra bleed |
| Scatter light energy | 0.4 | 5% of main beam energy |
| Scatter light texture_scale | 3.0 | Significant radius for ambient glow |

### Why Previous Fixes Were Insufficient

**Fix 1 (2px offset from wall)**: The `PointLight2D` was still too close to the `LightOccluder2D`. At 2px distance, the PCF shadow filter's penumbra easily bleeds around the occluder edge.

**Fix 2 (move to player center)**: While the light source was now 16px from the wall (player collision radius), the cone texture's visual reach (6144px) meant the beam still extended far beyond the wall. The PCF5 filter with `shadow_filter_smooth = 6.0` created enough penumbra to illuminate the wall body. Additionally, the scatter light was completely unhandled.

### Root Cause 4: Blindness Check Uses Barrel Position Past Wall

The `_check_enemies_in_beam()` function in `flashlight_effect.gd` uses `global_position` (the FlashlightEffect node's position at the weapon barrel) as the beam origin for the line-of-sight raycast to enemies. When the player is flush against a wall, the barrel position can be at or past the wall surface. The LOS raycast from the barrel to an enemy on the other side doesn't detect the intervening wall because it originates from beyond the wall — so enemies get blinded through walls.

### Root Cause 5: Enemy Flashlight Detection Uses Barrel Position Past Wall

Similarly, the `FlashlightDetectionComponent.check_flashlight()` obtains `flashlight_origin` from `player.get_flashlight_origin()`, which returns `_flashlight_node.global_position` — the barrel position. The detection algorithm samples points along the beam from this origin and checks if walls block the beam. When the barrel is past the wall, sample points beyond the wall appear reachable because the origin is already on the other side.

The `is_position_lit()` method (used for passage avoidance by enemy AI) has the same issue.

### Root Cause 6: Wall Detection Only Checks Center-to-Barrel Path

The `_clamp_light_to_walls()` function casts a ray from `player_center` to `intended_pos` (barrel, 20px away). This only detects walls that intersect the short line segment between the player's center and the flashlight barrel. However, when the player stands flush against a wall at an angle, the wall may not be between the center and the barrel — the barrel can be on the player's side of the wall while the beam direction goes into/through the wall.

In the game logs, the player was at approximately `(727, 1040)` with the barrel at `(734.561, 1014.97)` and beam direction `(0.26158, -0.965182)` pointing mostly upward. The wall was in the beam's forward direction (within 30px of the barrel), but NOT between the center and the barrel. This meant `_is_wall_clamped` remained `false`, and all detection/blindness suppression was bypassed despite the beam being visually blocked by the wall's LightOccluder2D.

**Evidence from game logs:**
- `game_log_20260208_174653.txt` line 504+: Enemy3 and Enemy4 both detect flashlight with `estimated_pos=(734.561, 1014.97)`, triggering pursuit from IDLE state
- `game_log_20260208_174718.txt` line 559+: Enemy4 detects flashlight with `estimated_pos=(757.4615, 1022.563)`, repeated detection events
- No wall-clamping log entries appear in either log, confirming `_is_wall_clamped` was never set to `true`

### Root Cause 7: Raycasts Don't Detect Walls When Starting Inside Them (hit_from_inside)

Godot's `PhysicsRayQueryParameters2D.hit_from_inside` defaults to `false`. This means that if a ray STARTS inside a `CollisionShape2D`, it does not detect the collision. When the flashlight barrel is at the edge of or inside a wall body (common due to floating-point precision at wall boundaries), BOTH wall-detection raycasts can fail:

1. **Center→barrel ray**: If the barrel position is exactly at the wall boundary (within floating-point epsilon), the ray may or may not detect the wall depending on precision.
2. **Beam-direction ray**: If the barrel is inside the wall body, this ray starts inside the wall's `CollisionShape2D` and exits without detecting it — the wall is invisible to the raycast.

Additionally, the `FlashlightDetectionComponent._check_beam_reaches_point()` casts from the barrel (flashlight_origin) to beam sample points. When the barrel is inside a wall, this ray doesn't detect the wall either, so beam points on the other side of the wall appear reachable — enemies detect the "invisible" beam.

**Evidence from game log `game_log_20260208_184413.txt`:**
- BuildingLevel, `Room2_WallBottom` at `(712, 1012)`, size `400×24` → bounding box: x:512-912, y:1000-1024
- Player at `(817, 1040)` (16px below wall bottom at y=1024), barrel at approximately `(821, 1014)` (y=1014 is inside the wall body, between y=1000 and y=1024)
- Enemies (Enemy1, Enemy2, Enemy3, Enemy4) repeatedly detect flashlight with `estimated_pos=(821.2, 1014.4)` and `beam_dir=(0.15, -0.99)`
- No wall-clamping events in the log — `_is_wall_clamped` never becomes `true`

**Second scenario in same log:**
- Player at `(486, 1020)`, barrel at `(501, 999)` — pushed against `Room2_WallLeft` at x:500-524
- Barrel x=501 is inside the wall body (between x=500 and x=524)
- Enemy3 and Enemy4 detect flashlight with `estimated_pos=(501.2, 999.3)` and `beam_dir=(0.556, -0.831)`

**Reference:**
- [Godot Docs: PhysicsRayQueryParameters2D.hit_from_inside](https://docs.godotengine.org/en/4.3/classes/class_physicsrayqueryparameters2d.html)
- [Godot Forum: intersect_ray doesn't work when ray starts inside body](https://forum.godotengine.org/t/problem-with-intersect-ray-method/52649)

## Solution (Fix 3)

Three measures applied simultaneously:

### 1. Dynamic `texture_scale` Reduction

When wall is detected, `texture_scale` is reduced so the beam's visual reach only extends to the wall surface:

```gdscript
# scale = wall_distance * 2 / texture_size, clamped to [0.1, 6.0]
var clamped_scale = maxf(wall_dist * 2.0 / 2048.0, 0.1)
_point_light.texture_scale = minf(clamped_scale, LIGHT_TEXTURE_SCALE)
```

This prevents the cone from illuminating the wall body — the light simply doesn't reach that far.

### 2. Sharp Shadow Filter Near Walls

Switch from `SHADOW_FILTER_PCF5` to `SHADOW_FILTER_NONE` when wall-clamped:

```gdscript
_point_light.shadow_filter = PointLight2D.SHADOW_FILTER_NONE
```

This eliminates the soft penumbra that bleeds light around `LightOccluder2D` boundaries. When the player moves away from the wall, `SHADOW_FILTER_PCF5` is restored for normal soft shadow aesthetics.

### 3. Scatter Light Wall Handling

Two scatter light fixes:

- **Wall-clamped state**: When the main beam is wall-clamped (player flush against wall), the scatter light is hidden entirely. There's no meaningful surface for the beam to scatter from.
- **Normal wall hit**: When the beam hits a wall at normal range, the scatter light is pulled back 8px from the wall surface along the beam direction. This prevents the `PointLight2D` from sitting exactly on the `LightOccluder2D` boundary where Godot's shadow system can't reliably block it.

## Solution (Fix 4) — Gameplay Logic Through-Wall Prevention

Visual fix 3 solved the rendering issue, but the game logic (blindness, enemy AI detection) still used the barrel position as beam origin — which is past the wall when the player stands flush. Fix 4 addresses this by suppressing gameplay effects when `_is_wall_clamped` is true.

### 4. Suppress Blindness When Wall-Clamped

In `flashlight_effect.gd`, the `_physics_process()` now skips `_check_enemies_in_beam()` entirely when `_is_wall_clamped` is true:

```gdscript
if not _is_wall_clamped:
    _check_enemies_in_beam()
```

A new public method `is_wall_clamped()` exposes the wall-clamped state.

### 5. Suppress Enemy Flashlight Detection When Wall-Clamped

A new `is_flashlight_wall_clamped()` method on the Player class delegates to the FlashlightEffect's `is_wall_clamped()`. The `FlashlightDetectionComponent` checks this early in both `check_flashlight()` and `is_position_lit()`:

```gdscript
if player.has_method("is_flashlight_wall_clamped") and player.is_flashlight_wall_clamped():
    return false
```

This prevents enemies from detecting or tracking the beam through walls.

## Solution (Fix 5) — Beam-Direction Wall Detection

Fix 4 relied on `_is_wall_clamped` being `true`, but Root Cause #6 showed that `_is_wall_clamped` was never set when the wall wasn't between center and barrel. Fix 5 adds a secondary raycast in the beam direction.

### 6. Beam-Direction Wall Check

Added a second ray check in `_clamp_light_to_walls()`: when no wall is found between the player center and the barrel, cast a ray from the barrel along the beam direction for `BEAM_WALL_CLAMP_DISTANCE` (30px). If a wall is hit within this short distance, the beam is effectively blocked by the wall — set `_is_wall_clamped = true` and apply the same visual clamping (move light to player center, reduce texture_scale, switch to sharp shadows).

```gdscript
var beam_direction := Vector2.RIGHT.rotated(global_rotation)
var beam_check_end := intended_pos + beam_direction * BEAM_WALL_CLAMP_DISTANCE
var beam_query := PhysicsRayQueryParameters2D.create(intended_pos, beam_check_end)
beam_query.collision_mask = OBSTACLE_COLLISION_MASK
var beam_result := space_state.intersect_ray(beam_query)
```

This catches the case where the player faces a wall at an angle — the barrel stays on the player's side, but the beam direction immediately enters the wall body.

## Solution (Fix 6) — hit_from_inside + Player-Center Wall Check

Root cause #7 showed that raycasts from inside a wall don't detect it. Fix 6 applies two complementary measures:

### 7. Enable `hit_from_inside` on Wall-Clamping Raycasts

In `flashlight_effect.gd`, both wall-detection raycasts now set `hit_from_inside = true`:

```gdscript
query.hit_from_inside = true  # Center→barrel ray
beam_query.hit_from_inside = true  # Beam-direction ray
```

This ensures the wall is detected even if the ray origin is at the wall boundary or inside the wall body.

### 8. Player-Center Secondary Wall Check in Detection Component

In `flashlight_detection_component.gd`, after the existing barrel-origin wall check, a secondary check from the **player center** is added:

```gdscript
# Issue #640: Secondary wall check from the player center.
var player_center: Vector2 = player.global_position
if raycast != null and not _check_beam_reaches_point(player_center, point, raycast):
    continue
```

The player center (CharacterBody2D global_position) is always reliably outside walls — the physics engine guarantees no overlap with static bodies. A ray from the player center to a beam sample point will correctly detect any intervening wall, even when the barrel-origin ray doesn't.

This check is applied in both `check_flashlight()` (enemy AI detection) and `is_position_lit()` (passage avoidance).

### 9. Player-Center Secondary LOS Check for Blindness

In `flashlight_effect.gd`, the `_has_line_of_sight_to()` function now casts two rays:
1. From barrel to enemy (original check)
2. From player center to enemy (new secondary check)

If either ray hits a wall, the enemy is considered blocked and won't be blinded.

## Files in This Case Study

| File | Description |
|------|-------------|
| `README.md` | This case study document |
| `game_log_20260208_165935.txt` | Game log from user's testing session — light shining into wall (Godot 4.3-stable, Windows) |
| `game_log_20260208_172552.txt` | Game log from user's testing session — enemies blinded/detecting through wall |
| `game_log_20260208_174653.txt` | Game log from user's testing session — enemies detecting flashlight through wall (attempt 4) |
| `game_log_20260208_174718.txt` | Game log from user's testing session — enemies detecting flashlight through wall (attempt 4, continued) |
| `game_log_20260208_184413.txt` | Game log from user's testing session — enemies still detecting through wall (attempt 5) |
| `solution-draft-log-1.txt` | First AI solution draft execution log |
| `solution-draft-log-2.txt` | Second AI solution draft execution log (with player center fix) |

## References

- [Godot Docs: 2D lights and shadows](https://docs.godotengine.org/en/stable/tutorials/2d/2d_lights_and_shadows.html)
- [Godot Issue #79783: 2D Light Occlusion broken when light overlaps occluder](https://github.com/godotengine/godot/issues/79783)
- [Godot Issue #100664: Weird PointLight2D LightOccluder2D behavior](https://github.com/godotengine/godot/issues/100664)
- [Godot Forum: PointLight2D clipping through light occluder](https://forum.godotengine.org/t/pointlight2d-clipping-through-light-occluder/90885)
- [Catlike Coding: True Top-Down 2D - Light and Shadow](https://catlikecoding.com/godot/true-top-down-2d/4-light-and-shadow/)

## Lessons Learned

1. **Moving a light source away from a wall is necessary but not sufficient** — the light's visual reach (`texture_scale`) and shadow softness (`shadow_filter_smooth`) must also be adjusted.
2. **`PointLight2D` on a `LightOccluder2D` boundary is unreliable** — Godot's 2D shadow system has no inside/outside concept. Always offset lights from occluder boundaries.
3. **Multi-light systems need coordinated wall handling** — when the main beam is wall-clamped, secondary lights (scatter) must also be suppressed or adjusted.
4. **PCF shadow filtering trades edge quality for bleed risk** — use `SHADOW_FILTER_NONE` near walls for crisp edges, `SHADOW_FILTER_PCF5` in open areas for aesthetics.
5. **Visual fixes and gameplay logic fixes are separate concerns** — fixing the visual rendering (light not passing through walls) is not the same as fixing the game logic (blindness and AI detection). Both must be addressed when an effect has gameplay consequences.
6. **Barrel-offset origins are unreliable near walls** — when a game object is attached at an offset (barrel position), its global position can be past a wall the player is touching. All raycasts and checks that use this origin must account for the wall-clamped state.
7. **Wall detection must check multiple directions** — checking only the center→barrel path misses walls that are in the beam's forward direction but not between center and barrel. Always verify the beam direction for nearby walls as well, especially when the player approaches at an angle.
8. **`hit_from_inside` must be enabled for boundary-detection raycasts** — Godot's default `hit_from_inside = false` means raycasts starting inside a collision shape silently fail. When the ray origin can be at a wall boundary (barrel position), always set `hit_from_inside = true`.
9. **Use the most reliable origin for wall checks** — the CharacterBody2D center position is guaranteed to be outside walls by the physics engine. When wall detection is critical, use the player center as a secondary or primary ray origin, not just the barrel position which can be inside walls.
10. **Defense in depth for wall detection** — a single raycast is fragile at boundaries. Using multiple raycasts from different origins (barrel + player center) provides redundancy. If one misses due to floating-point or boundary conditions, the other catches it.
