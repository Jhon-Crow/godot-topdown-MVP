# Case Study: Issue #1061 — Add Roguelike Mode (добавить режим рогалика)

**Issue URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1061
**Reported by:** Jhon-Crow
**Created:** 2026-03-16T21:27:33Z
**Status:** OPEN

---

## 1. Issue Description

**Original (Russian):**
> добавить режим рогалика (рандомные комнаты/генерация, рандомное оружие, рандомные враги)

**Translation:**
> Add a roguelike mode (random rooms/generation, random weapons, random enemies)

### Requirements Summary

| Feature | Description |
|---|---|
| Random rooms/generation | Procedurally generated level layout each run |
| Random weapons | Enemies spawn with randomly chosen weapon types |
| Random enemies | Enemy count, type, and stats vary per run |

---

## 2. Context and Codebase Analysis

### Existing Level Architecture

All levels in this project are built **programmatically in GDScript** using:
- `StaticBody2D` nodes with `RectangleShape2D` for walls
- `ColorRect` for visual rendering (no TileMaps)
- `Node2D` container hierarchy: `Environment/Walls`, `Environment/InteriorWalls`, `Environment/Enemies`
- `NavigationRegion2D` with auto-baked `NavigationPolygon` for enemy pathfinding

This architecture is **ideal for procedural generation** — no tileset or TileMap setup is needed.

### Enemy System

The `Enemy.tscn` scene (script: `scripts/objects/enemy.gd`) exposes `@export` properties that make random configuration trivial:

```gdscript
@export var weapon_type: WeaponType = WeaponType.RIFLE  # 0=RIFLE, 1=SHOTGUN, 2=UZI, 3=MACHETE
@export var min_health: int = 2
@export var max_health: int = 4
@export var behavior_mode: BehaviorMode = BehaviorMode.GUARD  # GUARD or PATROL
```

These can be set before `add_child()` to randomize each spawned enemy.

### Available Weapon Types (from `WeaponConfigComponent`)

| ID | Name | Cooldown | Magazine | Notes |
|---|---|---|---|---|
| 0 | RIFLE (M16) | 0.1s | 30 | Default, fast fire |
| 1 | SHOTGUN | 0.8s | 8 | Slow, powerful, multiple pellets |
| 2 | UZI | 0.06s | 32 | Very fast, high spread |
| 3 | MACHETE | 1.5s | — | Melee, no projectiles |

### Level Script Pattern (from `labyrinth_level.gd`)

Key shared functions in all levels:
- `_setup_navigation()` — sets up `NavigationRegion2D`
- `_setup_enemy_tracking()` — connects enemy `died` signals
- `_setup_player_tracking()` — links player node
- `_initialize_score_manager()` — calls `ScoreManager.start_level(count)`
- `_setup_exit_zone()` — creates the `ExitZone` that triggers level completion
- Score screen shown on exit via `ScoreManager`/`ProgressManager`

### Autoload Singletons Used

| Autoload | Purpose |
|---|---|
| `GameManager` | Enemy killed signals, stats |
| `ScoreManager` | Level start/end, score calculation |
| `ProgressManager` | Save/load best rank per level |
| `DifficultyManager` | Current difficulty settings |
| `SceneLoader` | Background scene loading |

---

## 3. Research: Roguelike Room Generation Approaches

### 3.1 BSP Tree (Binary Space Partitioning)

- Recursively splits the map area into sub-rectangles
- Places one room per leaf node (guaranteed no overlap)
- Connects siblings via L-shaped corridors
- **Pros**: Guaranteed connectivity, uniform coverage, clean structure
- **Cons**: Rooms feel grid-like and regular

### 3.2 Scatter-and-Reject (Chosen Approach)

1. Attempt to place up to `MAX_ROOMS` rooms at random positions within bounds
2. Check each new room against existing rooms using AABB overlap check
3. Discard overlapping attempts
4. Connect each room to the previous with L-shaped corridors

- **Pros**: Simple to implement, natural-feeling layout variation
- **Cons**: No guarantee all rooms fit; rejected placements wasted
- **Best for**: First implementation — good enough, simple to debug

### 3.3 Rooms-and-Mazes (Bob Nystrom's Algorithm)

- Places rooms, fills remaining space with mazes, connects via spanning tree
- **Pros**: Very high quality, organic feel
- **Cons**: Complex implementation, requires grid-based thinking

