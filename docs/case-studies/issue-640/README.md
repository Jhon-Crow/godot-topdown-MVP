# Case Study: Issue #640 — Flashlight Passes Through Wall

## Problem Statement

When the player stands flush against a wall, the flashlight beam passes through and illuminates the other side. The issue was reported in Russian: "фонарь проходит сквозь стену если игрок стоит в упор к стене" (the flashlight passes through the wall if the player stands right up against the wall).

## Timeline

1. **Issue reported** — The flashlight beam visually shines through walls when the player's collision shape touches a wall.
2. **First fix attempt** — Moved the `PointLight2D` back 2px from the wall when a wall was detected between the player center and the flashlight barrel position.
3. **User feedback (comment 1)** — "сейчас фонарь не проходит сквозь стену, но светит внутрь стены если игрок в упор" — The light no longer passes through the wall, but it still illuminates the wall body itself. The nearest face of the wall should stop the light.
4. **Second fix attempt** — Changed approach to move `PointLight2D` all the way back to the player center (instead of 2px from wall), so the wall's `LightOccluder2D` is fully between the light source and the wall geometry.
5. **User feedback (comment 2)** — Two remaining issues: (1) "светит в стену" — light still shines into the wall, (2) "остаточное свечение - за стеной" — residual glow visible behind the wall.
6. **Third fix (current)** — Three-pronged approach addressing both the main beam and scatter light.

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

## Files in This Case Study

| File | Description |
|------|-------------|
| `README.md` | This case study document |
| `game_log_20260208_165935.txt` | Game log from user's testing session (Godot 4.3-stable, Windows) |
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
