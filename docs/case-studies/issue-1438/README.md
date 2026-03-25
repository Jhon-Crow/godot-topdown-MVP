# Case Study: Issue #1438 — Sewer Level (Канализация)

## Issue Summary

**Request**: Add a new level — "Sewer" (канализация) with the following specifications:
- Long narrow corridor (200-400px wide), starting from bottom going upward
- One fork (splits into two paths)
- Several small rooms before the fork
- Small rare cover objects in the corridor
- **Critical**: No gaps or cracks in the corridor walls

## Level Design Analysis

### Dimensions
- **Map size**: 400x3200 pixels (narrow and tall, vertical orientation)
- **Corridor width**: 300px (within the 200-400px specification)
- **Wall thickness**: 24px (consistent with other levels)

### Layout Description

The sewer level is a vertical corridor-based map:

```
                 ┌─────────────────────────────────────────────┐
                 │                  400px wide                  │
                 │  ┌───────┐               ┌───────┐          │
                 │  │ Left  │               │ Right │          │
                 │  │ Dead  │               │ Dead  │  ~800px  │
                 │  │ End   │               │ End   │          │
                 │  └───┬───┘               └───┬───┘          │
                 │      │      Fork Area        │              │
                 │      └───────────────────────┘              │
                 │              │                               │
                 │         Main Corridor                        │
                 │              │                               │
                 │  ┌───────────┼───────────┐   Room 2         │
                 │  │           │           │                   │
                 │  └───────────┼───────────┘                   │
                 │              │                               │
                 │  ┌───────────┼───────────┐   Room 1         │
                 │  │           │           │                   │
                 │  └───────────┼───────────┘                   │
                 │              │                               │
                 │         ┌────┴────┐                          │
                 │         │  START  │   Player spawn           │
                 │         └─────────┘                          │
                 └─────────────────────────────────────────────┘
```

### Color Scheme
- **Background**: Dark green-gray — Color(0.04, 0.06, 0.05) — underground/damp atmosphere
- **Floor**: Wet concrete — Color(0.12, 0.14, 0.12)
- **Walls**: Mossy concrete — Color(0.18, 0.22, 0.18)
- **Cover**: Rusty pipes/debris — Color(0.25, 0.18, 0.12)

### Enemies
- 8 enemies total, distributed along the corridor and in rooms
- Mix of behavior modes (stationary guards and patrolling)

### Technical Implementation
- Follows existing level patterns (Node2D root, Environment, Entities, CanvasLayer)
- Uses StaticBody2D with collision_layer=4 for all walls
- LightOccluder2D on every wall for shadow casting
- NavigationRegion2D with parsed_geometry_type=1, collision_mask=4
- Standard level script with all required systems (score, replay, exit zone, etc.)

## References
- Similar corridor-based levels: LabyrinthLevel, RevolverLevel (Double Corridor)
- Level registration: `scripts/ui/levels_menu.gd` LEVELS array
- Level script template: `scripts/levels/decadence_level.gd` (simplest standard level)
