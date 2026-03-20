# Case Study: Issue #1206 — Add Warm Light Sources to Building Map Rooms

## Summary

**Issue:** Add warm light sources to the centers of large rooms in the BuildingLevel scene to improve visual aesthetics.

**Request (original Russian):** "добавь в середину больших комнат источники тёплого света (чтоб было красивее)" — "add warm light sources to the center of large rooms (to make it more beautiful)"

---

## Room Layout Analysis

The `BuildingLevel.tscn` is a 2400×2000 pixel building with the following rooms (derived from `RoomLabels` node bounds):

| Room Name        | Bounds (x1,y1)–(x2,y2)     | Center         | Size      |
|------------------|-----------------------------|----------------|-----------|
| OFFICE 1         | (80, 80) – (500, 688)       | (290, 384)     | 420×608   |
| OFFICE 2         | (524, 712) – (912, 1000)    | (718, 856)     | 388×288   |
| CONFERENCE ROOM  | (1388, 80) – (2448, 600)    | (1918, 340)    | 1060×520  |
| BREAK ROOM       | (1388, 800) – (2448, 1188)  | (1918, 994)    | 1060×388  |
| SERVER ROOM      | (1700, 1212) – (2448, 2048) | (2074, 1630)   | 748×836   |
| STORAGE          | (80, 1612) – (500, 2048)    | (290, 1830)    | 420×436   |
| MAIN HALL        | (912, 1400) – (1488, 2048)  | (1200, 1724)   | 576×648   |

**Large rooms** (area > 200,000 px²): Conference Room, Break Room, Server Room, Main Hall.
**Smaller rooms**: Office 1, Office 2, Storage.

---

## Existing Lighting Architecture

The level already uses Godot 4 2D lighting:
- `LightOccluder2D` on all walls and covers for realistic shadow casting
- `PointLight2D` via `_setup_window_lights()` — cool blue moonlight from exterior windows
- `DirectionalLight2D` via `_create_ambient_moonlight()` — scene-wide ambient moonlight glow
- `CanvasModulate` (added by `RealisticVisibilityComponent`) — darkens the scene for visibility

## Existing Pattern Reference

`_create_window_light()` / `_create_window_light_texture()` in `building_level.gd` demonstrate the established pattern:
- Create `GradientTexture2D` with radial fill, fading to zero at ~55% radius
- Set large `texture_scale` (6.0) so gradient dissipates before reaching the quad edge
- Enable `shadow_enabled = true` with `SHADOW_FILTER_PCF5` for soft wall shadows
- Low `energy` (0.12) to avoid washing out the dark atmosphere

---

## Solution Chosen

Added two new methods to `building_level.gd`:

### `_setup_room_warm_lights()`
- Called from `_ready()` after `_setup_window_lights()`
- Creates a `Node2D` container "RoomLights" under "Environment"
- Places one warm `PointLight2D` at the geometric center of each room
- Large rooms: energy=0.85–0.9, texture_scale=4.5–5.0
- Small rooms: energy=0.7, texture_scale=3.5

### `_create_room_warm_light(parent, pos, energy, scale, room_name)`
- Adds a small visual fixture `ColorRect` (pale amber, semi-transparent) at the lamp position
- Adds a `PointLight2D` with warm amber-orange color `Color(1.0, 0.75, 0.3, 1.0)`
- `shadow_enabled = true` with PCF5 filtering — furniture and walls cast natural shadows
- Uses `_create_warm_light_texture()` for the radial gradient

### `_create_warm_light_texture()`
- Gradient fades to absolute zero at 60% radius (40% black buffer zone)
- Same "early fadeout" design as the moonlight texture to prevent visible edges
- Produces soft, natural-looking overhead illumination

---

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Warm amber color `(1.0, 0.75, 0.3)` | Mimics incandescent/halogen ceiling lights — classic office/building feel |
| Shadows enabled | Desks, cabinets, and walls cast realistic shadows, depth and atmosphere |
| 60% fade-out (vs 55% for moonlight) | Warm lights are larger; extra buffer prevents edge artifacts at high energy |
| Separate container node "RoomLights" | Clean scene hierarchy, easy to find/toggle in editor |
| Small amber ColorRect fixture | Provides visual anchor for where the light "comes from" |
| Dynamic creation in script (not baked into .tscn) | Consistent with existing window lights pattern; keeps .tscn diff small |

---

## Alternative Approaches Considered

1. **Bake lights directly into BuildingLevel.tscn** — Would clutter the scene file with many new sub-resources; harder to maintain. Rejected in favor of the existing dynamic pattern.
2. **Sprite-based lamp fixtures** — Would require art assets that don't exist; overkill for procedural ColorRect-based level. Rejected.
3. **Tiled/per-cell lighting** — The level is not tile-based, so a simpler per-room approach is appropriate.

---

## Files Changed

- `scripts/levels/building_level.gd` — Added `_setup_room_warm_lights()`, `_create_room_warm_light()`, `_create_warm_light_texture()` and a call in `_ready()`.
