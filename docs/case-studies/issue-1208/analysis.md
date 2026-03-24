# Case Study: Issue #1208 — Add Cold Light Sources to Laboratory Map

## Summary

**Issue:** Add the same type of light sources as in PR #1207 (BuildingLevel warm lights) to the Laboratory (LabyrinthLevel) map, but with a cold blue tint and dimmer intensity.

**Request (original Russian):** "добавить такие же источники света как в PR #1207 на карту Лаборатория, но цвет должен быть холодным с синим оттенком и более тусклым"

**Translation:** "Add the same light sources as in PR #1207 to the Laboratory map, but the color should be cold with a blue tint and more dim"

---

## Map Identification

The **Laboratory** map refers to **LabyrinthLevel** (`scenes/levels/LabyrinthLevel.tscn`, `scripts/levels/labyrinth_level.gd`). Although the in-game menu shows it as "Лабиринт" (Labyrinth), the code consistently calls it the "Laboratory" level (see `LABYRINTH_RANK_THRESHOLDS` comment: "Laboratory-specific rank thresholds", and PR #808's title: "update Laboratory tutorial").

Map dimensions: **1920×1080 pixels** — the smallest level in the game.

---

## Reference Implementation (PR #1207)

PR #1207 added warm amber-orange ceiling lights to **BuildingLevel** with these characteristics:

| Property | BuildingLevel (warm) |
|----------|---------------------|
| Color | `Color(1.0, 0.75, 0.3)` — amber-orange |
| Energy (large rooms) | 0.85–0.9 |
| Energy (small rooms) | 0.7 |
| Texture scale | 3.5–5.0× |
| Fixture | `Sprite2D` round disc, amber tint |
| Shadow filter | PCF5, smooth=3.0 |

Key design lessons from PR #1207:
- Used `Sprite2D` (not `ColorRect`/`Control`) for fixture to avoid blocking mouse events and breaking pause menu
- Used per-pixel `ImageTexture` with power-law falloff (`pow(1-t, 2.2)`) for smooth circular glow with no visible rectangular edge
- `shadow_enabled = true` so walls and furniture cast shadows

---

## Room Layout Analysis

From `scenes/levels/LabyrinthLevel.tscn` interior wall positions:

| Room | Approximate Bounds | Center Used |
|------|--------------------|-------------|
| Generator Room | x: 64–750, y: 64–540 | (400, 270) |
| Control Room | x: 1050–1920, y: 64–480 | (1500, 220) |
| Storage Hall | x: 64–450, y: 540–1128 | (220, 840) |
| Corridor Area | x: 450–1000, y: 64–680 | (700, 380) |
| Server Room | x: 450–1450, y: 680–1128 | (1100, 900) |
| Pipe/Elec Room | x: 1450–1920, y: 480–1128 | (1700, 700) |

Enemy positions for reference:
- Enemy1 (400, 300): Generator Room
- Enemy2 (900, 950): Server Room approach
- Enemy3 (1200, 1000): Server Room
- Enemy4 (1650, 650): Pipe/Elec Room
- Enemy5 (1500, 300): Control Room

---

## Solution

Added three new methods to `labyrinth_level.gd`:

### `_setup_room_cold_lights()`
- Called from `_ready()` after `_setup_window_lights()`
- Creates a `Node2D` container "RoomLights" under "Environment"
- Places one cold ceiling light at the geometric center of each room

### `_create_room_cold_light(parent, pos, energy, scale, room_name)`
- Adds a small `Sprite2D` fixture (cold blue tint, semi-transparent) at the lamp position
- Adds a `PointLight2D` with cold blue-white color `Color(0.55, 0.75, 1.0)`
- `shadow_enabled = true` with PCF5 filtering
- Uses `_create_cold_light_texture()` for the radial gradient

### `_create_cold_light_texture()`
- Per-pixel `ImageTexture` with `pow(1-t, 2.2)` falloff — same as PR #1207
- No abrupt edge, smooth circular fade to black

### `_create_lamp_fixture_texture()`
- 32×32 circular soft-edged disc for the ceiling lamp visual
- Same implementation as PR #1207 (shared design)

---

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Cold blue `Color(0.55, 0.75, 1.0)` | Mimics fluorescent/LED lab lighting — sterile, cold, institutional |
| Energy 0.50–0.65 (vs 0.7–0.9 warm) | Issue requests "more dim" — ~25% lower than BuildingLevel lights |
| Texture scale 3.0–4.0× (vs 3.5–5.0×) | Smaller radius for dimmer atmosphere |
| Fixture modulate `Color(0.7, 0.85, 1.0, 0.45)` | Pale cold blue, less opaque than warm fixture |
| `Sprite2D` not `ColorRect` | Same as PR #1207 fix — avoids blocking mouse input |
| Shadow color `Color(0, 0, 0.05, 0.65)` | Slight blue tint in shadows for consistent cold atmosphere |
| Lights in ALL rooms | LabyrinthLevel is small (1920×1080); even enemy rooms benefit from visual detail |

---

## Files Changed

- `scripts/levels/labyrinth_level.gd` — Added `_setup_room_cold_lights()`, `_create_room_cold_light()`, `_create_cold_light_texture()`, `_create_lamp_fixture_texture()` and a call in `_ready()`.
