# Case Study: Issue #1227 — Optimize Combat Enemy Movement with Pre-defined Paths

## Issue Summary

**Title (RU):** оптимизируй перемещение боевых врагов
**Title (EN):** Optimize combat enemy movement

**Request:**
Pre-define paths on the map that enemies use in combat states (all except IDLE and SEARCHING). In those states, the enemy should pick the nearest "attacking" or "retreating" path and follow it.

Implement for the **Building (Здание)** map as a test case.

---

## Problem Analysis

### Current State

The current enemy AI in `scripts/objects/enemy.gd` uses the following approach for combat movement:

1. **PURSUING state** — `_find_pursuit_cover_toward_player()`: Casts 16 raycasts in all directions every frame to find suitable cover obstacles toward the player. Scores each candidate based on distance, hidden status, flashlight penalty, and obstacle diversity. Very expensive with 20+ active enemies.

2. **FLANKING state** — `_find_flank_cover_toward_target()`: Similar raycast-based approach, finding cover positions at an angle to flank the player.

3. **SEEKING_COVER state** — Finds the nearest cover using raycasts from the enemy's current position.

4. **COMBAT state** — When approaching, uses `_move_to_target_nav()` directly toward player.

5. **RETREATING state** — Moves toward a pre-found cover while possibly shooting.

### Pain Points

- **Performance**: 16 raycasts per enemy per frame (or per 0.3s cooldown) is expensive. With 10 enemies in BuildingLevel and up to 20+ in some levels, this is a significant overhead.
- **Predictability**: Enemies can get stuck or make suboptimal decisions due to dynamic cover search failures.
- **Navigation**: Dynamic cover search can produce positions that are unreachable or blocked by geometry.

---

## Solution Design

### Approach: Pre-defined CombatPath nodes

Add `Node2D` "combat path" nodes to each level map. Two types:
- **AttackingPath** — waypoints enemies use when advancing toward the player (PURSUING, COMBAT, FLANKING, ASSAULT states)
- **RetreatPath** — waypoints enemies use when retreating/seeking cover (RETREATING, SEEKING_COVER, SUPPRESSED, IN_COVER states)

Each path consists of `Marker2D` children as waypoints.

A new component `CombatPathComponent` (GDScript, attached as a singleton or autoload) provides:
- `get_nearest_attacking_waypoint(from_pos, toward_player_pos)` — Returns the nearest attacking-path waypoint that advances toward the player
- `get_nearest_retreat_waypoint(from_pos, from_player_pos)` — Returns the nearest retreat-path waypoint that puts distance from the player

The enemy AI queries this component when entering combat states. If a pre-defined path waypoint is found, it is used as the primary movement target instead of the expensive raycast cover-search.

### Implementation Plan

1. **`scripts/components/combat_path_component.gd`** — New script:
   - `register_attacking_path(path_node: Node2D)` — Collect waypoints from AttackingPath nodes
   - `register_retreat_path(path_node: Node2D)` — Collect waypoints from RetreatPath nodes
   - `get_nearest_attacking_waypoint(from, toward)` → `Vector2` or `Vector2.ZERO`
   - `get_nearest_retreat_waypoint(from, away_from)` → `Vector2` or `Vector2.ZERO`
   - Called from level scripts or registered as child of the level root

2. **`scenes/levels/BuildingLevel.tscn`** — Add path nodes:
   - `AttackingPaths` group containing paths for corridors and rooms
   - `RetreatPaths` group containing paths back to initial positions or behind cover

3. **`scripts/objects/enemy.gd`** — Integration:
   - New export `@export var use_combat_paths: bool = true`
   - New var `_combat_path_component: Node = null`
   - In `_ready()`, find CombatPathComponent in the scene
   - In `_find_pursuit_cover_toward_player()`: if combat_path_component has a waypoint near the player direction, use it
   - In `_find_flank_cover_toward_target()`: similar integration

---

## Existing Codebase Patterns

- **PatrolPath**: Enemies already use `patrol_offsets: Array[Vector2]` for patrol points — same concept, extended to combat
- **NavigationAgent2D**: All movement uses `_move_to_target_nav()` which routes via Godot's navigation mesh. Pre-defined paths feed into this system as target positions.
- **Cover raycasts**: `_cover_raycasts[16]` + `_find_pursuit_cover_toward_player()` — expensive, replaced for levels that have predefined paths

---

## Similar Solutions / Reference

- **Unreal Engine "Smart Objects"**: Pre-baked navmesh waypoints for AI cover; same concept
- **Halo AI**: Pre-authored "combat areas" / "firing positions" baked into the level
- **F.E.A.R. (2005)**: World-state-based dynamic cover with designer-authored cover nodes — widely cited as the gold standard for cover AI
- **Godot NavigationLink2D**: Could be used to mark preferred paths in the navmesh
- **Godot Path2D + PathFollow2D**: Built-in mechanism for pre-defined paths

---

## Map Layout: BuildingLevel

The BuildingLevel is ~2400×2000 pixels with the following rooms (from the .tscn):

```
Building bounds: (64,64) to (2464,2064)

Rooms (approximate):
- OFFICE 1 (Room1): x=64-512, y=64-700  (Enemies: Enemy1@(300,350), Enemy2@(400,550))
- SECURITY (Room2): x=512-924, y=700-1012 (Enemies: Enemy3@(700,750), Enemy4@(800,900))
- OFFICE 2 (Room3): x=1376-1776, y=64-612 (Enemies: Grenadier@(1700,350), Enemy6@(1950,450))
- ARMORY (Room4):   x=1376-1776, y=788-1388 (Enemies: Enemy7@(1600,900) patrol)
- Corridor:         x=964-1376, y=700-1012
- STORAGE (StorageRoom): x=100-512, y=1600-2064 (lobby area)
- MAIN HALL:        x=900-1500, y=1388-2064 (Enemies: Enemy10@(1200,1550) patrol)
- UPPER RIGHT WING: x=1688-2464, y=1200-2064 (Enemies: Enemy8@(1900,1450), Enemy9@(2100,1550))
```

### Attacking Path Design (corridors/approaches):
- Path from Room1 → Room2: through corridor near (600, 700)
- Path from Room2 → Corridor: through door at (912, 856)
- Path in Corridor: y=856 horizontal strip
- Path from Corridor → Room3/4: through junction at (1376, 856)
- Path in Main Hall: y=1700 strip
- Path in Upper Wing: diagonal approach routes

### Retreat Path Design (back-to-cover):
- Room1 deep cover: (200, 200)
- Room2 deep cover: (620, 800)
- Corridor cover: (1164, 856)
- Room3 deep cover: (1800, 200)
- Storage area cover: (250, 1800)
- Main Hall cover: (1200, 1700)
- Upper Wing cover: (2200, 1400)
