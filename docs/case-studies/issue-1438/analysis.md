# Issue #1438: Add New Level — Sewer (Канализация)

## Requirements

From the issue description (translated from Russian):

- **Long corridor** — the main path is a long corridor
- **One fork (splits in two)** — the corridor branches into two paths
- **Several small rooms before the fork** — rooms/alcoves before the branching point
- **Small, rare cover** — minimal cover elements, creating tension

## Design Analysis

### Level Layout

The sewer level is designed as a linear progression map:

```
 ┌────────────────────────────────────────────────────────────┐
 │  ENTRANCE                                                  │
 │  (Player spawn)                                            │
 │                                                            │
 │  ┌──────┐  ┌──────┐                                       │
 │  │Room 1│  │Room 2│    Main Corridor                       │
 │  │      │  │      │  ═══════════════════════╗              │
 │  └──────┘  └──────┘                         ║              │
 │                        ┌──────┐             ║              │
 │                        │Room 3│             ║              │
 │                        │      │       FORK  ╠═══ Branch A  │
 │                        └──────┘             ║              │
 │                                             ║              │
 │                                             ╚═══ Branch B  │
 │                                                            │
 └────────────────────────────────────────────────────────────┘
```

### Technical Details

- **Map size**: ~3200x2000 pixels (larger than viewport for scrolling)
- **Color scheme**: Dark green/brown tones for sewer atmosphere
- **Walls**: Dark concrete gray-green (Color 0.18, 0.2, 0.16)
- **Floor**: Dark wet stone (Color 0.12, 0.13, 0.11)
- **Cover**: Pipes, debris, small crates — sparse placement
- **Enemy count**: ~10 enemies distributed across rooms and corridors
- **Navigation**: Standard navmesh with agent_radius 24.0

### References

- Similar to LabyrinthLevel in corridor structure
- Similar to BuildingLevel in room layout
- Uses same wall/cover pattern as all other levels (StaticBody2D + ColorRect + CollisionShape2D + LightOccluder2D)

### Implementation Plan

1. Create `scenes/levels/SewerLevel.tscn` — scene file with geometry
2. Create `scripts/levels/sewer_level.gd` — level logic script
3. Add to `scripts/ui/levels_menu.gd` LEVELS array
4. Update next-level paths in other level scripts
