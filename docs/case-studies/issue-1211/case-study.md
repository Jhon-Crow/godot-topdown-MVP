# Case Study: Issue #1211 — придумай какие ещё карты можно добавить
# (What Additional Maps Can Be Added)

## Issue Summary

**Title:** придумай какие ещё карты можно добавить (Think of what other maps can be added)

**Description:**
> Please collect data related about the issue to this repository, make sure we compile that data to `./docs/case-studies/issue-{id}` folder, and use it to do deep case study analysis (also make sure to search online for additional facts and data), and propose possible solutions (including known existing components/libraries, that solve similar problem or can help in solutions).

**URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1211

---

## Repository Context: Existing Maps

The project currently ships the following levels (as of this case study):

| Scene File | Script | Theme / Description |
|---|---|---|
| `TestTier.tscn` | `test_tier.gd` | Полигон (Training Grounds) — tactical combat arena; ~4000×2960 px, mixed cover types, 12 enemies |
| `LabyrinthLevel.tscn` | `labyrinth_level.gd` | Labyrinth of technical rooms — compact 1920×1080, narrow corridors, serves as first level |
| `Labyrinth2Level.tscn` | `labyrinth2_level.gd` | Larger labyrinth/maze-style building — ~3200×2400 px, more interconnected rooms |
| `BuildingLevel.tscn` | `building_level.gd` | Hotline Miami–style building — ~2400×2000 px, multiple rooms and hallways |
| `CastleLevel.tscn` | `castle_level.gd` | Outdoor castle fortress — ~6000×2560 px (3 viewports wide), oval walls, varied enemy weapons |
| `CityLevel.tscn` | `city_level.gd` | Large urban map — ~6000×5000 px, box-like buildings, long sightlines, Hotline Miami ranking |
| `BeachLevel.tscn` | `beach_level.gd` | Open outdoor beach — ~2400×2000 px, rocks/huts/barrels cover, melee + ranged enemies |
| `DocksLevel.tscn` | `docks_level.gd` | Industrial docks — ~5000×4000 px, shipping containers, warehouses, water boundaries, 20 enemies |
| `FactoryLevel.tscn` | `factory_level.gd` | Building-style factory — ~2400×2000 px, 13 enemies, interconnected rooms |
| `DecadenceLevel.tscn` | `decadence_level.gd` | Neon nightclub interior (Hotline Miami Ch.3 inspired) — synthwave aesthetic |
| `RevolverLevel.tscn` | `revolver_level.gd` | Double-corridor map designed for penetration shots and revolver gameplay |
| `ArenaLevel.tscn` | `arena_level.gd` | Endless wave survival arena — 1920×1080, fixed arena, escalating waves |
| `RoguelikeLevel.tscn` | `roguelike_level.gd` | Roguelike mode — Binding of Isaac–style room-by-room progression, treasure rooms |
| *(Tutorial)* | `tutorial_level.gd` | Tutorial — teaches reloads, fire modes, grenade throwing |

### Coverage Analysis

**What already exists:**
- Indoor/building interiors (Labyrinth, Building, Factory, Decadence)
- Outdoor open environments (Beach, Castle, City)
- Industrial/docks theme (Docks)
- Arena/survival mode (Arena)
- Roguelike meta-structure (Roguelike)
- Training/testing space (TestTier)
- Weapon-specific level (Revolver)

**Identified gaps — themes and mechanics NOT yet represented:**
- Underground / sewer / tunnel environment
- Snow / arctic / winter outdoor setting
- Forest / jungle / natural overgrown terrain
- Space station / sci-fi interior
- Laboratory / research facility
- Ancient ruins / temple
- Rooftop / elevated urban setting
- Hospital / prison interior
- Stealth-specific map with patrol route design
- Puzzle/hazard room
- Boss arena (dedicated, not part of roguelike)
- Escort / objective-based mission map
- Dynamic hazard map (flooding, moving walls)

---

## Deep Analysis

### 1. Map Type Classification Framework

Top-down game levels can be classified along three orthogonal axes:

