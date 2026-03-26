# Issue #1440: Winter Forest Level (Зимний лес)

## Issue Summary

Add a new map — Winter Forest. Layout:
- **Start**: Exit from the sewers (connects to Issue #1438 — sewer level).
- **Path through the forest**: A trail into the woods.
- **Sparse trees**: Trees that hide the player or enemy with their crown; tree trunks serve as cover (StaticBody2D obstacles).
- **Clearing (опушка)**: An open area with no trees but small cover objects scattered around.

## Design Analysis

### Map Layout Concept

The map progresses from a sewer exit point at the bottom-left through a forested area toward an open clearing:

```
+-------------------------------------------------------+
|                    CLEARING (опушка)                    |
|       Small cover objects (stumps, rocks, logs)        |
|                                                         |
|--------------------------------------------------------|
|                                                         |
|     FOREST ZONE - Sparse trees with crowns             |
|     Tree trunks = StaticBody2D cover                   |
|     Crowns = visual overlay (higher z_index)           |
|                                                         |
|--------------------------------------------------------|
|                                                         |
|     FOREST TRAIL                                        |
|     Path leading from sewer exit into forest            |
|                                                         |
|  [SEWER EXIT]                                           |
|  Player start                                           |
+-------------------------------------------------------+
```

### Map Size

Based on existing levels (Beach: 2400x2000, Factory: 2400x2000), this level uses **3200x2400 pixels** — slightly larger to accommodate the open forest layout with transition zones.

### Key Design Elements

1. **Sewer Exit (Starting Area)**
   - Small concrete/metal structure at bottom-left
   - Player spawns here
   - Connects thematically to Issue #1438

2. **Forest Trail**
   - Winding path through the forest
   - Some sparse trees on both sides

3. **Sparse Trees (Cover + Visual)**
   - Tree trunks: StaticBody2D with collision (40x40 px), act as cover
   - Tree crowns: ColorRect with semi-transparent green overlay at higher z_index
   - Crowns hide characters visually (both player and enemies)
   - This is the core mechanic of this level

4. **Clearing (Опушка)**
   - Open area in the upper portion
   - Small cover objects: rocks, stumps, fallen logs
   - More tactical, less visual concealment

### Technical Implementation

- Follows the standard level pattern (BeachLevel, CastleLevel, etc.)
- Tree trunks use collision_layer = 4 (obstacles) with LightOccluder2D
- Tree crowns use z_index = 10 to render above characters
- Winter color palette: snow-white ground, dark green/brown trees, grey sky
- Includes NavigationRegion2D, SearchPathWaypoints, ExitZone

### Color Palette

- **Snow ground**: Color(0.9, 0.92, 0.95, 1.0)
- **Sky/Background**: Color(0.6, 0.65, 0.72, 1.0)
- **Tree trunks**: Color(0.35, 0.25, 0.18, 1.0)
- **Tree crowns (snow-covered)**: Color(0.2, 0.35, 0.2, 0.6) with white snow overlay
- **Sewer exit structure**: Color(0.35, 0.35, 0.38, 1.0)
- **Small rocks**: Color(0.5, 0.48, 0.45, 1.0)
- **Fallen logs**: Color(0.4, 0.3, 0.2, 1.0)

### Enemy Configuration

- Mix of rifle and machete enemies (8-10 total)
- Some enemies positioned among trees (hidden by crowns)
- Some in the clearing with cover-seeking behavior
- All with enable_flanking and enable_cover = true

### References

- Issue #1438: Sewer level (precedes this level thematically)
- Existing levels for pattern reference: BeachLevel, CastleLevel, FactoryLevel
- Cover system: scripts/components/cover_component.gd
- Vision system: scripts/components/vision_component.gd
