# Case Study: Issue #1463 — Railway Station Map (ЖД Станция)

## Issue Summary

Add a new map "Railway Station" (Железнодорожная станция) as the level following Winter Forest (Зимний Лес).

### Requirements from Issue

1. **Entry**: Player enters from the bottom (exiting Winter Forest)
2. **Layout**: Horizontal orientation — player must cross the map from bottom to top
3. **Bottom zone**: Station building + platform (almost no cover)
4. **Middle zone**: 2 rows of railway tracks with trains, then a narrow path, then 2 more rows of tracks with trains
5. **Upper zone**: Embankment with snowdrift — several narrow passages (player-sized)
6. **Exit**: Top center, slightly to the right (direction of sunlight)
7. **No enemies** for now
8. **Winter/snow theme** (connected to Winter Forest)

## Map Layout Design

```
+================================================================+
|                    EXIT (top center-right)                       |
|                         ↑                                       |
|  ═══════╗    ═══════╗    ╔═══    ═══════╗    ═══════╗           |
|  SNOWDRIFT EMBANKMENT - narrow gaps (player-width passages)     |
|  ═══════╝    ═══════╝    ╚═══    ═══════╝    ═══════╝           |
|                                                                  |
|  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             |
|  │   TRAIN     │  │   TRAIN     │  │   TRAIN     │  Track 4    |
|  └─────────────┘  └─────────────┘  └─────────────┘             |
|  ═══════════════════════════════════════════════════  Rail 4    |
|  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             |
|  │   TRAIN     │  │   TRAIN     │  │   TRAIN     │  Track 3    |
|  └─────────────┘  └─────────────┘  └─────────────┘             |
|  ═══════════════════════════════════════════════════  Rail 3    |
|                                                                  |
|  ~~~~~~~~~ NARROW WALKWAY BETWEEN TRACK GROUPS ~~~~~~~~~        |
|                                                                  |
|  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             |
|  │   TRAIN     │  │   TRAIN     │  │   TRAIN     │  Track 2    |
|  └─────────────┘  └─────────────┘  └─────────────┘             |
|  ═══════════════════════════════════════════════════  Rail 2    |
|  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             |
|  │   TRAIN     │  │   TRAIN     │  │   TRAIN     │  Track 1    |
|  └─────────────┘  └─────────────┘  └─────────────┘             |
|  ═══════════════════════════════════════════════════  Rail 1    |
|                                                                  |
|  ┌────────────────────────────────────────┐                     |
|  │           PLATFORM (перрон)            │                     |
|  └────────────────────────────────────────┘                     |
|  ┌────────────────────────────────────────┐                     |
|  │     STATION BUILDING (здание)          │                     |
|  │     (almost no cover)                  │                     |
|  └────────────────────────────────────────┘                     |
|                                                                  |
|                    PLAYER SPAWN (bottom)                         |
+================================================================+
```

## Technical Analysis

### Existing Level Patterns

All levels in this project follow the same architecture:
- **Scene file** (`.tscn`): Defines visual layout using `ColorRect` for visuals, `StaticBody2D` + `CollisionShape2D` for physics, `LightOccluder2D` for shadows
- **Script file** (`.gd`): Handles game logic (enemy tracking, player setup, exit zone, score)
- **Registration**: Level added to `LEVELS` array in `levels_menu.gd` and `_get_next_level_path()` in level scripts

### Map Dimensions

Based on similar levels:
- Beach: 2400x2000, Castle: 6000x2560, Docks: 5000x4000
- Railway Station: **4000x4000** (needs vertical space for all zones)

### Color Palette (Winter/Industrial Theme)

- Background: Dark steel blue `Color(0.12, 0.14, 0.18)` — cold winter night
- Snow ground: Light gray-blue `Color(0.75, 0.78, 0.82)` — snow-covered ground
- Rails: Dark gray `Color(0.3, 0.3, 0.32)` — steel rails
- Trains: Dark blue-gray `Color(0.2, 0.25, 0.35)` — train carriages
- Platform: Concrete gray `Color(0.4, 0.42, 0.45)` — concrete platform
- Station building: Warm brown `Color(0.35, 0.28, 0.22)` — brick building
- Embankment: Brown-gray `Color(0.4, 0.35, 0.3)` — dirt/gravel
- Snowdrift: White-blue `Color(0.85, 0.88, 0.92)` — snow

### No Enemies

Issue explicitly states "пока что сделай без врагов" (for now, make without enemies).
The level will have 0 enemies and the exit zone will be immediately active.

## Solution

1. Create `scenes/levels/RailwayStationLevel.tscn` with the full map layout
2. Create `scripts/levels/railway_station_level.gd` based on `beach_level.gd` pattern
3. Register in `levels_menu.gd` LEVELS array
4. Update `_get_next_level_path()` in all level scripts that reference the progression chain

## References

- Existing level patterns: `BeachLevel.tscn`, `DocksLevel.tscn` (industrial theme)
- Wall validation: `docs/map-wall-validation-checklist.md`
- Contributing guidelines: `CONTRIBUTING.md`