**Axis A — Geometry Type:**
- *Closed*: player is surrounded by walls; map is self-contained
- *Open*: large outdoor spaces with scattered cover
- *Mixed*: building interiors within a larger outdoor context

**Axis B — Structural Flow:**
- *Linear*: single path from start to exit
- *Branching*: multiple routes; optional detours
- *Arena*: no spatial progression; survive in place
- *Hub-and-spoke*: central safe area, multiple radiating challenge rooms

**Axis C — Primary Challenge:**
- *Combat*: enemy elimination
- *Navigation*: orientation and exploration
- *Survival*: timed resistance
- *Puzzle/Hazard*: environmental obstacles
- *Stealth*: avoidance and timing

Mapping existing levels:

| Level | Geometry | Flow | Challenge |
|---|---|---|---|
| TestTier | Open/mixed | Arena | Combat |
| Labyrinth | Closed | Branching | Navigation+Combat |
| Labyrinth2 | Closed | Branching | Navigation+Combat |
| Building | Closed | Linear+Branch | Combat |
| Castle | Open | Linear | Combat |
| City | Open | Branching | Combat |
| Beach | Open | Linear | Combat |
| Docks | Mixed | Linear | Combat |
| Factory | Closed | Linear | Combat |
| Decadence | Closed | Linear | Combat |
| Revolver | Closed | Linear | Combat (weapon-specific) |
| Arena | Open | Arena | Survival |
| Roguelike | Closed | Hub-and-spoke | Combat+Exploration |

**Gaps clearly visible:**
- No Stealth challenge type at all
- No Puzzle/Hazard challenge type as a primary focus
- No Dynamic geometry (changing environment)
- No objective-based (Escort, Defend, etc.)
- Many unexplored geometry themes

### 2. Comparison with Reference Games

| Feature | Enter the Gungeon | Nuclear Throne | Hotline Miami | Dead Cells | This Project |
|---|---|---|---|---|---|
| Indoor rooms | ✅ | ✅ | ✅ | ✅ | ✅ |
| Outdoor open | ✅ | ✅ | ✅ | ✅ | ✅ |
| Sewer/underground | ✅ | ✅ | — | ✅ | ❌ |
| Ice/snow biome | ✅ | ✅ | — | ✅ | ❌ |
| Forest/jungle | — | ✅ | — | ✅ | ❌ |
| Space/sci-fi | ✅ | ✅ | — | — | ❌ |
| Ancient ruins | ✅ | — | — | ✅ | ❌ |
| Rooftop | — | — | ✅ | — | ❌ |
| Stealth focus | — | — | ✅ | — | ❌ |
| Dynamic hazards | ✅ | ✅ | — | ✅ | ❌ |
| Boss arena | ✅ | ✅ | ✅ | ✅ | ❌ (standalone) |

---

## Proposed New Maps (Prioritized)

### Priority 1 — High Impact, Low Implementation Complexity

---

#### Map A: Sewer / Underground Tunnel Level

**Theme:** Underground drainage system or smuggler tunnels beneath the city.

**Geometry:** Closed, organic curved corridors (~2400×2000 px)

**Primary Challenge:** Navigation + Combat

**Design notes:**
- Branching narrow tunnels (width ~96–128 px) create natural chokepoints
- Flooded sections (visually distinct dark-blue floor tiles) slow movement (optional: apply slow effect via Area2D)
- Grates and manhole covers as environmental cover (RectangleShape2D obstacles)
- Enemy placement exploits blind corners — ambush mechanics are primary
- Enemies with machetes/shotguns (close-range weapons) are dominant

**Unique mechanics:**
- Partial lighting (optional: dark overlay with light radius around player)
- Splashing sound on flooded tile entry
- Rats or pipe hazards (decorative or damaging Area2D)

**Godot implementation path:**
- Reuse `building_level.gd` as base script
- New `.tscn` with irregular corridor shapes (polygon StaticBody2D)
- Navigation mesh adapted for narrow corridors

---

#### Map B: Rooftop Level

**Theme:** Urban rooftop fight across multiple buildings connected by planks, fire escapes, and vents.

