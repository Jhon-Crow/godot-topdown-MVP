# Case Study: Issue #593 - Add Weak Light Sources in Corridors Without Enemies

## Issue Summary

**Original request (Russian):**
> добавь слабые источники света в коридорах без врагов на карте Здание
> (чтоб в ночном режиме можно было видеть стены)
> добавь что то вроде окно - чтоб тусклый синий прямоугольный свет падал в комноту и от рассеивания были видны очертания вещей.

**Translation:**
Add weak light sources in corridors without enemies on the Building map, so that in
night mode you can see the walls. Add something like a window, so that dim blue
rectangular light falls into the room and from the diffusion the outlines of things
are visible.

## Problem Analysis

The BuildingLevel currently has a night mode (realistic visibility) implemented via
`RealisticVisibilityComponent` (Issue #540). When enabled:
- A `CanvasModulate` node darkens the entire scene to near-black (`Color(0.02, 0.02, 0.04)`)
- A `PointLight2D` on the player provides a cone of vision with shadows
- `LightOccluder2D` nodes on walls cast shadows, preventing the player from seeing through walls

**Problem:** In corridors and rooms without enemies, the player cannot see anything at all.
The only light comes from the player's own visibility light. This makes navigation in
empty corridors very disorienting as you can't see wall outlines or room shapes ahead.

## Building Layout Analysis

### Rooms WITH enemies (no window lights needed):
| Room | Bounds | Enemies |
|------|--------|---------|
| OFFICE 1 | (80-500, 80-688) | Enemy1 (300,350), Enemy2 (400,550) |
| OFFICE 2 | (524-912, 712-1000) | Enemy3 (700,750), Enemy4 (800,900) |
| CONFERENCE ROOM | (1388-2448, 80-600) | Enemy5 (1700,350), Enemy6 (1950,450) |
| BREAK ROOM | (1388-2448, 800-1188) | Enemy7 (1600,900) |
| SERVER ROOM | (1700-2448, 1212-2048) | Enemy8 (1900,1450), Enemy9 (2100,1550) |
| MAIN HALL | (912-1488, 1400-2048) | Enemy10 (1200,1550) |

### Areas WITHOUT enemies (window lights should be placed here):
| Area | Bounds | Description |
|------|--------|-------------|
| Central Corridor | (512-1376, 700-1012) | Horizontal corridor connecting left and right wings |
| Left Lobby | (64-900, 1000-1400) | Area between Office 2 and Storage/Main Hall |
| Storage Room | (80-500, 1612-2048) | Empty room in bottom-left |
| Right Connector | (1376-2448, 612-800) | Gap between Conference Room and Break Room walls |

## Existing Lighting System

### RealisticVisibilityComponent (scripts/components/realistic_visibility_component.gd)
- Creates `CanvasModulate` with `FOG_COLOR = Color(0.02, 0.02, 0.04)`
- Creates `PointLight2D` with `LIGHT_ENERGY = 1.5`, `VISIBILITY_RADIUS = 600.0`
- Uses `GradientTexture2D` with radial fill for smooth falloff
- Shadow-casting enabled via `shadow_filter = PCF5`
- Player and weapons get `LIGHT_MODE_UNSHADED` material to stay visible

### FlashlightEffect (scripts/effects/flashlight_effect.gd)
- Directional beam with `LIGHT_ENERGY = 8.0`
- Uses cone texture (`flashlight_cone_18deg.png`)
- `texture_scale = 6.0` for long range
- Shadow-casting enabled

### LightOccluder2D nodes
Already present on all walls, interior walls, corner fills, and cover objects in
BuildingLevel.tscn. This means any new lights added will properly cast shadows
against walls.

## Solution Design

### Approach: Primary Window Lights + DirectionalLight2D Ambient

Each window creates ONE `PointLight2D` for the visible moonlight patch near
the window, and a SINGLE `DirectionalLight2D` provides scene-wide ambient
moonlight with NO visible edges:

1. **Per-window "MoonLight"** — the visible moonlight patch near the window:
   - Blue-tinted (`Color(0.4, 0.5, 0.9)`) to simulate cool moonlight
   - Very low energy (`0.08`), large spread (`texture_scale = 6.0`)
   - Early-fadeout gradient: reaches zero at 55% radius, 45% pure black buffer
   - **Shadows enabled** with PCF5 filter (`shadow_filter_smooth = 4.0`)
   - Shadow color `Color(0, 0, 0, 0.7)` for slightly soft shadow edges
   - Interior walls cast natural shadows, giving the light realistic shape

2. **Single "AmbientMoonlight"** — one DirectionalLight2D covering the entire scene:
   - Subtle blue (`Color(0.35, 0.45, 0.85)`)
   - Extremely faint energy (`0.04`)
   - Shadows disabled so it provides uniform glow through all walls
   - **No position, no radius, no texture** — DirectionalLight2D illuminates
     the entire scene uniformly by definition, unlike PointLight2D which
     always has a finite circular boundary

This architecture completely eliminates visible light edges because
DirectionalLight2D has no boundary — it covers the entire scene like moonlight.

### Design decisions and iteration history

**Iteration 1 (commit 5a5002b):** Initial implementation with `shadow_enabled = true`,
`energy = 0.5`. Owner feedback: "light cuts off abruptly, looks like it crashed
into a wall."

**Iteration 2 (commit d6b63af):** Disabled shadows on both layers, increased energy
to `0.6` primary + `0.25` ambient, increased texture_scale to `5.0` + `10.0`.
Owner feedback: "too bright, shadows from windows should exist, weapon flash
lights stopped working."

**Iteration 3 (commit 9ce2ca2):** Re-enabled shadows on primary (`0.3` energy),
very faint per-window ambient (`0.08` energy, `texture_scale = 6.0`).
Owner feedback: "square edges of light still clearly visible, weapon flashes
still not working."

**Root cause of v3 failures:**
- Per-window ambient lights had `texture_scale = 6.0` (coverage ~3072px diameter),
  creating visible circular boundaries on a 2400x2000 map
- 11 windows × 2 lights = 22 PointLight2D nodes, total energy = `11 × (0.3 + 0.08) = 4.18`
  — nearly equal to muzzle flash energy (`4.5`), drowning out weapon effects

**Iteration 4 (commit 089b1ed):** Replaced per-window ambient with single map-wide
PointLight2D ambient. Primary energy halved from `0.3` to `0.15`. Single map-wide
ambient at `0.04` energy, `texture_scale = 7.0`. Total energy `1.69` vs muzzle
flash `4.5`. Owner feedback: "hard boundary still visible" — despite the large
`texture_scale`, the PointLight2D still had a finite circular boundary.

**Root cause of v4 failure:**
- **PointLight2D always has a finite circular boundary** where its gradient texture
  ends. No matter how large the `texture_scale`, there is always a visible transition
  from lit to unlit at the edge of the radial gradient. Against the near-black
  `CanvasModulate` (`Color(0.02, 0.02, 0.04)`), even the faintest edge is visible.
- The owner provided a reference image showing soft moonlight with no hard edges.

**Iteration 5 (commit bef1e78):** Replaced map-wide PointLight2D with `DirectionalLight2D`.
- `DirectionalLight2D` illuminates the **entire scene uniformly** — it has no position,
  no radius, and no boundary where light stops. It's the correct Godot node for
  simulating moonlight (parallel rays from a distant source).
- Same color `Color(0.35, 0.45, 0.85)` and energy `0.04` — only the node type changed.
- Simpler code: no gradient texture needed, no position calculation, no texture_scale.
- Total energy: `11 × 0.15 + 0.04 = 1.69` (37% of muzzle flash `4.5`).
- Owner feedback: "rectangular light edges still clearly visible" — the ambient
  DirectionalLight2D has no edges, but the **11 primary PointLight2D** window lights
  still show their quad boundaries.

**Root cause of v5 failure:**
- The primary window `PointLight2D` lights use `GradientTexture2D` with `FILL_RADIAL`.
  The gradient reaches zero at the inscribed circle edge (offset 1.0 in the gradient),
  but the `PointLight2D` is rendered as a **square quad** in the GPU. The corners of
  the square texture beyond the inscribed circle can produce subpixel artifacts.
- More importantly, the gradient at `texture_scale = 3.0` (covering ~1536px diameter)
  has its zero-crossing right at the texture boundary. Against the near-black
  `CanvasModulate` (`Color(0.02, 0.02, 0.04)`), even a 1/255 difference at the
  boundary is visible as a hard edge.
- The owner's reference image and linked Reddit post about [faking GI in 2D scenes](https://www.reddit.com/r/godot/comments/173w2u1/faking_global_illumination_in_a_2d_scene_using/)
  demonstrate that moonlight should have a very gradual, imperceptible transition.

**Iteration 6 (current):** Early-fadeout gradient with large texture_scale.
- **Key insight:** The gradient must reach absolute zero well before the texture edge,
  creating a "buffer zone" of pure black pixels where no light contribution exists.
  This eliminates visible edges because the transition from light to dark happens
  entirely within the interior of the texture, far from the quad boundary.
- Primary energy reduced from `0.15` to `0.08` — the larger texture_scale (6.0 vs 3.0)
  compensates for coverage while keeping total energy low.
- Gradient now fades to zero at 55% of the radius, leaving 45% as pure black buffer.
- `shadow_filter_smooth` increased from 3.0 to 4.0 for even softer shadow edges.
- Total energy: `11 × 0.08 + 0.04 = 0.92` (20% of muzzle flash `4.5`) — weapon
  flashes will be clearly dominant at 4.9× the total window light energy.

### Window Light Placement

Lights are placed along exterior walls (WallTop, WallBottom, WallLeft, WallRight)
in sections that correspond to corridors and rooms without enemies:

1. **Left wall (WallLeft, x=64)** - Storage room area
2. **Top wall (WallTop, y=64)** - Near corridor entrance
3. **Bottom wall (WallBottom, y=2064)** - Storage and lobby areas
4. **Interior corridor** - Ambient lights along the central corridor

### Visual Indicators

Small blue `ColorRect` nodes (window frames) are added at window positions
to give a visual representation of windows on the walls, even when night mode
is disabled.

## Game Logs

- `game_log_20260208_150328.txt` — Owner testing v5 (DirectionalLight2D ambient).
  Shows realistic visibility toggled on at 15:03:34 and off at 15:03:47 (13 seconds).
  Confirms rectangular edges still visible from primary PointLight2D window lights.

## References

- [Godot 2D Lighting Docs](https://docs.godotengine.org/en/stable/tutorials/2d/2d_lights_and_shadows.html)
- [PointLight2D Class](https://docs.godotengine.org/en/stable/classes/class_pointlight2d.html)
- [DirectionalLight2D Class](https://docs.godotengine.org/en/stable/classes/class_directionallight2d.html)
- [GradientTexture2D Class](https://docs.godotengine.org/en/stable/classes/class_gradienttexture2d.html)
- [CanvasModulate Class](https://docs.godotengine.org/en/stable/classes/class_canvasmodulate.html)
- [Reddit: Faking Global Illumination in 2D using light masks](https://www.reddit.com/r/godot/comments/173w2u1/faking_global_illumination_in_a_2d_scene_using/)
- [Godot Proposals #3444: Mathematically defined PointLight2D textures](https://github.com/godotengine/godot-proposals/issues/3444)
- Issue #540: Realistic visibility implementation
- Issue #570: Night mode weapon fix
