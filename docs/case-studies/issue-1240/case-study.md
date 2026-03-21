# Case Study: Issue #1240 — Roguelike Mode Diversity & Room Size

## Issue Summary

**Title:** update рогалик (update roguelike)
**Reporter:** Jhon-Crow
**Description (translated from Russian):**
> "Not diverse generations in roguelike mode and rooms are very small, not enough tactically complex situations. Add more diversity."
> Implement it.

## Current State Analysis

### Room Dimensions
- Fixed size: **1280×720 pixels** for all rooms
- No variation in room size — every room is exactly the same dimensions
- The room always fills the full viewport (matches 1280×720 screen resolution)

### Room Types (5 total)
Each run shuffles all 5 types and picks 3–5 of them:
1. **LABYRINTH** — Corridors / maze: 2 horizontal + 1 vertical divider wall + 2 L-wall pieces
2. **BUILDING** — Indoor rooms: 1 vertical divider + 2 alcoves + 2 cover pieces
3. **BEACH** — Open area: 7 small cover objects + 1 sandbag wall
4. **DOCKS** — Container yard: 3 pairs of parallel horizontal walls + 2 end walls
5. **CITY** — Urban: 2 L-shaped blocks + 2 long barriers + 3 bollards

### Problems Identified

#### 1. Repetitive Room Layouts (No Procedural Variation)
Each room type has **exactly one hardcoded layout**. Every time LABYRINTH appears, the exact same walls are at the exact same positions. There's no randomization *within* each room type — only the *sequence* of types changes between runs.

#### 2. Room Size Is Always Identical
All rooms are 1280×720. There is no larger, more spacious combat room, no corridor room, and no compact tight-quarters room. The tactical situation is the same every run.

#### 3. Limited Enemy Positions
Enemy spawn positions are fixed arrays of 5 per room type. There's no positional variation based on room variant or layout randomization.

#### 4. Low Enemy Diversity per Room Type
Weapon pools per room type use at most 3 options and are hardcoded. No level-scaled weapon diversity.

#### 5. Enemy Behavior Is Too Predictable
Only 2 behaviors: GUARD (67%) and PATROL (33%). No variation in patrol routes. No ambush-style placement.

#### 6. Small Obstacles = Low Tactical Depth
Obstacles (walls, cover) are small relative to the room. Few tight chokepoints, flanking routes, or blind corners.

## Research Findings

### Roguelike Room Diversity Techniques

#### 1. Multiple Layout Variants per Room Type
Leading roguelikes (The Binding of Isaac, Enter the Gungeon, Dead Cells) define **multiple hand-crafted (or semi-random) room templates** for each room type. Each time a room type is selected, one template is randomly chosen. This gives exponentially more variety with relatively small code effort.

#### 2. BSP (Binary Space Partitioning) Partitioned Rooms
BSP recursively divides a space into sub-regions, then places rooms in leaf nodes. Splitting at varied positions (0.1–0.9 range) gives very heterogeneous room sizes. Corridors connect adjacent leaves. This is the standard approach for games like NetHack and Dungeon Crawl.
- **Source:** RogueBasin BSP Dungeon Generation

#### 3. Cellular Automata Cave Generation
Iterative smoothing of a randomly initialized grid creates organic, cave-like layouts. Good for tactically varied terrain (chokepoints, pockets, blind spots). Best for cave/dungeon themes.
- **Source:** RogueBasin Cellular Automata Method

#### 4. Seeded Per-Room Randomization
Re-seeding the RNG with `(run_seed + room_index + variant_seed)` ensures each room is procedurally different while still being reproducible for debugging.

#### 5. Obstacle Density Scaling
Higher difficulty levels should have more obstacles and tighter layouts, making flanking and positioning matter more.

### Industry Examples

| Game | Technique | Key Feature |
|------|-----------|-------------|
| The Binding of Isaac | Handcrafted room templates (~600+) | Massive variety from template pool |
| Enter the Gungeon | Multi-zone rooms + enemy waves | Tactical wave spawning |
| Dead Cells | Procedural + curated hybrid | Zone-based biomes with layout variation |
| Hades | Fixed rooms, varied enemy combos | Diversity from enemy composition |
| Risk of Rain 2 | Handcrafted stages | Spawn point diversity |

## Proposed Solution

### Core Strategy: Multiple Layout Variants Per Room Type + Larger Rooms

Rather than one fixed layout per room type, define **3–5 layout variants** per room type. Each variant is a procedurally varied arrangement of walls and cover. The variant is selected randomly when the room is built.

### Specific Changes

#### 1. Room Size Variants
Define 3 room sizes:
- **Small:** 1280×720 (current — keep for balance)
- **Medium:** 1600×900 (larger, more space for maneuvering)
- **Large:** 1920×1080 (epic rooms, for boss-like encounters)

Random selection per room, weighted toward medium/large on higher levels.

#### 2. Multiple Layout Variants per Room Type (3 variants each)
Each room type gets 3 variants. Variant is chosen randomly with `randi() % 3`. Total layout combinations: **5 types × 3 variants = 15 unique room configurations**.

#### 3. Increased Enemy Count
- Base: 3–5 enemies (up from 3–4)
- Level scaling: cap raised to 8 (from 6)
- More enemy positions defined per room (up to 8 per type)

#### 4. Patrol Route Variation
Different patrol offsets per room type and variant, creating more interesting movement patterns.

#### 5. Sniper Enemy Type
Add sniper behavior for long-corridor rooms (DOCKS, LABYRINTH variants), requiring different player tactics.

#### 6. Cover Richness Scaling
Higher difficulty levels add more cover pieces to the room, making late-game rooms feel different from early ones.

## Files to Change

- `scripts/levels/roguelike_level.gd` — main implementation

## Implementation Plan

1. Add `ROOM_WIDTH_OPTIONS` and `ROOM_HEIGHT_OPTIONS` arrays
2. Select random room size at build time, store in `_room_width` / `_room_height`
3. Replace each `_build_*_interior()` with a variant dispatcher that calls `_build_*_interior_v1/v2/v3()`
4. Update `_build_room_boundary_closed()` to use `_room_width`/`_room_height`
5. Expand `_get_enemy_positions()` to return 7–8 positions using dynamic dimensions
6. Increase `ENEMIES_PER_ROOM_MAX` to 5 and level cap to 8
7. Update `_spawn_player()` to use `_room_width`/`_room_height`
8. Update `_setup_exit_zone()` to use `_room_width`/`_room_height`
