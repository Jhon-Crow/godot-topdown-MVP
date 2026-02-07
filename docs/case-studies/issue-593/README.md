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

### Approach: Window Light Sources as PointLight2D Nodes

Add `PointLight2D` nodes along exterior walls in corridors without enemies,
simulating moonlight coming through windows. These lights:

1. **Blue-tinted** (`Color(0.4, 0.5, 0.9)`) to simulate cool moonlight
2. **Low energy** (`0.4-0.6`) to be dim but visible, not overpowering the darkness
3. **Shadow-casting enabled** so light doesn't pass through walls/objects
4. **Placed on exterior walls** to simulate windows facing outside
5. **Only in areas without enemies** to maintain tension in enemy areas

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

## References

- [Godot 2D Lighting Docs](https://docs.godotengine.org/en/stable/tutorials/2d/2d_lights_and_shadows.html)
- [PointLight2D Class](https://docs.godotengine.org/en/stable/classes/class_pointlight2d.html)
- [CanvasModulate Class](https://docs.godotengine.org/en/stable/classes/class_canvasmodulate.html)
- Issue #540: Realistic visibility implementation
- Issue #570: Night mode weapon fix