### 3.4 Corridor Connection Algorithms

| Algorithm | Complexity | Connectivity | Loops |
|---|---|---|---|
| L-shaped tunnels | Low | Sequential (may miss rooms) | None |
| MST (Kruskal/Prim) | Medium | All rooms guaranteed | Optional add-backs |
| Spanning-tree + connectors | High | All regions guaranteed | Optional |

### 3.5 Existing Godot 4 Libraries and Examples

| Name | Source | Notes |
|---|---|---|
| `Edgar.Godot` | Godot Asset Library | Full roguelike generator, MIT, Godot 4.5 |
| `statico/godot-roguelike-example` | GitHub | BSP + Kruskal MST in GDScript, Godot 4 |
| `liagame/godot-roguelike-demo` | GitHub | Simple room placement demo |
| Custom GDScript | (this project) | Matches existing code style, no new dependencies |

**Decision**: Implement custom GDScript solution matching the project's node-based (non-TileMap) architecture. No external library needed.

---

## 4. Solution Design

### Architecture

```
RoguelikeLevel (Node2D)          # roguelike_level.gd
├── Environment (Node2D)
│   ├── Background (ColorRect)   # dark floor background
│   ├── Rooms (Node2D)           # generated floor tiles per room
│   ├── Corridors (Node2D)       # generated floor tiles per corridor
│   ├── Walls (Node2D)           # perimeter + room walls (StaticBody2D)
│   └── Enemies (Node2D)         # spawned Enemy instances
├── NavigationRegion2D           # baked after generation
├── Player (instance)
├── ExitZone (instance)
└── CanvasLayer/UI               # HUD (enemy count, ammo, kills, etc.)
```

### Room Generation Algorithm (Scatter-and-Reject)

```
LEVEL_WIDTH  = 3840px (3× viewport width)
LEVEL_HEIGHT = 2160px (3× viewport height)
MIN_ROOM_W/H = 160px
MAX_ROOM_W/H = 400px
MIN_ROOMS    = 6
MAX_ROOMS    = 12
CORRIDOR_W   = 80px
```

1. Place player spawn room at center-left
2. Attempt MAX_ROOMS placements; keep non-overlapping ones
3. Connect each room to nearest unconnected room via L-shaped corridor
4. Place exit zone in the last/farthest room from spawn
5. Build walls around each room and corridor
6. Bake navigation polygon

### Enemy Placement (Floor-1 defaults, scales with future floor system)

```
Enemies per room: randi_range(1, 3)
(skip player spawn room and exit room)

Weapon weights (floor 1):
  RIFLE   35%
  SHOTGUN 25%
  UZI     20%
  MACHETE 20%

Health: min=1, max=randi_range(2, 3)
Behavior: 60% GUARD, 40% PATROL
```

### Level Menu Integration

Add roguelike entry to `LevelsMenu.LEVELS` array with path `"res://scenes/levels/RoguelikeLevel.tscn"`.
Mark it as always-unlocked or after completing first standard level.

---

## 5. Proposed Solutions Considered

| Option | Description | Chosen? |
|---|---|---|
| **Custom scatter-and-reject + L-corridors** | Matches codebase style, no deps, simple | ✓ Yes |
| BSP Tree | More uniform rooms, harder to implement | Future enhancement |
| Edgar.Godot asset | Full-featured, but requires TileMap integration | No |
| Pre-built random room sets | Static room templates, randomly assembled | No (less replayable) |

---

## 6. Implementation Summary

**Files created/modified:**

| File | Action | Description |
|---|---|---|
| `scenes/levels/RoguelikeLevel.tscn` | Created | Minimal scene with script + NavigationRegion2D |
| `scripts/levels/roguelike_level.gd` | Created | Full procedural generation + enemy/weapon randomization |
| `scripts/ui/levels_menu.gd` | Modified | Added roguelike entry to LEVELS array |

**Key implementation highlights:**
- Room layout re-generated each time the scene loads (`_ready()` calls `_generate_level()`)
- Random seed printed to console for reproducible debugging
- Enemy count, weapon types, health, and behavior all randomized per run
- Uses `ExitZone.tscn` (existing scene) to trigger level completion
- Full HUD (enemy count, ammo, kills, accuracy, combo) matching other levels
- Score tracking via `ScoreManager` with S/A+/A/B/C/D/F ranking
- Compatible with all difficulty modes