**Geometry:** Open/Mixed, large (~3000×2000 px)

**Primary Challenge:** Combat (long sightlines, sniper-friendly)

**Design notes:**
- Multiple rooftop "islands" with gaps between buildings (fall-zone, Area2D with damage or respawn)
- Crossing points: planks (narrow linear paths), ladders (one-way traversal if desired), and vent shafts
- Rooftop A/C units, water towers, vents as cover (RectangleShape2D obstacles)
- Long sightlines reward sniper and assault rifle play
- Close-range enemies must navigate bridges — delay builds tension before engagement
- Exit zone on the far rooftop from spawn

**Unique mechanics:**
- Gap/fall zones (Area2D → instakill or damage + respawn at edge)
- Directional wind effect (cosmetic particle system)

**Godot implementation path:**
- New `.tscn`; gap zones as Area2D with `body_entered` → apply damage
- Plank bridges as narrow StaticBody2D walkways

---

#### Map C: Forest / Jungle Level

**Theme:** Dense jungle with clearings, fallen trees, and vine cover.

**Geometry:** Open (outdoor), large (~3000×3000 px)

**Primary Challenge:** Combat + Navigation (organic irregular shapes break grid intuition)

**Design notes:**
- Alternating open clearings (arena-style engagement) and dense tree clusters (cover and LoS blocking)
- Trees as large circular/polygon cover objects (not full walls, but LoS blockers for enemies too)
- Fallen log obstacles (RectangleShape2D, low cover)
- Mud patches (Area2D slow effect optional)
- Enemy types: machete enemies hiding in brush, long-range snipers in clearings
- Natural winding path from start to exit

**Unique mechanics:**
- Bush/vine cover: player can hide in bush Area2D, reducing enemy detection range (optional stealth layer)
- Ambient wildlife sounds

**Godot implementation path:**
- Reuse `beach_level.gd` as outdoor template
- Polygon-shaped tree stumps using `CollisionPolygon2D`
- Optional: LightOccluder2D on dense foliage

---

### Priority 2 — Medium Impact, Medium Complexity

---

#### Map D: Prison / Jail Level

**Theme:** Interior of a detention facility — cell blocks, guard posts, and a courtyard.

**Geometry:** Closed, grid-like corridors (~2400×2000 px)

**Primary Challenge:** Combat + Stealth

**Design notes:**
- Cell rows create tight uniform corridors — predictable geometry enables stealth strategy
- Guard post rooms with line-of-sight cones (optional stealth mechanic: enemies detect if approached from front)
- Courtyard section: large open area mid-level providing contrast to enclosed corridors
- Breakable cell doors (optional: destructible obstacle)
- Enemy distribution: guards at fixed posts, roving patrol in corridors

**Unique mechanics:**
- Guard detection (if not already in the engine): enemy in GUARD state faces a fixed direction; approaching from that arc triggers alert
- Alarm state spreads to nearby enemies via signal

**Godot implementation path:**
- Extend `building_level.gd`; add patrol route logic (already available in enemy AI)
- Grid-based wall layout using repeated RectangleShape2D for cell blocks
- Optional detection cone using RayCast2D from guard node

---

#### Map E: Hospital Level

**Theme:** Abandoned or overrun hospital — operating rooms, patient wards, pharmacy, and emergency corridor.

**Geometry:** Closed, multi-room interior (~2400×2000 px)

**Primary Challenge:** Combat (with pacing through room themes)

**Design notes:**
- Room variety provides strong thematic pacing: narrow supply closets → large OR → long corridor → ER bay
- Hospital equipment as cover: gurneys (RectangleShape2D), trolleys, medical screens
- Breakable medical equipment (glass sound FX optional)
- Enemies in surgical scrubs/lab coats (visual reskin of existing enemy sprites optional)
- Pharmacy room: optional ammo pickup zone (health + ammo pickups concentrated here for mid-level reward)
- OR room: large dramatic arena fight for mid-level climax before final corridor

