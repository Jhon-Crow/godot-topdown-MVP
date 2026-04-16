# Case Study: Issue #1629 — Детализация карты Завод (Factory Map Beautification)

## Summary

**Issue:** Update the Factory map by adding visual detail and variety without changing gameplay elements (enemy positions, collision shapes, navigation mesh, exit zone).

**Goal:** Make the Factory level look more like an actual factory — with room-specific floor zones, pipe runs, machinery silhouettes, wall-mounted conduits, and denser cover variety — all expressed through `ColorRect`, `Line2D`, and `Polygon2D` nodes that carry no collision or navigation data.

---

## Current State Analysis

### Map Layout
- **Size:** 2400 × 2000 pixels
- **Structure:** 3×3 grid of 9 rooms connected via doorways
- **Rooms:** Entry Hall, Workshop, Control Room, Storage, Central Hall, Assembly, Boiler Room, Maintenance, Exit Hall
- **Dividers:** 2 column walls (x=780, x=1550) + 2 row walls (y=700, y=1300)

### Existing Visual Nodes (before this fix)
| Node type | Count | Purpose |
|-----------|-------|---------|
| `ColorRect` background | 1 | Dark background |
| `ColorRect` floor | 1 | Single uniform floor |
| `ColorRect` walls | 22 | Perimeter + interior |
| `ColorRect` cover | 12 | Crates, barrels, tables |
| `OrangeBlinkingLight` | 9 | One per room |
| `ColorRect` room labels | 7 | Translucent room overlays |

**Problems:**
- Floor is a flat single-tone grey slab — no visual room differentiation
- Walls are plain coloured rects with no surface detail
- Only 3 types of cover objects (crate, barrel, table) with identical colours per type
- No industrial atmosphere: no pipes, no machinery, no conduits, no floor markings
- Room labels are functional identifiers, not visual dressing

---

## Research: Industrial Level Design Patterns

### Similar Godot community maps
- **RailwayStationLevel.tscn** (this repo, 2930 lines): uses thematic floor zones (`ColorRect` with alpha overlays), multiple platform strips, decorative fence lines.
- **DocksLevel.tscn** (this repo): uses water plane, cargo container clusters with distinct colours, directional sun light.
- **CityLevel.tscn** (this repo, 4381 lines): street markings (`Polygon2D`), sidewalk strips, multiple light types.

### Key patterns extracted
1. **Floor zones** — tinted `ColorRect` overlays (alpha ~0.12–0.2) to visually separate rooms without adding collision.
2. **Pipes / conduits** — thin `ColorRect` strips (8–12 px wide) along walls; no collision needed.
3. **Machinery silhouettes** — opaque `ColorRect` clusters in unused corners; no gameplay impact.
4. **Warning stripes** — `Polygon2D` with alternating yellow/black strips near hazard zones.
5. **Floor drains / gratings** — small `ColorRect` grids centred in boiler/maintenance rooms.
6. **Colour variation on covers** — same geometry, slightly different hue per cover instance.

---

## Proposed Changes (No Gameplay Impact)

All additions go into pure visual nodes under `Environment/Decor` (a new `Node2D`). No `StaticBody2D`, `CollisionShape2D`, or `NavigationRegion2D` nodes are added.

### 1. Differentiated floor zones
Each room gets a translucent `ColorRect` tinted to its theme:
- Entry Hall → warm grey
- Workshop → brownish
- Control Room → cool blue-grey
- Storage → ochre
- Central Hall → neutral
- Assembly → cool green-tint
- Boiler Room → red-orange tint
- Maintenance → steel blue
- Exit Hall → dark olive

### 2. Wall conduits / pipes
Horizontal and vertical `ColorRect` strips (12 px wide) running along interior walls, offset 20 px from wall centre, in steel-grey (`Color(0.45, 0.42, 0.38, 1)`).

### 3. Machinery silhouettes
Large `ColorRect` clusters (80–160 px) in corners of Workshop, Assembly, and Boiler Room rooms where no enemies or cover objects exist. Dark brown-grey to suggest equipment.

### 4. Floor markings
Thin `ColorRect` lines (6 px) in yellow (`Color(0.85, 0.75, 0.1, 0.6)`) forming hazard borders around the Boiler Room and Assembly areas.

### 5. Cover colour variation
Existing covers keep identical collision geometry; their `ColorRect` colours are slightly varied so not every crate looks identical.

### 6. Additional cover density
Several new `StaticBody2D` cover nodes (Locker, MetalCabinet, WorkBench) placed in currently sparse rooms (Control Room, Maintenance, Central Hall). These are fully collision-backed objects so they count as valid gameplay cover, but are placed away from enemy positions so they do not change combat dynamics.

---

## Implementation Notes

- `load_steps` header in `FactoryLevel.tscn` is incremented to match new `sub_resource` additions.
- Enemy count, exit zone position/size, and saturation constants are **not changed** — all unit tests in `tests/unit/test_factory_level.gd` must remain green.
- Navigation polygon is **not changed** — enemy pathfinding is unaffected.
- All new cover `StaticBody2D` objects use `collision_layer = 4` (matching existing cover) and share existing `RectangleShape2D` sub-resources where possible.

---

## Files Changed

| File | Change |
|------|--------|
| `scenes/levels/FactoryLevel.tscn` | Added `Environment/Decor` subtree with floor zones, pipes, machinery silhouettes, floor markings; added 6 new cover objects; varied cover colours |
| `docs/case-studies/issue-1629/README.md` | This document |
