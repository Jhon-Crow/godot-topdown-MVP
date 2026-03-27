# Case Study: Issue #1631 — Add Weak Wall Lamps to Sewer Map

## Issue Summary

**Repository:** Jhon-Crow/godot-topdown-MVP
**Issue:** [#1631 — update карту Канализация](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1631)
**Request:** Add weak wall light sources (like wall-mounted lamps) to the Sewer (Канализация) level.

The issue author referenced an image showing dim incandescent/utility lamps mounted along walls — the kind seen in underground utility corridors and sewers.

---

## Map Layout Analysis

The SewerLevel (`scenes/levels/SewerLevel.tscn`) consists of:

| Zone | X range | Y range | Description |
|------|---------|---------|-------------|
| Main corridor | 112–288 | 112–3088 | Long vertical corridor, player spawn at bottom |
| Top room | 50–550 | 112–450 | Wide entry room at top |
| Right branch | 288–2100 | 1362–1538 | Horizontal branch from main corridor |
| Room A | 950–1424 | 1538–2050 | Side room off right branch |
| Room B | 1600–2100 | 1538–2100 | Large room at end of right branch |
| Right bend | 1424–1600 | 2050–2200 | Passage connecting rooms |
| Small rooms | 288–488 | 1850–2750 | Three alcoves off main corridor |

The level had **no lighting effects** before this fix — just flat colored rectangles for the floor and walls.

---

## Existing Lighting Approach in the Project

### OrangeBlinkingLight (FactoryLevel)

The closest existing example is `scenes/effects/OrangeBlinkingLight.tscn` (Issue #1436), used in FactoryLevel:
- Two `PointLight2D` nodes rotating 360° at `π rad/s`
- Blinking on/off every 0.4 seconds
- Orange color (`Color(1.0, 0.45, 0.05, 1.0)`)
- Energy: 4.0, radius scale: 8.0 (large)

This is a rotating warning beacon — **not appropriate** for sewer wall lamps.

### FactoryLevel Lighting Pattern

```gdscript
[node name="Lighting" type="Node2D" parent="."]
[node name="EntryHallLight" parent="Lighting" instance=ExtResource("6_orange_blinking_light")]
position = Vector2(422, 382)
```

Nine lights placed at room centers across a 2450×1900 grid.

---

## Approach Chosen: SewerWallLamp

### Design decisions

| Property | Value | Reason |
|----------|-------|--------|
| Color | `Color(0.85, 0.8, 0.55)` | Warm yellowish-white, realistic incandescent utility lamp |
| Energy | `0.8` | Weak/dim — as specified in issue ("слабые источники света") |
| Shadow | enabled, color `(0,0,0,0.5)` | Creates atmospheric depth |
| Texture scale | `3.0` | Small radius — wall lamp, not flood light |
| Animation | None (static) | Wall lamps don't rotate or blink |

### Ambient darkness

A `CanvasModulate` node is added with `Color(0.12, 0.14, 0.13, 1.0)` — a very dark greenish-gray that:
- Makes the sewer feel underground and oppressive
- Makes the wall lamps visible and impactful (without darkness, PointLight2D has no effect on bright floors)
- Matches the dark green-gray aesthetic described in `sewer_level.gd`

### Light placement (21 lamps total)

| Group | Count | Spacing |
|-------|-------|---------|
| Main corridor | 9 | ~300px vertical |
| Right branch | 4 | ~400px horizontal |
| Right bend | 1 | At bend center |
| Room A | 2 | Corner placement |
| Room B | 2 | Corner placement |
| Top room | 2 | Side walls |

---

## Files Changed

| File | Change |
|------|--------|
| `scenes/effects/SewerWallLamp.tscn` | **New** — wall lamp scene (PointLight2D, dim, static, warm yellow) |
| `scenes/levels/SewerLevel.tscn` | Added `Lighting` node with `CanvasModulate` + 21 lamp instances |

---

## Alternative Solutions Considered

### 1. Reuse OrangeBlinkingLight
- **Pros:** No new scene needed
- **Cons:** Wrong aesthetic (orange rotating beacon vs. static wall lamp); too bright; wrong color for sewer

### 2. Use a Sprite2D lamp graphic + PointLight2D
- **Pros:** More realistic visual representation of the lamp fixture
- **Cons:** Requires a dedicated lamp sprite asset; overkill for this request; no existing sprite in assets

### 3. Flickering effect (like a worn-out lamp)
- **Pros:** More atmospheric
- **Cons:** Not requested; adds complexity; issue says "weak" not "flickering"

### 4. Static PointLight2D inline in scene (no separate scene file)
- **Pros:** Simpler, fewer files
- **Cons:** Harder to reuse/modify; inconsistent with project pattern (FactoryLevel uses separate scene files)

---

## Testing Notes

- The `CanvasModulate` requires Godot's 2D lighting pipeline to be active (default in Godot 4)
- `PointLight2D` requires a texture to function; `GradientTexture2D` provides a radial falloff
- Shadow rendering (`shadow_enabled = true`) requires occluders on walls — the SewerLevel already has `LightOccluder2D` nodes on all walls

---

## References

- [Godot 4 PointLight2D docs](https://docs.godotengine.org/en/stable/classes/class_pointlight2d.html)
- [Godot 4 CanvasModulate docs](https://docs.godotengine.org/en/stable/classes/class_canvasmodulate.html)
- [Issue #1436 — OrangeBlinkingLight for Factory](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1436)
- [Issue #1631 — Source issue](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1631)