**Godot implementation path:**
- Reuse `factory_level.gd` as room-corridor base
- New `.tscn` with hospital aesthetic (lighter wall colors, medical cross symbols as decorative ColorRects)

---

#### Map F: Ancient Ruins / Temple Level

**Theme:** Crumbling stone temple complex — open courtyard, internal chambers, and a central altar room.

**Geometry:** Mixed (outdoor courtyard + indoor chambers), large (~3000×2500 px)

**Primary Challenge:** Combat + Navigation

**Design notes:**
- Ruined walls (partial: StaticBody2D that only partially blocks — low cover) vs. full standing walls
- Pit traps: Area2D instakill or damage zones in floor
- Central altar room: symmetrical boss-arena layout with pillar cover (creates de facto boss room even without a dedicated boss)
- Archaeological debris as scattered low cover
- Enemy composition: heavy melee enemies inside (axes/machetes), ranged enemies on ruined walls
- Multiple entrances to the altar room reward flanking

**Godot implementation path:**
- New `.tscn`; exterior polygon walls for ruined sections
- Pit zones: Area2D with `body_entered` signal
- Can serve as setting for a future boss encounter

---

#### Map G: Research Laboratory / Sci-Fi Facility

**Theme:** Underground research lab — clean white corridors, experimental chambers, server rooms.

**Geometry:** Closed, building-interior (~2400×2000 px)

**Primary Challenge:** Combat + Puzzle/Hazard

