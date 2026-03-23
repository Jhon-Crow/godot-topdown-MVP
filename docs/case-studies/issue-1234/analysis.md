# Case Study: Issue #1234 — Add Sunlight Source to Beach Map

## Summary

**Issue:** Add a sunlight source to the Beach map (BeachLevel), analogous to the lights on the Laboratory (LabyrinthLevel) map. The light should be positioned off-screen in the top-right corner and simulate sunlight illuminating the whole accessible map without passing through obstacles.

**Request (original Russian):** "по аналогии светом на карте Лаборатория, но на пляже должен быть один источник света за кадром (в правом верхнем углу) — свет должен имитировать солнечный и освещать всю доступную карту (естественно не проходить сквозь препятствия на самой карте)."

**Translation:** "Analogous to the lights on the Laboratory map, but on the beach there should be one light source off-screen (in the top-right corner) — the light should simulate sunlight and illuminate the whole accessible map (naturally not passing through obstacles on the map)."

---

## Map Analysis

**BeachLevel** (`scenes/levels/BeachLevel.tscn`, `scripts/levels/beach_level.gd`).

Map bounds: x 64–2464, y 64–2064 (playable area ~2400×2000 px).

Existing obstacles with `LightOccluder2D` (will correctly block sunlight):
- Rock1 (400, 700), Rock3 (1600, 650), Rock5 (2100, 800)
- Hut1 (600, 1100), Hut2 (1800, 1200), Hut3 (2200, 1500)

---

## Reference Implementation (PR #1210 — Laboratory cold lights)

PR #1210 added cold blue ceiling lights to LabyrinthLevel using:
- `PointLight2D` with per-pixel `ImageTexture` and `pow(1-t, 2.2)` falloff
- `Sprite2D` fixture (not `ColorRect`) to avoid blocking mouse events
- `shadow_enabled = true` with PCF5 filtering

Key pattern reused:
- `_create_cold_light_texture()` → `_create_sunlight_texture()` (same math, different color)
- Node2D container at light position with PointLight2D child

---

## Design Decisions

| Property | Value | Rationale |
|----------|-------|-----------|
| Position | `Vector2(2700, -200)` | Off-screen top-right corner; x > 2464 (map right), y < 64 (map top) |
| Color | `Color(1.0, 0.92, 0.7)` | Warm golden-yellow — outdoor sunlight |
| Energy | 1.2 | Bright outdoor scene; higher than indoor lab lights (0.5–0.65) |
| Texture scale | 14.0 | 14 × 256 = 3584 px radius; covers farthest corner ~3475 px away |
| Shadow enabled | true | Rocks and huts cast shadows, creating depth |
| Shadow filter | PCF5, smooth=4.0 | Soft shadow edges appropriate for diffuse sunlight |
| Shadow color | `Color(0,0,0, 0.5)` | Natural dark shadow tint |
| Count | 1 | Single sun — per issue requirement |

### Coverage calculation

Sun position: `(2700, -200)`. Farthest map corner: bottom-left `(64, 2064)`.

Distance = √((2700-64)² + (-200-2064)²) = √(2636² + 2264²) ≈ 3475 px

Light radius = 14.0 × 256 = **3584 px** ✓ — covers entire map.

---

## Files Changed

- `scripts/levels/beach_level.gd` — Added `_setup_sunlight()` and `_create_sunlight_texture()`, called from `_ready()`.
- `tests/unit/test_level_scripts.gd` — Added sunlight configuration constants to `MockBeachLevel` and 5 unit tests verifying position, color warmth, energy, map coverage, and shadow flag.