**Design notes:**
- Environmental hazards: laser tripwires (Area2D line barriers, instaKill or damage), electrified floors (toggleable Area2D)
- Server racks and equipment as irregular cover (breaks the grid)
- Security turret objects (could be Godot StaticBody2D enemies with GUARD AI that don't move)
- Airlock rooms: tight two-door sequences that create pressure zones
- Sterile visual aesthetic: light grey floor, white walls, neon blue accent lines (ColorRect decorations)
- Enemy composition: armored guards, automated turrets (stationary enemies)

**Unique mechanics (new):**
- Laser tripwire: Area2D with animation; triggers when player `body_entered`
- Security panel interactable: deactivates a nearby turret or door

**Godot implementation path:**
- Reuse `factory_level.gd` as room base
- Add laser hazard Area2D nodes
- Security panel: Area2D + interactable signal

---

### Priority 3 — High Complexity / High Novelty

---

#### Map H: Snow / Arctic Outdoor Level

**Theme:** Winter military base or snowy research station — white open snowfields, bunkers, fences.

**Geometry:** Open/Mixed, large (~3000×2500 px)

**Primary Challenge:** Combat (long sightlines, exposure risk)

**Design notes:**
- Snow physics optional: apply slow movement modifier in snow Area2D zones
- Bunkers as large rectangular covers; snowdrifts as low cover
- Frozen lake: slippery floor physics (apply velocity in `_physics_process` when in Area2D)
- Blizzard visibility overlay (optional: white particle system + reduced enemy detection range)
- Long sightlines reward ranged weapons; close bunker-to-bunker fights reward shotgun/pistol

**Unique mechanics:**
- Slippery floor: when player is in frozen-lake Area2D, reduce friction coefficient (set on CharacterBody2D)
- Footprint visual FX (cosmetic particle)

**Godot implementation path:**
- Extend `beach_level.gd` for outdoor template
- Slippery physics: Area2D sets a flag on player; player script applies modified friction value

---

#### Map I: Dynamic Hazard Level — Flooding Warehouse

**Theme:** Waterfront warehouse where rising water forces constant upward movement.

**Geometry:** Closed/Mixed vertical layout (~1920×3000 px — taller than wide)

**Primary Challenge:** Survival + Combat (with time pressure)

**Design notes:**
- Map is oriented vertically; player starts at bottom; exit is at top
- Water rises at ~30 px/second, tracked by a Timer + AnimatableBody2D water plane
- If player touches water: damage per second (Area2D body_entered)
- Stacked platform levels connected by ramps/ladders
- Enemies spawn from above (never from rising water direction)
- Crates can be pushed onto water (visual detail only) or used as temporary higher ground

**Unique mechanics (new):**
- Rising water: AnimatableBody2D water node, position driven by Timer `_on_timeout` → y position decreases
- Player takes damage in water Area2D
- Level auto-fails if player is fully submerged for > 3 seconds

**Godot implementation path:**
- New `.tscn` with vertical layout
- Water node: AnimatableBody2D + ColorRect water visual + Area2D damage zone stacked together
- No dependency on existing level scripts beyond base pattern

---

#### Map J: Dedicated Boss Arena

**Theme:** Thematic arena tailored for a single powerful boss encounter (placeholder for future boss character).

**Geometry:** Closed, large symmetrical arena (~1920×1920 px)

**Primary Challenge:** Combat (boss fight)

**Design notes:**
- Symmetrical room with 4 pillar covers at fixed positions
- Destructible pillars: at phase 2, pillars break (set `CollisionShape2D.disabled = true`, animate)
- Boss spawn point at center; player spawn at bottom
- Sealed exit that opens only on boss death
- Dramatic visual: dim overall lighting, bright spot on boss spawn
- Can be connected to Roguelike level as a final room per run, or standalone

**Godot implementation path:**
- New `.tscn` with symmetrical layout
- Destructible pillars: `animated_sprite.play("break")` → disable collision
- Boss AI: extend existing enemy AI with phase transitions (health threshold signals)

---

#### Map K: Stealth Map — Research Compound (Exterior)

**Theme:** Exterior of a guarded compound — fences, guard towers, bushes, patrol paths.

**Geometry:** Open/Mixed (~3000×2500 px)

**Primary Challenge:** Stealth + Combat

**Design notes:**
- Guard patrol routes using existing PATROL enemy behavior
- Light cone visualization (Light2D with narrow angle, colored orange) emanating from guard
- Bush areas: Area2D reduces enemy vision range when player is inside
- Alarm state: first alert → all guards converge on last known position (5 sec)
- Second alert → continuous combat mode (no more stealth possible)
- Optional: silent kill mechanic (machete/knife = no sound range)

**Unique mechanics (new):**
- Vision cone: Light2D + Area2D; when player enters Area2D in guard's current facing arc → alert
- Stealth bush: Area2D flag on player; enemy detection radius halved when flag is active
- Alarm propagation: signal emitted by alerted enemy → received by all enemies within radius

**Godot implementation path:**
- Extend `beach_level.gd` with exterior layout
- Add vision-cone Area2D to each guard enemy instance
- New `stealth_level.gd` script extending the patrol behavior

---

## Existing Libraries and Tools That Can Help

### Procedural Generation (if procedural maps are desired)

| Tool | Type | Godot Asset Library ID | Best For |
|---|---|---|---|
| **Edgar.Godot** | Room-graph procedural dungeons | #3770 | Roguelike-style room assembly |
| **Procedural-Map-Generator** | Cellular Automata + WFC | #2979 | Cave/organic map generation |
| **WFC by AlexeyBond** | Wave Function Collapse | GitHub | Tile-based constraint-solving maps |
| **Procedural World Map Generator** | Biome world maps | #1913 | Zone-level map prototyping |
| **DungeonTemplateLibrary-Godot** | Multi-algorithm dungeon | GitHub | Roguelike dungeon variety |

### Level Design Workflow

| Tool | Purpose | Source |
|---|---|---|
| **LDtk Importer** | Import LDtk editor files as Godot scenes | Asset #2181 / GitHub |
| **Godot Tiled Importer** | Import Tiled Map Editor tilemaps | Asset Library |
| **GDQuest Procedural Generation** | Reference demos for noise/biome generation | GitHub |
| **BSP Dungeon Generation** | Tutorial for binary-space-partition dungeons | Abitawake blog |

### Relevant Tutorials and Design References

- [Dungeon Generation in Enter The Gungeon — BorisTheBrave.Com](https://www.boristhebrave.com/2019/07/28/dungeon-generation-in-enter-the-gungeon/)
- [The Level Design of Dead Cells — Deepnight Games](https://deepnight.net/tutorial/the-level-design-of-dead-cells-a-hybrid-approach/)
- [Level Design in Top-Down Shooters — MY.GAMES / Medium](https://medium.com/my-games-company/level-design-in-top-down-shooters-creating-diversified-experience-using-maps-ff9e21c8e600)
- [Cover Object Placement — World of Level Design](https://worldofleveldesign.com/categories/level_design_tutorials/cover-object-placement-for-level-design.php)
- [Hades Level Design Analysis — Kotaku](https://kotaku.com/hades-level-design-is-less-random-than-it-seems-1845254545)
- [BSP Dungeon Generation in Godot — Abitawake](https://abitawake.com/news/articles/procedural-generation-with-godot-create-dungeons-using-a-bsp-tree)
- [Six Principles of Roguelike Design — Black Shell Media](https://blackshellmedia.com/2017/04/28/six-principles-roguelike-design-nuclear-throne-exemplifies/)
- [Edgar.Godot — Godot Asset Library](https://godotengine.org/asset-library/asset/3770)
- [Wave Function Collapse for Godot — AlexeyBond GitHub](https://github.com/AlexeyBond/godot-constraint-solving)

---

## Summary: Proposed Maps Ranked by Recommendation

| # | Map Name | Theme | New Mechanics | Complexity | Priority |
|---|---|---|---|---|---|
| A | **Sewer / Underground Tunnel** | Underground corridors, flooded sections | Flooded slow zone (Area2D) | Low | ⭐⭐⭐ |
| B | **Rooftop** | Urban rooftops, planks, gaps | Fall-zone damage (Area2D) | Low | ⭐⭐⭐ |
| C | **Forest / Jungle** | Natural outdoor, trees, clearings | Bush stealth (optional) | Low | ⭐⭐⭐ |
| D | **Prison / Jail** | Cell blocks, courtyard, guard posts | Guard detection cone (optional) | Medium | ⭐⭐ |
| E | **Hospital** | Abandoned hospital, room variety | Ammo/health pickup zone | Medium | ⭐⭐ |
| F | **Ancient Ruins / Temple** | Stone temple, altar room, pit traps | Pit damage zones (Area2D) | Medium | ⭐⭐ |
| G | **Research Laboratory** | Sci-fi lab, laser hazards, turrets | Laser tripwires, turret enemies | Medium | ⭐⭐ |
| H | **Snow / Arctic** | Winter base, frozen lake | Slippery floor (physics modifier) | Medium-High | ⭐ |
| I | **Flooding Warehouse** | Rising water, vertical layout | Dynamic rising water mechanic | High | ⭐ |
| J | **Boss Arena** | Symmetrical arena, boss fight | Phase-transition boss, destructible pillars | High | ⭐ |
| K | **Stealth Compound** | Guard compound, vision cones, bushes | Full stealth system (vision cone, alarm) | High | ⭐ |

**Recommended starting point for next implementation:** Maps A, B, and C offer the best return on investment — rich new aesthetics and gameplay variety with minimal new code, building directly on existing level templates.

---

## Key Design Principles for All New Maps

1. **Contrast with what exists** — each new map should differ from all existing ones in at least two of the three axes (Geometry / Flow / Challenge).
2. **Build on existing scripts** — use `beach_level.gd` for outdoors, `building_level.gd` / `factory_level.gd` for indoors, `arena_level.gd` for survival; avoid rewriting from scratch.
3. **Size guidelines** — small maps: ~1920×1080 (single viewport); medium: ~2400×2000; large: ~4000–6000 px on the long axis.
4. **Enemy variety** — each map should introduce at least one enemy configuration not seen in adjacent levels (weapon type, behavior mode, or HP tier).
5. **Cover placement** — always use island clusters, never solid walls of cover; leave exposure gaps to punish static camping.
6. **Pickup placement** — at minimum one ammo pickup mid-level and one health pickup near end for long maps.
7. **Navigation mesh** — always define a NavigationPolygon2D adapted to the geometry; avoid reusing another level's nav mesh.

---

*Case study authored for Issue #1211 by the AI Issue Solver on 2026-03-20.*
